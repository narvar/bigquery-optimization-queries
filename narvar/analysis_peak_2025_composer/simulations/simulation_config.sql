-- Simulation Configuration: Template for slot allocation simulation parameters
-- Purpose: Centralized configuration for all slot allocation simulations
--
-- This file defines configurable parameters used across all simulation queries:
--   - Slot allocations per category
--   - Reservation configurations (committed vs. flex slots)
--   - Peak period dates
--   - Growth scenarios
--   - QoS thresholds
--
-- Usage: Copy parameter declarations to individual simulation queries
--
-- Parameters:
--   peak_period_start: DATE - Start of peak period (default: 2025-11-01)
--   peak_period_end: DATE - End of peak period (default: 2026-01-31)
--   growth_scenario: STRING - 'CONSERVATIVE', 'BASE', 'OPTIMISTIC'
--
-- Slot Allocations (defaults for baseline - adjust per simulation):
--   external_critical_slots: INT64 - Slots for EXTERNAL_CRITICAL category
--   automated_critical_slots: INT64 - Slots for AUTOMATED_CRITICAL category
--   internal_slots: INT64 - Slots for INTERNAL category
--   total_slot_capacity: INT64 - Total slot capacity
--
-- QoS Thresholds:
--   external_critical_threshold_seconds: INT64 - Max acceptable duration (default: 60)
--   internal_threshold_seconds: INT64 - Max acceptable duration (default: 600)

DECLARE peak_period_start DATE DEFAULT '2025-11-01';
DECLARE peak_period_end DATE DEFAULT '2026-01-31';
DECLARE growth_scenario STRING DEFAULT 'BASE';

-- Baseline slot allocations (shared pool)
DECLARE external_critical_slots INT64 DEFAULT NULL;  -- NULL = shared pool
DECLARE automated_critical_slots INT64 DEFAULT NULL;
DECLARE internal_slots INT64 DEFAULT NULL;
DECLARE total_slot_capacity INT64 DEFAULT 1700;

-- QoS Thresholds
DECLARE external_critical_threshold_seconds INT64 DEFAULT 60;
DECLARE internal_threshold_seconds INT64 DEFAULT 600;

-- Cost parameters
DECLARE cost_per_slot_1yr_monthly FLOAT64 DEFAULT 2000.0;
DECLARE cost_per_slot_3yr_monthly FLOAT64 DEFAULT 1500.0;
DECLARE cost_per_slot_paygo_monthly FLOAT64 DEFAULT 2500.0;
DECLARE ondemand_cost_per_slot_hour FLOAT64 DEFAULT 0.04;

-- Example configuration for Simulation 1: Isolated Internal Users
-- DECLARE external_critical_slots INT64 DEFAULT NULL;  -- Shared with automated
-- DECLARE automated_critical_slots INT64 DEFAULT NULL;
-- DECLARE internal_slots INT64 DEFAULT 300;  -- Isolated

-- Example configuration for Simulation 2: Fully Segmented
-- DECLARE external_critical_slots INT64 DEFAULT 800;
-- DECLARE automated_critical_slots INT64 DEFAULT 600;
-- DECLARE internal_slots INT64 DEFAULT 300;

SELECT
  'Configuration parameters defined. Use DECLARE statements in individual simulation queries.' AS note;

