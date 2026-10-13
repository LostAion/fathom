from typing import List
from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy.orm import Session
from sqlalchemy.exc import IntegrityError
from app.database import get_db
from app.models import Vessel
from app.schemas import VesselCreate, VesselUpdate, VesselRead

router = APIRouter(prefix="/vessels", tags=["Vessels"])

@router.get("/", response_model=List[VesselRead])
def get_vessels(
    skip: int = Query(0, ge=0),
    limit: int = Query(100, ge=1, le=500),
    db: Session = Depends(get_db)
):
    """Retrieve all vessels with pagination."""
    return db.query(Vessel).offset(skip).limit(limit).all()

@router.get("/{vessel_id}", response_model=VesselRead)
def get_vessel(vessel_id: int, db: Session = Depends(get_db)):
    """Retrieve a single vessel by vessel_id."""
    vessel = db.query(Vessel).filter(Vessel.vessel_id == vessel_id).first()
    if not vessel:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Vessel not found")
    return vessel

@router.post("/", response_model=VesselRead, status_code=status.HTTP_201_CREATED)
def create_vessel(payload: VesselCreate, db: Session = Depends(get_db)):
    """Create a new vessel."""
    vessel = Vessel(**payload.model_dump())
    db.add(vessel)
    try:
        db.commit()
    except IntegrityError:
        db.rollback()
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"Vessel with imo_number '{payload.imo_number}' already exists"
        )
    db.refresh(vessel)
    return vessel

@router.put("/{vessel_id}", response_model=VesselRead)
def update_vessel(vessel_id: int, payload: VesselUpdate, db: Session = Depends(get_db)):
    """Update an existing vessel."""
    vessel = db.query(Vessel).filter(Vessel.vessel_id == vessel_id).first()
    if not vessel:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Vessel not found")
    
    update_data = payload.model_dump(exclude_unset=True)
    for field, value in update_data.items():
        setattr(vessel, field, value)
        
    try:
        db.commit()
    except IntegrityError:
        db.rollback()
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Update failed: imo_number must be unique"
        )
    db.refresh(vessel)
    return vessel

@router.delete("/{vessel_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_vessel(vessel_id: int, db: Session = Depends(get_db)):
    """Delete a vessel by vessel_id."""
    vessel = db.query(Vessel).filter(Vessel.vessel_id == vessel_id).first()
    if not vessel:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Vessel not found")
    db.delete(vessel)
    db.commit()
    return None
