from typing import Optional
from fastapi import APIRouter, Depends, Query
from sqlalchemy.orm import Session
from app.database import get_db
from app.schemas_underwriting import UnderwriteAssessRequest
from services.sanctions import sanctions_screener
from services.underwriting_engine import underwriting_engine
from evaluation.rubric_eval import evaluator

router = APIRouter(prefix="/underwriting", tags=["Underwriting Demo"])

@router.post("/assess", summary="Assess Policy Risk and Generate Decision")
def assess_policy_risk(
    payload: UnderwriteAssessRequest,
    db: Session = Depends(get_db)
):
    """
    Automated Marine Underwriting Assessment:
    - Screens local synthetic sanctions fixtures
    - Checks fixed voyage risk corridors (no live AIS feed)
    - Evaluates portfolio loss ratio & vessel claims
    - Retrieves local guideline excerpts using BM25
    - Computes recommended rate & warranties
    """
    return underwriting_engine.evaluate_risk(
        db=db,
        **payload.model_dump()
    )

@router.get("/sanctions-check", summary="Check Local Sanctions Fixtures")
def check_sanctions(
    imo_number: Optional[str] = Query(None, description="Vessel IMO Number"),
    vessel_name: Optional[str] = Query(None, description="Vessel Name"),
    client_name: Optional[str] = Query(None, description="Client / Owner Name")
):
    """Check synthetic coursework sanctions fixtures, not a live sanctions list."""
    return sanctions_screener.screen(
        imo_number=imo_number,
        vessel_name=vessel_name,
        client_name=client_name
    )

@router.post("/evaluate-engine", summary="Run Rubric Benchmark Evaluation Suite")
def run_evaluation(db: Session = Depends(get_db)):
    """Runs synthetic benchmark suite assessing compliance accuracy and underwriting bounds."""
    return evaluator.run_benchmark_evaluation(db=db)
