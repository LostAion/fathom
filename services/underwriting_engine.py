import os
from typing import Dict, Any, List
from sqlalchemy.orm import Session
from app.models import Client, Vessel, Voyage, Cargo

from services.sanctions import sanctions_screener
from services.ais_tracker import ais_tracker
from services.claims_history import claims_history_service
from rag.vector_store import vector_store

class UnderwritingDecisionEngine:
    """
    Synthesizes rule guardrails, sanctions screening, AIS tracking,
    claims loss ratios, and RAG guidelines into an actionable underwriting decision.
    """

    def evaluate_risk(
        self,
        db: Session,
        policy_type: str,
        sum_insured: float,
        premium: float = None,
        client_id: int = None,
        vessel_id: int = None,
        voyage_id: int = None,
        cargo_id: int = None,
        vessel_age: int = 10,
        imo_number: str = None,
        vessel_name: str = None,
        client_name: str = None,
        origin_port: str = None,
        dest_port: str = None
    ) -> Dict[str, Any]:

        # Database identities take precedence over user-supplied display names.
        from fastapi import HTTPException

        for model, key in ((Client, client_id), (Vessel, vessel_id), (Voyage, voyage_id), (Cargo, cargo_id)):
            if key is not None and db.get(model, key) is None:
                raise HTTPException(status_code=400, detail=f"{model.__name__} {key} does not exist")
        if client_id is not None:
            client_name = db.get(Client, client_id).name
        if vessel_id is not None:
            vessel = db.get(Vessel, vessel_id)
            imo_number, vessel_name = vessel.imo_number, vessel.name
        if voyage_id is not None:
            voyage = db.get(Voyage, voyage_id)
            if vessel_id is not None and voyage.vessel_id != vessel_id:
                raise HTTPException(status_code=400, detail="Voyage must belong to the selected vessel")
            origin_port, dest_port = voyage.origin_port, voyage.dest_port

        # 2. Compliance / Sanctions Check (Hard Guardrail)
        sanctions_res = sanctions_screener.screen(
            imo_number=imo_number,
            vessel_name=vessel_name,
            client_name=client_name
        )

        if sanctions_res["is_sanctioned"]:
            return {
                "decision": "DECLINE",
                "risk_score": 100,
                "sanctions_cleared": False,
                "sanctions_matches": sanctions_res["matches"],
                "risk_factors": ["Target matches the local demonstration sanctions list."],
                "base_rate_percent": 0.0,
                "recommended_premium": 0.0,
                "warranties_required": ["Binding blocked by the demonstration sanctions rule."],
                "retrieved_guidelines": [],
                "summary": "Application declined due to a match in the local demonstration sanctions list."
            }

        # 3. AIS & Navigational Corridor Check
        ais_res = ais_tracker.assess_voyage_route(origin_port=origin_port, dest_port=dest_port)

        # 4. Claims History & Loss Ratio Check
        history_res = claims_history_service.analyze_client_exposure(db, client_id=client_id) if client_id else {}
        vessel_hist = claims_history_service.analyze_vessel_casualty_history(db, vessel_id=vessel_id) if vessel_id else {}

        # 5. RAG Guideline Retrieval
        rag_query = f"{policy_type} policy vessel age {vessel_age} voyage {origin_port or ''} to {dest_port or ''}"
        guideline_matches = []
        try:
            guideline_matches = vector_store.retrieve_guidelines(rag_query, n_results=3)
        except OSError:
            # Missing local guideline files do not change the deterministic decision.
            pass

        # 6. Deterministic Risk Scoring & Premium Loading Calculation
        risk_score = 20 # baseline low risk
        risk_factors: List[str] = []
        if not origin_port or not dest_port:
            risk_factors.append("Voyage not supplied; route hazards were not assessed.")
        warranties: List[str] = ["Standard Institute Clauses apply."]
        base_rate_percent = 0.50 # 0.50% base rate

        # Vessel Age loading
        if vessel_age > 25:
            risk_score += 50
            risk_factors.append(f"Vessel age ({vessel_age} yrs) exceeds standard 25yr market limit.")
            base_rate_percent += 0.40
            warranties.append("Warranted IACS structural condition survey within 30 days.")
        elif vessel_age >= 20:
            risk_score += 25
            risk_factors.append(f"Vessel age ({vessel_age} yrs) in elevated 20-25yr tier.")
            base_rate_percent += 0.20
            warranties.append("Warranted valid Class Maintenance Certificate without outstanding items.")
        elif vessel_age >= 15:
            risk_score += 10
            base_rate_percent += 0.10

        # Navigational Hazard loading
        if ais_res.get("has_danger_exposure"):
            risk_score += 30
            for z in ais_res.get("zones", []):
                risk_factors.append(f"Transit exposure: {z['zone_name']} ({z['risk_level']}) - {z['reason']}")
            base_rate_percent += ais_res.get("total_awrp_surcharge_percent", 0.0)
            warranties.append(ais_res.get("warranty_recommended"))

        # Client Loss Ratio loading
        lr = history_res.get("loss_ratio_percent", 0.0)
        if lr > 100.0:
            risk_score += 25
            risk_factors.append(f"Client historical loss ratio is severe ({lr}%).")
            base_rate_percent += 0.25
            warranties.append("Warranted deductible increased by 100%.")
        elif lr > 70.0:
            risk_score += 15
            risk_factors.append(f"Client historical loss ratio is elevated ({lr}%).")
            base_rate_percent += 0.15

        # Vessel past accidents
        cas_count = vessel_hist.get("casualty_count", 0)
        if cas_count >= 2:
            risk_score += 20
            risk_factors.append(f"Vessel has {cas_count} prior casualty claims on record.")

        risk_score = min(risk_score, 100)

        # Final decision categorization
        if risk_score >= 65:
            decision = "REFER_TO_SENIOR"
        elif risk_score >= 45:
            decision = "APPROVE_WITH_CONDITIONS"
        else:
            decision = "APPROVE"


        rec_premium = round(sum_insured * (base_rate_percent / 100.0), 2)

        return {
            "decision": decision,
            "risk_score": risk_score,
            "sanctions_cleared": True,
            "base_rate_percent": round(base_rate_percent, 3),
            "recommended_premium": rec_premium,
            "risk_factors": risk_factors,
            "warranties_required": warranties,
            "loss_ratio_data": history_res,
            "ais_voyage_data": ais_res,
            "retrieved_guidelines": [
                {"title": g.get("metadata", {}).get("source", ""), "excerpt": g.get("content", "")[:200]}
                for g in guideline_matches
            ],
            "summary": f"Application rated with risk score {risk_score}/100. Outcome: {decision}."
        }

underwriting_engine = UnderwritingDecisionEngine()
