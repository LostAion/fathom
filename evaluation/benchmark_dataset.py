# Synthetic Maritime Benchmark Submissions for Evaluation
BENCHMARK_CASES = [
    {
        "id": "CASE-01-SANCTIONED-IMO",
        "description": "Vessel on OFAC SDN list with sanctioned IMO",
        "input": {
            "policy_type": "HULL",
            "sum_insured": 30000000.0,
            "imo_number": "IMO8912345",
            "vessel_name": "NEVA LEADER",
            "vessel_age": 12,
            "origin_port": "Novorossiysk",
            "dest_port": "Istanbul"
        },
        "expected_decision": "DECLINE",
        "expected_sanctions_cleared": False,
        "max_risk_score": 100,
        "min_risk_score": 100
    },
    {
        "id": "CASE-02-CLEAN-CONTAINER",
        "description": "Modern container vessel on safe standard route",
        "input": {
            "policy_type": "HULL",
            "sum_insured": 50000000.0,
            "imo_number": "IMO9988776",
            "vessel_name": "PACIFIC STAR",
            "vessel_age": 5,
            "origin_port": "Tokyo",
            "dest_port": "Seattle"
        },
        "expected_decision": "APPROVE",
        "expected_sanctions_cleared": True,
        "max_risk_score": 35,
        "min_risk_score": 0
    },
    {
        "id": "CASE-03-OVERAGE-VESSEL",
        "description": "Old cargo ship (27 years old) exceeding age limits",
        "input": {
            "policy_type": "HULL",
            "sum_insured": 12000000.0,
            "imo_number": "IMO8501122",
            "vessel_name": "ANCIENT MARINER",
            "vessel_age": 27,
            "origin_port": "Rotterdam",
            "dest_port": "Hamburg"
        },
        "expected_decision": "REFER_TO_SENIOR",
        "expected_sanctions_cleared": True,
        "max_risk_score": 100,
        "min_risk_score": 60
    },
    {
        "id": "CASE-04-RED-SEA-VOYAGE",
        "description": "Voyage transiting Red Sea / Bab-el-Mandeb danger corridor",
        "input": {
            "policy_type": "CARGO",
            "sum_insured": 5000000.0,
            "imo_number": "IMO9341122",
            "vessel_name": "EURO CARRIER",
            "vessel_age": 8,
            "origin_port": "Rotterdam",
            "dest_port": "Singapore"
        },
        "expected_decision": "APPROVE_WITH_CONDITIONS",
        "expected_sanctions_cleared": True,
        "max_risk_score": 75,
        "min_risk_score": 45
    }
]
