from typing import List
from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy.orm import Session
from app.database import get_db
from app.models import Reinsurer
from app.schemas import ReinsurerCreate, ReinsurerUpdate, ReinsurerRead

router = APIRouter(prefix="/reinsurers", tags=["Reinsurers"])

@router.get("/", response_model=List[ReinsurerRead])
def get_reinsurers(
    skip: int = Query(0, ge=0),
    limit: int = Query(100, ge=1, le=500),
    db: Session = Depends(get_db)
):
    """Retrieve all reinsurers with pagination."""
    return db.query(Reinsurer).offset(skip).limit(limit).all()

@router.get("/{reinsurer_id}", response_model=ReinsurerRead)
def get_reinsurer(reinsurer_id: int, db: Session = Depends(get_db)):
    """Retrieve a single reinsurer by reinsurer_id."""
    reinsurer = db.query(Reinsurer).filter(Reinsurer.reinsurer_id == reinsurer_id).first()
    if not reinsurer:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Reinsurer not found")
    return reinsurer

@router.post("/", response_model=ReinsurerRead, status_code=status.HTTP_201_CREATED)
def create_reinsurer(payload: ReinsurerCreate, db: Session = Depends(get_db)):
    """Create a new reinsurer."""
    reinsurer = Reinsurer(**payload.model_dump())
    db.add(reinsurer)
    db.commit()
    db.refresh(reinsurer)
    return reinsurer

@router.put("/{reinsurer_id}", response_model=ReinsurerRead)
def update_reinsurer(reinsurer_id: int, payload: ReinsurerUpdate, db: Session = Depends(get_db)):
    """Update an existing reinsurer."""
    reinsurer = db.query(Reinsurer).filter(Reinsurer.reinsurer_id == reinsurer_id).first()
    if not reinsurer:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Reinsurer not found")
    
    update_data = payload.model_dump(exclude_unset=True)
    for field, value in update_data.items():
        setattr(reinsurer, field, value)
        
    db.commit()
    db.refresh(reinsurer)
    return reinsurer

@router.delete("/{reinsurer_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_reinsurer(reinsurer_id: int, db: Session = Depends(get_db)):
    """Delete a reinsurer by reinsurer_id."""
    reinsurer = db.query(Reinsurer).filter(Reinsurer.reinsurer_id == reinsurer_id).first()
    if not reinsurer:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Reinsurer not found")
    db.delete(reinsurer)
    db.commit()
    return None
