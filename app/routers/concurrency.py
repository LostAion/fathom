import time
from decimal import Decimal
from typing import Dict, Any
from concurrent.futures import ThreadPoolExecutor
from fastapi import APIRouter, HTTPException, status
from sqlalchemy.orm import Session
from sqlalchemy import func
from app.database import SessionLocal
from app.models import Policy, Claim, Client

router = APIRouter(prefix="/concurrency", tags=["DBMS Concurrency Demonstrations"])

def _setup_concurrency_policy() -> int:
    """Helper to create a dedicated test policy with $100,000 sum insured."""
    db: Session = SessionLocal()
    try:
        # Check or create test client
        client = db.query(Client).filter(Client.name == "Concurrency Demo Shipper").first()
        if not client:
            client = Client(name="Concurrency Demo Shipper", address="100 Parallel Quay")
            db.add(client)
            db.commit()
            db.refresh(client)

        policy = Policy(
            policy_type="HULL",
            sum_insured=Decimal("100000.00"),
            premium=Decimal("5000.00"),
            status="BOUND",
            deductible=Decimal("0.00"),
            client_id=client.client_id
        )
        db.add(policy)
        db.commit()
        db.refresh(policy)
        return policy.policy_no
    finally:
        db.close()


@router.post("/demo-race-condition", summary="Demonstrate Lost Update / Aggregate Limit Breach (Without Row Locking)")
def demo_race_condition() -> Dict[str, Any]:
    """
    Demonstrates what happens WITHOUT transaction row-locking:
    - Policy has an aggregate limit of $100,000.
    - Two concurrent threads attempt to file and settle $60,000 claims simultaneously.
    - Because neither locks the policy row, both threads read remaining capacity = $100,000.
    - Both threads approve and commit.
    - RESULT: Total claims paid = $120,000 (breaches the $100,000 limit!).
    """
    policy_no = _setup_concurrency_policy()
    claim_amount = Decimal("60000.00")
    thread_logs = []

    def unsafe_worker(thread_id: str):
        db: Session = SessionLocal()
        try:
            # 1. Unsafe read: No row lock (no FOR UPDATE)
            pol = db.query(Policy).filter(Policy.policy_no == policy_no).first()
            current_claims = db.query(func.coalesce(func.sum(Claim.claim_amount), 0)).filter(
                Claim.policy_no == policy_no
            ).scalar()

            remaining = pol.sum_insured - Decimal(str(current_claims))
            thread_logs.append(f"[{thread_id}] Read remaining limit: ${remaining:,.2f}")

            # Simulate processing delay during which race occurs
            time.sleep(0.1)

            if claim_amount <= remaining:
                claim = Claim(
                    policy_no=policy_no,
                    claim_amount=claim_amount,
                    status="SETTLED",
                    settled_amount=claim_amount
                )
                db.add(claim)
                db.commit()
                thread_logs.append(f"[{thread_id}] COMMITTED claim of ${claim_amount:,.2f}")
                return {"thread": thread_id, "status": "APPROVED", "amount": float(claim_amount)}
            else:
                return {"thread": thread_id, "status": "REJECTED_EXCEEDED_LIMIT"}
        finally:
            db.close()

    # Execute both workers concurrently
    with ThreadPoolExecutor(max_workers=2) as executor:
        f1 = executor.submit(unsafe_worker, "Thread-1")
        f2 = executor.submit(unsafe_worker, "Thread-2")
        r1 = f1.result()
        r2 = f2.result()

    # Verify final aggregate total
    verify_db = SessionLocal()
    total_paid = verify_db.query(func.coalesce(func.sum(Claim.claim_amount), 0)).filter(
        Claim.policy_no == policy_no
    ).scalar()
    verify_db.close()

    return {
        "scenario": "RACE_CONDITION_UNSAFE",
        "policy_no": policy_no,
        "policy_sum_insured": 100000.0,
        "thread_results": [r1, r2],
        "total_claims_paid": float(total_paid),
        "anomaly_detected": float(total_paid) > 100000.0,
        "explanation": (
            "Both transactions read the balance before either committed. "
            f"Result: ${float(total_paid):,.2f} paid out on a $100,000 policy. "
            "Financial aggregate limit was breached due to lack of pessimistic locking."
        ),
        "execution_log": thread_logs
    }


@router.post("/demo-safe-transaction", summary="Demonstrate ACID Concurrency Control with Pessimistic Row Locking (FOR UPDATE)")
def demo_safe_transaction() -> Dict[str, Any]:
    """
    Demonstrates proper DBMS Concurrency Control:
    - Policy has an aggregate limit of $100,000.
    - Two concurrent threads attempt to file and settle $60,000 claims simultaneously.
    - Each thread executes: SELECT * FROM POLICY WHERE policy_no = :id FOR UPDATE
    - Thread-1 acquires the X-Lock. Thread-2 is queued and waits until Thread-1 commits.
    - Thread-1 approves $60,000 and commits.
    - Thread-2 resumes, reads updated remaining balance ($40,000), sees $60,000 > $40,000,
      and aborts/rolls back.
    - RESULT: Total claims paid = $60,000 <= $100,000 (Consistent state preserved!).
    """
    policy_no = _setup_concurrency_policy()
    claim_amount = Decimal("60000.00")
    thread_logs = []

    def safe_worker(thread_id: str):
        db: Session = SessionLocal()
        try:
            # PESSIMISTIC LOCK: with_for_update() issues SELECT ... FOR UPDATE
            # MariaDB acquires an exclusive row-level lock
            thread_logs.append(f"[{thread_id}] Requesting exclusive lock (SELECT ... FOR UPDATE)...")
            pol = db.query(Policy).filter(Policy.policy_no == policy_no).with_for_update().first()
            thread_logs.append(f"[{thread_id}] ACQUIRED lock on Policy #{policy_no}")

            current_claims = db.query(func.coalesce(func.sum(Claim.claim_amount), 0)).filter(
                Claim.policy_no == policy_no
            ).scalar()

            remaining = pol.sum_insured - Decimal(str(current_claims))
            thread_logs.append(f"[{thread_id}] Remaining available limit: ${remaining:,.2f}")

            # Brief simulation delay while holding lock
            time.sleep(0.1)

            if claim_amount <= remaining:
                claim = Claim(
                    policy_no=policy_no,
                    claim_amount=claim_amount,
                    status="SETTLED",
                    settled_amount=claim_amount
                )
                db.add(claim)
                db.commit() # Releases the row lock
                thread_logs.append(f"[{thread_id}] COMMITTED claim of ${claim_amount:,.2f} and released lock")
                return {"thread": thread_id, "status": "APPROVED", "amount": float(claim_amount)}
            else:
                db.rollback() # Release lock on failure
                thread_logs.append(f"[{thread_id}] INSUFFICIENT LIMIT (${claim_amount:,.2f} > ${remaining:,.2f}) - ROLLED BACK")
                return {
                    "thread": thread_id,
                    "status": "REJECTED_CONCURRENCY_LIMIT",
                    "reason": f"Requested ${float(claim_amount):,.2f} exceeds remaining ${float(remaining):,.2f}"
                }
        finally:
            db.close()

    # Execute both workers concurrently
    with ThreadPoolExecutor(max_workers=2) as executor:
        f1 = executor.submit(safe_worker, "Thread-1")
        f2 = executor.submit(safe_worker, "Thread-2")
        r1 = f1.result()
        r2 = f2.result()

    # Verify final aggregate total
    verify_db = SessionLocal()
    total_paid = verify_db.query(func.coalesce(func.sum(Claim.claim_amount), 0)).filter(
        Claim.policy_no == policy_no
    ).scalar()
    verify_db.close()

    return {
        "scenario": "PESSIMISTIC_LOCK_SAFE",
        "policy_no": policy_no,
        "policy_sum_insured": 100000.0,
        "thread_results": [r1, r2],
        "total_claims_paid": float(total_paid),
        "acid_safety_preserved": float(total_paid) <= 100000.0,
        "explanation": (
            "Exclusive row-level locking (SELECT ... FOR UPDATE) serialized the concurrent transactions. "
            f"Thread-1 completed first. Thread-2 was blocked, observed the remaining balance, "
            "and safely aborted, preventing over-payment."
        ),
        "execution_log": thread_logs
    }
