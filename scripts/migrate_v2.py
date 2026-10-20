import os
import pymysql
from dotenv import load_dotenv

load_dotenv()

DB_HOST = os.getenv("DB_HOST", "127.0.0.1")
DB_PORT = int(os.getenv("DB_PORT", "3306"))
DB_USER = os.getenv("DB_USER", "root")
DB_PASSWORD = os.getenv("DB_PASSWORD", "mysecretpassword")
DB_NAME = os.getenv("DB_NAME", "marine_insurance")

MIGRATIONS = [
    # Enhanced fields on POLICY
    "ALTER TABLE POLICY ADD COLUMN IF NOT EXISTS underwriting_report JSON NULL;",
    "ALTER TABLE POLICY ADD COLUMN IF NOT EXISTS status VARCHAR(20) DEFAULT 'DRAFT';",
    "ALTER TABLE POLICY ADD COLUMN IF NOT EXISTS deductible DECIMAL(12, 2) DEFAULT 10000.00;",
    "ALTER TABLE POLICY ADD COLUMN IF NOT EXISTS underwriting_decision VARCHAR(30) NULL;",
    "ALTER TABLE POLICY ADD COLUMN IF NOT EXISTS risk_score INT NULL;",
    "ALTER TABLE POLICY ADD COLUMN IF NOT EXISTS warranties TEXT NULL;",
    "ALTER TABLE POLICY ADD COLUMN IF NOT EXISTS awrp_surcharge DECIMAL(5, 2) DEFAULT 0.00;",
    "ALTER TABLE POLICY ADD COLUMN IF NOT EXISTS is_active BOOLEAN DEFAULT TRUE;",

    # Enhanced fields on CLAIM
    "ALTER TABLE CLAIM ADD COLUMN IF NOT EXISTS status VARCHAR(20) DEFAULT 'REPORTED';",
    "ALTER TABLE CLAIM ADD COLUMN IF NOT EXISTS reserve_amount DECIMAL(12, 2) NULL;",
    "ALTER TABLE CLAIM ADD COLUMN IF NOT EXISTS deductible_applied DECIMAL(12, 2) DEFAULT 0.00;",
    "ALTER TABLE CLAIM ADD COLUMN IF NOT EXISTS settled_amount DECIMAL(12, 2) NULL;",
    "ALTER TABLE CLAIM ADD COLUMN IF NOT EXISTS is_active BOOLEAN DEFAULT TRUE;",

    # Populate defaults for pre-existing rows
    "UPDATE POLICY SET status = 'DRAFT' WHERE status IS NULL;",
    "UPDATE POLICY SET deductible = 10000.00 WHERE deductible IS NULL;",
    "UPDATE POLICY SET awrp_surcharge = 0.00 WHERE awrp_surcharge IS NULL;",
    "UPDATE POLICY SET is_active = TRUE WHERE is_active IS NULL;",
    "UPDATE CLAIM SET status = 'REPORTED' WHERE status IS NULL;",
    "UPDATE CLAIM SET deductible_applied = 0.00 WHERE deductible_applied IS NULL;",
    "UPDATE CLAIM SET is_active = TRUE WHERE is_active IS NULL;",
]

def run_migration():
    print(f"Connecting to {DB_NAME} at {DB_HOST}:{DB_PORT} as {DB_USER} for v2 migration...")
    conn = pymysql.connect(
        host=DB_HOST,
        port=DB_PORT,
        user=DB_USER,
        password=DB_PASSWORD,
        database=DB_NAME,
        autocommit=True
    )

    with conn.cursor() as cursor:
        for stmt in MIGRATIONS:
            print(f"Executing: {stmt}")
            cursor.execute(stmt)

    conn.close()
    print("Migration v2 completed successfully!")

if __name__ == "__main__":
    run_migration()
