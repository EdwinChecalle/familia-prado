CREATE TABLE family_members (
    id UUID PRIMARY KEY,
    display_name VARCHAR(100) NOT NULL,
    rotation_position INTEGER NOT NULL CHECK (rotation_position BETWEEN 1 AND 8),
    CONSTRAINT uq_family_rotation UNIQUE (rotation_position) DEFERRABLE INITIALLY DEFERRED,
    active BOOLEAN NOT NULL DEFAULT TRUE
);
CREATE TABLE app_users (
    id UUID PRIMARY KEY,
    email VARCHAR(254) NOT NULL UNIQUE,
    password_hash VARCHAR(120) NOT NULL,
    role VARCHAR(16) NOT NULL CHECK(role IN ('ADMIN','MEMBER')),
    member_id UUID UNIQUE REFERENCES family_members(id),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE TABLE login_tokens (
    token_hash VARCHAR(64) PRIMARY KEY,
    user_id UUID NOT NULL REFERENCES app_users(id),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    expires_at TIMESTAMPTZ NOT NULL,
    revoked_at TIMESTAMPTZ
);
CREATE INDEX idx_login_tokens_user ON login_tokens(user_id);
CREATE TABLE rotation_config (
    id INTEGER PRIMARY KEY DEFAULT 1 CHECK (id=1),
    anchor_monday DATE NOT NULL,
    anchor_position INTEGER NOT NULL CHECK (anchor_position BETWEEN 1 AND 8),
    confirmed BOOLEAN NOT NULL DEFAULT FALSE
);
CREATE TABLE week_overrides (
    week_monday DATE PRIMARY KEY,
    member_id UUID NOT NULL REFERENCES family_members(id)
);
CREATE TABLE meal_checks (
    id UUID PRIMARY KEY,
    week_monday DATE NOT NULL,
    meal_date DATE NOT NULL,
    meal VARCHAR(16) NOT NULL CHECK (meal IN ('BREAKFAST','LUNCH','DINNER')),
    completed BOOLEAN NOT NULL,
    changed_by UUID NOT NULL REFERENCES app_users(id),
    changed_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE(meal_date, meal),
    CHECK (meal_date >= week_monday AND meal_date < week_monday + 7)
);
CREATE INDEX idx_meal_checks_week ON meal_checks(week_monday);
CREATE TABLE swap_requests (
    id UUID PRIMARY KEY,
    week_a DATE NOT NULL,
    week_b DATE NOT NULL,
    member_a UUID NOT NULL REFERENCES family_members(id),
    member_b UUID NOT NULL REFERENCES family_members(id),
    requested_by UUID NOT NULL REFERENCES app_users(id),
    decided_by UUID REFERENCES app_users(id),
    status VARCHAR(16) NOT NULL CHECK(status IN ('PENDING','ACCEPTED','REJECTED')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    decided_at TIMESTAMPTZ,
    CHECK(week_a <> week_b)
);
CREATE TABLE family_fund_lock (id INTEGER PRIMARY KEY CHECK(id=1));
CREATE TABLE collections (
    id UUID PRIMARY KEY,
    concept VARCHAR(200) NOT NULL,
    amount_per_member NUMERIC(12,2) NOT NULL CHECK(amount_per_member>0),
    due_date DATE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    created_by UUID NOT NULL REFERENCES app_users(id)
);
CREATE TABLE contributions (
    id UUID PRIMARY KEY,
    collection_id UUID NOT NULL REFERENCES collections(id),
    member_id UUID NOT NULL REFERENCES family_members(id),
    amount NUMERIC(12,2) NOT NULL CHECK(amount>0),
    payment_method VARCHAR(24) NOT NULL CHECK(payment_method IN ('YAPE','PLIN','TRANSFER','CASH')),
    payment_reference VARCHAR(120),
    status VARCHAR(16) NOT NULL CHECK(status IN ('SUBMITTED','VERIFIED','REJECTED')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    submitted_by UUID NOT NULL REFERENCES app_users(id),
    reviewed_by UUID REFERENCES app_users(id),
    reviewed_at TIMESTAMPTZ
);
CREATE INDEX idx_contribution_collection ON contributions(collection_id,member_id);
CREATE TABLE expenses (
    id UUID PRIMARY KEY,
    concept VARCHAR(200) NOT NULL,
    amount NUMERIC(12,2) NOT NULL CHECK(amount>0),
    receipt_reference VARCHAR(250),
    status VARCHAR(16) NOT NULL CHECK(status IN ('REQUESTED','APPROVED','REJECTED')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    requested_by UUID NOT NULL REFERENCES app_users(id),
    reviewed_by UUID REFERENCES app_users(id),
    reviewed_at TIMESTAMPTZ
);
CREATE TABLE appointments (
    id UUID PRIMARY KEY,
    appointment_at TIMESTAMPTZ NOT NULL,
    hospital VARCHAR(160) NOT NULL,
    specialty VARCHAR(120) NOT NULL,
    responsible_member_id UUID REFERENCES family_members(id),
    status VARCHAR(16) NOT NULL CHECK(status IN ('PLANNED','CONFIRMED','COMPLETED','CANCELLED')),
    preparation VARCHAR(500),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    created_by UUID NOT NULL REFERENCES app_users(id)
);
CREATE INDEX idx_appointments_date ON appointments(appointment_at);
INSERT INTO family_fund_lock(id) VALUES(1);
INSERT INTO rotation_config(id, anchor_monday, anchor_position, confirmed) VALUES(1,'2026-11-16',1,FALSE);
INSERT INTO family_members(id, display_name, rotation_position) VALUES
('10000000-0000-4000-8000-000000000001','Ángel',1),
('10000000-0000-4000-8000-000000000002','Carlos',2),
('10000000-0000-4000-8000-000000000003','Jorge',3),
('10000000-0000-4000-8000-000000000004','Olga',4),
('10000000-0000-4000-8000-000000000005','Enrique',5),
('10000000-0000-4000-8000-000000000006','Isabel',6),
('10000000-0000-4000-8000-000000000007','Carmen',7),
('10000000-0000-4000-8000-000000000008','Lucho',8);
