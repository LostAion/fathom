from decimal import Decimal
from typing import Dict, Any
from sqlalchemy.orm import Session
from sqlalchemy import func
from app.models import Client, Policy, Claim, Vessel

class ClaimsHistoryService:
    """
    Computes internal portfolio loss ratio and past casualty records from MariaDB.
    """

    def analyze_client_exposure(self, db: Session, client_id: int) -> Dict[str, Any]:
        if not client_id:
            return {"loss_ratio": 0.0, "total_claims": 0.0, "total_premium": 0.0, "status": "NO_HISTORY"}

        # Total premium paid by client across all past policies
        premium_sum = db.query(func.coalesce(func.sum(Policy.premium), 0)).filter(
            Policy.client_id == client_id,
            Policy.status.in_(["BOUND", "ACTIVE", "CANCELLED"])
        ).scalar() or Decimal(0)

        # Total claims incurred under all policies of this client
        from sqlalchemy import case

        incurred = case((Claim.status == "SETTLED", Claim.settled_amount), else_=Claim.claim_amount)
        claims_sum = db.query(func.coalesce(func.sum(incurred), 0)).join(
            Policy, Policy.policy_no == Claim.policy_no
        ).filter(
            Policy.client_id == client_id,
            Policy.status.in_(["BOUND", "ACTIVE", "CANCELLED"]),
            Claim.status != "REJECTED"
        ).scalar() or Decimal(0)

        claims_count = db.query(func.count(Claim.claim_id)).join(
            Policy, Policy.policy_no == Claim.policy_no
        ).filter(
            Policy.client_id == client_id,
            Policy.status.in_(["BOUND", "ACTIVE", "CANCELLED"]),
            Claim.status != "REJECTED"
        ).scalar() or 0

        p_float = float(premium_sum)
        c_float = float(claims_sum)

        if p_float > 0:
            loss_ratio = (c_float / p_float) * 100.0
        else:
            loss_ratio = 0.0 if c_float == 0 else 100.0

        if loss_ratio > 100.0:
            rating = "DEFICIT_HIGH_RISK"
        elif loss_ratio > 70.0:
            rating = "ELEVATED_LOSS_RECORD"
        elif loss_ratio > 40.0:
            rating = "ACCEPTABLE"
        else:
            rating = "EXCELLENT"

        return {
            "client_id": client_id,
            "total_premium_paid": p_float,
            "total_claims_incurred": c_float,
            "claims_count": claims_count,
            "loss_ratio_percent": round(loss_ratio, 2),
            "performance_rating": rating
        }

    def analyze_vessel_casualty_history(self, db: Session, vessel_id: int) -> Dict[str, Any]:
        if not vessel_id:
            return {"casualty_count": 0, "total_damage": 0.0, "status": "UNKNOWN_VESSEL"}

        claims = db.query(Claim).join(
            Policy, Policy.policy_no == Claim.policy_no
        ).filter(
            Policy.vessel_id == vessel_id,
            Claim.status != "REJECTED"
        ).all()

        total_damage = sum(float(c.claim_amount or 0) for c in claims)
        count = len(claims)

        return {
            "vessel_id": vessel_id,
            "casualty_count": count,
            "total_casualty_cost": total_damage,
            "clean_record": count == 0
        }

claims_history_service = ClaimsHistoryService()
