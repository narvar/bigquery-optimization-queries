-- Check if service-prod-messaging-pubsub@narvar-prod.iam.gserviceaccount.com exists in audit logs

DECLARE analysis_start_date TIMESTAMP DEFAULT TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 7 DAY);

SELECT
  user_email,
  project_id,
  COUNT(*) AS query_count,
  MIN(creation_time) AS first_query,
  MAX(creation_time) AS last_query,
  AVG(TIMESTAMP_DIFF(start_time, creation_time, SECOND)) AS avg_queue_sec,
  MAX(TIMESTAMP_DIFF(start_time, creation_time, SECOND)) AS max_queue_sec
FROM `region-us`.INFORMATION_SCHEMA.JOBS_BY_PROJECT
WHERE creation_time >= analysis_start_date
  AND (
    user_email = 'service-prod-messaging-pubsub@narvar-prod.iam.gserviceaccount.com'
    OR user_email LIKE '%messaging%'
    OR user_email LIKE '%pubsub%'
  )
  AND job_type = 'QUERY'
  AND state = 'DONE'
GROUP BY user_email, project_id
ORDER BY query_count DESC;
