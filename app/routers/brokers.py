from typing import List
from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy.orm import Session
from sqlalchemy.exc import IntegrityError
from app.database import get_db
from app.models import Broker
from app.schemas import BrokerCreate, BrokerUpdate, BrokerRead

router = APIRouter(prefix="/brokers", tags=["Brokers"])

@router.get("/", response_model=List[BrokerRead])
def get_brokers(
    skip: int = Query(0, ge=0),
    limit: int = Query(100, ge=1, le=500),
    db: Session = Depends(get_db)
):
    """Retrieve all brokers with pagination."""
    return db.query(Broker).offset(skip).limit(limit).all()

@router.get("/{broker_id}", response_model=BrokerRead)
def get_broker(broker_id: int, db: Session = Depends(get_db)):
    """Retrieve a broker by broker_id."""
    broker = db.query(Broker).filter(Broker.broker_id == broker_id).first()
    if not broker:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Broker not found")
    return broker

@router.post("/", response_model=BrokerRead, status_code=status.HTTP_201_CREATED)
def create_broker(payload: BrokerCreate, db: Session = Depends(get_db)):
    """Create a new broker."""
    broker = Broker(**payload.model_dump())
    db.add(broker)
    try:
        db.commit()
    except IntegrityError:
        db.rollback()
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"Broker with licence_no '{payload.licence_no}' already exists"
        )
    db.refresh(broker)
    return broker

@router.put("/{broker_id}", response_model=BrokerRead)
def update_broker(broker_id: int, payload: BrokerUpdate, db: Session = Depends(get_db)):
    """Update an existing broker."""
    broker = db.query(Broker).filter(Broker.broker_id == broker_id).first()
    if not broker:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Broker not found")
    
    update_data = payload.model_dump(exclude_unset=True)
    for field, value in update_data.items():
        setattr(broker, field, value)
        
    try:
        db.commit()
    except IntegrityError:
        db.rollback()
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Update failed: licence_no must be unique"
        )
    db.refresh(broker)
    return broker

@router.delete("/{broker_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_broker(broker_id: int, db: Session = Depends(get_db)):
    """Delete a broker by broker_id."""
    broker = db.query(Broker).filter(Broker.broker_id == broker_id).first()
    if not broker:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Broker not found")
    db.delete(broker)
    db.commit()
    return None
