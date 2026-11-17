"""Account and demo-data commands for the ASD-Sense backend. Does not load TensorFlow.

    python manage.py create-clinician --name "Dr Sara Ali" --email sara@clinic.example
    python manage.py set-password --email sara@clinic.example
    python manage.py seed-demo

The database is ASD_SENSE_DB_PATH, or backend/asd_sense.db when it is not set
(the same rule as main.py). Clinicians cannot sign up themselves; their
accounts are issued here and they sign in on the clinician portal (specialist_web).
"""
from __future__ import annotations

import argparse
import getpass
import os
import sqlite3
import sys
from datetime import datetime, timedelta, timezone
from pathlib import Path

from auth_api import _password_hash
from clinic_api import CLINIC_ROLES, log_activity

BASE_DIR = Path(__file__).resolve().parent
SCHEMA_PATH = BASE_DIR / "asd_sense_database_schema.sql"

DEMO_CLINICIAN = ("Dr Demo Clinician", "clinician@asdsense.com", "Clinic#2026demo")
DEMO_GUARDIAN = ("Demo Guardian", "guardian@asdsense.com", "Guardian#2026demo")


def db_path() -> Path:
    return Path(os.environ.get("ASD_SENSE_DB_PATH", BASE_DIR / "asd_sense.db"))


def connect(path: Path) -> sqlite3.Connection:
    conn = sqlite3.connect(path)
    conn.row_factory = sqlite3.Row
    conn.execute("PRAGMA foreign_keys = ON")
    conn.executescript(SCHEMA_PATH.read_text(encoding="utf-8"))
    return conn


def _check_password(password: str) -> None:
    # Same rule as sign-up and sign-in (auth_api.Credentials).
    if not 12 <= len(password) <= 128:
        sys.exit("The password must be 12 to 128 characters.")


def create_user(conn: sqlite3.Connection, name: str, email: str, password: str, role: str) -> int:
    email = email.strip().casefold()
    if conn.execute("SELECT 1 FROM Users WHERE email = ?", (email,)).fetchone():
        raise ValueError(f"An account with {email} already exists.")
    cur = conn.execute(
        "INSERT INTO Users (full_name, email, password_hash, role) VALUES (?, ?, ?, ?)",
        (name.strip(), email, _password_hash(password), role),
    )
    if role in CLINIC_ROLES:
        conn.execute("INSERT OR IGNORE INTO Clinician_Profiles (user_id) VALUES (?)", (cur.lastrowid,))
    return int(cur.lastrowid)


def cmd_create_clinician(args: argparse.Namespace) -> None:
    password = args.password or getpass.getpass("Password (12+ characters): ")
    _check_password(password)
    with connect(db_path()) as conn:
        try:
            user_id = create_user(conn, args.name, args.email, password, "admin" if args.admin else "clinician")
        except ValueError as e:
            sys.exit(str(e))
    print(f"Created clinician account {args.email} (user_id {user_id}) in {db_path()}")


def cmd_set_password(args: argparse.Namespace) -> None:
    """For clinicians (guardians can reset theirs from the app's sign-in screen)."""
    password = args.password or getpass.getpass("New password (12+ characters): ")
    _check_password(password)
    email = args.email.strip().casefold()
    with connect(db_path()) as conn:
        user = conn.execute("SELECT user_id FROM Users WHERE email = ?", (email,)).fetchone()
        if user is None:
            sys.exit(f"No account with {email}.")
        conn.execute("UPDATE Users SET password_hash = ?, updated_at = CURRENT_TIMESTAMP WHERE user_id = ?",
                     (_password_hash(password), user["user_id"]))
        conn.execute("UPDATE Auth_Sessions SET revoked_at = strftime('%s','now') "
                     "WHERE user_id = ? AND revoked_at IS NULL", (user["user_id"],))
    print(f"Password changed for {email}; its sessions were signed out.")


def cmd_seed_demo(_args: argparse.Namespace) -> None:
    """Demo accounts and a little sample data. Never use these accounts on a real deployment."""
    with connect(db_path()) as conn:
        if conn.execute("SELECT 1 FROM Users WHERE email = ?", (DEMO_CLINICIAN[1],)).fetchone():
            print("Demo data is already there.")
        else:
            clinician = create_user(conn, *DEMO_CLINICIAN, role="clinician")
            conn.execute(
                """UPDATE Clinician_Profiles SET job_title = 'Developmental Paediatrician',
                specialty = 'Developmental paediatrics', clinic_name = 'ASD-Sense Demo Clinic'
                WHERE user_id = ?""", (clinician,))
            guardian = create_user(conn, *DEMO_GUARDIAN, role="guardian")
            child = conn.execute(
                "INSERT INTO Child_Profiles (user_id, first_name, date_of_birth) VALUES (?, 'Demo Child', '2022-04-12')",
                (guardian,)).lastrowid
            conn.execute(
                """INSERT INTO Screening_Records (child_id, performed_by_user_id, model_name, model_version,
                predicted_class, autism_probability, confidence, notes)
                VALUES (?, ?, 'Simulated_Facial_Model', '1.0', 'autistic', 0.86, 0.86,
                        'Demo data (not a real screening)')""", (child, guardian))
            when = (datetime.now(timezone.utc) + timedelta(days=3)).replace(hour=6, minute=0, second=0, microsecond=0)
            conn.execute(
                """INSERT INTO Appointments (child_id, user_id, scheduled_at, location, appointment_type)
                VALUES (?, ?, ?, 'ASD-Sense Demo Clinic', 'Personal reminder (not provider-confirmed)')""",
                (child, guardian, when.isoformat()))
            log_activity(conn, clinician, "Demo data added")
    print(f"Demo data is in {db_path()}. Demo accounts (do not use these on a real deployment):")
    print(f"  Clinician portal: {DEMO_CLINICIAN[1]} / {DEMO_CLINICIAN[2]}")
    print(f"  Guardian app:     {DEMO_GUARDIAN[1]} / {DEMO_GUARDIAN[2]}")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    commands = parser.add_subparsers(dest="command", required=True)
    clinician = commands.add_parser("create-clinician", help="issue a clinician portal account")
    clinician.add_argument("--name", required=True)
    clinician.add_argument("--email", required=True)
    clinician.add_argument("--password", help="asked for on the terminal when omitted")
    clinician.add_argument("--admin", action="store_true", help="create an admin instead of a clinician")
    clinician.set_defaults(run=cmd_create_clinician)
    password = commands.add_parser("set-password", help="set any account's password and sign it out")
    password.add_argument("--email", required=True)
    password.add_argument("--password", help="asked for on the terminal when omitted")
    password.set_defaults(run=cmd_set_password)
    demo = commands.add_parser("seed-demo", help="add demo accounts and sample data")
    demo.set_defaults(run=cmd_seed_demo)
    args = parser.parse_args()
    args.run(args)


if __name__ == "__main__":
    main()
