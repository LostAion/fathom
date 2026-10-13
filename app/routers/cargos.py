from typing import List
from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy.orm import Session
from app.database import get_db
from app.models import Cargo
from app.schemas import CargoCreate, CargoUpdate, CargoRead

router = APIRouter(prefix="/cargos", tags=["Cargos"])

@router.get("/", response_model=List[CargoRead])
def get_cargos(
    skip: int = Query(0, ge=0),
    limit: int = Query(100, ge=1, le=500),
    db: Session = Depends(get_db)
):
    """Retrieve all cargos with pagination."""
    return db.query(Cargo).offset(skip).limit(limit).all()

@router.get("/{cargo_id}", response_model=CargoRead)
def get_cargo(cargo_id: int, db: Session = Depends(get_db)):
    """Retrieve a single cargo by cargo_id."""
    cargo = db.query(Cargo).filter(Cargo.cargo_id == cargo_id).first()
    if not cargo:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Cargo not found")
    return cargo

@router.post("/", response_model=CargoRead, status_code=status.HTTP_201_CREATED)
def create_cargo(payload: CargoCreate, db: Session = Depends(get_db)):
    """Create a new cargo entry."""
    cargo = Cargo(**payload.model_dump())
    db.add(cargo)
    db.commit()
    db.refresh(cargo)
    return cargo

@router.put("/{cargo_id}", response_model=CargoRead)
def update_cargo(cargo_id: int, payload: CargoUpdate, db: Session = Depends(get_db)):
    """Update an existing cargo entry."""
    cargo = db.query(Cargo).filter(Cargo.cargo_id == cargo_id).first()
    if not cargo:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Cargo not found")
    
    update_data = payload.model_dump(exclude_unset=True)
    for field, value in update_data.items():
        setattr(cargo, field, value)
        
    db.commit()
    db.refresh(cargo)
    return cargo

@router.delete("/{cargo_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_cargo(cargo_id: int, db: Session = Depends(get_db)):
    """Delete a cargo entry by cargo_id."""
    cargo = db.query(Cargo).filter(Cargo.cargo_id == cargo_id).first()
    if not cargo:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Cargo not found")
    db.delete(cargo)
    db.commit()
    return None
