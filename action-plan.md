# action-plan.md — Board Status Update

**Last updated:** 2026-03-24 05:31 UTC  
**Status:** Phase 1 Complete, Data Expansion Sprint In Progress

---

## ✅ Completed Milestones (Phase 1)

### Power Bug (FIXED — commit b7664f3)
- **Issue:** RAPL readings were stale (global min, not per-socket)
- **Solution:** Fixed energy counter updates in benchmark-inference-v0.3.sh
- **Verification:** wq-013/014/015 all passed with stable power measurements
- **Impact:** Power deltas now trustworthy for all future runs

### v1.4 Schema (LIVE — commit 6e6112f)
- **Hardware fingerprint:** machine_id, CPU, GPU, OS now tracked in tao-forge
- **Baseline tracking:** Network/cold-start/sustained/power baselines stored per machine
- **Stability flag:** dmesg error count logged with each run
- **Result schema:** handoff-schema.json standard across all agents
- **Status:** All new submissions use v1.4 schema; older entries backfilled

### Confirmed Stack (wq-013/014/015 validated)
- **Tweaks:** `sched_util_clamp_min=128`, `tcp_tw_reuse=1`, `vm.swappiness=0`
- **v0.8 preset script** deployed with all three tweaks
- **Performance:** -25.7ms cold-start improvement, +425% network, minimal inference regression
- **Stability:** No throttling events, no dmesg errors across 3 independent runs
- **Status:** Auto-committed, integrated into confirmed-stack.json

---

## 🔄 Active Sprint: Expanded Data Collection (THIS SPRINT)

**Directive:** Capture all helpful metrics from benchmarks starting with next run.

### Work Items

#### 1. Extended Hardware Fingerprint (NEW FIELDS)
- **CPU microcode version** — identify vulnerability patches, silicon revisions
- **L1/L2/L3 cache sizes** — capacity-aware prefetch tuning
- **GPU VRAM amount** — correlate with model sizing / batch depth
- **GPU driver version** — identify driver-level regressions
- **RAM speed & channel config** — DRAM bandwidth limiting factor

**Implementation:**
- Create `scripts/collect-hardware-fingerprint.sh` — one-shot script that probes all five fields
- Integrate into `benchmark-v0.9-paired.sh` (CPU) and `benchmark-inference-v0.3.sh` (GPU)
- Feed result JSON into handoff schema under new `hardware_extended` object

#### 2. Inference Tokens Per Second (BASELINE + TUNED)
- **Baseline:** tok/s with vanilla presets (current)
- **Tuned:** tok/s with optimizations applied (current)
- **New:** Track *both* in explicit fields instead of deltas only

**Implementation:**
- Update handoff schema: add `inference_baseline_toks_per_sec`, `inference_tuned_toks_per_sec`
- Benchmark scripts already extract tok/s; just normalize the field names
- Ensure BenchmarkAgent logs both values separately

#### 3. Stability Metrics (DMESG + THROTTLING)
- **dmesg errors/warnings count** — system stability signal (already captured)
- **CPU throttling events count** — frequency scaling events during run
- **GPU throttling events count** — power/thermal throttling during run
- **Temperature throttling count** — distinct from power throttling

**Implementation:**
- Create `scripts/collect-stability-metrics.sh` — greps dmesg, reads thermal logs, counts throttling events
- Run before/after each benchmark pass
- Feed into handoff schema under new `stability_extended` object

#### 4. Update Handoff Schema
- Extend `agents/handoff-schema.json` with all new fields
- Keep old fields for backwards compatibility
- Make new fields optional initially (allow sparse data)

#### 5. Update BenchmarkAgent Spec
- Extend `agents/specs/benchmark-agent.md` to extract and validate new fields
- Add quality checks: "microcode version parsed", "VRAM > 0", "cache hierarchy complete"
- Flag if any new required field is missing or null

#### 6. Update Benchmark Scripts
- `benchmark-inference-v0.3.sh` (cold-start, GPU-intensive)
- `benchmark-inference-v0.1.sh` (sustained throughput, GPU-intensive)
- `benchmark-v0.9-paired.sh` (CPU benchmark)
- `benchmark-network-v0.1.sh` (network benchmark — may skip hardware, focus on throttling)

Each must:
1. Collect hardware fingerprint at start (once per session)
2. Collect stability metrics before baseline pass
3. Run baseline, collect post-baseline stability
4. Run tuned, collect post-tuned stability
5. Write all to log with structured `EXTENDED_DATA:` prefix
6. Feed BenchmarkAgent the raw log

---

## Tao-Forge Integration (Next Phase)

Once new fields are flowing from benchmarks:
1. **Database migration** — add columns to tao-forge `runs` table (Connor/Frosty decision)
2. **Schema sync** — ensure column names match handoff schema exactly
3. **Backfill logic** — decide: skip old runs, or best-effort extract?
4. **Query templates** — update tao-forge-status.sh to display new fields

---

## Data Collection Roll-Out Timeline

| Milestone | Date | Status |
|-----------|------|--------|
| Create collection scripts | 2026-03-24 | **IN PROGRESS** |
| Update handoff schema | 2026-03-24 | **IN PROGRESS** |
| Integrate into v0.3/v0.9 benchmarks | 2026-03-24 | **IN PROGRESS** |
| Update BenchmarkAgent spec | 2026-03-24 | **IN PROGRESS** |
| First test run (manual) | 2026-03-24 (evening) | PLANNED |
| wq-018 (full integration test) | 2026-03-25 | PLANNED |

---

## Risk / Open Items

- **Supabase schema change:** Board approval needed if we add columns. Propose add-only (no breaking changes).
- **Collection script robustness:** Hardware probes may fail on unknown CPUs/GPUs. Build graceful degradation (null fields OK for now).
- **Performance impact:** Running collection scripts adds ~2–5s per benchmark. Acceptable?

---

## Next Action (Connor)

Review this update and confirm:
1. Scope OK (5 new data categories)?
2. Timeline OK (roll-out by 2026-03-25)?
3. Supabase approval (new columns)?
4. Proceed with sprint execution?

---

**Board Summary:**
- ✅ Phase 1 complete: power bug fixed, v1.4 schema live, confirmed stack validated
- 🔄 Sprint: capturing comprehensive hardware + stability data starting next run
- 📊 Moat: tao-forge becomes increasingly defensible as dataset grows with each run
