from fastapi.testclient import TestClient
from app.main import app

client = TestClient(app)

def test_sanctions_check_endpoint():
    # 1. Test clean vessel
    clean_res = client.get("/api/underwriting/sanctions-check?imo_number=IMO9999999")
    assert clean_res.status_code == 200
    data = clean_res.json()
    assert data["is_sanctioned"] is False
    assert data["status"] == "CLEARED"

    # 2. Test sanctioned vessel (NEVA LEADER / IMO8912345)
    sdn_res = client.get("/api/underwriting/sanctions-check?imo_number=IMO8912345")
    assert sdn_res.status_code == 200
    data_sdn = sdn_res.json()
    assert data_sdn["is_sanctioned"] is True
    assert data_sdn["status"] == "BLOCKED"
    assert len(data_sdn["matches"]) > 0

def test_underwriting_assess_sanctioned_vessel():
    payload = {
        "policy_type": "HULL",
        "sum_insured": 25000000.0,
        "imo_number": "IMO8912345",
        "vessel_name": "NEVA LEADER",
        "vessel_age": 14
    }
    res = client.post("/api/underwriting/assess", json=payload)
    assert res.status_code == 200
    data = res.json()
    assert data["decision"] == "DECLINE"
    assert data["risk_score"] == 100
    assert data["sanctions_cleared"] is False

def test_underwriting_assess_clean_vessel():
    payload = {
        "policy_type": "HULL",
        "sum_insured": 50000000.0,
        "imo_number": "IMO9123456",
        "vessel_name": "Ever Pioneer",
        "vessel_age": 7,
        "origin_port": "Tokyo",
        "dest_port": "Seattle"
    }
    res = client.post("/api/underwriting/assess", json=payload)
    assert res.status_code == 200
    data = res.json()
    assert data["decision"] == "APPROVE"
    assert data["sanctions_cleared"] is True
    assert data["risk_score"] < 50
    assert data["recommended_premium"] > 0

def test_underwriting_assess_danger_voyage_corridor():
    payload = {
        "policy_type": "CARGO",
        "sum_insured": 10000000.0,
        "imo_number": "IMO9654321",
        "vessel_age": 8,
        "origin_port": "Rotterdam",
        "dest_port": "Singapore"
    }
    res = client.post("/api/underwriting/assess", json=payload)
    assert res.status_code == 200
    data = res.json()
    assert data["ais_voyage_data"]["has_danger_exposure"] is True
    assert data["decision"] in ["APPROVE_WITH_CONDITIONS", "REFER_TO_SENIOR"]
    assert any("Bab-el-Mandeb" in w or "JWC" in w or "BMP" in w for w in data["warranties_required"])

def test_policy_submit_underwriting_and_bind_flow():
    """Test policy submission to automated underwriting engine and binding transitions."""
    # 1. Fetch seed vessel and client
    vessels = client.get("/api/vessels/").json()
    clients = client.get("/api/clients/").json()
    assert len(vessels) > 0
    assert len(clients) > 0

    # 2. Create draft policy
    p_payload = {
        "policy_type": "HULL",
        "sum_insured": "30000000.00",
        "premium": "45000.00",
        "vessel_id": vessels[0]["vessel_id"],
        "client_id": clients[0]["client_id"]
    }
    create_p = client.post("/api/policies/", json=p_payload)
    assert create_p.status_code == 201
    p_no = create_p.json()["policy_no"]
    assert create_p.json()["status"] == "DRAFT"

    # 3. Submit underwriting
    uw_res = client.post(f"/api/policies/{p_no}/submit-underwriting")
    assert uw_res.status_code == 200
    uw_data = uw_res.json()
    assert uw_data["status"] == "QUOTED"
    assert uw_data["risk_score"] is not None
    assert uw_data["underwriting_decision"] in ["APPROVE", "APPROVE_WITH_CONDITIONS", "REFER_TO_SENIOR"]
    assert len(uw_data["warranties"]) > 0

    # 4. Bind policy to ACTIVE
    bind_res = client.post(f"/api/policies/{p_no}/bind?target_status=ACTIVE")
    assert bind_res.status_code == 200
    assert bind_res.json()["status"] == "ACTIVE"

    # Clean up
    client.delete(f"/api/policies/{p_no}")

def test_policy_underwriting_sanctioned_vessel_blocks_binding():
    """Test that a policy on an OFAC sanctioned vessel receives DECLINE and cannot be bound."""
    clients = client.get("/api/clients/").json()
    c_id = clients[0]["client_id"]

    # Create sanctioned test vessel
    v_res = client.post("/api/vessels/", json={
        "name": "NEVA LEADER",
        "imo_number": "IMO8912345",
        "tonnage": 45000,
        "flag": "Russia"
    })
    # If already created or succeeds
    if v_res.status_code == 201:
        v_id = v_res.json()["vessel_id"]
        created_v = True
    else:
        # Fetch vessel
        all_v = client.get("/api/vessels/").json()
        matching = [v for v in all_v if v["imo_number"] == "IMO8912345"]
        v_id = matching[0]["vessel_id"]
        created_v = False

    # Create policy
    pol_res = client.post("/api/policies/", json={
        "policy_type": "HULL",
        "sum_insured": "15000000.00",
        "client_id": c_id,
        "vessel_id": v_id
    })
    assert pol_res.status_code == 201
    p_no = pol_res.json()["policy_no"]

    # Submit underwriting - must DECLINE
    uw_res = client.post(f"/api/policies/{p_no}/submit-underwriting")
    assert uw_res.status_code == 200
    uw_data = uw_res.json()
    assert uw_data["underwriting_decision"] == "DECLINE"
    assert uw_data["risk_score"] == 100

    # Attempting to bind must fail with 400
    bind_res = client.post(f"/api/policies/{p_no}/bind")
    assert bind_res.status_code == 400
    assert "declined" in bind_res.json()["detail"].lower()

    # Clean up
    client.delete(f"/api/policies/{p_no}")
    if created_v:
        client.delete(f"/api/vessels/{v_id}")

def test_rubric_evaluation_engine_benchmark():
    res = client.post("/api/underwriting/evaluate-engine")
    assert res.status_code == 200
    data = res.json()
    assert data["overall_status"] == "PASSED"
    assert data["sanctions_violations_count"] == 0
    assert data["decision_accuracy_percent"] >= 90.0
    assert data["total_benchmark_cases"] >= 4
