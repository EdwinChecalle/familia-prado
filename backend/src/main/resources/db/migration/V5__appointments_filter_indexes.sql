-- Additive indexes only. Never modify or delete existing appointments.
CREATE INDEX IF NOT EXISTS idx_appointments_active_sort
    ON appointments (appointment_at, id)
    WHERE status IN ('PLANNED', 'CONFIRMED');
CREATE INDEX IF NOT EXISTS idx_appointments_cancelled_sort
    ON appointments (appointment_at DESC, id DESC)
    WHERE status = 'CANCELLED';
CREATE INDEX IF NOT EXISTS idx_appointments_responsible_sort
    ON appointments (responsible_member_id, appointment_at DESC, id DESC);
