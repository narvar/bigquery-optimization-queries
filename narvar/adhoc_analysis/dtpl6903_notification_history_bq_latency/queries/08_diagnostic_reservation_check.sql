-- Diagnostic: Check what reservations are actually being used

DECLARE analysis_start_date TIMESTAMP DEFAULT TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 7 DAY);
DECLARE analysis_end_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP();

SELECT
  reservation_id,
  COUNT(DISTINCT user_email) AS distinct_users,
  COUNT(*) AS total_queries,
  SUM(total_slot_ms) / 3600000 AS total_slot_hours,
  
  ARRAY_AGG(DISTINCT user_email LIMIT 10) AS sample_users

FROM `region-us`.INFORMATION_SCHEMA.JOBS_BY_PROJECT
WHERE creation_time BETWEEN analysis_start_date AND analysis_end_date
  AND job_type = 'QUERY'
  AND state = 'DONE'
GROUP BY reservation_id
ORDER BY total_slot_hours DESC
LIMIT 20;
