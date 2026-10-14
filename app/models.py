from sqlalchemy import Column, Integer, String, Numeric, Date, ForeignKey, CheckConstraint
from sqlalchemy.orm import relationship
from app.database import Base

class Client(Base):
    __tablename__ = "CLIENT"

    client_id = Column(Integer, primary_key=True, autoincrement=True, index=True)
    name = Column(String(100), nullable=False)
    address = Column(String(255), nullable=True)

    policies = relationship("Policy", back_populates="client")


class Broker(Base):
    __tablename__ = "BROKER"

    broker_id = Column(Integer, primary_key=True, autoincrement=True, index=True)
    agency_name = Column(String(100), nullable=False)
    licence_no = Column(String(50), unique=True, nullable=False)

    policies = relationship("Policy", back_populates="broker")


class Surveyor(Base):
    __tablename__ = "SURVEYOR"

    surveyor_id = Column(Integer, primary_key=True, autoincrement=True, index=True)
    name = Column(String(100), nullable=False)
    qualification = Column(String(100), nullable=True)

    assessed_claims = relationship("AssessedBy", back_populates="surveyor", cascade="all, delete-orphan", passive_deletes=True)


class Reinsurer(Base):
    __tablename__ = "REINSURER"

    reinsurer_id = Column(Integer, primary_key=True, autoincrement=True, index=True)
    name = Column(String(100), nullable=False)

    reinsured_policies = relationship("ReinsuredBy", back_populates="reinsurer", cascade="all, delete-orphan", passive_deletes=True)


class Cargo(Base):
    __tablename__ = "CARGO"

    cargo_id = Column(Integer, primary_key=True, autoincrement=True, index=True)
    description = Column(String(255), nullable=True)
    value = Column(Numeric(12, 2), nullable=True)

    policies = relationship("Policy", back_populates="cargo")
    voyage_carries = relationship("Carries", back_populates="cargo", cascade="all, delete-orphan", passive_deletes=True)


class Vessel(Base):
    __tablename__ = "VESSEL"

    vessel_id = Column(Integer, primary_key=True, autoincrement=True, index=True)
    name = Column(String(100), nullable=False)
    imo_number = Column(String(20), unique=True, nullable=False)
    tonnage = Column(Integer, nullable=True)
    flag = Column(String(50), nullable=True)

    policies = relationship("Policy", back_populates="vessel")
    voyages = relationship("Voyage", back_populates="vessel")


class Department(Base):
    __tablename__ = "DEPARTMENT"

    dept_id = Column(Integer, primary_key=True, autoincrement=True, index=True)
    name = Column(String(100), nullable=False)
    location = Column(String(100), nullable=True)

    underwriters = relationship("Underwriter", back_populates="department")


class Underwriter(Base):
    __tablename__ = "UNDERWRITER"

    emp_id = Column(Integer, primary_key=True, autoincrement=True, index=True)
    name = Column(String(100), nullable=False)
    designation = Column(String(50), nullable=True)
    dept_id = Column(Integer, ForeignKey("DEPARTMENT.dept_id"), nullable=True)

    department = relationship("Department", back_populates="underwriters")
    policies = relationship("Policy", back_populates="underwriter")


class Voyage(Base):
    __tablename__ = "VOYAGE"

    voyage_id = Column(Integer, primary_key=True, autoincrement=True, index=True)
    origin_port = Column(String(100), nullable=True)
    dest_port = Column(String(100), nullable=True)
    depart_date = Column(Date, nullable=True)
    vessel_id = Column(Integer, ForeignKey("VESSEL.vessel_id"), nullable=True)

    vessel = relationship("Vessel", back_populates="voyages")
    carried_cargos = relationship("Carries", back_populates="voyage", cascade="all, delete-orphan", passive_deletes=True)


class Policy(Base):
    __tablename__ = "POLICY"
    __table_args__ = (
        CheckConstraint("policy_type IN ('HULL', 'CARGO', 'PI')", name="check_policy_type"),
    )

    policy_no = Column(Integer, primary_key=True, autoincrement=True, index=True)
    issue_date = Column(Date, nullable=True)
    expiry_date = Column(Date, nullable=True)
    premium = Column(Numeric(10, 2), nullable=True)
    sum_insured = Column(Numeric(12, 2), nullable=True)
    policy_type = Column(String(20), nullable=True)
    vessel_value_covered = Column(Numeric(12, 2), nullable=True)
    cargo_type = Column(String(50), nullable=True)
    liability_limit = Column(Numeric(12, 2), nullable=True)
    status = Column(String(20), default="DRAFT", nullable=False)
    deductible = Column(Numeric(12, 2), default=10000.00, nullable=False)

    client_id = Column(Integer, ForeignKey("CLIENT.client_id"), nullable=True)
    broker_id = Column(Integer, ForeignKey("BROKER.broker_id"), nullable=True)
    emp_id = Column(Integer, ForeignKey("UNDERWRITER.emp_id"), nullable=True)
    vessel_id = Column(Integer, ForeignKey("VESSEL.vessel_id"), nullable=True)
    cargo_id = Column(Integer, ForeignKey("CARGO.cargo_id"), nullable=True)

    client = relationship("Client", back_populates="policies")
    broker = relationship("Broker", back_populates="policies")
    underwriter = relationship("Underwriter", back_populates="policies")
    vessel = relationship("Vessel", back_populates="policies")
    cargo = relationship("Cargo", back_populates="policies")
    claims = relationship("Claim", back_populates="policy", cascade="all, delete-orphan", passive_deletes=True)
    reinsurers = relationship("ReinsuredBy", back_populates="policy", cascade="all, delete-orphan", passive_deletes=True)


class Claim(Base):
    __tablename__ = "CLAIM"

    claim_id = Column(Integer, primary_key=True, autoincrement=True, index=True)
    loss_date = Column(Date, nullable=True)
    claim_amount = Column(Numeric(12, 2), nullable=True)
    policy_no = Column(Integer, ForeignKey("POLICY.policy_no"), nullable=True)
    status = Column(String(20), default="REPORTED", nullable=False)
    deductible_applied = Column(Numeric(12, 2), default=0.00, nullable=False)
    settled_amount = Column(Numeric(12, 2), nullable=True)

    policy = relationship("Policy", back_populates="claims")
    surveyors = relationship("AssessedBy", back_populates="claim", cascade="all, delete-orphan", passive_deletes=True)


class ReinsuredBy(Base):
    __tablename__ = "REINSURED_BY"

    policy_no = Column(Integer, ForeignKey("POLICY.policy_no"), primary_key=True)
    reinsurer_id = Column(Integer, ForeignKey("REINSURER.reinsurer_id"), primary_key=True)
    share_percent = Column(Numeric(5, 2), nullable=True)

    policy = relationship("Policy", back_populates="reinsurers")
    reinsurer = relationship("Reinsurer", back_populates="reinsured_policies")


class AssessedBy(Base):
    __tablename__ = "ASSESSED_BY"

    claim_id = Column(Integer, ForeignKey("CLAIM.claim_id"), primary_key=True)
    surveyor_id = Column(Integer, ForeignKey("SURVEYOR.surveyor_id"), primary_key=True)

    claim = relationship("Claim", back_populates="surveyors")
    surveyor = relationship("Surveyor", back_populates="assessed_claims")


class Carries(Base):
    __tablename__ = "CARRIES"

    voyage_id = Column(Integer, ForeignKey("VOYAGE.voyage_id"), primary_key=True)
    cargo_id = Column(Integer, ForeignKey("CARGO.cargo_id"), primary_key=True)

    voyage = relationship("Voyage", back_populates="carried_cargos")
    cargo = relationship("Cargo", back_populates="voyage_carries")
