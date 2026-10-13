from datetime import date
from decimal import Decimal
from typing import Optional, Literal
from pydantic import BaseModel, ConfigDict, Field

# ==========================================
# CLIENT
# ==========================================
class ClientBase(BaseModel):
    name: str = Field(..., max_length=100)
    address: Optional[str] = Field(None, max_length=255)

class ClientCreate(ClientBase):
    pass

class ClientUpdate(BaseModel):
    name: Optional[str] = Field(None, max_length=100)
    address: Optional[str] = Field(None, max_length=255)

class ClientRead(ClientBase):
    client_id: int
    model_config = ConfigDict(from_attributes=True)


# ==========================================
# BROKER
# ==========================================
class BrokerBase(BaseModel):
    agency_name: str = Field(..., max_length=100)
    licence_no: str = Field(..., max_length=50)

class BrokerCreate(BrokerBase):
    pass

class BrokerUpdate(BaseModel):
    agency_name: Optional[str] = Field(None, max_length=100)
    licence_no: Optional[str] = Field(None, max_length=50)

class BrokerRead(BrokerBase):
    broker_id: int
    model_config = ConfigDict(from_attributes=True)


# ==========================================
# SURVEYOR
# ==========================================
class SurveyorBase(BaseModel):
    name: str = Field(..., max_length=100)
    qualification: Optional[str] = Field(None, max_length=100)

class SurveyorCreate(SurveyorBase):
    pass

class SurveyorUpdate(BaseModel):
    name: Optional[str] = Field(None, max_length=100)
    qualification: Optional[str] = Field(None, max_length=100)

class SurveyorRead(SurveyorBase):
    surveyor_id: int
    model_config = ConfigDict(from_attributes=True)


# ==========================================
# REINSURER
# ==========================================
class ReinsurerBase(BaseModel):
    name: str = Field(..., max_length=100)

class ReinsurerCreate(ReinsurerBase):
    pass

class ReinsurerUpdate(BaseModel):
    name: Optional[str] = Field(None, max_length=100)

class ReinsurerRead(ReinsurerBase):
    reinsurer_id: int
    model_config = ConfigDict(from_attributes=True)


# ==========================================
# CARGO
# ==========================================
class CargoBase(BaseModel):
    description: Optional[str] = Field(None, max_length=255)
    value: Optional[Decimal] = None

class CargoCreate(CargoBase):
    pass

class CargoUpdate(BaseModel):
    description: Optional[str] = Field(None, max_length=255)
    value: Optional[Decimal] = None

class CargoRead(CargoBase):
    cargo_id: int
    model_config = ConfigDict(from_attributes=True)


# ==========================================
# VESSEL
# ==========================================
class VesselBase(BaseModel):
    name: str = Field(..., max_length=100)
    imo_number: str = Field(..., max_length=20)
    tonnage: Optional[int] = None
    flag: Optional[str] = Field(None, max_length=50)

class VesselCreate(VesselBase):
    pass

class VesselUpdate(BaseModel):
    name: Optional[str] = Field(None, max_length=100)
    imo_number: Optional[str] = Field(None, max_length=20)
    tonnage: Optional[int] = None
    flag: Optional[str] = Field(None, max_length=50)

class VesselRead(VesselBase):
    vessel_id: int
    model_config = ConfigDict(from_attributes=True)


# ==========================================
# DEPARTMENT
# ==========================================
class DepartmentBase(BaseModel):
    name: str = Field(..., max_length=100)
    location: Optional[str] = Field(None, max_length=100)

class DepartmentCreate(DepartmentBase):
    pass

class DepartmentUpdate(BaseModel):
    name: Optional[str] = Field(None, max_length=100)
    location: Optional[str] = Field(None, max_length=100)

class DepartmentRead(DepartmentBase):
    dept_id: int
    model_config = ConfigDict(from_attributes=True)


# ==========================================
# UNDERWRITER
# ==========================================
class UnderwriterBase(BaseModel):
    name: str = Field(..., max_length=100)
    designation: Optional[str] = Field(None, max_length=50)
    dept_id: Optional[int] = None

class UnderwriterCreate(UnderwriterBase):
    pass

class UnderwriterUpdate(BaseModel):
    name: Optional[str] = Field(None, max_length=100)
    designation: Optional[str] = Field(None, max_length=50)
    dept_id: Optional[int] = None

class UnderwriterRead(UnderwriterBase):
    emp_id: int
    model_config = ConfigDict(from_attributes=True)


# ==========================================
# VOYAGE
# ==========================================
class VoyageBase(BaseModel):
    origin_port: Optional[str] = Field(None, max_length=100)
    dest_port: Optional[str] = Field(None, max_length=100)
    depart_date: Optional[date] = None
    vessel_id: Optional[int] = None

class VoyageCreate(VoyageBase):
    pass

class VoyageUpdate(BaseModel):
    origin_port: Optional[str] = Field(None, max_length=100)
    dest_port: Optional[str] = Field(None, max_length=100)
    depart_date: Optional[date] = None
    vessel_id: Optional[int] = None

class VoyageRead(VoyageBase):
    voyage_id: int
    model_config = ConfigDict(from_attributes=True)


# ==========================================
# POLICY
# ==========================================
class PolicyBase(BaseModel):
    issue_date: Optional[date] = None
    expiry_date: Optional[date] = None
    premium: Optional[Decimal] = None
    sum_insured: Optional[Decimal] = None
    policy_type: Optional[Literal["HULL", "CARGO", "PI"]] = None
    vessel_value_covered: Optional[Decimal] = None
    cargo_type: Optional[str] = Field(None, max_length=50)
    liability_limit: Optional[Decimal] = None
    status: Optional[str] = "DRAFT"
    deductible: Optional[Decimal] = Decimal("10000.00")
    client_id: Optional[int] = None
    broker_id: Optional[int] = None
    emp_id: Optional[int] = None
    vessel_id: Optional[int] = None
    cargo_id: Optional[int] = None

class PolicyCreate(PolicyBase):
    pass

class PolicyUpdate(BaseModel):
    issue_date: Optional[date] = None
    expiry_date: Optional[date] = None
    premium: Optional[Decimal] = None
    sum_insured: Optional[Decimal] = None
    policy_type: Optional[Literal["HULL", "CARGO", "PI"]] = None
    vessel_value_covered: Optional[Decimal] = None
    cargo_type: Optional[str] = Field(None, max_length=50)
    liability_limit: Optional[Decimal] = None
    status: Optional[str] = None
    deductible: Optional[Decimal] = None
    client_id: Optional[int] = None
    broker_id: Optional[int] = None
    emp_id: Optional[int] = None
    vessel_id: Optional[int] = None
    cargo_id: Optional[int] = None

class PolicyRead(PolicyBase):
    policy_no: int
    model_config = ConfigDict(from_attributes=True)


# ==========================================
# CLAIM
# ==========================================
class ClaimBase(BaseModel):
    loss_date: Optional[date] = None
    claim_amount: Optional[Decimal] = None
    policy_no: Optional[int] = None
    status: Optional[str] = "REPORTED"
    deductible_applied: Optional[Decimal] = Decimal("0.00")
    settled_amount: Optional[Decimal] = None

class ClaimCreate(ClaimBase):
    pass

class ClaimUpdate(BaseModel):
    loss_date: Optional[date] = None
    claim_amount: Optional[Decimal] = None
    policy_no: Optional[int] = None
    status: Optional[str] = None
    deductible_applied: Optional[Decimal] = None
    settled_amount: Optional[Decimal] = None

class ClaimRead(ClaimBase):
    claim_id: int
    model_config = ConfigDict(from_attributes=True)


# ==========================================
# REINSURED_BY (Junction)
# ==========================================
class ReinsuredByBase(BaseModel):
    share_percent: Optional[Decimal] = None

class ReinsuredByCreate(ReinsuredByBase):
    policy_no: int
    reinsurer_id: int

class ReinsuredByUpdate(ReinsuredByBase):
    pass

class ReinsuredByRead(ReinsuredByBase):
    policy_no: int
    reinsurer_id: int
    model_config = ConfigDict(from_attributes=True)


# ==========================================
# ASSESSED_BY (Junction)
# ==========================================
class AssessedByBase(BaseModel):
    claim_id: int
    surveyor_id: int

class AssessedByCreate(AssessedByBase):
    pass

class AssessedByRead(AssessedByBase):
    model_config = ConfigDict(from_attributes=True)


# ==========================================
# CARRIES (Junction)
# ==========================================
class CarriesBase(BaseModel):
    voyage_id: int
    cargo_id: int

class CarriesCreate(CarriesBase):
    pass

class CarriesRead(CarriesBase):
    model_config = ConfigDict(from_attributes=True)
