from typing import Dict, Any, List

# Joint War Committee (JWC) Listed Areas and Danger Port Coordinates
JWC_AREAS = [
    {
        "name": "Southern Red Sea & Gulf of Aden",
        "description": "High missile/drone and boarding risk (Bab-el-Mandeb Strait)",
        "lat_range": (11.0, 18.0),
        "lon_range": (40.0, 52.0),
        "danger_ports": ["Hodeidah", "Aden", "Djibouti", "Port Sudan"],
        "awrp_recommended_rate": 0.50, # 0.50% of sum insured
        "risk_level": "CRITICAL"
    },
    {
        "name": "Black Sea & Sea of Azov",
        "description": "Active naval conflict, floating mines, and military strikes",
        "lat_range": (41.0, 47.5),
        "lon_range": (28.0, 42.0),
        "danger_ports": ["Odessa", "Novorossiysk", "Sevastopol"],
        "awrp_recommended_rate": 1.25,
        "risk_level": "SEVERE"
    },
    {
        "name": "Persian Gulf & Strait of Hormuz",
        "description": "Heightened state seizure and tanker interdiction zone",
        "lat_range": (24.0, 30.0),
        "lon_range": (48.0, 58.0),
        "danger_ports": ["Bandar Abbas", "Basra"],
        "awrp_recommended_rate": 0.25,
        "risk_level": "HIGH"
    },
    {
        "name": "Gulf of Guinea",
        "description": "Maritime piracy, armed robbery, and hostage-taking corridor",
        "lat_range": (1.0, 7.0),
        "lon_range": (-3.0, 9.0),
        "danger_ports": ["Lagos", "Port Harcourt", "Cotonou"],
        "awrp_recommended_rate": 0.35,
        "risk_level": "ELEVATED"
    }
]

class AISTracker:
    """
    Assesses vessel voyage paths and coordinates against maritime risk zones (JWC).
    """

    def assess_voyage_route(self, origin_port: str = None, dest_port: str = None, waypoints: List[Dict[str, float]] = None) -> Dict[str, Any]:
        origin = (origin_port or "").lower()
        dest = (dest_port or "").lower()
        detected_danger_zones: List[Dict[str, Any]] = []

        # 1. Check known high risk transit corridors by port names
        for area in JWC_AREAS:
            matched_port = None
            for p in area["danger_ports"]:
                if p.lower() in origin or p.lower() in dest:
                    matched_port = p
                    break

            # Check common transit routes that must transit the corridor (e.g. Europe <-> Asia transits Suez/Red Sea)
            suez_route = (
                ("rotterdam" in origin or "hamburg" in origin or "london" in origin) and
                ("singapore" in dest or "shanghai" in dest or "yokohama" in dest)
            ) or (
                ("singapore" in origin or "shanghai" in origin or "yokohama" in origin) and
                ("rotterdam" in dest or "hamburg" in dest or "london" in dest)
            )

            if matched_port or (area["name"] == "Southern Red Sea & Gulf of Aden" and suez_route):
                detected_danger_zones.append({
                    "zone_name": area["name"],
                    "risk_level": area["risk_level"],
                    "reason": f"Voyage visits or transits via {matched_port if matched_port else 'Suez/Red Sea corridor'}",
                    "awrp_rate": area["awrp_recommended_rate"]
                })

        # 2. Check explicit coordinates / AIS waypoints if provided
        if waypoints:
            for pt in waypoints:
                lat = pt.get("lat", 0.0)
                lon = pt.get("lon", 0.0)
                for area in JWC_AREAS:
                    lat_min, lat_max = area["lat_range"]
                    lon_min, lon_max = area["lon_range"]
                    if lat_min <= lat <= lat_max and lon_min <= lon <= lon_max:
                        if not any(z["zone_name"] == area["name"] for z in detected_danger_zones):
                            detected_danger_zones.append({
                                "zone_name": area["name"],
                                "risk_level": area["risk_level"],
                                "reason": f"AIS coordinate ({lat}, {lon}) falls within {area['name']}",
                                "awrp_rate": area["awrp_recommended_rate"]
                            })

        has_danger_exposure = len(detected_danger_zones) > 0
        total_awrp = sum(z["awrp_rate"] for z in detected_danger_zones)

        return {
            "has_danger_exposure": has_danger_exposure,
            "danger_zones_count": len(detected_danger_zones),
            "zones": detected_danger_zones,
            "total_awrp_surcharge_percent": total_awrp,
            "warranty_recommended": (
                "Warranted 48-hour prior notice to underwriter before entering JWC listed waters; BMP security protocol maintained."
                if has_danger_exposure else "Standard Institute Navigational Limits (INL) apply."
            )
        }

ais_tracker = AISTracker()
