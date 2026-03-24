# BENCHMARK-INTEGRATION-v1.5.md

**Updated:** 2026-03-24  
**Purpose:** Integration guide for extended data collection in benchmark scripts.

This document guides the update of all benchmark scripts to include v1.5+ data fields (hardware fingerprint + stability metrics).

---

## Quick Reference

### New Scripts Available
- `~/TAO-OS/scripts/collect-hardware-fingerprint.sh` — captures CPU/GPU/RAM info
- `~/TAO-OS/scripts/collect-stability-metrics.sh` — captures dmesg/throttling data
- `~/TAO-OS/scripts/inject-extended-data.sh` — helper functions to inject into logs

### Updated Schema
- `~/TAO-OS/agents/handoff-schema.json` — now includes `hardware_extended` and `stability_extended` objects
- All 16 new fields are optional (null if unavailable)

### Updated Agent Spec
- `~/TAO-OS/agents/specs/benchmark-agent.md` — extracts and validates new fields

---

## Integration Pattern for Benchmark Scripts

All benchmark scripts should follow this pattern:

### 1. Source the Helper Script at Top
```bash
#!/usr/bin/env bash
set -e

# ... existing preamble ...

# Source data injection helpers
source "$HOME/TAO-OS/scripts/inject-extended-data.sh"
```

### 2. Collect Hardware Once (before any benchmarks)
```bash
# Collect hardware fingerprint once at session start (after preflight setup)
inject_hardware_fingerprint "$LOG_FILE"
echo "[INFO] Hardware fingerprint captured" | tee -a "$LOG_FILE"
```

### 3. Collect Stability Before Baseline
```bash
# Baseline pass — capture pre-baseline stability state
echo "[INFO] Capturing baseline stability metrics..." | tee -a "$LOG_FILE"
inject_stability_metrics "$LOG_FILE" "baseline" ".stability-baseline.txt"

# Run baseline benchmarks...
```

### 4. Collect Stability After Baseline (and Before Tuned)
```bash
# After baseline completes, capture post-baseline state
# (This establishes "delta" for the tuned pass to compare against)
inject_stability_metrics "$LOG_FILE" "baseline" ".stability-baseline.txt"

# Apply presets...

# Collect stability before tuned (reset baseline file for tuned pass)
rm -f .stability-baseline.txt
inject_stability_metrics "$LOG_FILE" "tuned" ".stability-baseline.txt"

# Run tuned benchmarks...
```

### 5. Collect Stability After Tuned
```bash
# After tuned completes, capture final state
inject_stability_metrics "$LOG_FILE" "tuned" ".stability-baseline.txt"

# Summarize results...
```

---

## Example: Updated Inference Benchmark (Pseudocode)

```bash
#!/usr/bin/env bash
# benchmark-inference-v0.4.sh (updated for v1.5)

set -e
source "$HOME/TAO-OS/scripts/inject-extended-data.sh"

LOG_FILE="${LOG_DIR}/bench-$(date +%Y%m%d-%H%M%S).log"

# --- PREFLIGHT ---
echo "[INFO] Starting inference benchmark (v0.4 with extended data)" | tee "$LOG_FILE"

# Collect hardware once
inject_hardware_fingerprint "$LOG_FILE"
echo "[INFO] Hardware fingerprint captured" | tee -a "$LOG_FILE"

# --- BASELINE PASS ---
echo "[INFO] Starting BASELINE pass..." | tee -a "$LOG_FILE"
inject_stability_metrics "$LOG_FILE" "baseline" ".stability-baseline.txt"

# Run baseline inference calls
# (existing code for measuring cold_total, tok/s, etc.)
BASELINE_COLD_MS="1019.7"
BASELINE_TOKS_PER_SEC="71.12"

# Log performance results (existing format)
echo "BASELINE_RESULT: cold_total=${BASELINE_COLD_MS}ms, tok/s=${BASELINE_TOKS_PER_SEC}" | tee -a "$LOG_FILE"

# Capture post-baseline stability
inject_stability_metrics "$LOG_FILE" "baseline" ".stability-baseline.txt"

# --- TUNED PASS ---
echo "[INFO] Applying presets..." | tee -a "$LOG_FILE"
bash "$PRESET_SCRIPT" # Or whatever applies presets

# Reset stability baseline for tuned pass
rm -f .stability-baseline.txt
inject_stability_metrics "$LOG_FILE" "tuned" ".stability-baseline.txt"

echo "[INFO] Starting TUNED pass..." | tee -a "$LOG_FILE"

# Run tuned inference calls
TUNED_COLD_MS="1014.0"
TUNED_TOKS_PER_SEC="69.90"

echo "TUNED_RESULT: cold_total=${TUNED_COLD_MS}ms, tok/s=${TUNED_TOKS_PER_SEC}" | tee -a "$LOG_FILE"

# Capture post-tuned stability
inject_stability_metrics "$LOG_FILE" "tuned" ".stability-baseline.txt"

# --- SUMMARY ---
COLD_DELTA=$(echo "scale=2; ($TUNED_COLD_MS - $BASELINE_COLD_MS)" | bc)
TOK_DELTA=$(echo "scale=2; (($TUNED_TOKS_PER_SEC - $BASELINE_TOKS_PER_SEC) / $BASELINE_TOKS_PER_SEC * 100)" | bc)

echo "SUMMARY: cold-start ${COLD_DELTA}ms, inference ${TOK_DELTA}%" | tee -a "$LOG_FILE"
echo "PASS_RESULT: baseline=$BASELINE_COLD_MS, tuned=$TUNED_COLD_MS, delta=$COLD_DELTA" | tee -a "$LOG_FILE"

# Undo presets
bash "$PRESET_SCRIPT" --undo

echo "[INFO] Benchmark complete. Log: $LOG_FILE" | tee -a "$LOG_FILE"
```

### Expected Log Output
```
[INFO] Starting inference benchmark (v0.4 with extended data)
EXTENDED_DATA:hardware={"cpu_microcode_version": "0x0a001144", "cpu_l1_cache_kb": 32, ...}
[INFO] Hardware fingerprint captured
[INFO] Starting BASELINE pass...
STABILITY_DATA:baseline={"dmesg_errors": 0, "cpu_throttle_events": 0, ...}
BASELINE_RESULT: cold_total=1019.7ms, tok/s=71.12
STABILITY_DATA:baseline={"dmesg_errors": 1, "cpu_throttle_events": 0, ...}
[INFO] Applying presets...
[INFO] Starting TUNED pass...
STABILITY_DATA:tuned={"dmesg_errors": 0, "cpu_throttle_events": 0, ...}
TUNED_RESULT: cold_total=1014.0ms, tok/s=69.90
STABILITY_DATA:tuned={"dmesg_errors": 2, "cpu_throttle_events": 1, ...}
SUMMARY: cold-start -5.7ms, inference -1.71%
PASS_RESULT: baseline=1019.7, tuned=1014.0, delta=-5.7
```

---

## BenchmarkAgent Extraction (Automatic)

BenchmarkAgent will automatically:
1. Grep the log for `EXTENDED_DATA:hardware=` → parse JSON → populate `hardware_extended`
2. Grep the log for `STABILITY_DATA:baseline=` and `STABILITY_DATA:tuned=` → parse JSON → populate `stability_extended`
3. Extract baseline/tuned metrics from existing `BASELINE_RESULT` and `TUNED_RESULT` lines
4. Validate all fields present; flag if any critical field is missing

---

## Scripts to Update

### Priority 1 (GPU-intensive, used in wq queue)
- [ ] `benchmarks/benchmark-inference-v0.3.sh` — cold-start, PRIMARY
- [ ] `benchmarks/benchmark-inference-v0.1.sh` — sustained throughput, used in fulltest

### Priority 2 (CPU-intensive, secondary)
- [ ] `benchmarks/benchmark-v0.9-paired.sh` — CPU paired test
- [ ] `benchmarks/benchmark-network-v0.1.sh` — Network BBR vs CUBIC (may skip hardware, focus on throttling)

### Implementation Order
1. Update benchmark-inference-v0.3.sh first (most critical)
2. Test with manual wq-018 run
3. Update others incrementally

---

## Rollback Plan

If new data collection causes benchmark timeouts or failures:
1. Comment out `inject_hardware_fingerprint` line (hardware capture only ~50ms)
2. Comment out `inject_stability_metrics` lines (stability capture ~100ms each)
3. Revert to previous v0.X script

New fields are optional in the schema, so incomplete data won't break tao-forge submissions.

---

## Testing Checklist (Before Merge)

- [ ] Script runs without errors on primary test rig (Arc A750)
- [ ] Log file contains `EXTENDED_DATA:hardware=` line with valid JSON
- [ ] Log file contains `STABILITY_DATA:baseline=` and `STABILITY_DATA:tuned=` lines
- [ ] Baseline and tuned passes complete successfully
- [ ] Performance deltas match expected ranges (no regressions from data collection overhead)
- [ ] BenchmarkAgent extracts all fields without errors
- [ ] Result JSON validates against handoff-schema.json

---

## Timeline

| Task | ETA | Status |
|------|-----|--------|
| Update handoff schema ✓ | 2026-03-24 | DONE |
| Update BenchmarkAgent spec ✓ | 2026-03-24 | DONE |
| Create collection scripts ✓ | 2026-03-24 | DONE |
| Update benchmark-inference-v0.3 | 2026-03-24 | TODO |
| Manual test run (wq-018) | 2026-03-24 eve | PLANNED |
| Update remaining benchmarks | 2026-03-25 | PLANNED |

---

## Questions?

- **"What if hardware probe fails?"** → Script returns null for that field. BenchmarkAgent logs the gap. Not fatal.
- **"Will stability metrics slow down benchmarks?"** → No. Collection is O(200 dmesg lines) = <100ms per call.
- **"Can I skip EXTENDED_DATA if no GPU?"** → Not recommended. Always inject; use null for missing fields.
- **"Do I need to update tao-forge schema?"** → Not yet. Test first. Supabase migration happens post-test (Connor decision).
