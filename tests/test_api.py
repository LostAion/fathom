import pytest
from decimal import Decimal
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
    assert created_client["is_active"] is True

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
    assert "already exists" in res2.json()["detail"] or "integrity error" in res2.json()["detail"].lower()

    # Clean up
    client.delete(f"/api/brokers/{broker_id}")

def test_full_marine_insurance_lifecycle():
    """
    End-to-end full marine insurance lifecycle:
    Draft Policy -> Submit Underwriting -> Bind -> File Claim -> Settle Claim with Deductible -> Soft Delete
    """
    # 0. Fetch seed client & vessel
    clients_res = client.get("/api/clients/").json()
    vessels_res = client.get("/api/vessels/").json()
    assert len(clients_res) > 0
    assert len(vessels_res) > 0
    c_id = clients_res[0]["client_id"]
    v_id = vessels_res[0]["vessel_id"]

    # 1. Draft Policy
    policy_payload = {
        "issue_date": "2026-06-01",
        "expiry_date": "2027-05-31",
        "premium": "20000.00",
        "sum_insured": "500000.00",
        "policy_type": "HULL",
        "vessel_value_covered": "500000.00",
        "deductible": "15000.00",
        "client_id": c_id,
        "vessel_id": v_id
    }
    p_res = client.post("/api/policies/", json=policy_payload)
    assert p_res.status_code == 201
    policy_data = p_res.json()
    p_no = policy_data["policy_no"]
    assert policy_data["status"] == "DRAFT"
    assert float(policy_data["deductible"]) == 15000.00
    assert policy_data["is_active"] is True
    assert policy_data["underwriting_decision"] is None

    # 2. Submit Underwriting
    uw_res = client.post(f"/api/policies/{p_no}/submit-underwriting")
    assert uw_res.status_code == 200
    uw_data = uw_res.json()
    assert uw_data["status"] == "QUOTED"
    assert uw_data["underwriting_decision"] in ["APPROVE", "APPROVE_WITH_CONDITIONS", "REFER_TO_SENIOR"]
    assert uw_data["risk_score"] is not None
    assert uw_data["risk_score"] > 0
    assert uw_data["warranties"] is not None

    # 3. Bind Policy
    bind_res = client.post(f"/api/policies/{p_no}/bind?target_status=ACTIVE")
    assert bind_res.status_code == 200
    bound_data = bind_res.json()
    assert bound_data["status"] == "ACTIVE"

    # 4. File Claim
    claim_payload = {
        "loss_date": "2026-08-15",
        "claim_amount": "65000.00",
        "policy_no": p_no
    }
    cl_res = client.post("/api/claims/", json=claim_payload)
    assert cl_res.status_code == 201
    claim_data = cl_res.json()
    cl_id = claim_data["claim_id"]
    assert claim_data["status"] == "REPORTED"
    assert claim_data["is_active"] is True
    assert float(claim_data["deductible_applied"]) == 0.00
    assert claim_data["settled_amount"] is None

    # 5. Settle Claim with Deductible
    # claim_amount = 65000, sum_insured = 500000, deductible = 15000
    # payout = max(0, min(65000, 500000) - 15000) = 50000.00
    # deductible_applied = 15000.00
    settle_res = client.post(f"/api/claims/{cl_id}/settle")
    assert settle_res.status_code == 200
    settle_data = settle_res.json()
    assert settle_data["status"] == "SETTLED"
    assert float(settle_data["settled_amount"]) == 50000.00
    assert float(settle_data["deductible_applied"]) == 15000.00

    # 6. Soft Delete Policy (sets is_active=False, status='CANCELLED')
    del_res = client.delete(f"/api/policies/{p_no}")
    assert del_res.status_code == 204

    # Verify soft deleted policy
    get_pol_res = client.get(f"/api/policies/{p_no}")
    assert get_pol_res.status_code == 200
    del_pol_data = get_pol_res.json()
    assert del_pol_data["is_active"] is False
    assert del_pol_data["status"] == "CANCELLED"

    # Verify cancelled policy cannot be bound
    bind_cancelled = client.post(f"/api/policies/{p_no}/bind")
    assert bind_cancelled.status_code == 400

    # Soft delete claim
    del_claim_res = client.delete(f"/api/claims/{cl_id}")
    assert del_claim_res.status_code == 204
    get_cl_res = client.get(f"/api/claims/{cl_id}")
    assert get_cl_res.status_code == 200
    assert get_cl_res.json()["is_active"] is False

def test_claim_settlement_below_deductible():
    """Test claim payout formula when loss is less than policy deductible."""
    clients_res = client.get("/api/clients/").json()
    c_id = clients_res[0]["client_id"]

    policy_payload = {
        "premium": "10000.00",
        "sum_insured": "100000.00",
        "deductible": "15000.00",
        "policy_type": "CARGO",
        "client_id": c_id
    }
    p_res = client.post("/api/policies/", json=policy_payload)
    p_no = p_res.json()["policy_no"]

    # File small claim of 8,000 (less than 15,000 deductible)
    cl_res = client.post("/api/claims/", json={"claim_amount": "8000.00", "policy_no": p_no})
    cl_id = cl_res.json()["claim_id"]

    # Settle: payout = max(0, 8000 - 15000) = 0.00, deductible_applied = 8000.00
    settle_res = client.post(f"/api/claims/{cl_id}/settle")
    assert settle_res.status_code == 200
    data = settle_res.json()
    assert float(data["settled_amount"]) == 0.00
    assert float(data["deductible_applied"]) == 8000.00
    assert data["status"] == "SETTLED"

    # Clean up
    client.delete(f"/api/claims/{cl_id}")
    client.delete(f"/api/policies/{p_no}")

def test_claim_settlement_above_sum_insured():
    """Test claim payout capped at sum_insured minus deductible."""
    clients_res = client.get("/api/clients/").json()
    c_id = clients_res[0]["client_id"]

    policy_payload = {
        "premium": "5000.00",
        "sum_insured": "50000.00",
        "deductible": "5000.00",
        "policy_type": "PI",
        "client_id": c_id
    }
    p_res = client.post("/api/policies/", json=policy_payload)
    p_no = p_res.json()["policy_no"]

    # File catastrophic claim of 200,000 against 50,000 limit
    cl_res = client.post("/api/claims/", json={"claim_amount": "200000.00", "policy_no": p_no})
    cl_id = cl_res.json()["claim_id"]

    # Payout = max(0, min(200000, 50000) - 5000) = 45,000.00
    settle_res = client.post(f"/api/claims/{cl_id}/settle")
    assert settle_res.status_code == 200
    data = settle_res.json()
    assert float(data["settled_amount"]) == 45000.00
    assert float(data["deductible_applied"]) == 5000.00

    # Clean up
    client.delete(f"/api/claims/{cl_id}")
    client.delete(f"/api/policies/{p_no}")

def test_policies_pagination_and_search():
    # 1. Test standard PaginatedResponse envelope
    res = client.get("/api/policies/?page=1&limit=2")
    assert res.status_code == 200
    data = res.json()
    assert "items" in data
    assert "total" in data
    assert "page" in data
    assert "limit" in data
    assert "total_pages" in data
    assert data["page"] == 1
    assert data["limit"] == 2
    assert len(data["items"]) <= 2

    # 2. Test search filter
    search_res = client.get("/api/policies/?search=HULL")
    assert search_res.status_code == 200
    search_data = search_res.json()
    assert search_data["total"] > 0
    assert all("HULL" in p["policy_type"] or "HULL" in str(p.values()) for p in search_data["items"])

def test_claims_pagination_and_search():
    # 1. Test PaginatedResponse envelope on claims
    res = client.get("/api/claims/?page=1&limit=5")
    assert res.status_code == 200
    data = res.json()
    assert "items" in data
    assert "total" in data
    assert "page" in data
    assert "limit" in data
    assert "total_pages" in data

    # 2. Test search filter
    search_res = client.get("/api/claims/?search=REPORTED")
    assert search_res.status_code == 200
    search_data = search_res.json()
    assert isinstance(search_data["items"], list)

def test_junction_reinsured_by():
    # Get existing policy and reinsurer
    policies_res = client.get("/api/policies/").json()
    policies = policies_res["items"] if "items" in policies_res else policies_res
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
