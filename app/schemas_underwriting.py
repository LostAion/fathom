from typing import Literal, Optional
from pydantic import BaseModel, Field


class PolicyAssessRequest(BaseModel):
    # Age is supplied for the demo because the vessel table has no build year.
    vessel_age: int = Field(10, ge=0, le=100)
    voyage_id: Optional[int] = Field(None, gt=0)


class UnderwriteAssessRequest(PolicyAssessRequest):
    policy_type: Literal["HULL", "CARGO", "PI"]
    sum_insured: float = Field(..., gt=0, allow_inf_nan=False)
    premium: Optional[float] = Field(None, ge=0, allow_inf_nan=False)
    client_id: Optional[int] = Field(None, gt=0)
    vessel_id: Optional[int] = Field(None, gt=0)
    cargo_id: Optional[int] = Field(None, gt=0)
    imo_number: Optional[str] = Field(None, max_length=20)
    vessel_name: Optional[str] = Field(None, max_length=100)
    client_name: Optional[str] = Field(None, max_length=100)
    origin_port: Optional[str] = Field(None, max_length=100)
    dest_port: Optional[str] = Field(None, max_length=100)
