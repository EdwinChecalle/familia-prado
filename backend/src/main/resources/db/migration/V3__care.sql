-- Bloque 03: Datos privados de salud. Migración aditiva: NO elimina datos anteriores.
CREATE TABLE care_access (
    member_id UUID PRIMARY KEY REFERENCES family_members(id),
    granted_by UUID NOT NULL REFERENCES app_users(id),
    granted_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE TABLE care_medications (
    id UUID PRIMARY KEY,
    name VARCHAR(140) NOT NULL,
    instructions VARCHAR(500) NOT NULL,
    prescriber VARCHAR(140),
    schedule_times VARCHAR(120) NOT NULL,
    starts_on DATE NOT NULL,
    ends_on DATE,
    active BOOLEAN NOT NULL DEFAULT TRUE,
    created_by UUID NOT NULL REFERENCES app_users(id),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CHECK (ends_on IS NULL OR ends_on >= starts_on)
);
CREATE TABLE care_medication_records (
    id UUID PRIMARY KEY,
    medication_id UUID NOT NULL REFERENCES care_medications(id),
    scheduled_date DATE NOT NULL,
    scheduled_time TIME NOT NULL,
    status VARCHAR(24) NOT NULL CHECK (status IN ('REPORTED_GIVEN','REPORTED_NOT_GIVEN')),
    comment VARCHAR(500),
    registered_by UUID NOT NULL REFERENCES app_users(id),
    registered_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE(medication_id, scheduled_date, scheduled_time)
);
CREATE INDEX idx_care_records_date ON care_medication_records(scheduled_date DESC);
CREATE TABLE care_medication_corrections (
    id UUID PRIMARY KEY,
    record_id UUID NOT NULL REFERENCES care_medication_records(id),
    old_status VARCHAR(24) NOT NULL,
    new_status VARCHAR(24) NOT NULL,
    reason VARCHAR(300) NOT NULL,
    corrected_by UUID NOT NULL REFERENCES app_users(id),
    corrected_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE TABLE care_observations (
    id UUID PRIMARY KEY,
    kind VARCHAR(20) NOT NULL CHECK(kind IN ('GLUCOSE','BLOOD_PRESSURE','TEMPERATURE','NOTE')),
    value_primary NUMERIC(8,2),
    value_secondary NUMERIC(8,2),
    notes VARCHAR(700),
    observed_at TIMESTAMPTZ NOT NULL,
    recorded_by UUID NOT NULL REFERENCES app_users(id),
    recorded_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX idx_care_observations_date ON care_observations(observed_at DESC);
CREATE TABLE care_documents (
    id UUID PRIMARY KEY,
    title VARCHAR(140) NOT NULL,
    category VARCHAR(24) NOT NULL CHECK (category IN ('RECIPE','EXAM','ORDER','OTHER')),
    original_name VARCHAR(180) NOT NULL,
    stored_name VARCHAR(80) NOT NULL UNIQUE,
    mime_type VARCHAR(40) NOT NULL,
    size_bytes BIGINT NOT NULL CHECK(size_bytes BETWEEN 1 AND 5242880),
    uploaded_by UUID NOT NULL REFERENCES app_users(id),
    uploaded_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
