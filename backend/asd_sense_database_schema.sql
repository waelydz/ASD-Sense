PRAGMA foreign_keys = ON;

CREATE TABLE IF NOT EXISTS Users (
    user_id INTEGER PRIMARY KEY AUTOINCREMENT,
    full_name TEXT NOT NULL,
    email TEXT NOT NULL UNIQUE,
    password_hash TEXT NOT NULL,
    phone TEXT,
    role TEXT NOT NULL DEFAULT 'parent'
        CHECK (role IN ('parent', 'guardian', 'clinician', 'admin')),
    created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS Child_Profiles (
    child_id INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id INTEGER NOT NULL,
    first_name TEXT NOT NULL,
    last_name TEXT,
    date_of_birth TEXT NOT NULL,
    sex TEXT CHECK (sex IN ('female', 'male', 'other', 'prefer_not_to_say')),
    relationship_to_user TEXT,
    notes TEXT,
    created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (user_id) REFERENCES Users(user_id)
        ON UPDATE CASCADE
        ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS Screening_Records (
    screening_id INTEGER PRIMARY KEY AUTOINCREMENT,
    child_id INTEGER NOT NULL,
    performed_by_user_id INTEGER,
    screening_date TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    model_name TEXT NOT NULL,
    model_version TEXT,
    predicted_class TEXT NOT NULL
        CHECK (predicted_class IN ('autistic', 'non_autistic', 'inconclusive')),
    autism_probability REAL
        CHECK (autism_probability IS NULL OR (autism_probability >= 0.0 AND autism_probability <= 1.0)),
    confidence REAL
        CHECK (confidence IS NULL OR (confidence >= 0.0 AND confidence <= 1.0)),
    image_reference TEXT,
    notes TEXT,
    created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (child_id) REFERENCES Child_Profiles(child_id)
        ON UPDATE CASCADE
        ON DELETE CASCADE,
    FOREIGN KEY (performed_by_user_id) REFERENCES Users(user_id)
        ON UPDATE CASCADE
        ON DELETE SET NULL
);

CREATE TABLE IF NOT EXISTS Appointments (
    appointment_id INTEGER PRIMARY KEY AUTOINCREMENT,
    child_id INTEGER NOT NULL,
    user_id INTEGER NOT NULL,
    scheduled_at TEXT NOT NULL,
    clinician_name TEXT,
    appointment_type TEXT,
    location TEXT,
    status TEXT NOT NULL DEFAULT 'scheduled'
        CHECK (status IN ('scheduled', 'confirmed', 'completed', 'cancelled', 'no_show')),
    notes TEXT,
    created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (child_id) REFERENCES Child_Profiles(child_id)
        ON UPDATE CASCADE
        ON DELETE CASCADE,
    FOREIGN KEY (user_id) REFERENCES Users(user_id)
        ON UPDATE CASCADE
        ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_child_profiles_user_id
    ON Child_Profiles(user_id);

CREATE INDEX IF NOT EXISTS idx_screening_records_child_id
    ON Screening_Records(child_id);

CREATE INDEX IF NOT EXISTS idx_screening_records_date
    ON Screening_Records(screening_date);

CREATE INDEX IF NOT EXISTS idx_appointments_child_id
    ON Appointments(child_id);

CREATE INDEX IF NOT EXISTS idx_appointments_user_id
    ON Appointments(user_id);

CREATE INDEX IF NOT EXISTS idx_appointments_scheduled_at
    ON Appointments(scheduled_at);

-- Non-destructive auth migration: only new accounts with valid password hashes
-- can sign in. Existing Users/Child_Profiles/Screening_Records remain intact.
CREATE TABLE IF NOT EXISTS Auth_Sessions (
    session_id INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id INTEGER NOT NULL,
    token_hash TEXT NOT NULL UNIQUE,
    expires_at INTEGER NOT NULL,
    revoked_at INTEGER,
    created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (user_id) REFERENCES Users(user_id) ON DELETE CASCADE
);
CREATE INDEX IF NOT EXISTS idx_auth_sessions_user_id ON Auth_Sessions(user_id);

-- Additive persistence migration; existing tables and rows remain unchanged.
-- Physical document bytes live outside the Git checkout and use random filenames.
CREATE TABLE IF NOT EXISTS Medical_Records (
    record_id INTEGER PRIMARY KEY AUTOINCREMENT,
    child_id INTEGER NOT NULL,
    uploaded_by_user_id INTEGER NOT NULL,
    file_name TEXT NOT NULL,
    storage_key TEXT NOT NULL UNIQUE,
    content_type TEXT NOT NULL,
    file_size INTEGER NOT NULL CHECK (file_size >= 1),
    record_type TEXT NOT NULL CHECK (record_type IN ('document', 'imaging')),
    created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (child_id) REFERENCES Child_Profiles(child_id) ON DELETE RESTRICT,
    FOREIGN KEY (uploaded_by_user_id) REFERENCES Users(user_id) ON DELETE RESTRICT
);
CREATE INDEX IF NOT EXISTS idx_medical_records_child_id ON Medical_Records(child_id);

CREATE TABLE IF NOT EXISTS User_Preferences (
    user_id INTEGER PRIMARY KEY,
    push_notifications INTEGER NOT NULL DEFAULT 1 CHECK (push_notifications IN (0, 1)),
    email_notifications INTEGER NOT NULL DEFAULT 0 CHECK (email_notifications IN (0, 1)),
    updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (user_id) REFERENCES Users(user_id) ON DELETE CASCADE
);

-- Clinician portal (specialist_web) migration; additive like the ones above.
-- Used by clinic_api.py. Guardian tables and routes are unchanged.

-- Professional profile and portal preferences of clinician/admin accounts.
CREATE TABLE IF NOT EXISTS Clinician_Profiles (
    user_id INTEGER PRIMARY KEY,
    job_title TEXT NOT NULL DEFAULT '',
    specialty TEXT NOT NULL DEFAULT '',
    clinic_name TEXT NOT NULL DEFAULT '',
    licence_number TEXT NOT NULL DEFAULT '',
    languages TEXT NOT NULL DEFAULT '',
    bio TEXT NOT NULL DEFAULT '',
    use_24_hour_time INTEGER NOT NULL DEFAULT 0 CHECK (use_24_hour_time IN (0, 1)),
    auto_sign_out_minutes INTEGER NOT NULL DEFAULT 15,
    password_changed_at TEXT,
    FOREIGN KEY (user_id) REFERENCES Users(user_id) ON DELETE CASCADE
);

-- Family contact details for children added in the portal rather than by a
-- guardian in the app. Such a child's Child_Profiles.user_id is the clinician.
CREATE TABLE IF NOT EXISTS Clinic_Patients (
    child_id INTEGER PRIMARY KEY,
    added_by_user_id INTEGER NOT NULL,
    guardian_name TEXT NOT NULL,
    guardian_phone TEXT NOT NULL DEFAULT '',
    guardian_email TEXT NOT NULL DEFAULT '',
    referral_source TEXT NOT NULL DEFAULT '',
    FOREIGN KEY (child_id) REFERENCES Child_Profiles(child_id) ON DELETE CASCADE,
    FOREIGN KEY (added_by_user_id) REFERENCES Users(user_id)
);

-- A clinician's review of one screening result. Clinic-only: not shown to families.
CREATE TABLE IF NOT EXISTS Screening_Reviews (
    screening_id INTEGER PRIMARY KEY,
    finding TEXT NOT NULL CHECK (finding IN ('agree', 'disagree', 'needs_more_info')),
    action TEXT NOT NULL
        CHECK (action IN ('refer_diagnostic', 'rescreen', 'monitor', 'no_further_action')),
    note TEXT NOT NULL DEFAULT '',
    reviewer_user_id INTEGER,
    reviewer_name TEXT NOT NULL,
    reviewed_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (screening_id) REFERENCES Screening_Records(screening_id) ON DELETE CASCADE,
    FOREIGN KEY (reviewer_user_id) REFERENCES Users(user_id) ON DELETE SET NULL
);

-- What a clinician did, shown on the portal's Security page.
CREATE TABLE IF NOT EXISTS Clinic_Activity (
    activity_id INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id INTEGER NOT NULL,
    at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    text TEXT NOT NULL,
    FOREIGN KEY (user_id) REFERENCES Users(user_id) ON DELETE CASCADE
);
CREATE INDEX IF NOT EXISTS idx_clinic_activity_user_id ON Clinic_Activity(user_id);

-- The image behind a screening, for the clinician's review. The file lives
-- outside the project (ASD_SENSE_SCREENINGS_DIR) under a random name; the
-- original filename is not kept. See screening_images.py.
CREATE TABLE IF NOT EXISTS Screening_Images (
    screening_id INTEGER PRIMARY KEY,
    storage_key TEXT NOT NULL UNIQUE,
    content_type TEXT NOT NULL,
    created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (screening_id) REFERENCES Screening_Records(screening_id) ON DELETE CASCADE
);

-- Updates for guardians: a screening was reviewed, an appointment's status
-- changed. Shown in the app; emailed too if they turned that on. See family_api.py.
CREATE TABLE IF NOT EXISTS Notifications (
    notification_id INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id INTEGER NOT NULL,
    child_id INTEGER,
    title TEXT NOT NULL,
    body TEXT NOT NULL,
    created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    read_at TEXT,
    FOREIGN KEY (user_id) REFERENCES Users(user_id) ON DELETE CASCADE,
    FOREIGN KEY (child_id) REFERENCES Child_Profiles(child_id) ON DELETE CASCADE
);
CREATE INDEX IF NOT EXISTS idx_notifications_user_id ON Notifications(user_id);

-- One pending password-reset code per account; only a hash of the code is kept.
CREATE TABLE IF NOT EXISTS Password_Resets (
    user_id INTEGER PRIMARY KEY,
    code_hash TEXT NOT NULL,
    expires_at INTEGER NOT NULL,
    attempts INTEGER NOT NULL DEFAULT 0,
    FOREIGN KEY (user_id) REFERENCES Users(user_id) ON DELETE CASCADE
);

-- One number that goes up on every change to the data above, so the portal can
-- poll cheaply (GET /api/clinic/sync/revision) and reload only when needed.
CREATE TABLE IF NOT EXISTS Sync_State (
    id INTEGER PRIMARY KEY CHECK (id = 1),
    revision INTEGER NOT NULL DEFAULT 0
);
INSERT OR IGNORE INTO Sync_State (id, revision) VALUES (1, 0);
CREATE TRIGGER IF NOT EXISTS sync_users_insert AFTER INSERT ON Users
BEGIN UPDATE Sync_State SET revision = revision + 1 WHERE id = 1; END;
CREATE TRIGGER IF NOT EXISTS sync_users_update AFTER UPDATE ON Users
BEGIN UPDATE Sync_State SET revision = revision + 1 WHERE id = 1; END;
CREATE TRIGGER IF NOT EXISTS sync_users_delete AFTER DELETE ON Users
BEGIN UPDATE Sync_State SET revision = revision + 1 WHERE id = 1; END;
CREATE TRIGGER IF NOT EXISTS sync_child_profiles_insert AFTER INSERT ON Child_Profiles
BEGIN UPDATE Sync_State SET revision = revision + 1 WHERE id = 1; END;
CREATE TRIGGER IF NOT EXISTS sync_child_profiles_update AFTER UPDATE ON Child_Profiles
BEGIN UPDATE Sync_State SET revision = revision + 1 WHERE id = 1; END;
CREATE TRIGGER IF NOT EXISTS sync_child_profiles_delete AFTER DELETE ON Child_Profiles
BEGIN UPDATE Sync_State SET revision = revision + 1 WHERE id = 1; END;
CREATE TRIGGER IF NOT EXISTS sync_screening_records_insert AFTER INSERT ON Screening_Records
BEGIN UPDATE Sync_State SET revision = revision + 1 WHERE id = 1; END;
CREATE TRIGGER IF NOT EXISTS sync_screening_records_update AFTER UPDATE ON Screening_Records
BEGIN UPDATE Sync_State SET revision = revision + 1 WHERE id = 1; END;
CREATE TRIGGER IF NOT EXISTS sync_screening_records_delete AFTER DELETE ON Screening_Records
BEGIN UPDATE Sync_State SET revision = revision + 1 WHERE id = 1; END;
CREATE TRIGGER IF NOT EXISTS sync_appointments_insert AFTER INSERT ON Appointments
BEGIN UPDATE Sync_State SET revision = revision + 1 WHERE id = 1; END;
CREATE TRIGGER IF NOT EXISTS sync_appointments_update AFTER UPDATE ON Appointments
BEGIN UPDATE Sync_State SET revision = revision + 1 WHERE id = 1; END;
CREATE TRIGGER IF NOT EXISTS sync_appointments_delete AFTER DELETE ON Appointments
BEGIN UPDATE Sync_State SET revision = revision + 1 WHERE id = 1; END;
CREATE TRIGGER IF NOT EXISTS sync_medical_records_insert AFTER INSERT ON Medical_Records
BEGIN UPDATE Sync_State SET revision = revision + 1 WHERE id = 1; END;
CREATE TRIGGER IF NOT EXISTS sync_medical_records_update AFTER UPDATE ON Medical_Records
BEGIN UPDATE Sync_State SET revision = revision + 1 WHERE id = 1; END;
CREATE TRIGGER IF NOT EXISTS sync_medical_records_delete AFTER DELETE ON Medical_Records
BEGIN UPDATE Sync_State SET revision = revision + 1 WHERE id = 1; END;
CREATE TRIGGER IF NOT EXISTS sync_clinician_profiles_insert AFTER INSERT ON Clinician_Profiles
BEGIN UPDATE Sync_State SET revision = revision + 1 WHERE id = 1; END;
CREATE TRIGGER IF NOT EXISTS sync_clinician_profiles_update AFTER UPDATE ON Clinician_Profiles
BEGIN UPDATE Sync_State SET revision = revision + 1 WHERE id = 1; END;
CREATE TRIGGER IF NOT EXISTS sync_clinician_profiles_delete AFTER DELETE ON Clinician_Profiles
BEGIN UPDATE Sync_State SET revision = revision + 1 WHERE id = 1; END;
CREATE TRIGGER IF NOT EXISTS sync_clinic_patients_insert AFTER INSERT ON Clinic_Patients
BEGIN UPDATE Sync_State SET revision = revision + 1 WHERE id = 1; END;
CREATE TRIGGER IF NOT EXISTS sync_clinic_patients_update AFTER UPDATE ON Clinic_Patients
BEGIN UPDATE Sync_State SET revision = revision + 1 WHERE id = 1; END;
CREATE TRIGGER IF NOT EXISTS sync_clinic_patients_delete AFTER DELETE ON Clinic_Patients
BEGIN UPDATE Sync_State SET revision = revision + 1 WHERE id = 1; END;
CREATE TRIGGER IF NOT EXISTS sync_screening_reviews_insert AFTER INSERT ON Screening_Reviews
BEGIN UPDATE Sync_State SET revision = revision + 1 WHERE id = 1; END;
CREATE TRIGGER IF NOT EXISTS sync_screening_reviews_update AFTER UPDATE ON Screening_Reviews
BEGIN UPDATE Sync_State SET revision = revision + 1 WHERE id = 1; END;
CREATE TRIGGER IF NOT EXISTS sync_screening_reviews_delete AFTER DELETE ON Screening_Reviews
BEGIN UPDATE Sync_State SET revision = revision + 1 WHERE id = 1; END;
CREATE TRIGGER IF NOT EXISTS sync_clinic_activity_insert AFTER INSERT ON Clinic_Activity
BEGIN UPDATE Sync_State SET revision = revision + 1 WHERE id = 1; END;
CREATE TRIGGER IF NOT EXISTS sync_clinic_activity_update AFTER UPDATE ON Clinic_Activity
BEGIN UPDATE Sync_State SET revision = revision + 1 WHERE id = 1; END;
CREATE TRIGGER IF NOT EXISTS sync_clinic_activity_delete AFTER DELETE ON Clinic_Activity
BEGIN UPDATE Sync_State SET revision = revision + 1 WHERE id = 1; END;
CREATE TRIGGER IF NOT EXISTS sync_screening_images_insert AFTER INSERT ON Screening_Images
BEGIN UPDATE Sync_State SET revision = revision + 1 WHERE id = 1; END;
CREATE TRIGGER IF NOT EXISTS sync_screening_images_delete AFTER DELETE ON Screening_Images
BEGIN UPDATE Sync_State SET revision = revision + 1 WHERE id = 1; END;
