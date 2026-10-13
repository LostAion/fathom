from typing import List
from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy.orm import Session
from app.database import get_db
from app.models import Surveyor
from app.schemas import SurveyorCreate, SurveyorUpdate, SurveyorRead

router = APIRouter(prefix="/surveyors", tags=["Surveyors"])

@router.get("/", response_model=List[SurveyorRead])
def get_surveyors(
    skip: int = Query(0, ge=0),
    limit: int = Query(100, ge=1, le=500),
    db: Session = Depends(get_db)
):
    """Retrieve all surveyors with pagination."""
    return db.query(Surveyor).offset(skip).limit(limit).all()

@router.get("/{surveyor_id}", response_model=SurveyorRead)
def get_surveyor(surveyor_id: int, db: Session = Depends(get_db)):
    """Retrieve a single surveyor by surveyor_id."""
    surveyor = db.query(Surveyor).filter(Surveyor.surveyor_id == surveyor_id).first()
    if not surveyor:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Surveyor not found")
    return surveyor

@router.post("/", response_model=SurveyorRead, status_code=status.HTTP_201_CREATED)
def create_surveyor(payload: SurveyorCreate, db: Session = Depends(get_db)):
    """Create a new surveyor."""
    surveyor = Surveyor(**payload.model_dump())
    db.add(surveyor)
    db.commit()
    db.refresh(surveyor)
    return surveyor

@router.put("/{surveyor_id}", response_model=SurveyorRead)
def update_surveyor(surveyor_id: int, payload: SurveyorUpdate, db: Session = Depends(get_db)):
    """Update an existing surveyor."""
    surveyor = db.query(Surveyor).filter(Surveyor.surveyor_id == surveyor_id).first()
    if not surveyor:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Surveyor not found")
    
    update_data = payload.model_dump(exclude_unset=True)
    for field, value in update_data.items():
        setattr(surveyor, field, value)
        
    db.commit()
    db.refresh(surveyor)
    return surveyor

@router.delete("/{surveyor_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_surveyor(surveyor_id: int, db: Session = Depends(get_db)):
    """Delete a surveyor by surveyor_id."""
    surveyor = db.query(Surveyor).filter(Surveyor.surveyor_id == surveyor_id).first()
    if not surveyor:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Surveyor not found")
    db.delete(surveyor)
    db.commit()
    return None
