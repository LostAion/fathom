from typing import List, Optional
from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy.orm import Session
from sqlalchemy.exc import IntegrityError
from app.database import get_db
from app.models import Underwriter, Department
from app.schemas import UnderwriterCreate, UnderwriterUpdate, UnderwriterRead

router = APIRouter(prefix="/underwriters", tags=["Underwriters"])

@router.get("/", response_model=List[UnderwriterRead])
def get_underwriters(
    skip: int = Query(0, ge=0),
    limit: int = Query(100, ge=1, le=500),
    dept_id: Optional[int] = Query(None, description="Filter by department ID"),
    db: Session = Depends(get_db)
):
    """Retrieve all underwriters with optional department filter."""
    query = db.query(Underwriter)
    if dept_id is not None:
        query = query.filter(Underwriter.dept_id == dept_id)
    return query.offset(skip).limit(limit).all()

@router.get("/{emp_id}", response_model=UnderwriterRead)
def get_underwriter(emp_id: int, db: Session = Depends(get_db)):
    """Retrieve a single underwriter by emp_id."""
    underwriter = db.query(Underwriter).filter(Underwriter.emp_id == emp_id).first()
    if not underwriter:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Underwriter not found")
    return underwriter

@router.post("/", response_model=UnderwriterRead, status_code=status.HTTP_201_CREATED)
def create_underwriter(payload: UnderwriterCreate, db: Session = Depends(get_db)):
    """Create a new underwriter."""
    if payload.dept_id is not None:
        dept = db.query(Department).filter(Department.dept_id == payload.dept_id).first()
        if not dept:
            raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=f"Department with dept_id {payload.dept_id} does not exist")

    underwriter = Underwriter(**payload.model_dump())
    db.add(underwriter)
    db.commit()
    db.refresh(underwriter)
    return underwriter

@router.put("/{emp_id}", response_model=UnderwriterRead)
def update_underwriter(emp_id: int, payload: UnderwriterUpdate, db: Session = Depends(get_db)):
    """Update an existing underwriter."""
    underwriter = db.query(Underwriter).filter(Underwriter.emp_id == emp_id).first()
    if not underwriter:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Underwriter not found")

    if payload.dept_id is not None:
        dept = db.query(Department).filter(Department.dept_id == payload.dept_id).first()
        if not dept:
            raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=f"Department with dept_id {payload.dept_id} does not exist")

    update_data = payload.model_dump(exclude_unset=True)
    for field, value in update_data.items():
        setattr(underwriter, field, value)

    db.commit()
    db.refresh(underwriter)
    return underwriter

@router.delete("/{emp_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_underwriter(emp_id: int, db: Session = Depends(get_db)):
    """Delete an underwriter by emp_id."""
    underwriter = db.query(Underwriter).filter(Underwriter.emp_id == emp_id).first()
    if not underwriter:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Underwriter not found")
    db.delete(underwriter)
    db.commit()
    return None
