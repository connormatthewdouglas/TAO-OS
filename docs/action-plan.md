# CursiveOS Action Plan
**Last updated:** 2026-03-25
**Current preset:** v0.8 (28 tweaks) — validated on Arc A750 + RX 580
**Current wrapper:** v1.4
**Board reviewed:** 2026-03-23 05:30 EDT

---

## Current State

Self-fleet validation is in progress. v0.8 preset stack confirmed (wq-013/014/015 all passed individual + integration tests). Power bug fixed (RAPL reads, b7664f3). v1.4 schema live — hardware fingerprint, stability flag, split power fields. CursiveRoot auto-submitting from both fleet machines.

**3 machines in CursiveRoot (49 runs total as of 2026-03-25):**
- Vega — AMD Ryzen 7 5700 + Arc A750 — 31 runs, primary test rig
- Stardust — AMD FX-8350 + RX 580 — 17 runs
- bda4bd63 — AMD Ryzen 7 5700 + Arc A750 — 1 run (early partial entry)

**v0.8 confirmed stack (3 tweaks on top of v0.7 base):**
- `kernel.sched_util_clamp_min=128` (wq-013)
- `net.ipv4.tcp_tw_reuse=1` (wq-014)
- `vm.swappiness=0` (wq-015)

---

## Active Board Tasks — Priority Order

### 1. Define the Founding Operator program
- Write the simple rules for who qualifies, what they do, what they get, and how future upside will be considered.
- Keep the framing serious and non-hype: early operators, not disposable testers.

### 2. Create the contributor ledger
- Track who contributed hardware, runs, bugs found, and overall contribution value.
- This is the bridge between goodwill now and stronger incentives later.

### 3. Improve the first-run external experience
- Tighten onboarding, rollback clarity, error reporting, and expectation-setting.
- Goal: the first external run feels safe, legible, and worth repeating.

### 4. Recruit 3–5 technically aligned founding operators
- Prioritize local AI, mining, homelab, and builder communities.
- Prefer mission-aligned operators over one-off paid testers.

### 5. White-glove the first cohort
- Treat the first external operators as collaborators.
- Use their runs and feedback to harden the product and onboarding.

### 6. Use paid testers only for narrow QA later
- Fiverr-style testing is not the main validation engine.
- Reserve paid testers for controlled onboarding/usability checks after the first-run flow is stable.

### 7. Buy hardware only where it closes meaningful validation gaps
- Spend hardware budget where it reduces uncertainty or covers an important user segment.
- Prefer coverage/relevance over raw compute prestige.

### 8. Prioritize reliability and repeatability over flashy features
- Near-term product work should focus on safe rollback, debuggability, and predictable external success.
- Add new features only when they support trust or leverage.

### 9. Continue improving the preset stack only when gains are measured
- Every new tweak should be benchmarked, meaningful, and worth the added complexity.
- Avoid complexity creep that makes external testing harder.

### 10. Build early community through measured proof
- Share evidence, real deltas, and trust-building results where target users already gather.
- The immediate goal is not broad hype; it is converting a few good operators into repeat contributors.

---

## v1.5 Gate Checklist

- [ ] 5+ external machines running the wrapper with auto-submit to CursiveRoot
- [ ] Clean safety record — no bricked systems, no data loss
- [ ] ≥1.5% average mining/inference gain confirmed from external machines
- [ ] CursiveRoot confirmed receiving auto-submit from machines we don't control
- [ ] Safety audit: `--undo` tested on every fleet machine
- [ ] Wrapper works on fresh git clone
- [ ] Plain-English explainer written for external testers
- [x] CursiveOS rebrand executed (2026-03-25)

---

## Scope Rules (standing)

- **Complexity kill switch:** >1 new package required → simplify or drop
- **Validation rule:** ≥2 paired runs before any tweak enters preset stack
- **No permanent changes:** every tweak reversible, `--undo` always works
- **Self-fleet only** until v1.5 gate — no public solicitation before then
- **No DePIN/incentive layer** before v1.5 gate
- **Broader crypto mining scope:** tool is chain-agnostic, Kaspa/ETC/Monero valid targets for Phase 2+

---

## Copper Execution Docket (deferred to Copper)

These are approved tasks ready for Copper to execute — do not re-debate strategy, just implement:

- **Whitepaper rewrite** (`white-paper.md`) — update to reflect expanded audience (crypto miners + local AI/LLM users). Lead with data moat + DePIN vision. Position both audiences as identical beneficiaries of the same OS-level bottleneck fixes.
- **README rewrite** (`README.md`) — expand from crypto mining focus to include local AI users (Ollama, llama.cpp, home inference clusters). Lead with the network win (+454–616%). Add local AI use case section after mining results. Keep technical, no hype.

---

## Benchmark Limitations (known, documented)

- **Inference delta is small on GPU (~5–15%)** — network is the headline (+400–900%). Inference improvement from GPU freq + THP is real but modest for single-stream workloads.
- **Concurrent throughput not measured** — this is where scheduler tuning (autogroup, granularity, sched_util_clamp_min) shows its real inference impact. Multiple parallel requests stress the scheduler in ways single-stream doesn't.
- **VRAM model table incomplete** — inference benchmark covers 4GB+ (phi3) and 8GB+ (mistral). Cards with 2–3GB VRAM have no recommendation yet.
- **ROCm auto-install Ubuntu/Debian only** — other distros get a manual URL. Covers the majority of mining rigs.
- **CPU inference correctly suppressed** — cold-start is the honest CPU story; sustained CPU inference delta is unreliable due to thermal variance from C-state changes.

## Parking Lot (post-v1.5)

- **Full NVIDIA GPU tuning** — power limits, persistence mode, clock management targeting desktop RTX cards (3080/4090). Dedicated workstream, requires desktop NVIDIA hardware to validate properly.
- **Concurrent throughput benchmark** — measure requests/sec under parallel load. Scheduler tweaks show here.
- **VRAM model table expansion** — add llama3.2:1b (~0.8GB), qwen2:1.5b (~0.9GB) for 2–3GB cards.
- Intel Arc SYCL backend for llama.cpp (current Vulkan crashes on 3B+)
- DePIN incentive layer (Hivemapper/Helium style)
- SN64 Chutes live validator test
- Bittensor subnet design (v3.0)
- Bootable ISO (v4.0+)
