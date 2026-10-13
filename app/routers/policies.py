import math
from decimal import Decimal
from typing import Optional, Literal
from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy import or_, cast, String
from sqlalchemy.orm import Session

from app.database import get_db
from app.models import Policy, Client, Broker, Underwriter, Vessel, Cargo, Voyage
from app.schemas import PolicyCreate, PolicyUpdate, PolicyRead, PaginatedResponse
from services.underwriting_engine import underwriting_engine

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

@router.get("/", response_model=PaginatedResponse[PolicyRead])
def get_policies(
    page: int = Query(1, ge=1, description="Page number (1-indexed)"),
    limit: int = Query(50, ge=1, le=500, description="Max items per page"),
    skip: Optional[int] = Query(None, ge=0, description="Offset override"),
    search: Optional[str] = Query(None, description="Search term across policy fields"),
    status: Optional[str] = Query(None, description="Filter by status (DRAFT, QUOTED, BOUND, ACTIVE, CANCELLED)"),
    policy_type: Optional[str] = Query(None, description="Filter by type (HULL, CARGO, PI)"),
    client_id: Optional[int] = Query(None, description="Filter by client ID"),
    vessel_id: Optional[int] = Query(None, description="Filter by vessel ID"),
    is_active: Optional[bool] = Query(None, description="Filter by active status"),
    db: Session = Depends(get_db)
):
    """Retrieve all policies with search, filters, and standard paginated envelope."""
    query = db.query(Policy)

    if is_active is not None:
        query = query.filter(Policy.is_active == is_active)
    if status is not None:
        query = query.filter(Policy.status == status.upper())
    if policy_type is not None:
        query = query.filter(Policy.policy_type == policy_type.upper())
    if client_id is not None:
        query = query.filter(Policy.client_id == client_id)
    if vessel_id is not None:
        query = query.filter(Policy.vessel_id == vessel_id)

    if search:
        search_term = f"%{search.strip()}%"
        query = query.outerjoin(Client, Policy.client_id == Client.client_id).outerjoin(Vessel, Policy.vessel_id == Vessel.vessel_id)
        query = query.filter(
            or_(
                cast(Policy.policy_no, String).ilike(search_term),
                Policy.policy_type.ilike(search_term),
                Policy.status.ilike(search_term),
                Policy.cargo_type.ilike(search_term),
                Policy.underwriting_decision.ilike(search_term),
                Policy.warranties.ilike(search_term),
                Client.name.ilike(search_term),
                Vessel.name.ilike(search_term),
                Vessel.imo_number.ilike(search_term),
            )
        )

    total = query.count()

    if skip is not None:
        offset = skip
        current_page = (skip // limit) + 1
    else:
        offset = (page - 1) * limit
        current_page = page

    items = query.order_by(Policy.policy_no.asc()).offset(offset).limit(limit).all()
    total_pages = math.ceil(total / limit) if total > 0 else 0

    return PaginatedResponse(
        items=items,
        total=total,
        page=current_page,
        limit=limit,
        total_pages=total_pages
    )

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

    for field, value in update_data.items():
        setattr(policy, field, value)

    db.commit()
    db.refresh(policy)
    return policy

@router.post("/{policy_no}/submit-underwriting", response_model=PolicyRead)
def submit_underwriting(policy_no: int, db: Session = Depends(get_db)):
    """
    Submits a policy to the automated underwriting engine.
    Computes risk score, decision, required warranties, AWRP surcharge,
    updates status to 'QUOTED', and commits results to the database.
    """
    policy = db.query(Policy).filter(Policy.policy_no == policy_no).first()
    if not policy:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Policy not found")

    if not policy.is_active or policy.status == "CANCELLED":
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Cannot submit an inactive or cancelled policy for underwriting"
        )

    # Resolve voyage details if vessel is linked
    origin_port = None
    dest_port = None
    voyage_id = None
    if policy.vessel_id:
        voy = db.query(Voyage).filter(Voyage.vessel_id == policy.vessel_id).order_by(Voyage.voyage_id.desc()).first()
        if voy:
            voyage_id = voy.voyage_id
            origin_port = voy.origin_port
            dest_port = voy.dest_port

    vessel_name = policy.vessel.name if policy.vessel else None
    imo_number = policy.vessel.imo_number if policy.vessel else None
    client_name = policy.client.name if policy.client else None

    # Run underwriting decision engine
    underwriting_result = underwriting_engine.evaluate_risk(
        db=db,
        policy_type=policy.policy_type or "HULL",
        sum_insured=float(policy.sum_insured or 0.0),
        premium=float(policy.premium) if policy.premium else None,
        client_id=policy.client_id,
        vessel_id=policy.vessel_id,
        voyage_id=voyage_id,
        cargo_id=policy.cargo_id,
        vessel_name=vessel_name,
        imo_number=imo_number,
        client_name=client_name,
        origin_port=origin_port,
        dest_port=dest_port
    )

    decision = underwriting_result.get("decision")
    risk_score = underwriting_result.get("risk_score")
    warranties_list = underwriting_result.get("warranties_required", [])
    warranties_text = "; ".join(warranties_list) if warranties_list else None
    ais_data = underwriting_result.get("ais_voyage_data", {})
    awrp_surcharge = ais_data.get("total_awrp_surcharge_percent", 0.0)

    # Persist underwriting output to policy
    policy.underwriting_decision = decision
    policy.risk_score = risk_score
    policy.warranties = warranties_text
    policy.awrp_surcharge = Decimal(str(awrp_surcharge))
    if underwriting_result.get("recommended_premium") and (not policy.premium or policy.premium == Decimal("0.00")):
        policy.premium = Decimal(str(underwriting_result.get("recommended_premium")))

    policy.status = "QUOTED"
    db.commit()
    db.refresh(policy)
    return policy

@router.post("/{policy_no}/bind", response_model=PolicyRead)
def bind_policy(
    policy_no: int,
    target_status: Literal["BOUND", "ACTIVE"] = Query("ACTIVE", description="Target status: BOUND or ACTIVE"),
    db: Session = Depends(get_db)
):
    """
    Binds an underwritten policy.
    Transitions status from 'QUOTED' or 'DRAFT' to 'BOUND' or 'ACTIVE'.
    Rejects binding if policy was declined by underwriting.
    """
    policy = db.query(Policy).filter(Policy.policy_no == policy_no).first()
    if not policy:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Policy not found")

    if not policy.is_active or policy.status == "CANCELLED":
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Cannot bind an inactive or cancelled policy")

    if policy.underwriting_decision == "DECLINE":
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Cannot bind a policy declined by underwriting")

    if policy.status not in ["QUOTED", "DRAFT", "BOUND"]:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"Cannot bind policy with status '{policy.status}'. Status must be 'QUOTED', 'DRAFT', or 'BOUND'."
        )

    policy.status = target_status
    db.commit()
    db.refresh(policy)
    return policy

@router.delete("/{policy_no}", status_code=status.HTTP_204_NO_CONTENT)
def delete_policy(policy_no: int, db: Session = Depends(get_db)):
    """Soft delete a policy by policy_no (sets is_active=False, status='CANCELLED')."""
    policy = db.query(Policy).filter(Policy.policy_no == policy_no).first()
    if not policy:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Policy not found")

    policy.is_active = False
    policy.status = "CANCELLED"
    db.commit()
    return None
