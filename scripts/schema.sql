-- 1. INDEPENDENT TABLES (No Foreign Keys)

CREATE TABLE IF NOT EXISTS CLIENT (
    client_id INT AUTO_INCREMENT PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    address VARCHAR(255)
);

CREATE TABLE IF NOT EXISTS BROKER (
    broker_id INT AUTO_INCREMENT PRIMARY KEY,
    agency_name VARCHAR(100) NOT NULL,
    licence_no VARCHAR(50) UNIQUE NOT NULL
);

CREATE TABLE IF NOT EXISTS SURVEYOR (
    surveyor_id INT AUTO_INCREMENT PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    qualification VARCHAR(100)
);

CREATE TABLE IF NOT EXISTS REINSURER (
    reinsurer_id INT AUTO_INCREMENT PRIMARY KEY,
    name VARCHAR(100) NOT NULL
);

CREATE TABLE IF NOT EXISTS CARGO (
    cargo_id INT AUTO_INCREMENT PRIMARY KEY,
    description VARCHAR(255),
    value DECIMAL(12, 2)
);

CREATE TABLE IF NOT EXISTS VESSEL (
    vessel_id INT AUTO_INCREMENT PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    imo_number VARCHAR(20) UNIQUE NOT NULL,
    tonnage INT,
    flag VARCHAR(50)
);

CREATE TABLE IF NOT EXISTS DEPARTMENT (
    dept_id INT AUTO_INCREMENT PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    location VARCHAR(100)
);

-- 2. DEPENDENT TABLES (Contains Foreign Keys)

CREATE TABLE IF NOT EXISTS UNDERWRITER (
    emp_id INT AUTO_INCREMENT PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    designation VARCHAR(50),
    dept_id INT,
    FOREIGN KEY (dept_id) REFERENCES DEPARTMENT(dept_id) ON DELETE SET NULL
);

CREATE TABLE IF NOT EXISTS VOYAGE (
    voyage_id INT AUTO_INCREMENT PRIMARY KEY,
    origin_port VARCHAR(100),
    dest_port VARCHAR(100),
    depart_date DATE,
    vessel_id INT,
    FOREIGN KEY (vessel_id) REFERENCES VESSEL(vessel_id) ON DELETE SET NULL
);

CREATE TABLE IF NOT EXISTS POLICY (
    policy_no INT AUTO_INCREMENT PRIMARY KEY,
    issue_date DATE,
    expiry_date DATE,
    premium DECIMAL(10, 2),
    sum_insured DECIMAL(12, 2),
    policy_type VARCHAR(20) CHECK (policy_type IN ('HULL', 'CARGO', 'PI')),
    vessel_value_covered DECIMAL(12, 2),
    cargo_type VARCHAR(50),
    liability_limit DECIMAL(12, 2),
    client_id INT,
    broker_id INT,
    emp_id INT,
    vessel_id INT,
    cargo_id INT,
    FOREIGN KEY (client_id) REFERENCES CLIENT(client_id) ON DELETE SET NULL,
    FOREIGN KEY (broker_id) REFERENCES BROKER(broker_id) ON DELETE SET NULL,
    FOREIGN KEY (emp_id) REFERENCES UNDERWRITER(emp_id) ON DELETE SET NULL,
    FOREIGN KEY (vessel_id) REFERENCES VESSEL(vessel_id) ON DELETE SET NULL,
    FOREIGN KEY (cargo_id) REFERENCES CARGO(cargo_id) ON DELETE SET NULL
);

CREATE TABLE IF NOT EXISTS CLAIM (
    claim_id INT AUTO_INCREMENT PRIMARY KEY,
    loss_date DATE,
    claim_amount DECIMAL(12, 2),
    policy_no INT,
    FOREIGN KEY (policy_no) REFERENCES POLICY(policy_no) ON DELETE CASCADE
);

-- 3. JUNCTION TABLES (Many-to-Many Relationships)

CREATE TABLE IF NOT EXISTS REINSURED_BY (
    policy_no INT,
    reinsurer_id INT,
    share_percent DECIMAL(5, 2),
    PRIMARY KEY (policy_no, reinsurer_id),
    FOREIGN KEY (policy_no) REFERENCES POLICY(policy_no) ON DELETE CASCADE,
    FOREIGN KEY (reinsurer_id) REFERENCES REINSURER(reinsurer_id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS ASSESSED_BY (
    claim_id INT,
    surveyor_id INT,
    PRIMARY KEY (claim_id, surveyor_id),
    FOREIGN KEY (claim_id) REFERENCES CLAIM(claim_id) ON DELETE CASCADE,
    FOREIGN KEY (surveyor_id) REFERENCES SURVEYOR(surveyor_id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS CARRIES (
    voyage_id INT,
    cargo_id INT,
    PRIMARY KEY (voyage_id, cargo_id),
    FOREIGN KEY (voyage_id) REFERENCES VOYAGE(voyage_id) ON DELETE CASCADE,
    FOREIGN KEY (cargo_id) REFERENCES CARGO(cargo_id) ON DELETE CASCADE
);
