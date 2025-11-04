-- Simulation 3: Flexible Allocation with Priorities
-- Purpose: Simulates dynamic allocation with priority-based access
--
-- Configuration:
--   - Reserved minimums per category
--   - Shared flex pool for burst capacity
--   - Priority-based allocation (CRITICAL categories get flex slots first)
--
-- This simulation evaluates a hybrid approach with guaranteed minimums and shared burst capacity.

DECLARE peak_period_start DATE DEFAULT '2025-11-01';
DECLARE peak_period_end DATE DEFAULT '2026-01-31';
DECLARE total_slot_capacity INT64 DEFAULT 1700;

-- Reserved minimums per category
DECLARE external_critical_min_slots INT64 DEFAULT 600;
DECLARE automated_critical_min_slots INT64 DEFAULT 400;
DECLARE internal_min_slots INT64 DEFAULT 200;

-- Flex pool (shared burst capacity)
DECLARE flex_pool_slots INT64 DEFAULT 500;  -- total_slot_capacity - sum of minimums

DECLARE external_critical_threshold_seconds INT64 DEFAULT 60;
DECLARE internal_threshold_seconds INT64 DEFAULT 600;

WITH reserved_allocation AS (
  SELECT 'EXTERNAL_CRITICAL' AS consumer_category, external_critical_min_slots AS min_slots, 1 AS priority
  UNION ALL
  SELECT 'AUTOMATED_CRITICAL' AS consumer_category, automated_critical_min_slots AS min_slots, 2 AS priority
  UNION ALL
  SELECT 'INTERNAL' AS consumer_category, internal_min_slots AS min_slots, 3 AS priority
),
simulation_results AS (
  SELECT
    consumer_category,
    min_slots AS guaranteed_slots,
    flex_pool_slots AS available_flex_pool,
    priority,
    'Simulation 3: Priority-Based with Flex Pool' AS simulation_name,
    CURRENT_TIMESTAMP() AS simulation_timestamp
  FROM reserved_allocation
)

SELECT
  simulation_name,
  consumer_category,
  guaranteed_slots,
  available_flex_pool,
  priority,
  simulation_timestamp
FROM simulation_results
ORDER BY priority;

-- Note: Full implementation would model flex pool allocation based on priority and demand

