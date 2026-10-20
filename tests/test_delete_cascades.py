import uuid
from fastapi.testclient import TestClient
from app.main import app

client = TestClient(app)


def _create(path, payload):
    response = client.post(f"/api/{path}/", json=payload)
    assert response.status_code == 201, response.text
    return response.json()


def test_deleting_policy_cascades_to_claims_shares_and_surveys():
    policy = _create("policies", {"policy_type": "HULL", "sum_insured": "1000000", "premium": "1000"})
    reinsurer = _create("reinsurers", {"name": f"Cascade Re {uuid.uuid4().hex[:6]}"})
    surveyor = _create("surveyors", {"name": f"Cascade Surveyor {uuid.uuid4().hex[:6]}"})
    claim = _create("claims", {"policy_no": policy["policy_no"], "claim_amount": "5000"})
    _create("reinsured-by", {"policy_no": policy["policy_no"], "reinsurer_id": reinsurer["reinsurer_id"], "share_percent": "40"})
    _create("assessed-by", {"claim_id": claim["claim_id"], "surveyor_id": surveyor["surveyor_id"]})

    assert client.delete(f"/api/policies/{policy['policy_no']}").status_code == 204
    assert client.get(f"/api/claims/{claim['claim_id']}").status_code == 404
    assert client.get(f"/api/reinsured-by/{policy['policy_no']}/{reinsurer['reinsurer_id']}").status_code == 404
    assert client.get(f"/api/assessed-by/{claim['claim_id']}/{surveyor['surveyor_id']}").status_code == 404

    client.delete(f"/api/reinsurers/{reinsurer['reinsurer_id']}")
    client.delete(f"/api/surveyors/{surveyor['surveyor_id']}")


def test_deleting_link_owners_removes_junction_rows():
    policy = _create("policies", {"policy_type": "CARGO", "sum_insured": "1000", "premium": "10"})
    reinsurer = _create("reinsurers", {"name": f"Cascade Re {uuid.uuid4().hex[:6]}"})
    surveyor = _create("surveyors", {"name": f"Cascade Surveyor {uuid.uuid4().hex[:6]}"})
    claim = _create("claims", {"policy_no": policy["policy_no"], "claim_amount": "50"})
    cargo = _create("cargos", {"description": "Cascade cargo", "value": "100"})
    voyage = _create("voyages", {"origin_port": "Rotterdam", "dest_port": "Singapore"})
    _create("reinsured-by", {"policy_no": policy["policy_no"], "reinsurer_id": reinsurer["reinsurer_id"], "share_percent": "10"})
    _create("assessed-by", {"claim_id": claim["claim_id"], "surveyor_id": surveyor["surveyor_id"]})
    _create("carries", {"voyage_id": voyage["voyage_id"], "cargo_id": cargo["cargo_id"]})

    assert client.delete(f"/api/reinsurers/{reinsurer['reinsurer_id']}").status_code == 204
    assert client.delete(f"/api/surveyors/{surveyor['surveyor_id']}").status_code == 204
    assert client.delete(f"/api/cargos/{cargo['cargo_id']}").status_code == 204
    assert client.get(f"/api/carries/{voyage['voyage_id']}/{cargo['cargo_id']}").status_code == 404

    # Claim and voyage deletes with their own junction rows.
    surveyor2 = _create("surveyors", {"name": f"Cascade Surveyor {uuid.uuid4().hex[:6]}"})
    cargo2 = _create("cargos", {"description": "Cascade cargo", "value": "100"})
    _create("assessed-by", {"claim_id": claim["claim_id"], "surveyor_id": surveyor2["surveyor_id"]})
    _create("carries", {"voyage_id": voyage["voyage_id"], "cargo_id": cargo2["cargo_id"]})
    assert client.delete(f"/api/claims/{claim['claim_id']}").status_code == 204
    assert client.delete(f"/api/voyages/{voyage['voyage_id']}").status_code == 204
    assert client.get(f"/api/carries/{voyage['voyage_id']}/{cargo2['cargo_id']}").status_code == 404

    client.delete(f"/api/policies/{policy['policy_no']}")
    client.delete(f"/api/surveyors/{surveyor2['surveyor_id']}")
    client.delete(f"/api/cargos/{cargo2['cargo_id']}")
