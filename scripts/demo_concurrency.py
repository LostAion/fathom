#!/usr/bin/env python3
"""
DBMS Concurrency Control Demonstration Script
==============================================
Simulates two concurrent transactions attempting to draw from the same Policy Sum Insured.

Demonstrates:
  Part 1: The Race Condition (Lost Update / Limit Breach without row locks).
  Part 2: ACID Transaction Serialization using MariaDB Row-Level Locking (SELECT ... FOR UPDATE).
"""

import sys
import os
import time
from decimal import Decimal
from concurrent.futures import ThreadPoolExecutor

# Add parent directory to path
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
    print(f"\n{BOLD}{YELLOW}=================================================================={RESET}")
    print(f"{BOLD}PART 1: UNLOCKED CONCURRENT TRANSACTIONS (RACE CONDITION / ANOMALY){RESET}")
    print(f"{BOLD}{YELLOW}=================================================================={RESET}")
    
    policy_no = setup_policy()
    print(f"Created Policy #{policy_no} with Sum Insured: {CYAN}$100,000.00{RESET}")
    print(f"Two concurrent adjusters submit {YELLOW}$60,000.00{RESET} claims simultaneously.\n")

    def worker(name):
        db = SessionLocal()
        pol = db.query(Policy).filter(Policy.policy_no == policy_no).first()
        paid = db.query(func.coalesce(func.sum(Claim.claim_amount), 0)).filter(
            Claim.policy_no == policy_no
        ).scalar()
        avail = pol.sum_insured - Decimal(str(paid))
        print(f"  {CYAN}[{name}]{RESET} Read available limit: ${avail:,.2f}")

        # Simulate concurrent processing delay
        time.sleep(0.15)

        if Decimal("60000.00") <= avail:
            cl = Claim(policy_no=policy_no, claim_amount=Decimal("60000.00"), status="SETTLED")
            db.add(cl)
            db.commit()
            print(f"  {GREEN}[{name}] APPROVED & COMMITTED $60,000.00 claim!{RESET}")
        else:
            print(f"  {RED}[{name}] REJECTED!{RESET}")
        db.close()

    with ThreadPoolExecutor(max_workers=2) as ex:
        f1 = ex.submit(worker, "Thread-1")
        f2 = ex.submit(worker, "Thread-2")
        f1.result()
        f2.result()

    db = SessionLocal()
    total = db.query(func.coalesce(func.sum(Claim.claim_amount), 0)).filter(
        Claim.policy_no == policy_no
    ).scalar()
    db.close()

    print(f"\n{BOLD}Final Result:{RESET}")
    print(f"  Policy Limit:    $100,000.00")
    print(f"  Total Payout:    {RED}${total:,.2f}{RESET}")
    if total > 100000.00:
        print(f"  {RED}{BOLD}ANOMALY DETECTED: Over-payment breach of ${(total - 100000):,.2f}!{RESET}")
        print("  Cause: Dirty/Non-repeatable read without pessimistic locking.")

def run_safe_pessimistic_lock():
    print(f"\n{BOLD}{CYAN}=================================================================={RESET}")
    print(f"{BOLD}PART 2: ACID TRANSACTION CONCURRENCY (PESSIMISTIC FOR UPDATE LOCK){RESET}")
    print(f"{BOLD}{CYAN}=================================================================={RESET}")

    policy_no = setup_policy()
    print(f"Created Policy #{policy_no} with Sum Insured: {CYAN}$100,000.00{RESET}")
    print(f"Two concurrent adjusters submit {YELLOW}$60,000.00{RESET} claims using MariaDB row locks.\n")

    def worker(name):
        db = SessionLocal()
        print(f"  {CYAN}[{name}]{RESET} Executing: SELECT ... FOR UPDATE (Requesting exclusive lock)")
        
        # PESSIMISTIC ROW-LEVEL LOCK
        pol = db.query(Policy).filter(Policy.policy_no == policy_no).with_for_update().first()
        print(f"  {GREEN}[{name}] ACQUIRED row lock on Policy #{policy_no}{RESET}")

        paid = db.query(func.coalesce(func.sum(Claim.claim_amount), 0)).filter(
            Claim.policy_no == policy_no
        ).scalar()
        avail = pol.sum_insured - Decimal(str(paid))
        print(f"  {CYAN}[{name}]{RESET} Actual remaining limit: ${avail:,.2f}")

        time.sleep(0.15)

        if Decimal("60000.00") <= avail:
            cl = Claim(policy_no=policy_no, claim_amount=Decimal("60000.00"), status="SETTLED")
            db.add(cl)
            db.commit()
            print(f"  {GREEN}[{name}] COMMITTED $60,000.00 and RELEASED lock.{RESET}")
        else:
            db.rollback()
            print(f"  {RED}[{name}] $60,000.00 exceeds remaining ${avail:,.2f} -> ROLLED BACK & RELEASED lock.{RESET}")
        db.close()

    with ThreadPoolExecutor(max_workers=2) as ex:
        f1 = ex.submit(worker, "Thread-1")
        f2 = ex.submit(worker, "Thread-2")
        f1.result()
        f2.result()

    db = SessionLocal()
    total = db.query(func.coalesce(func.sum(Claim.claim_amount), 0)).filter(
        Claim.policy_no == policy_no
    ).scalar()
    db.close()

    print(f"\n{BOLD}Final Result:{RESET}")
    print(f"  Policy Limit:    $100,000.00")
    print(f"  Total Payout:    {GREEN}${total:,.2f}{RESET}")
    if total <= 100000.00:
        print(f"  {GREEN}{BOLD}ACID CONSISTENCY MAINTAINED: No over-payment!{RESET}")
        print("  Mechanism: MariaDB row-level exclusive lock serialized the concurrent transactions.")

if __name__ == "__main__":
    run_unsafe_race_condition()
    run_safe_pessimistic_lock()
