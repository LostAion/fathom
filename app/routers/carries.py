from typing import List, Optional
from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy.orm import Session
from sqlalchemy.exc import IntegrityError
from app.database import get_db
from app.models import Carries, Voyage, Cargo
from app.schemas import CarriesCreate, CarriesRead

router = APIRouter(prefix="/carries", tags=["Carries (Junction)"])

@router.get("/", response_model=List[CarriesRead])
def get_carries_links(
    skip: int = Query(0, ge=0),
    limit: int = Query(100, ge=1, le=500),
    voyage_id: Optional[int] = Query(None, description="Filter by voyage ID"),
    cargo_id: Optional[int] = Query(None, description="Filter by cargo ID"),
    db: Session = Depends(get_db)
):
    """List voyage-cargo carried relationships with optional filters."""
    query = db.query(Carries)
    if voyage_id is not None:
        query = query.filter(Carries.voyage_id == voyage_id)
    if cargo_id is not None:
        query = query.filter(Carries.cargo_id == cargo_id)
    return query.offset(skip).limit(limit).all()

@router.get("/{voyage_id}/{cargo_id}", response_model=CarriesRead)
def get_carries_link(voyage_id: int, cargo_id: int, db: Session = Depends(get_db)):
    """Get a specific voyage-cargo link by composite key."""
    link = db.query(Carries).filter(
        Carries.voyage_id == voyage_id,
        Carries.cargo_id == cargo_id
    ).first()
    if not link:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Carries record not found")
    return link

@router.post("/", response_model=CarriesRead, status_code=status.HTTP_201_CREATED)
def create_carries_link(payload: CarriesCreate, db: Session = Depends(get_db)):
    """Create a new voyage-cargo relationship."""
    if not db.query(Voyage).filter(Voyage.voyage_id == payload.voyage_id).first():
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=f"Voyage {payload.voyage_id} does not exist")
    if not db.query(Cargo).filter(Cargo.cargo_id == payload.cargo_id).first():
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=f"Cargo {payload.cargo_id} does not exist")

    link = Carries(**payload.model_dump())
    db.add(link)
    try:
        db.commit()
    except IntegrityError:
        db.rollback()
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"Mapping for voyage {payload.voyage_id} and cargo {payload.cargo_id} already exists"
        )
    db.refresh(link)
    return link

@router.delete("/{voyage_id}/{cargo_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_carries_link(voyage_id: int, cargo_id: int, db: Session = Depends(get_db)):
    """Delete a voyage-cargo carried relationship."""
    link = db.query(Carries).filter(
        Carries.voyage_id == voyage_id,
        Carries.cargo_id == cargo_id
    ).first()
    if not link:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Carries record not found")
    db.delete(link)
    db.commit()
    return None
