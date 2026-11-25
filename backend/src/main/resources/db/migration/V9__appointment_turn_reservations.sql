-- New reservations only. Preserve earlier appointments, attendance and rotation cursor.
CREATE TABLE appointment_turn_reservations (
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    appointment_id UUID NOT NULL REFERENCES appointments(id),
    member_id UUID NOT NULL REFERENCES family_members(id),
    status VARCHAR(12) NOT NULL CHECK(status IN ('RESERVED','RELEASED','REUSED','FULFILLED','WAIVED')),
    reserved_at TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp(),
    released_at TIMESTAMPTZ,
    CHECK(status NOT IN ('RELEASED','REUSED','WAIVED') OR released_at IS NOT NULL)
);
CREATE UNIQUE INDEX idx_appointment_turn_active ON appointment_turn_reservations(appointment_id) WHERE status='RESERVED';
CREATE INDEX idx_appointment_turn_released ON appointment_turn_reservations(released_at,id) WHERE status='RELEASED';
