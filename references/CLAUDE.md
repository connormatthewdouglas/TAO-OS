# TAO-OS — Claude Orientation File

**Last updated:** 2026-03-20
**Founder:** Frosty Condor (@frostycondor)
**Status:** Fast Iteration Mode active (daily / every 2–3 days cadence)
**Active Collaborators:** Claude (Lead Dev) · OpenClaw (async execution while founder is away)

## Tool Error Handling (Important)
**If a tool call returns a JSON parse error or malformed response:**
1. **Retry once immediately** — network hiccups are real
2. **If retry fails:** escalate to Copper with the full error message
3. **Do NOT guess or work around** — structured data errors need transparency

This keeps debugging fast and prevents silent corruption of work_queue.json, hardware-profiles.json, etc.

## North Star
AI-guided self-improving OS + decentralized data→reward loop (DePIN style) for all crypto miners and beyond.
Data moat first. Execution discipline enforced.

Miners run TAO-OS → submit optimizations → benchmarks measure deltas → AI builds perfect OS → rewards distributed → more miners join → more data → better OS. Closed self-improving loop.

We stay in self-validation phase until we have undeniable proof.

## Project Purpose
AI-optimized Linux for crypto miners (Bittensor primary; Kaspa, ETC, Monero, etc. Phase 2+).
Primary subnet target: **SN64 Chutes** ("the Linux of AI").
Hardware philosophy: break NVIDIA dependency — develop and test on AMD CPU + Intel Arc GPU.

**Strategic framing:** This is a *data problem*. Hardware → tweaks → measured deltas → AI builds perfect OS.
The tao-forge schema is the true moat. DePIN-style incentive layer is the long-term goal (post-v1.5).
Broader crypto-mining gives AI the hardware diversity it needs for a 10x addressable market.

## Rebrand (Private — Locked Until v1.5)
- Public name stays **TAO-OS** until v1.5 gate (zero external users = perfect window to rename)
- Private shortlist winner: **ForgeOS** (keeps forge equity, chain-agnostic, premium signal)
- Do NOT touch public branding before v1.5 gate
- Action-plan.md should include a branding review line for the v1.5 milestone

## Current Phase
**Self-testing on Frosty's personal fleet only.**
No external sharing, no public testers until v1.5 gate (see Roadmap).
Fleet: Arc A750 rig (primary) · RX 580 machine · laptops + all-in-one · 1-2 trusted friends' PCs

## OpenClaw Integration
OpenClaw is online as an async execution agent — handles development tasks while founder is away from desk.
- OpenClaw takes direction from this CLAUDE.md and from Claude's lead-dev decisions
- Claude remains Lead Dev; OpenClaw executes
- Both agents must respect all versioning and design rules in this file

## Current Live Scripts (never overwrite old versions — always increment)
- `tao-os-full-test-v1.3.sh`          ← Main one-command wrapper (current)
- `tao-os-presets-v0.7.sh`            ← 25 reversible tweaks (current)
- `benchmark-v0.9-paired.sh`          ← Paired CPU benchmark
- `benchmark-inference-v0.1.sh`       ← Sustained throughput
- `benchmark-inference-v0.2.sh`       ← Cold-start latency (key for mining)
- `benchmark-network-v0.1.sh`         ← BBR vs CUBIC WAN sim
- `setup-intel-arc.sh`                ← Arc A750 driver/env setup

## Developer Hardware (primary test rig)
- CPU: AMD Ryzen 7 5700 (16 logical CPUs)
- GPU: Intel Arc A750 (DG2), idles at 600 MHz, boost 2400 MHz
- RAM: 15GB
- OS: Linux Mint 22.3
- Kernel: 6.17.0-19-generic
- Default governor: powersave (performance when presets applied)

## Hardware Database (Strategic Asset)
**`hardware-profiles.json`** — living, structured database that grows with every test run.
- Starts with Frosty's Arc A750 rig
- Long-term: AI gives instant, offline-optimized presets for any new machine
- Core subnet asset — treat with care, never overwrite blindly
- **v1.4 schema enhancements (mandatory, ship after power bug fix):**
  - `hardware_fingerprint_hash` — hardware-bound anti-gaming field
  - `stability_flag` — marks runs where presets caused instability
  - `power_idle_baseline_w` / `power_tuned_w` — split power fields (replaces null-buggy single field)
  - `thermal_headroom_c` — headroom above throttle threshold at test time
  - `kernel_version` — kernel string at time of run
  - `distro` — OS/distro name and version

## Three Benchmark Tools — Keep Them Separate from Presets

### 1. CPU Benchmark (`benchmark-v0.9-paired.sh`)
**Purpose:** Paired CPU stress test. Baseline vs tuned in same session.
- sysbench cpu (all threads, configurable duration)
- Both passes in same thermal window — avoids ambient temp drift

**sysbench limitation:** All cores at 100% continuously.
- C-state tweaks show no effect (cores never idle)
- GPU tweaks show no effect (sysbench is CPU-only)
- Network tweaks show no effect (no network I/O)
→ These tweaks ARE real improvements for mining but need purpose-built benchmarks.

### 2. Inference Benchmarks
#### `benchmark-inference-v0.1.sh` — Sustained throughput
- Model stays warm, measures steady-state tok/s
- tinyllama result: 68.75 vs 68.07 tok/s (flat — GPU-bound, CPU presets don't help)

#### `benchmark-inference-v0.2.sh` — Cold-start latency ← KEY FOR MINING
- Forces model unload between calls (`keep_alive=0s`), 15s GPU idle gap
- Measures `load_duration` + `prompt_eval_duration` (TTFT) — what validators wait for
- GPU idles to 600 MHz between calls without preset; 2000 MHz with preset
- Result: **-22–27ms per request** across fleet

### 3. Network Benchmark (`benchmark-network-v0.1.sh`)
- Uses `tc netem` on loopback: 50ms RTT + 0.5% loss (simulates WAN)
- Compares CUBIC vs BBR + 16MB buffers via iperf3
- Root cause: 212KB default socket buffer is smaller than BDP (2.4MB at 50ms RTT)
- Impact: 2.3x faster chain sync, model weight delivery, Bittensor gossip

## Preset Applicator (`tao-os-presets-v0.7.sh`)
**Purpose:** Apply temporary mining-tuned OS settings. Fully reversible.
- `--apply-temp`: applies tweaks, backs up original state
- `--undo`: reverts to saved state
- `--dry-run`: show what would change without applying

**Current version v0.7 tweaks (25 total)** — see script for full list.
Core categories: CPU governor · energy preference · net buffers · TCP (BBR/fq) · scheduler ·
swappiness · NMI watchdog · GPU SLPC · GPU min/boost freq · C2/C3 disable · THP

## Proven Results (as of v0.7 presets, multi-machine)
| Machine | Benchmark | Delta | Notes |
|---------|-----------|-------|-------|
| Arc A750 rig | Network throughput (WAN sim) | **+454–616%** | BBR + 16MB buffers |
| Arc A750 rig | Cold-start latency | **-22–27ms** | GPU freq lock |
| FX-8350 rig | Network throughput (WAN sim) | **+591%** | BBR + 16MB buffers |
| FX-8350 rig | Cold-start latency | **-366–395ms** | C-state + CPU preset |
| Any rig | Sustained inference (warm) | ~flat | Expected — GPU-bound |

## Known Limitations
**Vulkan backend (ollama 0.18.1) instability on Arc A750:**
- tinyllama (1.1B): works, 69-77 tok/s
- llama3.2:3b (3B): garbled output (Vulkan fp16 precision bug)
- mistral:7b (7B): crashes with `Assertion 'found' failed` (NaN logits in sampler)
→ Path forward: Intel SYCL/OpenVINO backend — parked until v1.5

**Current Active Bug:** `power_idle_tuned_w` returns null in wrapper (turbostat capture fails post-C-state disable). This is the Phase 1 gate blocker.

## Version History
- benchmark-v0.1/v0.2: tweaks baked in (don't use as baseline)
- benchmark-v0.4: first clean CPU sim (no progress, no temp)
- benchmark-v0.5/v0.6: live progress + AMD Tctl temp detection (v0.6 = best reference)
- benchmark-v0.7: regression — captured sysbench to variable, broke progress/temp/logging
- benchmark-v0.8-vanilla: fixed v0.7, added `last_print` tracker for progress
- benchmark-v0.9-paired: paired baseline+tuned in same session (thermal fair)
- benchmark-inference-v0.1: sustained throughput, ollama REST API
- benchmark-inference-v0.2: cold-start latency, keep_alive=0, GPU freq impact
- benchmark-network-v0.1: BBR vs CUBIC via iperf3 + tc netem WAN sim
- tao-os-presets-v0.1: governor + energy bias
- tao-os-presets-v0.2: + net buffers
- tao-os-presets-v0.3: + scheduler, BBR, swappiness, NMI, C-states, THP, GPU freq
- tao-os-presets-v0.4: dropped CPU min-freq lock (caused thermal regression)
- tao-os-presets-v0.5: all v0.4 tweaks + GPU SLPC, min/boost freq, C2/C3, THP
- tao-os-presets-v0.6: intermediate
- tao-os-presets-v0.7: current — 25 tweaks
- tao-os-full-test-v1.0.sh: first wrapper
- tao-os-full-test-v1.3.sh: current wrapper with turbostat power logging

## Active Roadmap

### COMPLETED
- [x] Fix hardcoded `SP="2633"` → prompt once, export `TAO_SUDO_PASS`
- [x] Rewrite README — lead with network win
- [x] Create wrapper (`tao-os-full-test-v1.3.sh`)
- [x] Add `CHANGELOG.md`
- [x] Multi-machine fleet runs documented
- [x] Add turbostat power draw logging
- [x] tao-forge auto-submit live
- [x] `docs/action-plan.md` — full phased roadmap

### PHASE 1 — CURRENT BLOCKER FIRST
1. **Fix power bug** — `power_idle_tuned_w` null (turbostat capture fails post-C-state disable)
2. **Implement v1.4 schema** — hardware_fingerprint_hash + stability_flag + split power fields + thermal_headroom_c + kernel_version + distro
3. **Add branding review line** to action-plan.md (at v1.5 milestone)
4. **Complete self-fleet runs** — log all machines to hardware-profiles.json

### EXTERNAL VALIDATION GATE — v1.5 "Proven & Trusted Fleet"
**Trigger:** 5+ external miners + clean safety record + documented ≥1.5% average mining/inference gain
- Do NOT share publicly or solicit external testers before this gate
- Rebrand review (ForgeOS) happens here

### PHASE 2+ — After v1.5 Gate
- Broader crypto-mining test (Kaspa, ETC, Monero rigs)
- DePIN/incentive layer exploration (Hivemapper/Helium model — NOT a new L1)
- Intel SYCL backend → stable 7B+ inference on Arc
- Batched inference benchmark (real mining request cadence)
- SN64 Chutes live validator test

## Rules / Design Principles
- **Never overwrite existing scripts** — always create new versioned file (v0.X / v1.X).
- Benchmark tools: NEVER apply tweaks inside them. Vanilla/neutral only.
- Preset tool: ALL tweaks must be temporary by default (reset on reboot or --undo).
- Support `--dry-run` in all new preset versions — show changes before applying.
- Always explain every sudo operation. Safety first.
- Always back up original state before applying presets.
- Always validate a new tweak with ≥2 before/after benchmark runs.
- Keep benchmark tools and preset tool versioned separately.
- Target AMD CPU + Intel Arc first — NVIDIA is not the primary focus.
- Keep scripts simple, readable bash — no complex dependencies.
- **Complexity Kill Switch:** if >1 new package required or logic becomes confusing → simplify or drop.
- No DePIN/incentive work until post-v1.5.
- No YouTube channel.

## Kill Switches
- If wrapper is confusing after 30 min → drop back to separate scripts
- If SYCL work exceeds 1 day → park it; v1.5 gate comes first
- If DePIN/incentive scope creeps before v1.5 → cut it
