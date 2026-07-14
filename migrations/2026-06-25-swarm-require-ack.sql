-- Migration: add require_ack / ack_deadline_at to delivery_outbox
-- Applies to every gbrain database on the VPS.
--
-- Symptom before migration:
--   swarm.notify() / swarm.escalate() calls fail with 500 because the code
--   references delivery_outbox.require_ack / ack_deadline_at columns
--   that don't exist in the older schema.
--
-- Verify before applying:
--   SELECT column_name FROM information_schema.columns
--     WHERE table_name='delivery_outbox' ORDER BY ordinal_position;
--
-- Should list 11 columns without require_ack/ack_deadline_at.
-- After applying, should list 13.

BEGIN;

ALTER TABLE delivery_outbox
    ADD COLUMN IF NOT EXISTS require_ack     boolean                  NOT NULL DEFAULT false,
    ADD COLUMN IF NOT EXISTS ack_deadline_at timestamp with time zone;

CREATE INDEX IF NOT EXISTS delivery_outbox_ack_deadline_idx
    ON delivery_outbox (ack_deadline_at)
    WHERE require_ack IS true;

COMMIT;

-- Post-check:
--   SELECT count(*) FROM delivery_outbox WHERE require_ack IS true;   -- 0 for fresh migration
--   \d delivery_outbox                                                  -- should include both columns
