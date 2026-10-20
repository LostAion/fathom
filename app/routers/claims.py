from math import ceil
from typing import List, Optional
from decimal import Decimal
from fastapi import APIRouter, Depends, HTTPException, Query, Response, status
from sqlalchemy.orm import Session
from app.database import get_db
from app.models import Claim, Policy
from app.schemas import ClaimCreate, ClaimUpdate, ClaimRead, PaginatedResponse

router = APIRouter(prefix="/claims", tags=["Claims"])

@router.get("/", response_model=List[ClaimRead] | PaginatedResponse[ClaimRead])
def get_claims(
    response: Response,
    skip: int = Query(0, ge=0),
    limit: int = Query(100, ge=1, le=500),
    policy_no: Optional[int] = Query(None, description="Filter by policy number"),
    status: Optional[str] = Query(None, description="Filter by status (REPORTED, UNDER_SURVEY, SETTLED, REJECTED)"),
    page: Optional[int] = Query(None, ge=1),
    is_active: Optional[bool] = Query(None),
    db: Session = Depends(get_db)
):
    """Retrieve all claims with optional filters and pagination."""
    query = db.query(Claim)
    if is_active is not None:
        query = query.filter(Claim.is_active == is_active)
    if policy_no is not None:
        query = query.filter(Claim.policy_no == policy_no)
    if status is not None:
        query = query.filter(Claim.status == status.upper())
    
    total = query.count()
    response.headers["X-Total-Count"] = str(total)
    offset = (page - 1) * limit if page is not None else skip
    items = query.order_by(Claim.claim_id).offset(offset).limit(limit).all()
    if page is not None:
        return PaginatedResponse(items=items, total=total, page=page, limit=limit, total_pages=ceil(total / limit))
    return items

from sqlalchemy import func

@router.post("/{claim_id}/settle", response_model=ClaimRead)
def settle_claim(claim_id: int, db: Session = Depends(get_db)):
    """
    Settle a claim enforcing both deductibles and cumulative aggregate policy limits.
    Transactionally locks the policy row (SELECT ... FOR UPDATE) to prevent concurrent limit breaches.
    """
    claim = db.query(Claim).filter(Claim.claim_id == claim_id).first()
    if not claim:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Claim not found")

    policy_no = claim.policy_no
    # End the lookup snapshot before waiting for the policy lock (REPEATABLE READ).
    db.rollback()
    policy = db.query(Policy).filter(Policy.policy_no == policy_no).with_for_update().first()
    if not policy:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Associated policy not found")

    claim = db.query(Claim).filter(Claim.claim_id == claim_id).populate_existing().with_for_update().first()
    if not claim or claim.policy_no != policy_no:
        raise HTTPException(status_code=409, detail="Claim changed during settlement; retry the request")
    if not claim.is_active or not policy.is_active:
        raise HTTPException(status_code=400, detail="Cannot settle an archived claim or policy")

    if claim.status == "SETTLED":
        return claim

    claim_val = Decimal(str(claim.claim_amount or 0.0))
    sum_insured = Decimal(str(policy.sum_insured or 0.0))
    deductible = Decimal(str(policy.deductible or 0.0))

    # Calculate cumulative prior settlements under this policy
    prior_settled = db.query(func.coalesce(func.sum(Claim.settled_amount), 0)).filter(
        Claim.policy_no == policy.policy_no,
        Claim.claim_id != claim_id,
        Claim.status == "SETTLED"
    ).scalar()

    remaining_aggregate = max(Decimal("0.00"), sum_insured - Decimal(str(prior_settled)))

    # Apply per-claim deductible first
    net_claim_after_deductible = max(Decimal("0.00"), claim_val - deductible)

    # Cap by remaining aggregate policy limit
    final_payout = min(net_claim_after_deductible, remaining_aggregate)

    claim.deductible_applied = deductible
    claim.settled_amount = final_payout
    claim.status = "SETTLED"
    db.commit()
    db.refresh(claim)
    return claim

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
def delete_claim(claim_id: int, permanent: bool = Query(True), db: Session = Depends(get_db)):
    """Delete a claim by claim_id."""
    claim = db.query(Claim).filter(Claim.claim_id == claim_id).first()
    if not claim:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Claim not found")
    if permanent:
        db.delete(claim)
    else:
        claim.is_active = False
    db.commit()
    return None
