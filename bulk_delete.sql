\set retention_days 7
BEGIN;
DELETE FROM demo_log_events WHERE event_time < now() - INTERVAL '7 days';
COMMIT;