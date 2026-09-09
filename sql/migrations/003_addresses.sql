-- 003: user addresses
-- One user keeps several labelled addresses; at most one is the default.
-- "at most one default per user" is a cross-row invariant -> partial UNIQUE index.

CREATE TABLE addresses (
  id          bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  user_id     bigint NOT NULL REFERENCES users (id) ON DELETE CASCADE,
  label       text NOT NULL,               -- 'home', 'work', ...
  line1       text NOT NULL,
  line2       text,
  city        text NOT NULL,
  region      text,
  postal_code text NOT NULL,
  country     char(2) NOT NULL,            -- ISO 3166-1 alpha-2
  is_default  boolean NOT NULL DEFAULT false,
  created_at  timestamptz NOT NULL DEFAULT now()
);

-- Composite natural key: a user cannot have two 'home' addresses.
ALTER TABLE addresses
  ADD CONSTRAINT addresses_user_label_key UNIQUE (user_id, label);

-- Cross-row invariant: at most ONE default address per user.
-- A partial unique index does this without a trigger.
CREATE UNIQUE INDEX addresses_one_default_per_user
  ON addresses (user_id) WHERE is_default;

CREATE INDEX idx_addresses_user_id ON addresses (user_id);
