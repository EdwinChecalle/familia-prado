-- 04-B2.2: documentos cifrados y persistentes en PostgreSQL/Neon.
-- Solo agrega una tabla: NO modifica registros/documentos anteriores.
CREATE TABLE care_document_contents (
    document_id UUID PRIMARY KEY REFERENCES care_documents(id) ON DELETE CASCADE,
    key_version SMALLINT NOT NULL DEFAULT 1 CHECK (key_version = 1),
    nonce BYTEA NOT NULL CHECK (octet_length(nonce) = 12),
    ciphertext BYTEA NOT NULL CHECK (octet_length(ciphertext) BETWEEN 17 AND 5242896),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
COMMENT ON TABLE care_document_contents IS
    'Contenido AES-256-GCM. Clave externa al servidor y a Neon; document_id vinculado como AAD.';
