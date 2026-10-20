import time
import threading
from decimal import Decimal
from typing import Dict, Any, List
from concurrent.futures import ThreadPoolExecutor
from fastapi import APIRouter
from sqlalchemy.orm import Session
from sqlalchemy import func
from app.database import SessionLocal
from app.models import Policy, Claim, Client

router = APIRouter(prefix="/concurrency", tags=["DBMS Concurrency Demonstrations"])

def _setup_concurrency_policy() -> int:
    """Helper to create a dedicated test policy with $100,000 aggregate limit."""
    db: Session = SessionLocal()
    try:
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


@router.post("/demo-race-condition", summary="Demonstrate Lost Invariant / Over-Allocation Race Condition (Without Row Locking)")
def demo_race_condition() -> Dict[str, Any]:
    """
    Demonstrates an Over-Allocation Race Condition (Lost Invariant):
    - Policy has an aggregate coverage limit of $100,000.
    - Two concurrent adjusters attempt to settle $60,000 claims simultaneously.
    - Both transactions execute concurrent non-locking reads: both read initial paid = $0, remaining = $100,000.
    - Both independently approve and commit their $60,000 claims.
    - RESULT: Total claims settled = $120,000, violating the $100,000 aggregate limit invariant.
    """
    policy_no = _setup_concurrency_policy()
    claim_amount = Decimal("60000.00")
    thread_logs: List[str] = []
    barrier = threading.Barrier(2)
    start_time = time.perf_counter()

    def unsafe_worker(thread_id: str):
        barrier.wait()
        db: Session = SessionLocal()
        try:
            t_now = time.perf_counter() - start_time
            # Unlocked snapshot read
            pol = db.query(Policy).filter(Policy.policy_no == policy_no).first()
            current_claims = db.query(func.coalesce(func.sum(Claim.settled_amount), 0)).filter(
                Claim.policy_no == policy_no,
                Claim.status == "SETTLED"
            ).scalar()

            remaining = pol.sum_insured - Decimal(str(current_claims))
            thread_logs.append(f"[{thread_id} @ {t_now:.3f}s] Non-locking read: Remaining aggregate capacity = ${remaining:,.2f}")

            # Simulate overlapping processing window
            time.sleep(0.12)

            if claim_amount <= remaining:
                claim = Claim(
                    policy_no=policy_no,
                    claim_amount=claim_amount,
                    status="SETTLED",
                    settled_amount=claim_amount
                )
                db.add(claim)
                db.commit()
                t_done = time.perf_counter() - start_time
                thread_logs.append(f"[{thread_id} @ {t_done:.3f}s] COMMITTED $60,000.00 payout based on stale read.")
                return {"thread": thread_id, "status": "APPROVED", "amount": float(claim_amount)}
            else:
                db.rollback()
                return {"thread": thread_id, "status": "REJECTED_EXCEEDED_LIMIT"}
        finally:
            db.close()

    with ThreadPoolExecutor(max_workers=2) as executor:
        f1 = executor.submit(unsafe_worker, "Thread-1")
        f2 = executor.submit(unsafe_worker, "Thread-2")
        r1 = f1.result()
        r2 = f2.result()

    verify_db = SessionLocal()
    total_paid = verify_db.query(func.coalesce(func.sum(Claim.settled_amount), 0)).filter(
        Claim.policy_no == policy_no,
        Claim.status == "SETTLED"
    ).scalar()
    verify_db.close()

    return {
        "scenario": "RACE_CONDITION_UNSAFE",
        "policy_no": policy_no,
        "policy_aggregate_limit": 100000.0,
        "thread_results": [r1, r2],
        "total_claims_paid": float(total_paid),
        "invariant_violated": float(total_paid) > 100000.0,
        "academic_root_cause": (
            "Concurrent read-modify-write race condition: Both transactions read the same initial "
            "remaining limit before either committed. Each independently verified that $60,000 <= $100,000, "
            f"resulting in an over-allocation of ${float(total_paid):,.2f} on a $100,000 aggregate limit. "
            "The database failed to preserve the aggregate coverage invariant because no serialization was enforced."
        ),
        "execution_log": thread_logs
    }


@router.post("/demo-safe-transaction", summary="Demonstrate ACID Concurrency Control with Pessimistic Row Locking (SELECT ... FOR UPDATE)")
def demo_safe_transaction() -> Dict[str, Any]:
    """
    Demonstrates ACID Concurrency Control preserving the Aggregate Limit Invariant:
    - Policy has an aggregate coverage limit of $100,000.
    - Two concurrent adjusters attempt to settle $60,000 claims simultaneously.
    - Both execute: SELECT * FROM POLICY WHERE policy_no = :id FOR UPDATE
    - MariaDB's InnoDB engine grants the exclusive X-Lock to Thread-1.
    - Thread-2 is queued and blocked at the database engine level.
    - Thread-1 commits its $60,000 claim and releases the lock.
    - Thread-2 unblocks, acquires the lock, reads remaining capacity = $40,000.
    - Thread-2 detects that $60,000 exceeds $40,000, aborts, and executes a clean ROLLBACK.
    - RESULT: Total claims paid = $60,000 <= $100,000 (Aggregate Invariant Preserved).
    """
    policy_no = _setup_concurrency_policy()
    claim_amount = Decimal("60000.00")
    thread_logs: List[str] = []
    start_time = time.perf_counter()
    barrier = threading.Barrier(2)

    def safe_worker(thread_id: str, hold_duration: float, start_delay: float):
        barrier.wait()
        time.sleep(start_delay)
        db: Session = SessionLocal()
        try:
            t_req = time.perf_counter() - start_time
            thread_logs.append(f"[{thread_id} @ {t_req:.3f}s] Requesting exclusive lock: SELECT ... FOR UPDATE")

            # InnoDB row-level lock
            pol = db.query(Policy).filter(Policy.policy_no == policy_no).with_for_update().first()
            t_acq = time.perf_counter() - start_time
            wait_time = t_acq - t_req
            thread_logs.append(f"[{thread_id} @ {t_acq:.3f}s] ACQUIRED row lock on Policy #{policy_no} (Waited {wait_time:.3f}s in lock queue)")

            time.sleep(hold_duration)

            current_claims = db.query(func.coalesce(func.sum(Claim.settled_amount), 0)).filter(
                Claim.policy_no == policy_no,
                Claim.status == "SETTLED"
            ).scalar()

            remaining = pol.sum_insured - Decimal(str(current_claims))
            thread_logs.append(f"[{thread_id} @ {time.perf_counter() - start_time:.3f}s] Verified remaining aggregate limit: ${remaining:,.2f}")

            if claim_amount <= remaining:
                claim = Claim(
                    policy_no=policy_no,
                    claim_amount=claim_amount,
                    status="SETTLED",
                    settled_amount=claim_amount
                )
                db.add(claim)
                t_pre_commit = time.perf_counter() - start_time
                thread_logs.append(f"[{thread_id} @ {t_pre_commit:.3f}s] Submitting COMMIT to MariaDB (will release exclusive lock)...")
                db.commit()
                t_post_commit = time.perf_counter() - start_time
                thread_logs.append(f"[{thread_id} @ {t_post_commit:.3f}s] Transaction committed successfully. Lock released.")
                return {"thread": thread_id, "status": "APPROVED", "amount": float(claim_amount)}
            else:
                t_pre_abort = time.perf_counter() - start_time
                thread_logs.append(f"[{thread_id} @ {t_pre_abort:.3f}s] Exceeds aggregate limit ($60k > ${remaining:,.2f}) -> Submitting ROLLBACK...")
                db.rollback()
                t_post_abort = time.perf_counter() - start_time
                thread_logs.append(f"[{thread_id} @ {t_post_abort:.3f}s] Transaction rolled back. Lock released.")
                return {
                    "thread": thread_id,
                    "status": "REJECTED_CONCURRENCY_LIMIT",
                    "reason": f"Requested ${float(claim_amount):,.2f} exceeds available ${float(remaining):,.2f}"
                }
        finally:
            db.close()

    with ThreadPoolExecutor(max_workers=2) as executor:
        f1 = executor.submit(safe_worker, "Thread-1", 0.20, 0.0)
        f2 = executor.submit(safe_worker, "Thread-2", 0.05, 0.04)
        r1 = f1.result()
        r2 = f2.result()

    verify_db = SessionLocal()
    total_paid = verify_db.query(func.coalesce(func.sum(Claim.settled_amount), 0)).filter(
        Claim.policy_no == policy_no,
        Claim.status == "SETTLED"
    ).scalar()
    verify_db.close()

    return {
        "scenario": "PESSIMISTIC_LOCK_SAFE",
        "policy_no": policy_no,
        "policy_aggregate_limit": 100000.0,
        "thread_results": [r1, r2],
        "total_claims_paid": float(total_paid),
        "invariant_preserved": float(total_paid) <= 100000.0,
        "academic_mechanism": (
            "InnoDB row-level exclusive locking (SELECT ... FOR UPDATE) serialized the concurrent transactions. "
            "Thread-2 was queued and blocked at the database engine level until Thread-1 committed. "
            "Upon acquiring the lock, Thread-2 observed the updated committed state ($40,000 remaining) and "
            "aborted via ROLLBACK, preserving the aggregate coverage invariant."
        ),
        "execution_log": thread_logs
    }
