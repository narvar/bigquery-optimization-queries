SELECT 
  UPPER(retailer_moniker) AS retailer_moniker,
  UPPER(carrier_moniker) AS carrier_moniker,
  UPPER(tracking_number) AS tracking_number,
  reference_number,
  order_number,
  event_ts,
  event_created_ts,
  ingestion_timestamp AS atlas_ingestion_ts
FROM `narvar-data-lake.atlas.atlas_tracking_event`
WHERE DATE(event_ts) > '2024-11-01' 
  AND DATE(event_ts) < '2025-11-21'
QUALIFY ROW_NUMBER() OVER (
  PARTITION BY UPPER(retailer_moniker), UPPER(carrier_moniker), UPPER(tracking_number) 
  ORDER BY event_ts DESC
) = 1


