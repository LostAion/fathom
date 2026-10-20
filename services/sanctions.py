import json
import os
from typing import Dict, Any, List

DATA_PATH = os.path.join(os.path.dirname(__file__), "data", "ofac_sdn_maritime.json")

class SanctionsScreener:
    def __init__(self):
        self.data: Dict[str, Any] = {"sanctioned_vessels": [], "sanctioned_entities": []}
        if os.path.exists(DATA_PATH):
            with open(DATA_PATH, "r", encoding="utf-8") as f:
                self.data = json.load(f)

    def screen(self, imo_number: str = None, vessel_name: str = None, client_name: str = None) -> Dict[str, Any]:
        """
        Screen an IMO, vessel name, or client name against the OFAC SDN list.
        Returns match status, flags, and regulatory reasoning.
        """
        matches: List[Dict[str, Any]] = []

        # 1. Match IMO Number (exact canonical check)
        clean_imo = (imo_number or "").strip().upper().removeprefix("IMO").strip()
        clean_vessel = (vessel_name or "").strip().upper()
        clean_client = (client_name or "").strip().upper()

        for vessel in self.data.get("sanctioned_vessels", []):
            sdn_imo = vessel.get("imo_number", "").strip().upper().removeprefix("IMO").strip()
            sdn_name = vessel.get("vessel_name", "").strip().upper()

            if clean_imo and sdn_imo and clean_imo == sdn_imo:
                matches.append({
                    "type": "VESSEL_IMO",
                    "matched_target": clean_imo,
                    "program": vessel.get("program"),
                    "details": vessel.get("reason"),
                    "vessel_name": vessel.get("vessel_name")
                })
            elif clean_vessel and sdn_name and clean_vessel == sdn_name:
                matches.append({
                    "type": "VESSEL_NAME",
                    "matched_target": clean_vessel,
                    "program": vessel.get("program"),
                    "details": vessel.get("reason"),
                    "imo_number": vessel.get("imo_number")
                })

        # 2. Match Client / Owner Entity Name (case-insensitive substring check)
        for entity in self.data.get("sanctioned_entities", []):
            sdn_entity = entity.strip().upper()
            if clean_client and (clean_client in sdn_entity or sdn_entity in clean_client):
                matches.append({
                    "type": "CLIENT_ENTITY",
                    "matched_target": clean_client,
                    "matched_sdn_entity": entity,
                    "program": "GLOBAL-SDN",
                    "details": f"Client matches sanctioned maritime entity '{entity}'"
                })

        is_sanctioned = len(matches) > 0
        return {
            "is_sanctioned": is_sanctioned,
            "data_source": "Local synthetic coursework fixtures, not a live sanctions list",
            "status": "BLOCKED" if is_sanctioned else "CLEARED",
            "matches_count": len(matches),
            "matches": matches,
            "recommendation": "STRICT_DECLINE" if is_sanctioned else "PROCEED"
        }

sanctions_screener = SanctionsScreener()
