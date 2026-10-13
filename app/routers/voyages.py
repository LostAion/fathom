from typing import List, Optional
from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy.orm import Session
from app.database import get_db
from app.models import Voyage, Vessel
from app.schemas import VoyageCreate, VoyageUpdate, VoyageRead

router = APIRouter(prefix="/voyages", tags=["Voyages"])

@router.get("/", response_model=List[VoyageRead])
def get_voyages(
    skip: int = Query(0, ge=0),
    limit: int = Query(100, ge=1, le=500),
    vessel_id: Optional[int] = Query(None, description="Filter by vessel ID"),
    db: Session = Depends(get_db)
):
    """Retrieve all voyages with optional vessel filter."""
    query = db.query(Voyage)
    if vessel_id is not None:
        query = query.filter(Voyage.vessel_id == vessel_id)
    return query.offset(skip).limit(limit).all()

@router.get("/{voyage_id}", response_model=VoyageRead)
def get_voyage(voyage_id: int, db: Session = Depends(get_db)):
    """Retrieve a single voyage by voyage_id."""
    voyage = db.query(Voyage).filter(Voyage.voyage_id == voyage_id).first()
    if not voyage:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Voyage not found")
    return voyage

@router.post("/", response_model=VoyageRead, status_code=status.HTTP_201_CREATED)
def create_voyage(payload: VoyageCreate, db: Session = Depends(get_db)):
    """Create a new voyage."""
    if payload.vessel_id is not None:
        vessel = db.query(Vessel).filter(Vessel.vessel_id == payload.vessel_id).first()
        if not vessel:
            raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=f"Vessel with vessel_id {payload.vessel_id} does not exist")

    voyage = Voyage(**payload.model_dump())
    db.add(voyage)
    db.commit()
    db.refresh(voyage)
    return voyage

@router.put("/{voyage_id}", response_model=VoyageRead)
def update_voyage(voyage_id: int, payload: VoyageUpdate, db: Session = Depends(get_db)):
    """Update an existing voyage."""
    voyage = db.query(Voyage).filter(Voyage.voyage_id == voyage_id).first()
    if not voyage:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Voyage not found")

    if payload.vessel_id is not None:
        vessel = db.query(Vessel).filter(Vessel.vessel_id == payload.vessel_id).first()
        if not vessel:
            raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=f"Vessel with vessel_id {payload.vessel_id} does not exist")

    update_data = payload.model_dump(exclude_unset=True)
    for field, value in update_data.items():
        setattr(voyage, field, value)

    db.commit()
    db.refresh(voyage)
    return voyage

@router.delete("/{voyage_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_voyage(voyage_id: int, db: Session = Depends(get_db)):
    """Delete a voyage by voyage_id."""
    voyage = db.query(Voyage).filter(Voyage.voyage_id == voyage_id).first()
    if not voyage:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Voyage not found")
    db.delete(voyage)
    db.commit()
    return None
