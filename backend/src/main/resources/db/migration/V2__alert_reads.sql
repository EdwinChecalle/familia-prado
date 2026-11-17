CREATE TABLE user_alert_reads (
    user_id UUID NOT NULL REFERENCES app_users(id) ON DELETE CASCADE,
    alert_key VARCHAR(160) NOT NULL,
    seen_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY(user_id,alert_key)
);
