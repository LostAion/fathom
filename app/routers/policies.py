from math import ceil
from decimal import Decimal
from typing import List, Optional, Literal
from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy.orm import Session
from app.database import get_db
from app.models import Policy, Client, Broker, Underwriter, Vessel, Cargo, Voyage
from app.schemas import PolicyCreate, PolicyUpdate, PolicyRead, PaginatedResponse
from app.schemas_underwriting import PolicyAssessRequest
from services.underwriting_engine import underwriting_engine
from services.sanctions import sanctions_screener

router = APIRouter(prefix="/policies", tags=["Policies"])

def validate_policy_foreign_keys(db: Session, payload_dict: dict):
    if payload_dict.get("client_id") is not None:
        if not db.query(Client).filter(Client.client_id == payload_dict["client_id"]).first():
            raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=f"Client with client_id {payload_dict['client_id']} does not exist")
            
    if payload_dict.get("broker_id") is not None:
        if not db.query(Broker).filter(Broker.broker_id == payload_dict["broker_id"]).first():
            raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=f"Broker with broker_id {payload_dict['broker_id']} does not exist")

    if payload_dict.get("emp_id") is not None:
        if not db.query(Underwriter).filter(Underwriter.emp_id == payload_dict["emp_id"]).first():
            raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=f"Underwriter with emp_id {payload_dict['emp_id']} does not exist")

    if payload_dict.get("vessel_id") is not None:
        if not db.query(Vessel).filter(Vessel.vessel_id == payload_dict["vessel_id"]).first():
            raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=f"Vessel with vessel_id {payload_dict['vessel_id']} does not exist")

    if payload_dict.get("cargo_id") is not None:
        if not db.query(Cargo).filter(Cargo.cargo_id == payload_dict["cargo_id"]).first():
            raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=f"Cargo with cargo_id {payload_dict['cargo_id']} does not exist")

from fastapi import APIRouter, Depends, HTTPException, Query, Response, status
from sqlalchemy import or_, cast, String

@router.get("/", response_model=List[PolicyRead] | PaginatedResponse[PolicyRead])
def get_policies(
    response: Response,
    skip: int = Query(0, ge=0),
    limit: int = Query(100, ge=1, le=500),
    policy_type: Optional[str] = Query(None, description="Filter by type (HULL, CARGO, PI)"),
    status: Optional[str] = Query(None, description="Filter by status (DRAFT, QUOTED, BOUND, ACTIVE, CANCELLED)"),
    search: Optional[str] = Query(None, description="Search cargo type, policy type, or ID"),
    client_id: Optional[int] = Query(None, description="Filter by client ID"),
    vessel_id: Optional[int] = Query(None, description="Filter by vessel ID"),
    page: Optional[int] = Query(None, ge=1),
    is_active: Optional[bool] = Query(None),
    db: Session = Depends(get_db)
):
    """Retrieve all policies with optional filters, search, and pagination."""
    query = db.query(Policy)
    if is_active is not None:
        query = query.filter(Policy.is_active == is_active)
    if policy_type is not None:
        query = query.filter(Policy.policy_type == policy_type.upper())
    if status is not None:
        query = query.filter(Policy.status == status.upper())
    if client_id is not None:
        query = query.filter(Policy.client_id == client_id)
    if vessel_id is not None:
        query = query.filter(Policy.vessel_id == vessel_id)
    if search:
        search_filter = f"%{search}%"
        query = query.filter(
            or_(
                Policy.cargo_type.ilike(search_filter),
                Policy.policy_type.ilike(search_filter),
                Policy.status.ilike(search_filter),
                cast(Policy.policy_no, String).ilike(search_filter),
                Policy.underwriting_decision.ilike(search_filter)
            )
        )
    
    total = query.count()
    response.headers["X-Total-Count"] = str(total)
    offset = (page - 1) * limit if page is not None else skip
    items = query.order_by(Policy.policy_no).offset(offset).limit(limit).all()
    if page is not None:
        return PaginatedResponse(items=items, total=total, page=page, limit=limit, total_pages=ceil(total / limit))
    return items

@router.post("/{policy_no}/quote", response_model=PolicyRead)
def quote_policy(policy_no: int, db: Session = Depends(get_db)):
    """Move a policy from DRAFT to QUOTED status."""
    policy = db.query(Policy).filter(Policy.policy_no == policy_no).first()
    if not policy:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Policy not found")
    if policy.status == "CANCELLED" or not policy.is_active:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Cannot quote a cancelled or archived policy")
    if policy.status not in {"DRAFT", "QUOTED"}:
        raise HTTPException(status_code=400, detail="Only draft or quoted policies can be quoted")
    policy.status = "QUOTED"
    db.commit()
    db.refresh(policy)
    return policy

@router.post("/{policy_no}/bind", response_model=PolicyRead)
def bind_policy(policy_no: int, target_status: Literal["BOUND", "ACTIVE"] = Query("BOUND"), db: Session = Depends(get_db)):
    """Bind a policy, locking legal coverage (BOUND status)."""
    policy = db.query(Policy).filter(Policy.policy_no == policy_no).first()
    if not policy:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Policy not found")
    if policy.status == "CANCELLED":
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Cannot bind a cancelled policy")
    if not policy.is_active:
        raise HTTPException(status_code=400, detail="Cannot bind an archived policy")
    screening = sanctions_screener.screen(
        imo_number=policy.vessel.imo_number if policy.vessel else None,
        vessel_name=policy.vessel.name if policy.vessel else None,
        client_name=policy.client.name if policy.client else None,
    )
    if screening["is_sanctioned"] or policy.underwriting_decision == "DECLINE":
        raise HTTPException(status_code=400, detail="Cannot bind a policy declined by underwriting or sanctions screening")
    if policy.underwriting_decision == "REFER_TO_SENIOR":
        raise HTTPException(status_code=400, detail="Senior review is required before binding")
    if policy.underwriting_report:
        report = policy.underwriting_report
        latest = underwriting_engine.evaluate_risk(
            db=db, policy_type=policy.policy_type, sum_insured=float(policy.sum_insured),
            client_id=policy.client_id, vessel_id=policy.vessel_id, cargo_id=policy.cargo_id,
            voyage_id=report.get("voyage_id"), vessel_age=report["vessel_age"],
        )
        if latest["decision"] in {"DECLINE", "REFER_TO_SENIOR"}:
            raise HTTPException(status_code=400, detail="Risk changed; reassess this policy before binding")
    policy.status = target_status
    db.commit()
    db.refresh(policy)
    return policy

@router.get("/{policy_no}", response_model=PolicyRead)
def get_policy(policy_no: int, db: Session = Depends(get_db)):
    """Retrieve a single policy by policy_no."""
    policy = db.query(Policy).filter(Policy.policy_no == policy_no).first()
    if not policy:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Policy not found")
    return policy

@router.post("/", response_model=PolicyRead, status_code=status.HTTP_201_CREATED)
def create_policy(payload: PolicyCreate, db: Session = Depends(get_db)):
    """Create a new policy."""
    data = payload.model_dump()
    validate_policy_foreign_keys(db, data)

    policy = Policy(**data)
    if policy.status in {"BOUND", "ACTIVE"}:
        vessel = db.get(Vessel, policy.vessel_id) if policy.vessel_id else None
        client = db.get(Client, policy.client_id) if policy.client_id else None
        screening = sanctions_screener.screen(
            imo_number=vessel.imo_number if vessel else None,
            vessel_name=vessel.name if vessel else None,
            client_name=client.name if client else None,
        )
        if screening["is_sanctioned"]:
            raise HTTPException(status_code=400, detail="Cannot bind a policy declined by sanctions screening")
    db.add(policy)
    db.commit()
    db.refresh(policy)
    return policy

@router.put("/{policy_no}", response_model=PolicyRead)
def update_policy(policy_no: int, payload: PolicyUpdate, db: Session = Depends(get_db)):
    """Update an existing policy."""
    policy = db.query(Policy).filter(Policy.policy_no == policy_no).first()
    if not policy:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Policy not found")

    update_data = payload.model_dump(exclude_unset=True)
    validate_policy_foreign_keys(db, update_data)

    if update_data.get("status") in {"BOUND", "ACTIVE"} and policy.status != update_data["status"]:
        raise HTTPException(status_code=400, detail="Use the bind endpoint to activate coverage")
    assessment_inputs = {"policy_type", "sum_insured", "premium", "client_id", "vessel_id", "cargo_id", "deductible"}
    if any(key in update_data and update_data[key] != getattr(policy, key) for key in assessment_inputs):
        if policy.status in {"BOUND", "ACTIVE"}:
            raise HTTPException(status_code=400, detail="Cannot change underwriting inputs on bound coverage")
        policy.underwriting_report = None
        policy.underwriting_decision = None
        policy.risk_score = None
        policy.warranties = None
        policy.awrp_surcharge = Decimal("0.00")
        policy.status = "DRAFT"
        update_data.pop("status", None)

    for field, value in update_data.items():
        setattr(policy, field, value)

    db.commit()
    db.refresh(policy)
    return policy

@router.delete("/{policy_no}", status_code=status.HTTP_204_NO_CONTENT)
def delete_policy(policy_no: int, permanent: bool = Query(True), db: Session = Depends(get_db)):
    """Delete a policy by policy_no."""
    policy = db.query(Policy).filter(Policy.policy_no == policy_no).first()
    if not policy:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Policy not found")
    if permanent:
        db.delete(policy)
    else:
        policy.is_active = False
        policy.status = "CANCELLED"
    db.commit()
    return None


@router.post("/{policy_no}/submit-underwriting", response_model=PolicyRead)
def submit_underwriting(policy_no: int, payload: PolicyAssessRequest = PolicyAssessRequest(), db: Session = Depends(get_db)):
    policy = db.query(Policy).filter(Policy.policy_no == policy_no).first()
    if not policy:
        raise HTTPException(status_code=404, detail="Policy not found")
    if not policy.is_active or policy.status not in {"DRAFT", "QUOTED"}:
        raise HTTPException(status_code=400, detail="Only active draft or quoted policies can be assessed")
    if not policy.sum_insured or policy.sum_insured <= 0 or not policy.policy_type:
        raise HTTPException(status_code=400, detail="Policy type and positive sum insured are required")
    voyage = None
    if payload.voyage_id is not None:
        voyage = db.get(Voyage, payload.voyage_id)
        if not voyage or voyage.vessel_id != policy.vessel_id:
            raise HTTPException(status_code=400, detail="Voyage must belong to the policy vessel")
    result = underwriting_engine.evaluate_risk(
        db=db, policy_type=policy.policy_type, sum_insured=float(policy.sum_insured),
        client_id=policy.client_id, vessel_id=policy.vessel_id, cargo_id=policy.cargo_id,
        voyage_id=payload.voyage_id, vessel_age=payload.vessel_age,
    )
    result["vessel_age"] = payload.vessel_age
    result["voyage_id"] = payload.voyage_id
    policy.underwriting_report = result
    policy.underwriting_decision = result["decision"]
    policy.risk_score = result["risk_score"]
    policy.warranties = "; ".join(result["warranties_required"])
    policy.awrp_surcharge = Decimal(str(result.get("ais_voyage_data", {}).get("total_awrp_surcharge_percent", 0)))
    if not policy.premium:
        policy.premium = Decimal(str(result["recommended_premium"]))
    policy.status = "QUOTED"
    db.commit()
    db.refresh(policy)
    return policy
