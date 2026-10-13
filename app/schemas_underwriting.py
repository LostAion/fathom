from typing import Optional, List, Dict, Any
from pydantic import BaseModel, Field

class UnderwriteAssessRequest(BaseModel):
    policy_type: str = Field(..., description="'HULL', 'CARGO', or 'PI'")
    sum_insured: float = Field(..., gt=0)
    premium: Optional[float] = None
    client_id: Optional[int] = None
    vessel_id: Optional[int] = None
    voyage_id: Optional[int] = None
    cargo_id: Optional[int] = None
    vessel_age: Optional[int] = 10
    imo_number: Optional[str] = None
    vessel_name: Optional[str] = None
    client_name: Optional[str] = None
    origin_port: Optional[str] = None
    dest_port: Optional[str] = None

class SanctionsCheckRequest(BaseModel):
    imo_number: Optional[str] = None
    vessel_name: Optional[str] = None
    client_name: Optional[str] = None
