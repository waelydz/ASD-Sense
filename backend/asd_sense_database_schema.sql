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
