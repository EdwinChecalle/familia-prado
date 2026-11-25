-- Independent rotation; no changes to meal rotation, existing appointments or old attendance.
CREATE TABLE appointment_rotation_order (
    member_id UUID PRIMARY KEY REFERENCES family_members(id),
    position INTEGER NOT NULL UNIQUE DEFERRABLE INITIALLY DEFERRED CHECK(position BETWEEN 1 AND 8)
);
INSERT INTO appointment_rotation_order(member_id,position)
SELECT id,rotation_position FROM family_members;
CREATE TABLE appointment_rotation_state (
    id INTEGER PRIMARY KEY CHECK(id=1),
    next_position INTEGER NOT NULL CHECK(next_position BETWEEN 1 AND 8),
    revision BIGINT NOT NULL DEFAULT 0
);
INSERT INTO appointment_rotation_state(id,next_position) VALUES(1,1);
ALTER TABLE appointments ADD COLUMN actual_member_id UUID REFERENCES family_members(id);
CREATE TABLE appointment_rotation_events (
    id UUID PRIMARY KEY,
    appointment_id UUID UNIQUE REFERENCES appointments(id),
    kind VARCHAR(16) NOT NULL CHECK(kind IN ('ATTENDED','SKIPPED','CONFIGURED')),
    suggested_member_id UUID REFERENCES family_members(id),
    actual_member_id UUID REFERENCES family_members(id),
    actor_user_id UUID NOT NULL REFERENCES app_users(id),
    advanced BOOLEAN NOT NULL,
    reason VARCHAR(300),
    occurred_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CHECK ((kind='ATTENDED') = (appointment_id IS NOT NULL))
);
CREATE INDEX idx_appointment_rotation_events_time ON appointment_rotation_events(occurred_at DESC);
