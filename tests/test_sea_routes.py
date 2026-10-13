from fastapi.testclient import TestClient
from app.main import app

client = TestClient(app)

def test_rotterdam_to_singapore_follows_suez():
    response = client.get("/api/sea-route/", params={
        "from_lat": 51.92, "from_lon": 4.48, "to_lat": 1.26, "to_lon": 103.82,
    })
    assert response.status_code == 200
    data = response.json()
    # Real Suez routing is ~8,300 nm; great-circle would be ~5,600 nm.
    assert 8000 < data["distance_nm"] < 8800
    assert len(data["coordinates"]) > 10

def test_invalid_latitude_rejected():
    response = client.get("/api/sea-route/", params={
        "from_lat": 120, "from_lon": 4.48, "to_lat": 1.26, "to_lon": 103.82,
    })
    assert response.status_code == 422
