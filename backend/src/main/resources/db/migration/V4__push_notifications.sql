-- Solo agrega tablas: nunca modifica ni elimina citas, caja ni documentos.
CREATE TABLE push_devices (
  token TEXT PRIMARY KEY,
  user_id UUID NOT NULL REFERENCES app_users(id) ON DELETE CASCADE,
  platform VARCHAR(10) NOT NULL CHECK (platform IN ('ANDROID','IOS')),
  spoken_sound BOOLEAN NOT NULL DEFAULT FALSE,
  registered_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  last_seen_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX idx_push_devices_user ON push_devices(user_id);

CREATE TABLE push_outbox (
  id UUID PRIMARY KEY,
  recipient_user_id UUID NOT NULL REFERENCES app_users(id) ON DELETE CASCADE,
  event_type VARCHAR(20) NOT NULL,
  event_id UUID NOT NULL,
  trigger_key VARCHAR(20) NOT NULL,
  due_at TIMESTAMPTZ NOT NULL,
  expire_at TIMESTAMPTZ NOT NULL,
  status VARCHAR(16) NOT NULL DEFAULT 'PENDING'
    CHECK (status IN ('PENDING','SENDING','SENT','CANCELLED','EXPIRED')),
  attempts INTEGER NOT NULL DEFAULT 0,
  available_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  last_error VARCHAR(300),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  sent_at TIMESTAMPTZ,
  UNIQUE(recipient_user_id,event_type,event_id,trigger_key)
);
CREATE INDEX idx_push_outbox_queue ON push_outbox(status, available_at, due_at);
