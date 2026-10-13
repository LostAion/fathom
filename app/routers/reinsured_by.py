from typing import List, Optional
from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy.orm import Session
from sqlalchemy.exc import IntegrityError
from app.database import get_db
from app.models import ReinsuredBy, Policy, Reinsurer
from app.schemas import ReinsuredByCreate, ReinsuredByUpdate, ReinsuredByRead

router = APIRouter(prefix="/reinsured-by", tags=["Reinsured By (Junction)"])

@router.get("/", response_model=List[ReinsuredByRead])
def get_reinsured_by_links(
    skip: int = Query(0, ge=0),
    limit: int = Query(100, ge=1, le=500),
    policy_no: Optional[int] = Query(None, description="Filter by policy number"),
    reinsurer_id: Optional[int] = Query(None, description="Filter by reinsurer ID"),
    db: Session = Depends(get_db)
):
    """List policy-reinsurer mappings with optional filters."""
    query = db.query(ReinsuredBy)
    if policy_no is not None:
        query = query.filter(ReinsuredBy.policy_no == policy_no)
    if reinsurer_id is not None:
        query = query.filter(ReinsuredBy.reinsurer_id == reinsurer_id)
    return query.offset(skip).limit(limit).all()

@router.get("/{policy_no}/{reinsurer_id}", response_model=ReinsuredByRead)
def get_reinsured_by_link(policy_no: int, reinsurer_id: int, db: Session = Depends(get_db)):
    """Get a specific policy-reinsurer link by composite key."""
    link = db.query(ReinsuredBy).filter(
        ReinsuredBy.policy_no == policy_no,
        ReinsuredBy.reinsurer_id == reinsurer_id
    ).first()
    if not link:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="ReinsuredBy record not found")
    return link

@router.post("/", response_model=ReinsuredByRead, status_code=status.HTTP_201_CREATED)
def create_reinsured_by_link(payload: ReinsuredByCreate, db: Session = Depends(get_db)):
    """Create a new policy-reinsurer reinsurance link."""
    # Validate foreign keys
    if not db.query(Policy).filter(Policy.policy_no == payload.policy_no).first():
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=f"Policy {payload.policy_no} does not exist")
    if not db.query(Reinsurer).filter(Reinsurer.reinsurer_id == payload.reinsurer_id).first():
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=f"Reinsurer {payload.reinsurer_id} does not exist")

    link = ReinsuredBy(**payload.model_dump())
    db.add(link)
    try:
        db.commit()
    except IntegrityError:
        db.rollback()
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"Mapping for policy {payload.policy_no} and reinsurer {payload.reinsurer_id} already exists"
        )
    db.refresh(link)
    return link

@router.put("/{policy_no}/{reinsurer_id}", response_model=ReinsuredByRead)
def update_reinsured_by_link(
    policy_no: int,
    reinsurer_id: int,
    payload: ReinsuredByUpdate,
    db: Session = Depends(get_db)
):
    """Update share_percent on an existing reinsurance link."""
    link = db.query(ReinsuredBy).filter(
        ReinsuredBy.policy_no == policy_no,
        ReinsuredBy.reinsurer_id == reinsurer_id
    ).first()
    if not link:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="ReinsuredBy record not found")

    update_data = payload.model_dump(exclude_unset=True)
    for field, value in update_data.items():
        setattr(link, field, value)

    db.commit()
    db.refresh(link)
    return link

@router.delete("/{policy_no}/{reinsurer_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_reinsured_by_link(policy_no: int, reinsurer_id: int, db: Session = Depends(get_db)):
    """Remove a policy-reinsurer link."""
    link = db.query(ReinsuredBy).filter(
        ReinsuredBy.policy_no == policy_no,
        ReinsuredBy.reinsurer_id == reinsurer_id
    ).first()
    if not link:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="ReinsuredBy record not found")
    db.delete(link)
    db.commit()
    return None
