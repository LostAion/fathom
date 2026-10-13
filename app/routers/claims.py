from typing import List, Optional
from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy.orm import Session
from app.database import get_db
from app.models import Claim, Policy
from app.schemas import ClaimCreate, ClaimUpdate, ClaimRead

router = APIRouter(prefix="/claims", tags=["Claims"])

@router.get("/", response_model=List[ClaimRead])
def get_claims(
    skip: int = Query(0, ge=0),
    limit: int = Query(100, ge=1, le=500),
    policy_no: Optional[int] = Query(None, description="Filter by policy number"),
    db: Session = Depends(get_db)
):
    """Retrieve all claims with optional policy filter."""
    query = db.query(Claim)
    if policy_no is not None:
        query = query.filter(Claim.policy_no == policy_no)
    return query.offset(skip).limit(limit).all()

@router.get("/{claim_id}", response_model=ClaimRead)
def get_claim(claim_id: int, db: Session = Depends(get_db)):
    """Retrieve a single claim by claim_id."""
    claim = db.query(Claim).filter(Claim.claim_id == claim_id).first()
    if not claim:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Claim not found")
    return claim

@router.post("/", response_model=ClaimRead, status_code=status.HTTP_201_CREATED)
def create_claim(payload: ClaimCreate, db: Session = Depends(get_db)):
    """Create a new claim."""
    if payload.policy_no is not None:
        policy = db.query(Policy).filter(Policy.policy_no == payload.policy_no).first()
        if not policy:
            raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=f"Policy with policy_no {payload.policy_no} does not exist")

    claim = Claim(**payload.model_dump())
    db.add(claim)
    db.commit()
    db.refresh(claim)
    return claim

@router.put("/{claim_id}", response_model=ClaimRead)
def update_claim(claim_id: int, payload: ClaimUpdate, db: Session = Depends(get_db)):
    """Update an existing claim."""
    claim = db.query(Claim).filter(Claim.claim_id == claim_id).first()
    if not claim:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Claim not found")

    if payload.policy_no is not None:
        policy = db.query(Policy).filter(Policy.policy_no == payload.policy_no).first()
        if not policy:
            raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=f"Policy with policy_no {payload.policy_no} does not exist")

    update_data = payload.model_dump(exclude_unset=True)
    for field, value in update_data.items():
        setattr(claim, field, value)

    db.commit()
    db.refresh(claim)
    return claim

@router.delete("/{claim_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_claim(claim_id: int, db: Session = Depends(get_db)):
    """Delete a claim by claim_id."""
    claim = db.query(Claim).filter(Claim.claim_id == claim_id).first()
    if not claim:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Claim not found")
    db.delete(claim)
    db.commit()
    return None
