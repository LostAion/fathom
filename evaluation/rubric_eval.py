from typing import Dict, Any, List
from sqlalchemy.orm import Session
from evaluation.benchmark_dataset import BENCHMARK_CASES
from services.underwriting_engine import underwriting_engine

class UnderwritingEvaluator:
    """
    Evaluates underwriting engine decisions against strict regulatory rubrics:
    1. Sanctions False-Negative Rate (must be 0.0%)
    2. Decision Alignment Accuracy
    3. Score Range & Premium Bounding
    """

    def run_benchmark_evaluation(self, db: Session) -> Dict[str, Any]:
        total_cases = len(BENCHMARK_CASES)
        sanctions_violations = 0
        decision_mismatches = 0
        score_violations = 0
        case_results: List[Dict[str, Any]] = []

        for case in BENCHMARK_CASES:
            res = underwriting_engine.evaluate_risk(
                db=db,
                **case["input"]
            )

            # Check 1: Sanctions zero-tolerance check
            expected_cleared = case["expected_sanctions_cleared"]
            actual_cleared = res["sanctions_cleared"]
            sanctions_pass = (expected_cleared == actual_cleared)
            if not sanctions_pass:
                sanctions_violations += 1

            # Check 2: Decision match
            expected_dec = case["expected_decision"]
            actual_dec = res["decision"]
            decision_pass = (expected_dec == actual_dec)
            if not decision_pass:
                decision_mismatches += 1

            # Check 3: Risk score within reasonable bounds
            score = res["risk_score"]
            score_pass = (case["min_risk_score"] <= score <= case["max_risk_score"])
            if not score_pass:
                score_violations += 1

            overall_case_pass = sanctions_pass and decision_pass and score_pass

            case_results.append({
                "case_id": case["id"],
                "description": case["description"],
                "expected_decision": expected_dec,
                "actual_decision": actual_dec,
                "risk_score": score,
                "sanctions_cleared": actual_cleared,
                "passed": overall_case_pass
            })

        decision_accuracy = ((total_cases - decision_mismatches) / total_cases) * 100.0
        sanctions_compliance = 100.0 if sanctions_violations == 0 else 0.0

        return {
            "total_benchmark_cases": total_cases,
            "decision_accuracy_percent": round(decision_accuracy, 1),
            "sanctions_compliance_percent": sanctions_compliance,
            "sanctions_violations_count": sanctions_violations,
            "score_bounds_violations": score_violations,
            "overall_status": "PASSED" if (sanctions_violations == 0 and decision_accuracy >= 90.0) else "FAILED",
            "cases": case_results
        }

evaluator = UnderwritingEvaluator()
