from typing import List, Optional
from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy.orm import Session
from sqlalchemy.exc import IntegrityError
from app.database import get_db
from app.models import AssessedBy, Claim, Surveyor
from app.schemas import AssessedByCreate, AssessedByRead

router = APIRouter(prefix="/assessed-by", tags=["Assessed By (Junction)"])

@router.get("/", response_model=List[AssessedByRead])
def get_assessed_by_links(
    skip: int = Query(0, ge=0),
    limit: int = Query(100, ge=1, le=500),
    claim_id: Optional[int] = Query(None, description="Filter by claim ID"),
    surveyor_id: Optional[int] = Query(None, description="Filter by surveyor ID"),
    db: Session = Depends(get_db)
):
    """List claim-surveyor assessment links with optional filters."""
    query = db.query(AssessedBy)
    if claim_id is not None:
        query = query.filter(AssessedBy.claim_id == claim_id)
    if surveyor_id is not None:
        query = query.filter(AssessedBy.surveyor_id == surveyor_id)
    return query.offset(skip).limit(limit).all()

@router.get("/{claim_id}/{surveyor_id}", response_model=AssessedByRead)
def get_assessed_by_link(claim_id: int, surveyor_id: int, db: Session = Depends(get_db)):
    """Get a specific claim-surveyor link by composite key."""
    link = db.query(AssessedBy).filter(
        AssessedBy.claim_id == claim_id,
        AssessedBy.surveyor_id == surveyor_id
    ).first()
    if not link:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="AssessedBy record not found")
    return link

@router.post("/", response_model=AssessedByRead, status_code=status.HTTP_201_CREATED)
def create_assessed_by_link(payload: AssessedByCreate, db: Session = Depends(get_db)):
    """Create a new claim assessment link to a surveyor."""
    if not db.query(Claim).filter(Claim.claim_id == payload.claim_id).first():
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=f"Claim {payload.claim_id} does not exist")
    if not db.query(Surveyor).filter(Surveyor.surveyor_id == payload.surveyor_id).first():
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=f"Surveyor {payload.surveyor_id} does not exist")

    link = AssessedBy(**payload.model_dump())
    db.add(link)
    try:
        db.commit()
    except IntegrityError:
        db.rollback()
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"Mapping for claim {payload.claim_id} and surveyor {payload.surveyor_id} already exists"
        )
    db.refresh(link)
    return link

@router.delete("/{claim_id}/{surveyor_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_assessed_by_link(claim_id: int, surveyor_id: int, db: Session = Depends(get_db)):
    """Delete an assessment link between claim and surveyor."""
    link = db.query(AssessedBy).filter(
        AssessedBy.claim_id == claim_id,
        AssessedBy.surveyor_id == surveyor_id
    ).first()
    if not link:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="AssessedBy record not found")
    db.delete(link)
    db.commit()
    return None
