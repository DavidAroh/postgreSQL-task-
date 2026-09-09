-- 001: extensions
-- pg_stat_statements needs shared_preload_libraries (set in docker-compose.yml);
-- the other two load unconditionally.

CREATE EXTENSION IF NOT EXISTS pg_trgm;    -- trigram indexes for LIKE searches
CREATE EXTENSION IF NOT EXISTS citext;     -- case-insensitive text (emails)

DO $$
BEGIN
  CREATE EXTENSION IF NOT EXISTS pg_stat_statements;
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'pg_stat_statements not available (is it in shared_preload_libraries?)';
END $$;
