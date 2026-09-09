-- 002: users + 1:1 profile
-- Design notes:
--  * email is CITEXT + UNIQUE: uniqueness is enforced case-insensitively, so
--    "Ana@example.com" and "ana@example.com" cannot both exist.
--  * user_profiles is a separate 1:1 table, not nullable columns on users:
--    keeps the hot users row narrow, and profile data can have its own
--    lifecycle (e.g. archived) without touching authentication data.

CREATE TABLE users (
  id          bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  email       citext NOT NULL,
  status      text NOT NULL DEFAULT 'active'
              CHECK (status IN ('active', 'banned', 'deleted')),
  created_at  timestamptz NOT NULL DEFAULT now(),
  updated_at  timestamptz NOT NULL DEFAULT now()
);

-- 1:1 in relational terms = FK to users + UNIQUE on the FK column.
CREATE TABLE user_profiles (
  user_id          bigint PRIMARY KEY REFERENCES users (id) ON DELETE CASCADE,
  full_name        text,
  phone            text,
  date_of_birth    date,
  marketing_opt_in boolean NOT NULL DEFAULT false
);

COMMENT ON TABLE users IS 'Customer accounts. Soft-deleted via status=deleted.';
COMMENT ON COLUMN users.status IS 'active | banned | deleted (soft delete)';
