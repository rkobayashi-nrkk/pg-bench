\set n_inserts 500
BEGIN;
INSERT INTO demo_log_events (event_time, event_type, message, payload)
SELECT now() + (random() * INTERVAL '30 days'), 'INFO', 'Log message for event' || generate_series(1, :n_inserts), '{}'::jsonb
FROM generate_series(1, :n_inserts);
COMMIT;