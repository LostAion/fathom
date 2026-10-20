#!/usr/bin/env python3
"""
DBMS Concurrency Control Demonstration Script
==============================================
Simulates two concurrent transactions attempting to draw from the same Policy Aggregate Limit.

Demonstrates:
  Part 1: The Race Condition (Lost Invariant / Over-allocation due to concurrent uncoordinated reads).
  Part 2: ACID Transaction Serialization using MariaDB InnoDB Row-Level Locking (SELECT ... FOR UPDATE).
"""

import sys
import os
import time
import threading
from decimal import Decimal
from concurrent.futures import ThreadPoolExecutor

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))

from sqlalchemy import func
from app.database import SessionLocal
from app.models import Policy, Claim, Client

GREEN = "\033[92m"
RED = "\033[91m"
YELLOW = "\033[93m"
CYAN = "\033[96m"
BOLD = "\033[1m"
RESET = "\033[0m"

def setup_policy():
    db = SessionLocal()
    client = db.query(Client).first()
    if not client:
        client = Client(name="Demo Marine Shipper", address="100 Commercial Quay")
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
    p_no = policy.policy_no
    db.close()
    return p_no

def run_unsafe_race_condition():
    print(f"\n{BOLD}{YELLOW}========================================================================{RESET}")
    print(f"{BOLD}PART 1: UNLOCKED CONCURRENT TRANSACTIONS (LOST INVARIANT RACE CONDITION){RESET}")
    print(f"{BOLD}{YELLOW}========================================================================{RESET}")

    policy_no = setup_policy()
    print(f"Created Policy #{policy_no} with Aggregate Limit: {CYAN}$100,000.00{RESET}")
    print(f"Two concurrent adjusters submit {YELLOW}$60,000.00{RESET} claims simultaneously.\n")

    barrier = threading.Barrier(2)
    start_time = time.perf_counter()

    def worker(name):
        barrier.wait()
        db = SessionLocal()
        t_start = time.perf_counter() - start_time
        pol = db.query(Policy).filter(Policy.policy_no == policy_no).first()
        paid = db.query(func.coalesce(func.sum(Claim.settled_amount), 0)).filter(
            Claim.policy_no == policy_no,
            Claim.status == "SETTLED"
        ).scalar()
        avail = pol.sum_insured - Decimal(str(paid))
        print(f"  {CYAN}[{name} @ {t_start:.3f}s]{RESET} Unlocked Read: Available aggregate capacity = ${avail:,.2f}")

        # Simulate concurrent processing delay
        time.sleep(0.12)

        if Decimal("60000.00") <= avail:
            cl = Claim(policy_no=policy_no, claim_amount=Decimal("60000.00"), status="SETTLED", settled_amount=Decimal("60000.00"))
            db.add(cl)
            db.commit()
            t_done = time.perf_counter() - start_time
            print(f"  {GREEN}[{name} @ {t_done:.3f}s] APPROVED & COMMITTED $60,000.00 based on initial read!{RESET}")
        else:
            db.rollback()
            print(f"  {RED}[{name}] REJECTED!{RESET}")
        db.close()

    with ThreadPoolExecutor(max_workers=2) as ex:
        f1 = ex.submit(worker, "Thread-1")
        f2 = ex.submit(worker, "Thread-2")
        f1.result()
        f2.result()

    db = SessionLocal()
    total = db.query(func.coalesce(func.sum(Claim.settled_amount), 0)).filter(
        Claim.policy_no == policy_no,
        Claim.status == "SETTLED"
    ).scalar()
    db.close()

    print(f"\n{BOLD}Final Result:{RESET}")
    print(f"  Aggregate Limit: $100,000.00")
    print(f"  Total Payout:    {RED}${total:,.2f}{RESET}")
    if total > 100000.00:
        print(f"  {RED}{BOLD}INVARIANT VIOLATED: Aggregate coverage overdrawn by ${(total - 100000):,.2f}!{RESET}")
        print("  Academic Cause: Concurrent read-modify-write race condition without locking serialization.")

def run_safe_pessimistic_lock():
    print(f"\n{BOLD}{CYAN}========================================================================{RESET}")
    print(f"{BOLD}PART 2: ACID TRANSACTION CONCURRENCY (PESSIMISTIC SELECT ... FOR UPDATE){RESET}")
    print(f"{BOLD}{CYAN}========================================================================{RESET}")

    policy_no = setup_policy()
    print(f"Created Policy #{policy_no} with Aggregate Limit: {CYAN}$100,000.00{RESET}")
    print(f"Two concurrent adjusters submit {YELLOW}$60,000.00{RESET} claims using MariaDB InnoDB row locks.\n")

    barrier = threading.Barrier(2)
    start_time = time.perf_counter()

    def worker(name, hold_duration, start_delay):
        barrier.wait()
        time.sleep(start_delay)
        db = SessionLocal()
        t_req = time.perf_counter() - start_time
        print(f"  {CYAN}[{name} @ {t_req:.3f}s]{RESET} Requesting lock: SELECT ... FOR UPDATE on Policy #{policy_no}")

        # PESSIMISTIC ROW-LEVEL LOCK
        pol = db.query(Policy).filter(Policy.policy_no == policy_no).with_for_update().first()
        t_acq = time.perf_counter() - start_time
        wait_time = t_acq - t_req
        print(f"  {GREEN}[{name} @ {t_acq:.3f}s] ACQUIRED row lock! (Waited {wait_time:.3f}s in lock queue){RESET}")

        time.sleep(hold_duration)

        paid = db.query(func.coalesce(func.sum(Claim.settled_amount), 0)).filter(
            Claim.policy_no == policy_no,
            Claim.status == "SETTLED"
        ).scalar()
        avail = pol.sum_insured - Decimal(str(paid))
        print(f"  {CYAN}[{name} @ {time.perf_counter() - start_time:.3f}s]{RESET} Verified available limit: ${avail:,.2f}")

        if Decimal("60000.00") <= avail:
            cl = Claim(policy_no=policy_no, claim_amount=Decimal("60000.00"), status="SETTLED", settled_amount=Decimal("60000.00"))
            db.add(cl)
            t_pre = time.perf_counter() - start_time
            print(f"  {GREEN}[{name} @ {t_pre:.3f}s] Submitting COMMIT to MariaDB (will release exclusive lock)...{RESET}")
            db.commit()
            t_done = time.perf_counter() - start_time
            print(f"  {GREEN}[{name} @ {t_done:.3f}s] Transaction committed successfully. Lock released.{RESET}")
        else:
            t_pre = time.perf_counter() - start_time
            print(f"  {RED}[{name} @ {t_pre:.3f}s] $60k exceeds available ${avail:,.2f} -> Submitting ROLLBACK...{RESET}")
            db.rollback()
            t_done = time.perf_counter() - start_time
            print(f"  {RED}[{name} @ {t_done:.3f}s] Transaction rolled back. Lock released.{RESET}")
        db.close()

    with ThreadPoolExecutor(max_workers=2) as ex:
        f1 = ex.submit(worker, "Thread-1", 0.20, 0.0)
        f2 = ex.submit(worker, "Thread-2", 0.05, 0.04)
        f1.result()
        f2.result()

    db = SessionLocal()
    total = db.query(func.coalesce(func.sum(Claim.settled_amount), 0)).filter(
        Claim.policy_no == policy_no,
        Claim.status == "SETTLED"
    ).scalar()
    db.close()

    print(f"\n{BOLD}Final Result:{RESET}")
    print(f"  Aggregate Limit: $100,000.00")
    print(f"  Total Payout:    {GREEN}${total:,.2f}{RESET}")
    if total <= 100000.00:
        print(f"  {GREEN}{BOLD}INVARIANT PRESERVED: Aggregate policy limit safely maintained!{RESET}")
        print("  Academic Mechanism: MariaDB InnoDB exclusive row lock serialized the transactions, enforcing consistency.")

if __name__ == "__main__":
    run_unsafe_race_condition()
    run_safe_pessimistic_lock()
