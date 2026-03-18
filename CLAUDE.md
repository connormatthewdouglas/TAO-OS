# TAO-OS — Claude Orientation File

## Project Purpose
AI-optimized Linux for Bittensor miners, validators, and beyond.
The loop: make miners faster → earn more TAO → improve the OS → repeat.
End goal: a one-click pre-tuned OS image that is auto-updated by AI.

Primary subnet target: **SN64 Chutes** ("the Linux of AI").
Hardware philosophy: break NVIDIA dependency — develop and test on AMD CPU + Intel Arc GPU.

## Developer Hardware (test rig)
- CPU: AMD Ryzen 7 5700 (16 logical CPUs)
- GPU: Intel Arc A750 (DG2), idles at 600 MHz, boost 2400 MHz
- RAM: 15GB
- OS: Linux Mint 22.3
- Kernel: 6.17.0-19-generic
- Default governor: powersave (performance when presets applied)

## Three Benchmark Tools — Keep Them Separate from Presets

### 1. CPU Benchmark (`benchmark-v0.9-paired.sh`)
**Purpose:** Paired CPU stress test. Baseline vs tuned in same session.
- sysbench cpu (all threads, configurable duration)
- Both passes in same thermal window — avoids ambient temp drift
- Current version: v0.9 paired (v0.8 fixed v0.7's logging regression)

**sysbench limitation:** All cores at 100% continuously.
- C-state tweaks show no effect (cores never idle)
- GPU tweaks show no effect (sysbench is CPU-only)
- Network tweaks show no effect (no network I/O)
→ These tweaks ARE real improvements for mining but need purpose-built benchmarks.

### 2. Inference Benchmarks
#### `benchmark-inference-v0.1.sh` — Sustained throughput
- Model stays warm, measures steady-state tok/s
- Tests GPU compute throughput
- tinyllama result: 68.75 vs 68.07 tok/s (flat — GPU-bound, CPU presets don't help)

#### `benchmark-inference-v0.2.sh` — Cold-start latency ← KEY FOR MINING
- Forces model unload between calls (`keep_alive=0s`), 15s GPU idle gap
- Measures `load_duration` + `prompt_eval_duration` (TTFT) — what validators wait for
- GPU idles to 600 MHz between calls without preset; 2000 MHz with preset
- Result: **1023.6ms → 1001.1ms (-2.19%, -22ms per request)**
- This validates the GPU min-freq preset. The impact scales with model size.

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

## Known Limitations
**Vulkan backend (ollama 0.18.1) instability on Arc A750:**
- tinyllama (1.1B): works, 69-77 tok/s
- llama3.2:3b (3B): runs but produces garbled output (Vulkan fp16 precision bug)
- mistral:7b (7B): crashes with `Assertion 'found' failed` (NaN logits in sampler)
→ Path forward: Intel SYCL/OpenVINO backend (llama.cpp built with SYCL)

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

## Roadmap (next steps)
1. Intel SYCL backend for llama.cpp → stable 7B+ inference on Arc A750
2. Batched inference benchmark → measure GPU freq lock impact between real mining requests
3. Bittensor subnet validator test (SN64 Chutes actual mining, not simulated)

## Rules / Design Principles
- Benchmark tools: NEVER apply tweaks inside them. Vanilla/neutral only.
- Preset tool: ALL tweaks must be temporary by default (reset on reboot or --undo).
- Always back up original state before applying presets.
- Always validate a new tweak with before/after benchmark runs.
- Keep benchmark tools and preset tool versioned separately.
- Target AMD CPU + Intel Arc first — NVIDIA is not the primary focus.
- Keep scripts simple, readable bash — no complex dependencies.
- sudo PIN is baked in via `SP="2633"` pattern in all scripts.
