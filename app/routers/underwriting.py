from typing import Optional
from fastapi import APIRouter, Depends, Query, status
from sqlalchemy.orm import Session
from app.database import get_db
from app.schemas_underwriting import UnderwriteAssessRequest, SanctionsCheckRequest
from services.sanctions import sanctions_screener
from services.underwriting_engine import underwriting_engine
from evaluation.rubric_eval import evaluator

router = APIRouter(prefix="/underwriting", tags=["Automated Underwriting & RAG"])

@router.post("/assess", summary="Assess Policy Risk and Generate Decision")
def assess_policy_risk(
    payload: UnderwriteAssessRequest,
    db: Session = Depends(get_db)
):
    """
    Automated Marine Underwriting Assessment:
    - Runs OFAC SDN sanctions screening
    - Checks voyage AIS / JWC high-risk corridors
    - Evaluates portfolio loss ratio & vessel claims
    - Retrieves RAG clauses from underwriting guidelines
    - Computes recommended rate & warranties
    """
    return underwriting_engine.evaluate_risk(
        db=db,
        **payload.model_dump()
    )

@router.get("/sanctions-check", summary="Direct OFAC SDN Compliance Screening")
def check_sanctions(
    imo_number: Optional[str] = Query(None, description="Vessel IMO Number"),
    vessel_name: Optional[str] = Query(None, description="Vessel Name"),
    client_name: Optional[str] = Query(None, description="Client / Owner Name")
):
    """Fast compliance check against OFAC SDN maritime sanctioned vessels & entities."""
    return sanctions_screener.screen(
        imo_number=imo_number,
        vessel_name=vessel_name,
        client_name=client_name
    )

@router.post("/evaluate-engine", summary="Run Rubric Benchmark Evaluation Suite")
def run_evaluation(db: Session = Depends(get_db)):
    """Runs synthetic benchmark suite assessing compliance accuracy and underwriting bounds."""
    return evaluator.run_benchmark_evaluation(db=db)
