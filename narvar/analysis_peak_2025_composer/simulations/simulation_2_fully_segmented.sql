-- Simulation 2: Fully Segmented
-- Purpose: Simulates separate slot allocation for each category
--
-- Configuration:
--   - EXTERNAL_CRITICAL: A slots
--   - AUTOMATED_CRITICAL: B slots
--   - INTERNAL: C slots
--   - Total: A + B + C ≤ 1,700 (or evaluate additional cost)
--
-- This simulation evaluates complete isolation of all categories.

DECLARE peak_period_start DATE DEFAULT '2025-11-01';
DECLARE peak_period_end DATE DEFAULT '2026-01-31';
DECLARE total_slot_capacity INT64 DEFAULT 1700;

-- Slot allocations for this simulation
DECLARE external_critical_slots INT64 DEFAULT 800;
DECLARE automated_critical_slots INT64 DEFAULT 600;
DECLARE internal_slots INT64 DEFAULT 300;

DECLARE external_critical_threshold_seconds INT64 DEFAULT 60;
DECLARE internal_threshold_seconds INT64 DEFAULT 600;

WITH slot_allocation AS (
  SELECT 'EXTERNAL_CRITICAL' AS consumer_category, external_critical_slots AS allocated_slots
  UNION ALL
  SELECT 'AUTOMATED_CRITICAL' AS consumer_category, automated_critical_slots AS allocated_slots
  UNION ALL
  SELECT 'INTERNAL' AS consumer_category, internal_slots AS allocated_slots
),
simulation_results AS (
  SELECT
    consumer_category,
    allocated_slots,
    'Simulation 2: Fully Segmented' AS simulation_name,
    CURRENT_TIMESTAMP() AS simulation_timestamp
  FROM slot_allocation
)

SELECT
  simulation_name,
  consumer_category,
  allocated_slots,
  simulation_timestamp
FROM simulation_results;

-- Note: For full simulation, integrate with slot_allocation_simulation_engine.sql

