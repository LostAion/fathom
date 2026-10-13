import os
import pymysql
from dotenv import load_dotenv

load_dotenv()

DB_HOST = os.getenv("DB_HOST", "127.0.0.1")
DB_PORT = int(os.getenv("DB_PORT", "3306"))
DB_USER = os.getenv("DB_USER", "root")
DB_PASSWORD = os.getenv("DB_PASSWORD", "mysecretpassword")
DB_NAME = os.getenv("DB_NAME", "marine_insurance")

def seed_database():
    print(f"Connecting to {DB_NAME} to insert initial seed data...")
    conn = pymysql.connect(
        host=DB_HOST,
        port=DB_PORT,
        user=DB_USER,
        password=DB_PASSWORD,
        database=DB_NAME,
        autocommit=True
    )
    
    with conn.cursor() as cur:
        # Check if already seeded
        cur.execute("SELECT COUNT(*) FROM CLIENT")
        if cur.fetchone()[0] > 0:
            print("Database already contains data. Skipping seeding.")
            conn.close()
            return
            
        print("Inserting seed data...")
        
        # 1. Independent Tables
        cur.execute("""
            INSERT INTO CLIENT (name, address) VALUES
            ('Oceanic Shipping Corp', '100 Harbour View, Singapore'),
            ('Atlantic Cargo Lines', '42 Docklands Way, London, UK'),
            ('Pacific Global Logistics', '777 Marina Blvd, San Francisco, USA');
        """)
        
        cur.execute("""
            INSERT INTO BROKER (agency_name, licence_no) VALUES
            ('Apex Maritime Brokers Ltd', 'BRK-2024-001'),
            ('BlueWave Risk Solutions', 'BRK-2024-002');
        """)
        
        cur.execute("""
            INSERT INTO SURVEYOR (name, qualification) VALUES
            ('Capt. Robert Vance', 'Master Mariner, Certified Marine Surveyor'),
            ('Dr. Elena Rostova', 'PhD Naval Architecture, IIMS Fellow');
        """)
        
        cur.execute("""
            INSERT INTO REINSURER (name) VALUES
            ('Swiss Marine Reinsurance AG'),
            ('Munich Global Re');
        """)
        
        cur.execute("""
            INSERT INTO CARGO (description, value) VALUES
            ('Containerized Consumer Electronics', 2500000.00),
            ('Refined Petroleum Products (40,000 MT)', 6200000.00),
            ('Bulk Wheat Grain (25,000 MT)', 1100000.00);
        """)
        
        cur.execute("""
            INSERT INTO VESSEL (name, imo_number, tonnage, flag) VALUES
            ('Ever Pioneer', 'IMO9123456', 85000, 'Panama'),
            ('Nordic Guardian', 'IMO9654321', 115000, 'Liberia'),
            ('Pacific Voyager', 'IMO9789012', 62000, 'Singapore');
        """)
        
        cur.execute("""
            INSERT INTO DEPARTMENT (name, location) VALUES
            ('Hull & Machinery Underwriting', 'Tower A, Floor 12, London HQ'),
            ('Cargo & Logistics Risk', 'Tower A, Floor 11, London HQ'),
            ('Marine Claims & Recovery', 'Tower B, Floor 4, London HQ');
        """)
        
        # 2. Dependent Tables
        cur.execute("""
            INSERT INTO UNDERWRITER (name, designation, dept_id) VALUES
            ('James Montgomery', 'Senior Hull Underwriter', 1),
            ('Sarah Jenkins', 'Lead Cargo Risk Underwriter', 2),
            ('Marcus Zhao', 'Junior Marine Underwriter', 1);
        """)
        
        cur.execute("""
            INSERT INTO VOYAGE (origin_port, dest_port, depart_date, vessel_id) VALUES
            ('Rotterdam', 'Singapore', '2026-11-01', 1),
            ('Shanghai', 'Los Angeles', '2026-11-15', 2),
            ('Yokohama', 'Hamburg', '2026-12-01', 3);
        """)
        
        cur.execute("""
            INSERT INTO POLICY (issue_date, expiry_date, premium, sum_insured, policy_type, vessel_value_covered, cargo_type, liability_limit, client_id, broker_id, emp_id, vessel_id, cargo_id) VALUES
            ('2026-01-01', '2026-12-31', 45000.00, 50000000.00, 'HULL', 50000000.00, NULL, NULL, 1, 1, 1, 1, NULL),
            ('2026-02-01', '2026-08-01', 12500.00, 2500000.00, 'CARGO', NULL, 'Containerized Electronics', NULL, 2, 2, 2, 1, 1),
            ('2026-03-01', '2027-02-28', 75000.00, 100000000.00, 'PI', NULL, NULL, 100000000.00, 3, 1, 1, 2, NULL);
        """)
        
        cur.execute("""
            INSERT INTO CLAIM (loss_date, claim_amount, policy_no) VALUES
            ('2026-05-14', 185000.00, 2),
            ('2026-07-22', 450000.00, 1);
        """)
        
        # 3. Junction Tables
        cur.execute("""
            INSERT INTO REINSURED_BY (policy_no, reinsurer_id, share_percent) VALUES
            (1, 1, 40.00),
            (1, 2, 35.00),
            (3, 1, 50.00);
        """)
        
        cur.execute("""
            INSERT INTO ASSESSED_BY (claim_id, surveyor_id) VALUES
            (1, 1),
            (2, 1),
            (2, 2);
        """)
        
        cur.execute("""
            INSERT INTO CARRIES (voyage_id, cargo_id) VALUES
            (1, 1),
            (2, 2),
            (3, 3);
        """)
        
    conn.close()
    print("Seed data inserted successfully!")

if __name__ == "__main__":
    seed_database()
