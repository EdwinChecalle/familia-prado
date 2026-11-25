-- Cambios aditivos: conservar citas y trazabilidad.
ALTER TABLE appointments ADD COLUMN deleted_at TIMESTAMPTZ;
ALTER TABLE appointments ADD COLUMN revision INTEGER NOT NULL DEFAULT 0;
CREATE TABLE appointment_audit (
    id UUID PRIMARY KEY,
    appointment_id UUID NOT NULL REFERENCES appointments(id),
    actor_user_id UUID NOT NULL REFERENCES app_users(id),
    action VARCHAR(20) NOT NULL CHECK (action IN ('EDITED','CANCELLED','CONFIRMED','COMPLETED','DELETED')),
    occurred_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX idx_appointment_audit ON appointment_audit(appointment_id,occurred_at);
