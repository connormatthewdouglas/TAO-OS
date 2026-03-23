# TAO-OS Action Plan
**Last updated:** 2026-03-23
**Current preset:** v0.8 (28 tweaks) — validated on Arc A750 + RX 580
**Current wrapper:** v1.4
**Board reviewed:** 2026-03-23 05:30 EDT

---

## Current State

Self-fleet validation is in progress. v0.8 preset stack confirmed (wq-013/014/015 all passed individual + integration tests). Power bug fixed (RAPL reads, b7664f3). v1.4 schema live — hardware fingerprint, stability flag, split power fields. tao-forge auto-submitting from both fleet machines.

**3 machines in tao-forge:**
- Vega — AMD Ryzen 7 5700 + Arc A750 — 25 runs, primary test rig
- Stardust — AMD FX-8350 + RX 580 — 4 runs, needs full v1.4 validation run
- bda4bd63 — AMD Ryzen 7 5700 + Arc A750 — 1 run (duplicate Vega entry, investigate)

**v0.8 confirmed stack (3 tweaks on top of v0.7 base):**
- `kernel.sched_util_clamp_min=128` (wq-013)
- `net.ipv4.tcp_tw_reuse=1` (wq-014)
- `vm.swappiness=0` (wq-015)

---

## Active Board Tasks — Priority Order

### 1. ✅ Enforce hybrid config + $2/day spend cap on Copper
- Heartbeat reduced to 60m ✅
- Spend monitor live — cron every 30m, auto-pauses gateway on breach ✅
- Dashboard spend card live ✅
- Next: route 85%+ of Copper workload to local Ollama (see task 5)

### 2. ✅ Update action-plan.md as single source of truth
- This document.

### 3. Run full v1.4 validation on Stardust (FX-8350 + RX 580)
- Run `tao-os-full-test-v1.4.sh` on Stardust
- Confirm v1.4 schema fields all populate (especially power readings)
- Submit results to tao-forge
- Need ≥2 clean v0.8 runs on Stardust before it counts toward v1.5 gate

### 4. Implement Copper Autonomy Score
- Daily metric: % of actions Copper completed without Founder approval
- Report in HEARTBEAT.md and dashboard
- Baseline first — track approvals.json + work_queue.json pass/flag/reject ratio
- Target: establish baseline before setting improvement goals

### 5. Route 85%+ of Copper workload to local Ollama
- Ollama models available: qwen2.5-coder:14b, mistral, mistral-cpu, llama3.2:3b, tinyllama
- OpenClaw doesn't natively expose Ollama in `models list` — routing approach TBD
- Goal: heartbeats + queue worker tasks on local model; cloud only for planner tasks
- This directly reduces cloud spend toward near-zero for routine work

### 6. Rebrand task prep — ForgeOS
- Private only — nothing public before v1.5 gate
- Prepare file list of everything that needs renaming (scripts, README, repo, dashboard)
- Do not execute the rename — prep the commit plan only
- Board shortlist winner: **ForgeOS**

### 7. Begin planning external testers + laptop/AIO validation (v1.5 gate prep)
- v1.5 gate conditions: 5+ external machines, clean safety record, ≥1.5% avg gain confirmed externally
- Identify 2-3 trusted testers for first external runs
- Verify `--undo` works cleanly on every fleet machine before sending to anyone
- Laptop + all-in-one: run v0.8 on remaining self-fleet hardware first
- Write plain-English "what TAO-OS does to your system" explainer for external testers
- **NVIDIA laptops:** run v0.8 as-is — wrapper detects NVIDIA, applies all GPU-agnostic tweaks (TCP, swappiness, scheduler), skips GPU-specific section gracefully, submits to tao-forge. Goal: NVIDIA hardware entries in database + proof that system-level gains apply regardless of GPU vendor. Do not attempt GPU clock/power tuning on laptop hardware.
- **Pre-req:** add NVIDIA detection block to wrapper (~20 lines bash) so GPU-specific section skips cleanly instead of erroring. Do this before running laptops.

---

## v1.5 Gate Checklist

- [ ] 5+ external machines running the wrapper with auto-submit to tao-forge
- [ ] Clean safety record — no bricked systems, no data loss
- [ ] ≥1.5% average mining/inference gain confirmed from external machines
- [ ] tao-forge confirmed receiving auto-submit from machines we don't control
- [ ] Safety audit: `--undo` tested on every fleet machine
- [ ] Wrapper works on fresh git clone
- [ ] Plain-English explainer written for external testers
- [ ] ForgeOS rebrand executed (one clean commit)

---

## Scope Rules (standing)

- **Complexity kill switch:** >1 new package required → simplify or drop
- **Validation rule:** ≥2 paired runs before any tweak enters preset stack
- **No permanent changes:** every tweak reversible, `--undo` always works
- **Self-fleet only** until v1.5 gate — no public solicitation before then
- **No DePIN/incentive layer** before v1.5 gate
- **No rebrand execution** before v1.5 gate — prep only
- **Broader crypto mining scope:** tool is chain-agnostic, Kaspa/ETC/Monero valid targets for Phase 2+

---

## Copper Execution Docket (deferred to Copper)

These are approved tasks ready for Copper to execute — do not re-debate strategy, just implement:

- **Whitepaper rewrite** (`docs/white-paper.md`) — update to reflect expanded audience (crypto miners + local AI/LLM users). Lead with data moat + DePIN vision. Position both audiences as identical beneficiaries of the same OS-level bottleneck fixes.
- **README rewrite** (`README.md`) — expand from crypto mining focus to include local AI users (Ollama, llama.cpp, home inference clusters). Lead with the network win (+454–616%). Add local AI use case section after mining results. Keep technical, no hype.

---

## Parking Lot (post-v1.5)

- **Full NVIDIA GPU tuning** — power limits, persistence mode, clock management targeting desktop RTX cards (3080/4090). Dedicated workstream, requires desktop NVIDIA hardware to validate properly.
- Intel Arc SYCL backend for llama.cpp (current Vulkan crashes on 3B+)
- DePIN incentive layer (Hivemapper/Helium style)
- Batched inference benchmark — multi-request throughput under load
- SN64 Chutes live validator test
- Bittensor subnet design (v3.0)
- Bootable ISO (v4.0+)
