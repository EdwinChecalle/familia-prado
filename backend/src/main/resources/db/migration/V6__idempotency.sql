-- Bloque 04-B1: protege reenvíos de operaciones creadoras. No modifica datos anteriores.
CREATE TABLE idempotency_requests (
    user_id UUID NOT NULL REFERENCES app_users(id),
    request_key VARCHAR(36) NOT NULL,
    route VARCHAR(160) NOT NULL,
    fingerprint CHAR(64) NOT NULL,
    result_id UUID,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY(user_id,request_key)
);
