from fastapi.testclient import TestClient
from app.main import app

client = TestClient(app)

def test_demo_race_condition():
    response = client.post("/api/concurrency/demo-race-condition")
    assert response.status_code == 200
    data = response.json()
    assert data["scenario"] == "RACE_CONDITION_UNSAFE"
    assert data["invariant_violated"] is True
    assert data["total_claims_paid"] == 120000.0
    assert len(data["thread_results"]) == 2

def test_demo_safe_pessimistic_lock():
    response = client.post("/api/concurrency/demo-safe-transaction")
    assert response.status_code == 200
    data = response.json()
    assert data["scenario"] == "PESSIMISTIC_LOCK_SAFE"
    assert data["invariant_preserved"] is True
    assert data["total_claims_paid"] == 60000.0
    assert any(t["status"] == "APPROVED" for t in data["thread_results"])
    assert any(t["status"] == "REJECTED_CONCURRENCY_LIMIT" for t in data["thread_results"])
