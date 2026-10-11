CREATE TABLE IF NOT EXISTS installation (id boolean PRIMARY KEY DEFAULT true CHECK(id), user_id text UNIQUE);
INSERT INTO installation(id) VALUES(true) ON CONFLICT DO NOTHING;
CREATE TABLE IF NOT EXISTS dashboard_sessions (hash text PRIMARY KEY, user_id text NOT NULL, created_at timestamptz NOT NULL, expires_at timestamptz NOT NULL, revoked_at timestamptz);
CREATE TABLE IF NOT EXISTS login_attempts (hash text PRIMARY KEY, binding_hash text NOT NULL, expires_at timestamptz NOT NULL, consumed_at timestamptz, session_hash text REFERENCES dashboard_sessions(hash));
CREATE TABLE IF NOT EXISTS broker_authorizations (user_id text PRIMARY KEY, encrypted_token bytea NOT NULL, status text NOT NULL CHECK(status IN ('active','reconnect_required','pending_revocation','revoked')), updated_at timestamptz NOT NULL, expires_at timestamptz NOT NULL);
ALTER TABLE installation ADD COLUMN IF NOT EXISTS auth_generation bigint NOT NULL DEFAULT 0;
ALTER TABLE login_attempts ADD COLUMN IF NOT EXISTS auth_generation bigint NOT NULL DEFAULT 0;
CREATE TABLE IF NOT EXISTS pending_revocations (id text PRIMARY KEY, user_id text NOT NULL, encrypted_token bytea NOT NULL, failures integer NOT NULL DEFAULT 0, retry_at timestamptz NOT NULL);
