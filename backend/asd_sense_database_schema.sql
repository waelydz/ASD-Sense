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
