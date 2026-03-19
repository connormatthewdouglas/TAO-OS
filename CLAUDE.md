# TAO-OS — Claude Orientation File

**Last updated:** 2026-03-19
**Founder:** Frosty Condor (@frostycondor)
**Status:** Fast Iteration Mode active (daily / every 2–3 days cadence)

## North Star
Miners run TAO-OS → submit optimizations → validators score → best improvements win TAO → entire network gets a better OS → closed self-improving loop.

We stay in self-validation phase until we have undeniable proof.

## Project Purpose
AI-optimized Linux for Bittensor miners, validators, and beyond.
Primary subnet target: **SN64 Chutes** ("the Linux of AI").
Hardware philosophy: break NVIDIA dependency — develop and test on AMD CPU + Intel Arc GPU.

## Current Phase
**Self-testing on Frosty's personal fleet only.**
No external sharing, no public testers until v1.5 gate (see Roadmap).
Fleet: Arc A750 rig (primary) · RX 580 machine · laptops + all-in-one · 1-2 trusted friends' PCs

## Current Live Scripts (never overwrite old versions — always increment)
- `tao-os-full-test-v1.0.sh`          ← Main one-command wrapper
- `tao-os-presets-v0.5.sh`            ← 14 reversible tweaks
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
- Result: **1023.6ms → 1001.1ms (-2.19%, -22ms per request)**

### 3. Network Benchmark (`benchmark-network-v0.1.sh`)
- Uses `tc netem` on loopback: 50ms RTT + 0.5% loss (simulates WAN)
- Compares CUBIC vs BBR + 16MB buffers via iperf3
- Result: **169.2 → 384.4 Mbit/s (+127%)**
- Root cause: 212KB default socket buffer is smaller than BDP (2.4MB at 50ms RTT)
- Impact: 2.3x faster chain sync, model weight delivery, Bittensor gossip

## Preset Applicator (`tao-os-presets-v0.5.sh`)
**Purpose:** Apply temporary mining-tuned OS settings. Fully reversible.
- `--apply-temp`: applies tweaks, backs up original state
- `--undo`: reverts to saved state
- `--dry-run`: show what would change without applying (add to all new versions)

**Current version v0.5 tweaks (14 total):**
- CPU governor → performance
- Energy performance preference → performance
- Net buffers: rmem_max + wmem_max → 16MB
- TCP congestion control → BBR + fq
- TCP slow start after idle → disabled
- Scheduler autogroup → disabled
- vm.swappiness → 10
- NMI watchdog → disabled
- GPU SLPC: efficiency hints ignored
- GPU min freq → 2000 MHz (prevents 600 MHz idle drop)
- GPU boost freq → 2400 MHz
- CPU C2 idle state → disabled (18μs latency)
- CPU C3 idle state → disabled (350μs latency)
- Transparent Huge Pages → always

## Proven Results (as of v0.5 presets)
| Benchmark | Baseline | Tuned | Delta | What it validates |
|-----------|---------|-------|-------|------------------|
| Cold-start latency | 1023.6ms | 1001.1ms | **-2.19%** | GPU min-freq preset |
| Network throughput (WAN sim) | 169.2 Mbit/s | 384.4 Mbit/s | **+127%** | BBR + 16MB buffers |
| Sustained inference (warm) | 68.75 tok/s | 68.07 tok/s | -0.98% (flat) | expected — GPU-bound |

## Personal Data History (5 runs, 2026-03-18)
| Run | Network delta | Cold-start delta | Power delta |
|-----|--------------|-----------------|-------------|
| 1   | +124%        | -2.19%          | N/A         |
| 2   | +110%        | -2.15%          | N/A         |
| 3   | +111%        | -1.21%          | +8.4W       |
| 4   | +55% (CUBIC anomaly — high baseline) | -1.41% | +5.7W |
| 5   | +123%        | ~-0.7%          | varies (thermal) |

Key observations:
- Network: BBR holds 380-390 Mbit/s consistently; CUBIC variance 140-248 Mbit/s skews delta
- Cold-start: consistent -1 to -2.2% direction across all runs — GPU freq lock confirmed
- Sustained inference: noisy within long sessions (thermal drift between baseline/tuned passes)
- Power: real +5-8W cost when system is at normal operating temperature

## Known Limitations
**Vulkan backend (ollama 0.18.1) instability on Arc A750:**
- tinyllama (1.1B): works, 69-77 tok/s
- llama3.2:3b (3B): garbled output (Vulkan fp16 precision bug)
- mistral:7b (7B): crashes with `Assertion 'found' failed` (NaN logits in sampler)
→ Path forward: Intel SYCL/OpenVINO backend (llama.cpp built with SYCL) — parked until v1.5

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
- tao-os-presets-v0.5: current — all v0.4 tweaks + GPU SLPC, min/boost freq, C2/C3, THP

## Active Roadmap

### COMPLETED — Day 1-3
- [x] Fix hardcoded `SP="2633"` → prompt once, export `TAO_SUDO_PASS`
- [x] Rewrite README — lead with +127% network win
- [x] Create `tao-os-full-test-v1.0.sh` — single command wrapper
- [x] Add `CHANGELOG.md`
- [x] 5 full wrapper runs, data history documented
- [x] Add turbostat power draw logging

### CURRENT — Self-Fleet Testing (Day 4+)
1. Run full-test wrapper on every fleet machine, log to hardware-profiles.json
2. Presets v0.6 queued tweaks: Hugepages + NUMA pinning · AMD CPB toggle · SYCL env vars for Arc stability · IRQ affinity
3. Test each new tweak ≥2× on founder's machine before fleet rollout

### EXTERNAL VALIDATION GATE — v1.5 "Proven & Trusted Fleet"
**Trigger:** 5+ external miners + clean safety record + documented ≥1.5% average mining/inference gain
- Do NOT share publicly or solicit external testers before this gate

### PARKED — after v1.5 gate clears
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
- No YouTube channel, no second autonomous agent (OpenClaw) — stay lean.

## Kill Switches
- If v1.0 wrapper is confusing after 30 min → drop back to separate scripts
- If SYCL work exceeds 1 day → park it; v1.5 gate comes first
