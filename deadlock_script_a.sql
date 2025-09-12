BEGIN;
UPDATE deadlock_test SET value = value + 10 WHERE id = 1;
SELECT pg_sleep(0.05);
UPDATE deadlock_test SET value = value + 10 WHERE id = 2;
COMMIT;