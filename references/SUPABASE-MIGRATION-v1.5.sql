-- TAO-OS tao-forge schema migration v1.5
-- Adds hardware_extended and stability_extended fields to the runs table.
-- All columns are nullable — old rows remain valid, new data populates going forward.
-- Run in Supabase SQL editor: https://supabase.com/dashboard/project/iovvktpuoinmjdgfxgvm/sql

ALTER TABLE runs
  -- Hardware fingerprint fields
  ADD COLUMN IF NOT EXISTS cpu_microcode_version  text,
  ADD COLUMN IF NOT EXISTS cpu_l1_cache_kb        numeric,
  ADD COLUMN IF NOT EXISTS cpu_l2_cache_kb        numeric,
  ADD COLUMN IF NOT EXISTS cpu_l3_cache_kb        numeric,
  ADD COLUMN IF NOT EXISTS gpu_vram_mb            numeric,
  ADD COLUMN IF NOT EXISTS gpu_driver_version     text,
  ADD COLUMN IF NOT EXISTS ram_speed_mhz          numeric,
  ADD COLUMN IF NOT EXISTS ram_channel_config     text,

  -- Stability metrics fields
  ADD COLUMN IF NOT EXISTS dmesg_errors_baseline          integer,
  ADD COLUMN IF NOT EXISTS dmesg_errors_tuned             integer,
  ADD COLUMN IF NOT EXISTS cpu_throttle_events_baseline   integer,
  ADD COLUMN IF NOT EXISTS cpu_throttle_events_tuned      integer,
  ADD COLUMN IF NOT EXISTS gpu_throttle_events_baseline   integer,
  ADD COLUMN IF NOT EXISTS gpu_throttle_events_tuned      integer,
  ADD COLUMN IF NOT EXISTS temp_throttle_count_baseline   integer,
  ADD COLUMN IF NOT EXISTS temp_throttle_count_tuned      integer;
