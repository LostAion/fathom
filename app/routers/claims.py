import math
from decimal import Decimal
from typing import Optional
from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy import or_, cast, String
from sqlalchemy.orm import Session

from app.database import get_db
from app.models import Claim, Policy
from app.schemas import ClaimCreate, ClaimUpdate, ClaimRead, PaginatedResponse

router = APIRouter(prefix="/claims", tags=["Claims"])

@router.get("/", response_model=PaginatedResponse[ClaimRead])
def get_claims(
    page: int = Query(1, ge=1, description="Page number (1-indexed)"),
    limit: int = Query(50, ge=1, le=500, description="Max items per page"),
    skip: Optional[int] = Query(None, ge=0, description="Offset override"),
    search: Optional[str] = Query(None, description="Search term for claim status or IDs"),
    status: Optional[str] = Query(None, description="Filter by status (REPORTED, UNDER_SURVEY, APPROVED, SETTLED, REJECTED)"),
    policy_no: Optional[int] = Query(None, description="Filter by policy number"),
    is_active: Optional[bool] = Query(None, description="Filter by active status"),
    db: Session = Depends(get_db)
):
    """Retrieve all claims with search, filters, and standard paginated envelope."""
    query = db.query(Claim)

    if is_active is not None:
        query = query.filter(Claim.is_active == is_active)
    if status is not None:
        query = query.filter(Claim.status == status.upper())
    if policy_no is not None:
        query = query.filter(Claim.policy_no == policy_no)

    if search:
        search_term = f"%{search.strip()}%"
        query = query.filter(
            or_(
                cast(Claim.claim_id, String).ilike(search_term),
                cast(Claim.policy_no, String).ilike(search_term),
                Claim.status.ilike(search_term),
                cast(Claim.loss_date, String).ilike(search_term),
            )
        )

    total = query.count()

    if skip is not None:
        offset = skip
        current_page = (skip // limit) + 1
    else:
        offset = (page - 1) * limit
        current_page = page

    items = query.order_by(Claim.claim_id.asc()).offset(offset).limit(limit).all()
    total_pages = math.ceil(total / limit) if total > 0 else 0

    return PaginatedResponse(
        items=items,
        total=total,
        page=current_page,
        limit=limit,
        total_pages=total_pages
    )

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

@router.post("/{claim_id}/settle", response_model=ClaimRead)
def settle_claim(claim_id: int, db: Session = Depends(get_db)):
    """
    Settles a claim by calculating payout against policy sum_insured and deductible:
    payout = max(0, min(claim_amount, policy.sum_insured) - policy.deductible).
    Updates settled_amount, deductible_applied, and sets status to 'SETTLED'.
    """
    claim = db.query(Claim).filter(Claim.claim_id == claim_id).first()
    if not claim:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Claim not found")

    if not claim.is_active:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Cannot settle an inactive claim")

    if not claim.policy_no:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Claim has no associated policy")

    policy = db.query(Policy).filter(Policy.policy_no == claim.policy_no).first()
    if not policy:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=f"Policy {claim.policy_no} not found")

    claim_amount = Decimal(str(claim.claim_amount or 0.00))
    sum_insured = Decimal(str(policy.sum_insured or claim_amount))
    deductible = Decimal(str(policy.deductible or 10000.00))

    # payout = max(0, min(claim_amount, policy.sum_insured) - policy.deductible)
    covered_amount = min(claim_amount, sum_insured)
    payout = max(Decimal("0.00"), covered_amount - deductible)
    deductible_applied = min(deductible, covered_amount)

    claim.settled_amount = payout
    claim.deductible_applied = deductible_applied
    claim.status = "SETTLED"

    db.commit()
    db.refresh(claim)
    return claim

@router.delete("/{claim_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_claim(claim_id: int, db: Session = Depends(get_db)):
    """Soft delete a claim by claim_id (sets is_active=False)."""
    claim = db.query(Claim).filter(Claim.claim_id == claim_id).first()
    if not claim:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Claim not found")
    claim.is_active = False
    db.commit()
    return None
