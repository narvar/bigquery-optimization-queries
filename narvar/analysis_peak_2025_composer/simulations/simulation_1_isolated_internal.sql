-- Simulation 1: Isolated Internal Users
-- Purpose: Simulates isolating INTERNAL users from CRITICAL categories
--
-- Configuration:
--   - CRITICAL (External + Automated): Shared pool (X slots)
--   - INTERNAL: Isolated allocation (Y slots)
--   - Total: X + Y ≤ 1,700 (or evaluate additional cost)
--
-- This simulation evaluates whether isolating internal users prevents QoS impact
-- on external customers and automated processes.

DECLARE peak_period_start DATE DEFAULT '2025-11-01';
DECLARE peak_period_end DATE DEFAULT '2026-01-31';
DECLARE total_slot_capacity INT64 DEFAULT 1700;

-- Slot allocations for this simulation
DECLARE critical_shared_slots INT64 DEFAULT 1400;  -- External + Automated share
DECLARE internal_isolated_slots INT64 DEFAULT 300;  -- Internal isolated

DECLARE external_critical_threshold_seconds INT64 DEFAULT 60;
DECLARE internal_threshold_seconds INT64 DEFAULT 600;

WITH slot_allocation AS (
  SELECT 'EXTERNAL_CRITICAL' AS consumer_category, critical_shared_slots AS allocated_slots
  UNION ALL
  SELECT 'AUTOMATED_CRITICAL' AS consumer_category, critical_shared_slots AS allocated_slots
  UNION ALL
  SELECT 'INTERNAL' AS consumer_category, internal_isolated_slots AS allocated_slots
),
-- Use simulation engine logic (see slot_allocation_simulation_engine.sql)
simulation_results AS (
  SELECT
    consumer_category,
    allocated_slots,
    'Simulation 1: Isolated Internal' AS simulation_name,
    CURRENT_TIMESTAMP() AS simulation_timestamp
  FROM slot_allocation
)

SELECT
  simulation_name,
  consumer_category,
  allocated_slots,
  simulation_timestamp
FROM simulation_results;

-- Note: This is a simplified version. For full simulation, integrate with 
-- slot_allocation_simulation_engine.sql logic to get QoS predictions.

