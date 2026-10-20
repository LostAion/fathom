"""Regression coverage for underwriting alongside the existing iOS API contract."""
import uuid
import pytest
from fastapi.testclient import TestClient
from app.main import app
from rag.vector_store import vector_store

client = TestClient(app)


@pytest.fixture
def records():
    created = []

    def create(resource, **payload):
        response = client.post(f"/api/{resource}/", json=payload)
        assert response.status_code == 201, response.text
        row = response.json()
        key = {"policies": "policy_no", "vessels": "vessel_id", "clients": "client_id",
               "voyages": "voyage_id", "claims": "claim_id"}[resource]
        created.append((resource, row[key]))
        return row

    yield create
    for resource, key in reversed(created):
        response = client.delete(f"/api/{resource}/{key}")
        assert response.status_code in {204, 404}, response.text


def test_assessment_persists_report_and_preserves_ios_arrays(records):
    vessel = records("vessels", name="Risk test", imo_number=uuid.uuid4().hex[:12])
    voyage = records("voyages", vessel_id=vessel["vessel_id"], origin_port="Rotterdam", dest_port="Singapore")
    policy = records("policies", vessel_id=vessel["vessel_id"], policy_type="HULL", sum_insured="100000")
    number = policy["policy_no"]
    response = client.post(f"/api/policies/{number}/submit-underwriting", json={"vessel_age": 12, "voyage_id": voyage["voyage_id"]})
    assert response.status_code == 200, response.text
    data = response.json()
    assert data["status"] == "QUOTED"
    assert data["underwriting_decision"] == "APPROVE_WITH_CONDITIONS"
    assert float(data["awrp_surcharge"]) == 0.5
    assert float(data["premium"]) == 1000
    assert data["underwriting_report"]["retrieved_guidelines"]
    assert data["underwriting_report"]["vessel_age"] == 12
    assert client.get(f"/api/policies/{number}").json() == data
    assert isinstance(client.get("/api/policies/").json(), list)
    assert isinstance(client.get("/api/claims/").json(), list)
    assert client.post(f"/api/policies/{number}/bind").json()["status"] == "BOUND"


def test_decline_cannot_be_bypassed_by_quote_or_update(records):
    vessel = records("vessels", name="Fixture vessel", imo_number="8912345")
    policy = records("policies", vessel_id=vessel["vessel_id"], policy_type="HULL", sum_insured="100000")
    path = f"/api/policies/{policy['policy_no']}"
    assert client.post(f"{path}/bind").status_code == 400
    assert client.post(f"{path}/submit-underwriting").json()["underwriting_decision"] == "DECLINE"
    assert client.post(f"{path}/quote").status_code == 200
    assert client.post(f"{path}/bind").status_code == 400
    assert client.put(path, json={"status": "ACTIVE"}).status_code == 400
    assert client.post("/api/policies/", json={"vessel_id": vessel["vessel_id"], "status": "ACTIVE"}).status_code == 400
    res = client.post("/api/underwriting/assess", json={
        "vessel_id": vessel["vessel_id"], "vessel_name": "Clean", "imo_number": "9999999",
        "policy_type": "HULL", "sum_insured": 100000,
    })
    assert res.json()["decision"] == "DECLINE"


def test_editing_assessed_inputs_invalidates_report(records):
    policy = records("policies", policy_type="HULL", sum_insured="100000")
    path = f"/api/policies/{policy['policy_no']}"
    assert client.post(f"{path}/submit-underwriting").json()["risk_score"] == 20
    changed = client.put(path, json={"sum_insured": "200000"}).json()
    assert changed["underwriting_decision"] is None
    assert changed["underwriting_report"] is None
    assert changed["status"] == "DRAFT"


def test_referrals_block_binding_and_bound_policies_cannot_be_requoted(records):
    policy = records("policies", policy_type="HULL", sum_insured="100000")
    path = f"/api/policies/{policy['policy_no']}"
    result = client.post(f"{path}/submit-underwriting", json={"vessel_age": 27}).json()
    assert result["underwriting_decision"] == "REFER_TO_SENIOR"
    assert client.post(f"{path}/bind").status_code == 400
    client.post(f"{path}/submit-underwriting", json={"vessel_age": 5})
    assert client.post(f"{path}/bind").status_code == 200
    assert client.post(f"{path}/submit-underwriting").status_code == 400
    assert client.post(f"{path}/quote").status_code == 400


def test_binding_rechecks_changed_voyage(records):
    vessel = records("vessels", name="Route test", imo_number=uuid.uuid4().hex[:12])
    voyage = records("voyages", vessel_id=vessel["vessel_id"], origin_port="Tokyo", dest_port="Seattle")
    policy = records("policies", vessel_id=vessel["vessel_id"], policy_type="HULL", sum_insured="100000")
    path = f"/api/policies/{policy['policy_no']}"
    result = client.post(f"{path}/submit-underwriting", json={"vessel_age": 20, "voyage_id": voyage["voyage_id"]}).json()
    assert result["underwriting_decision"] == "APPROVE_WITH_CONDITIONS"
    client.put(f"/api/voyages/{voyage['voyage_id']}", json={"origin_port": "Rotterdam", "dest_port": "Singapore"})
    assert client.post(f"{path}/bind").status_code == 400


@pytest.mark.parametrize("payload", [
    {"vessel_age": None}, {"vessel_age": -1}, {"vessel_age": 101},
    {"policy_type": "BOGUS"}, {"sum_insured": 0}, {"voyage_id": 0},
])
def test_invalid_assessment_inputs_return_422(payload):
    response = client.post("/api/underwriting/assess", json={"policy_type": "HULL", "sum_insured": 100000} | payload)
    assert response.status_code == 422


def test_unknown_and_mismatched_relations_are_rejected(records):
    vessel = records("vessels", name="One", imo_number=uuid.uuid4().hex[:12])
    other = records("vessels", name="Two", imo_number=uuid.uuid4().hex[:12])
    voyage = records("voyages", vessel_id=other["vessel_id"])
    policy = records("policies", vessel_id=vessel["vessel_id"], policy_type="HULL", sum_insured="100000")
    assert client.post(f"/api/policies/{policy['policy_no']}/submit-underwriting", json={"voyage_id": voyage["voyage_id"]}).status_code == 400
    assert client.post("/api/underwriting/assess", json={"policy_type": "HULL", "sum_insured": 100000, "client_id": 2147483647}).status_code == 400
    assert client.post("/api/policies/2147483647/submit-underwriting").status_code == 404


def test_optional_pagination_and_archive_keep_existing_delete_contract(records):
    policy = records("policies", policy_type="CARGO", sum_insured="100000")
    claim = records("claims", policy_no=policy["policy_no"], claim_amount="1000", reserve_amount="500")
    assert float(claim["reserve_amount"]) == 500
    for resource in ("policies", "claims"):
        response = client.get(f"/api/{resource}/?page=1&limit=1")
        assert response.status_code == 200
        assert len(response.json()["items"]) == 1
        assert response.json()["total"] == int(response.headers["X-Total-Count"])
    path = f"/api/policies/{policy['policy_no']}"
    assert client.delete(path + "?permanent=false").status_code == 204
    assert client.get(path).json()["is_active"] is False
    assert client.get(f"/api/claims/{claim['claim_id']}").status_code == 200
    assert client.post(f"/api/claims/{claim['claim_id']}/settle").status_code == 400
    assert client.delete(path).status_code == 204
    assert client.get(f"/api/claims/{claim['claim_id']}").status_code == 404


def test_guidelines_do_not_return_unrelated_zero_score_matches():
    assert vector_store.retrieve_guidelines("zzzzunrelatedzzzz") == []
    assert vector_store.retrieve_guidelines("hull vessel age")


def test_real_concurrent_settlements_use_latest_committed_aggregate(records):
    from concurrent.futures import ThreadPoolExecutor
    from threading import Barrier, Lock
    from sqlalchemy import event
    from app.database import engine

    policy = records("policies", policy_type="HULL", sum_insured="100000", deductible="0")
    claims = [records("claims", policy_no=policy["policy_no"], claim_amount="60000") for _ in range(2)]
    barrier, lock = Barrier(2), Lock()
    snapshots = set()

    def synchronize_claim_snapshots(conn, cursor, statement, parameters, context, executemany):
        # Both transactions establish a snapshot before either can lock the policy.
        if statement.startswith("SELECT") and "WHERE `CLAIM`.claim_id =" in statement:
            with lock:
                sync = id(conn) not in snapshots and len(snapshots) < 2
                if sync:
                    snapshots.add(id(conn))
            if sync:
                barrier.wait(timeout=10)

    event.listen(engine, "after_cursor_execute", synchronize_claim_snapshots)
    try:
        with ThreadPoolExecutor(max_workers=2) as executor:
            futures = [executor.submit(client.post, f"/api/claims/{row['claim_id']}/settle") for row in claims]
            responses = [future.result(timeout=20) for future in futures]
    finally:
        event.remove(engine, "after_cursor_execute", synchronize_claim_snapshots)
    assert len(snapshots) == 2
    assert all(response.status_code == 200 for response in responses)
    assert sorted(float(response.json()["settled_amount"]) for response in responses) == [40000, 60000]
