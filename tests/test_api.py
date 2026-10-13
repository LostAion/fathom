import pytest
from fastapi.testclient import TestClient
from app.main import app

client = TestClient(app)

def test_health_check():
    response = client.get("/api/health")
    assert response.status_code == 200
    data = response.json()
    assert data["status"] == "healthy"
    assert "marine_insurance" in data["database"]

def test_client_crud_lifecycle():
    # 1. Create client
    create_payload = {
        "name": "Global Sea Freight Ltd",
        "address": "12 Ocean Terminal, Hamburg"
    }
    create_res = client.post("/api/clients/", json=create_payload)
    assert create_res.status_code == 201
    created_client = create_res.json()
    client_id = created_client["client_id"]
    assert created_client["name"] == create_payload["name"]
    assert created_client["address"] == create_payload["address"]

    # 2. Read single client
    get_res = client.get(f"/api/clients/{client_id}")
    assert get_res.status_code == 200
    assert get_res.json()["client_id"] == client_id

    # 3. Read list of clients
    list_res = client.get("/api/clients/?limit=10")
    assert list_res.status_code == 200
    assert any(c["client_id"] == client_id for c in list_res.json())

    # 4. Update client
    update_payload = {"address": "Updated Terminal 99, Hamburg"}
    put_res = client.put(f"/api/clients/{client_id}", json=update_payload)
    assert put_res.status_code == 200
    assert put_res.json()["address"] == "Updated Terminal 99, Hamburg"

    # 5. Delete client
    del_res = client.delete(f"/api/clients/{client_id}")
    assert del_res.status_code == 204

    # 6. Verify 404
    get_after_del = client.get(f"/api/clients/{client_id}")
    assert get_after_del.status_code == 404

def test_broker_unique_constraint():
    unique_licence = "TEST-LIC-UNIQUE-999"
    payload = {"agency_name": "Test Agency", "licence_no": unique_licence}
    res1 = client.post("/api/brokers/", json=payload)
    assert res1.status_code == 201
    broker_id = res1.json()["broker_id"]

    # Second insert with same licence must fail with 400
    res2 = client.post("/api/brokers/", json=payload)
    assert res2.status_code == 400
    assert "already exists" in res2.json()["detail"]

    # Clean up
    client.delete(f"/api/brokers/{broker_id}")

def test_policy_and_claim_flow():
    # Fetch existing client, vessel, underwriter, broker from seed
    clients = client.get("/api/clients/").json()
    assert len(clients) > 0
    c_id = clients[0]["client_id"]

    vessels = client.get("/api/vessels/").json()
    assert len(vessels) > 0
    v_id = vessels[0]["vessel_id"]

    # Create a policy (starts in DRAFT)
    policy_payload = {
        "issue_date": "2026-06-01",
        "expiry_date": "2027-05-31",
        "premium": "15000.00",
        "sum_insured": "1000000.00",
        "policy_type": "HULL",
        "vessel_value_covered": "1000000.00",
        "client_id": c_id,
        "vessel_id": v_id,
        "deductible": "10000.00"
    }
    p_res = client.post("/api/policies/", json=policy_payload)
    assert p_res.status_code == 201
    policy_data = p_res.json()
    p_no = policy_data["policy_no"]
    assert policy_data["status"] == "DRAFT"

    # Move policy to QUOTED, then BOUND
    quote_res = client.post(f"/api/policies/{p_no}/quote")
    assert quote_res.status_code == 200
    assert quote_res.json()["status"] == "QUOTED"

    bind_res = client.post(f"/api/policies/{p_no}/bind")
    assert bind_res.status_code == 200
    assert bind_res.json()["status"] == "BOUND"

    # Create a claim under this policy
    claim_payload = {
        "loss_date": "2026-08-15",
        "claim_amount": "45000.00",
        "policy_no": p_no
    }
    cl_res = client.post("/api/claims/", json=claim_payload)
    assert cl_res.status_code == 201
    claim_data = cl_res.json()
    cl_id = claim_data["claim_id"]
    assert claim_data["status"] == "REPORTED"

    # Settle claim: $45,000 claim - $10,000 deductible = $35,000 net payout
    settle_res = client.post(f"/api/claims/{cl_id}/settle")
    assert settle_res.status_code == 200
    settled_data = settle_res.json()
    assert settled_data["status"] == "SETTLED"
    assert float(settled_data["settled_amount"]) == 35000.00
    assert float(settled_data["deductible_applied"]) == 10000.00

    # Delete claim and policy
    assert client.delete(f"/api/claims/{cl_id}").status_code == 204
    assert client.delete(f"/api/policies/{p_no}").status_code == 204

def test_junction_reinsured_by():
    # Get existing policy and reinsurer
    policies = client.get("/api/policies/").json()
    reinsurers = client.get("/api/reinsurers/").json()
    assert len(policies) > 0
    assert len(reinsurers) > 0

    p_no = policies[0]["policy_no"]
    # Create a temporary reinsurer to avoid conflict with existing seeds
    new_re = client.post("/api/reinsurers/", json={"name": "Temp Test Reinsurance"}).json()
    r_id = new_re["reinsurer_id"]

    # Create junction mapping
    link_res = client.post("/api/reinsured-by/", json={
        "policy_no": p_no,
        "reinsurer_id": r_id,
        "share_percent": "25.50"
    })
    assert link_res.status_code == 201

    # Get composite link
    get_link = client.get(f"/api/reinsured-by/{p_no}/{r_id}")
    assert get_link.status_code == 200
    assert float(get_link.json()["share_percent"]) == 25.50

    # Update composite link
    update_link = client.put(f"/api/reinsured-by/{p_no}/{r_id}", json={
        "share_percent": "30.00"
    })
    assert update_link.status_code == 200
    assert float(update_link.json()["share_percent"]) == 30.00

    # Delete composite link
    del_link = client.delete(f"/api/reinsured-by/{p_no}/{r_id}")
    assert del_link.status_code == 204

    # Clean up temp reinsurer
    client.delete(f"/api/reinsurers/{r_id}")

def test_cumulative_aggregate_limit_enforcement():
    # 1. Create client and policy with $100,000 aggregate sum insured and $5,000 deductible
    c_res = client.post("/api/clients/", json={"name": "Aggregate Limit Test Client"})
    client_id = c_res.json()["client_id"]

    p_res = client.post("/api/policies/", json={
        "client_id": client_id,
        "policy_type": "CARGO",
        "sum_insured": "100000.00",
        "deductible": "5000.00",
        "status": "BOUND"
    })
    policy_no = p_res.json()["policy_no"]

    # 2. Claim 1: $60,000. Payout = min(60000 - 5000, 100000) = $55,000.
    cl1 = client.post("/api/claims/", json={"policy_no": policy_no, "claim_amount": "60000.00"}).json()
    settle1 = client.post(f"/api/claims/{cl1['claim_id']}/settle").json()
    assert float(settle1["settled_amount"]) == 55000.00
    assert float(settle1["deductible_applied"]) == 5000.00

    # 3. Claim 2: $60,000. Remaining aggregate = $100,000 - $55,000 = $45,000.
    # Net claim after deductible = $55,000, capped by remaining aggregate limit = $45,000.
    cl2 = client.post("/api/claims/", json={"policy_no": policy_no, "claim_amount": "60000.00"}).json()
    settle2 = client.post(f"/api/claims/{cl2['claim_id']}/settle").json()
    assert float(settle2["settled_amount"]) == 45000.00

    # 4. Total settled claims now = $55,000 + $45,000 = $100,000 (Limit reached).
    # Claim 3: $20,000. Remaining aggregate = $0.00.
    cl3 = client.post("/api/claims/", json={"policy_no": policy_no, "claim_amount": "20000.00"}).json()
    settle3 = client.post(f"/api/claims/{cl3['claim_id']}/settle").json()
    assert float(settle3["settled_amount"]) == 0.00

    # Clean up
    for c_id in [cl1["claim_id"], cl2["claim_id"], cl3["claim_id"]]:
        client.delete(f"/api/claims/{c_id}")
    client.delete(f"/api/policies/{policy_no}")
    client.delete(f"/api/clients/{client_id}")

