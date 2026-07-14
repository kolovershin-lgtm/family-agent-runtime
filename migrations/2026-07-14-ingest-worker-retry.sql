-- Migration: add retry/error columns to embedding_jobs
-- Applies to every gbrain database on the VPS.
--
-- Context: the older schema on Andrei's VPS lacks attempts/max_attempts/
-- error_message/next_retry_at, which prevents ingest_worker from recording
-- retry state or diagnostic messages. Root cause of a 71084-restart
-- crash-loop discovered 2026-07-14 was code-level (missing ON CONFLICT),
-- but even after the code fix, retry semantics need these columns to work.
--
-- Verify before applying:
--   \d embedding_jobs   -- should show 5 columns (id, doc_id, status, created_at, updated_at)
-- After applying:
--   \d embedding_jobs   -- 9 columns + new index

BEGIN;

ALTER TABLE embedding_jobs
    ADD COLUMN IF NOT EXISTS attempts       int  NOT NULL DEFAULT 0,
    ADD COLUMN IF NOT EXISTS max_attempts   int  NOT NULL DEFAULT 3,
    ADD COLUMN IF NOT EXISTS error_message  text,
    ADD COLUMN IF NOT EXISTS next_retry_at  timestamp with time zone;

CREATE INDEX IF NOT EXISTS idx_embedding_jobs_next_retry
    ON embedding_jobs (next_retry_at)
    WHERE status = 'pending';

COMMIT;

-- Post-check:
--   SELECT status, count(*), max(attempts) FROM embedding_jobs GROUP BY status;
--   \d embedding_jobs
