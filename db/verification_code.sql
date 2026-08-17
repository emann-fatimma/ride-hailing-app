-- Verification codes for signup phone/email confirmation (dev-mode delivery: logged + returned in API response,
-- no real SMS/email provider wired up yet).
CREATE TABLE IF NOT EXISTS verification_code (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES app_user(id) ON DELETE CASCADE,
  channel VARCHAR(10) NOT NULL CHECK (channel IN ('phone', 'email')),
  destination VARCHAR(255) NOT NULL,
  code_hash VARCHAR(255) NOT NULL,
  purpose VARCHAR(30) NOT NULL DEFAULT 'signup',
  attempts INT NOT NULL DEFAULT 0,
  max_attempts INT NOT NULL DEFAULT 5,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  expires_at TIMESTAMPTZ NOT NULL,
  verified_at TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS idx_verification_code_user ON verification_code(user_id);
CREATE INDEX IF NOT EXISTS idx_verification_code_lookup ON verification_code(channel, destination, verified_at);
