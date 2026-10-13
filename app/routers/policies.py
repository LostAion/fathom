from typing import List, Optional
from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy.orm import Session
from app.database import get_db
from app.models import Policy, Client, Broker, Underwriter, Vessel, Cargo
from app.schemas import PolicyCreate, PolicyUpdate, PolicyRead

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
from sqlalchemy import or_

@router.get("/", response_model=List[PolicyRead])
def get_policies(
    response: Response,
    skip: int = Query(0, ge=0),
    limit: int = Query(100, ge=1, le=500),
    policy_type: Optional[str] = Query(None, description="Filter by type (HULL, CARGO, PI)"),
    status: Optional[str] = Query(None, description="Filter by status (DRAFT, QUOTED, BOUND, ACTIVE, CANCELLED)"),
    search: Optional[str] = Query(None, description="Search cargo type, policy type, or ID"),
    client_id: Optional[int] = Query(None, description="Filter by client ID"),
    vessel_id: Optional[int] = Query(None, description="Filter by vessel ID"),
    db: Session = Depends(get_db)
):
    """Retrieve all policies with optional filters, search, and pagination."""
    query = db.query(Policy)
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
                Policy.status.ilike(search_filter)
            )
        )
    
    total = query.count()
    response.headers["X-Total-Count"] = str(total)
    return query.offset(skip).limit(limit).all()

@router.post("/{policy_no}/quote", response_model=PolicyRead)
def quote_policy(policy_no: int, db: Session = Depends(get_db)):
    """Move a policy from DRAFT to QUOTED status."""
    policy = db.query(Policy).filter(Policy.policy_no == policy_no).first()
    if not policy:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Policy not found")
    if policy.status == "CANCELLED":
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Cannot quote a cancelled policy")
    policy.status = "QUOTED"
    db.commit()
    db.refresh(policy)
    return policy

@router.post("/{policy_no}/bind", response_model=PolicyRead)
def bind_policy(policy_no: int, db: Session = Depends(get_db)):
    """Bind a policy, locking legal coverage (BOUND status)."""
    policy = db.query(Policy).filter(Policy.policy_no == policy_no).first()
    if not policy:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Policy not found")
    if policy.status == "CANCELLED":
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Cannot bind a cancelled policy")
    policy.status = "BOUND"
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

@router.delete("/{policy_no}", status_code=status.HTTP_204_NO_CONTENT)
def delete_policy(policy_no: int, db: Session = Depends(get_db)):
    """Delete a policy by policy_no."""
    policy = db.query(Policy).filter(Policy.policy_no == policy_no).first()
    if not policy:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Policy not found")
    db.delete(policy)
    db.commit()
    return None
