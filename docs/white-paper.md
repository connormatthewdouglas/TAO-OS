# TAO-OS: AI-Optimized Linux for Bittensor Miners
### Technical White Paper — v0.1 Draft (March 2026)

---

## Abstract

TAO-OS is an open-source Linux optimization stack designed specifically for Bittensor miners and validators. By applying a set of temporary, fully-reversible OS-level tweaks, TAO-OS demonstrably improves the two metrics that determine mining profitability: network throughput and inference cold-start latency. In testing across two distinct hardware configurations, TAO-OS delivered **+129–300% network throughput** and **-2.9–15.8% cold-start latency** improvement with zero permanent system changes. Every tweak reverts on reboot or with a single command.

The long-term vision: a self-improving subnet where miners submit OS optimizations, validators score real performance gains, and TAO emissions flow to the best configurations — making the entire network faster through competitive iteration.

---

## 1. The Problem

Bittensor miners compete on response speed. Validators query miners unpredictably and score them on latency and throughput. Two bottlenecks account for the majority of preventable performance loss on Linux systems:

**1.1 Network throughput**

Linux ships with a 212KB default socket buffer — a value appropriate for 1990s modem speeds. The bandwidth-delay product (BDP) on a modern WAN link with 50ms RTT at 400 Mbit/s is approximately 2.4MB. When the buffer is smaller than the BDP, TCP cannot fill the pipe. The result: chain sync, model weight delivery, and Bittensor gossip traffic all run at a fraction of available bandwidth regardless of link speed.

Additionally, Linux defaults to CUBIC congestion control, which degrades aggressively under packet loss. Bittensor's P2P traffic operates over the public internet where 0.5–1% loss is normal.

**1.2 Cold-start latency**

Between validator queries, a miner's GPU idles to its minimum frequency — as low as 300–600 MHz on Intel Arc hardware. When a cold request arrives, the GPU must ramp back to operating frequency before inference can begin. On Intel Arc A750 hardware, this idle-to-active ramp adds approximately 22ms to every cold request. On older hardware without GPU frequency control, CPU governor and C-state latency dominate instead — adding 100–150ms per cold request on tested AMD FX-series hardware.

These losses are invisible in standard benchmarks and untreated in default Linux configurations. TAO-OS targets both.

---

## 2. The TAO-OS Approach

TAO-OS applies OS-level tweaks at runtime without modifying system files permanently. The design principles:

- **Temporary by default.** Every change reverts on reboot or with `--undo`. No permanent modifications.
- **Benchmarked before shipping.** No tweak enters the preset stack without a paired before/after measurement.
- **Hardware-aware.** The preset script detects available hardware features and skips inapplicable tweaks gracefully.
- **Single command.** `./tao-os-full-test-v1.2.sh` runs all benchmarks, applies presets, measures the delta, and submits results to the hardware database automatically.

---

## 3. Technical Implementation

### 3.1 Preset Stack (v0.6 — 18 tweaks)

**Network (4 tweaks)**
| Tweak | Value | Mechanism |
|-------|-------|-----------|
| Socket buffers (rmem/wmem_max) | 16MB | Allows TCP to fill the BDP on WAN links |
| TCP congestion control | BBR + fq | Better throughput under packet loss vs CUBIC |
| TCP slow start after idle | disabled | Prevents throughput reset after mining pauses |
| Scheduler autogroup | disabled | Removes desktop process grouping from server workloads |

**CPU (5 tweaks)**
| Tweak | Value | Mechanism |
|-------|-------|-----------|
| CPU governor | performance | Full clock speed, eliminates scaling delays |
| Energy performance preference | performance | Hardware power hint to CPU firmware |
| AMD CPU boost | enabled | Ensures turbo boost not disabled by power profiles |
| CPU C2 idle state | disabled | Eliminates 18μs wakeup latency spike |
| CPU C3 idle state | disabled | Eliminates 350μs wakeup latency spike |

**GPU — Intel Arc only (3 tweaks)**
| Tweak | Value | Mechanism |
|-------|-------|-----------|
| SLPC efficiency hints | ignored | Forces Arc into full performance mode |
| GPU minimum frequency | 2000 MHz | Prevents drop to 300–600 MHz between requests |
| GPU boost frequency | hardware max (2400 MHz) | Ensures peak throughput during inference |

**Memory (3 tweaks)**
| Tweak | Value | Mechanism |
|-------|-------|-----------|
| vm.swappiness | 10 | Avoids swap under sustained mining load |
| Transparent Huge Pages | always | Reduces TLB pressure for large ML model allocations |
| THP defrag | madvise | Targeted defrag for ML workloads without stalling the system |

**System (3 tweaks)**
| Tweak | Value | Mechanism |
|-------|-------|-----------|
| NMI watchdog | disabled | Reduces interrupt overhead |
| vm.dirty_ratio | 5 | Starts disk flush earlier, reduces writeback stall |
| vm.dirty_background_ratio | 2 | Background IO starts sooner, smoother throughput |

**Intel Compute (1 tweak — Arc only)**
| Tweak | Value | Mechanism |
|-------|-------|-----------|
| SYCL persistent kernel cache | enabled | Caches compiled GPU kernels across sessions |

### 3.2 Benchmark Methodology

Three paired benchmarks run in the same thermal window:

**Network benchmark (`benchmarks/benchmark-network-v0.1.sh`)**
- Applies `tc netem` WAN simulation: 25ms one-way delay + 0.5% packet loss on loopback
- Runs 5 × 10-second iperf3 passes under CUBIC (baseline) then BBR + 16MB buffers (tuned)
- Reports average Mbit/s and delta

**Cold-start latency benchmark (`benchmarks/benchmark-inference-v0.2.sh`)**
- Forces model unload between each call (`keep_alive=0s`) + 15s idle gap
- Measures `load_duration` + `prompt_eval_duration` (TTFT) — the exact window validators time
- 5 calls per pass, baseline then tuned

**Sustained inference benchmark (`benchmarks/benchmark-inference-v0.1.sh`)**
- Model stays warm between calls (steady-state throughput)
- 5 passes per condition, reports average tok/s
- Expected to show minimal delta (GPU-bound workload, CPU tweaks don't help)

All benchmarks are measurement-only — no tweaks are baked in. Presets are applied and reverted by the benchmark scripts as arguments.

---

## 4. Results

### 4.1 Primary Test Rig — AMD Ryzen 7 5700 + Intel Arc A750

| Benchmark | Baseline | Tuned | Delta |
|-----------|---------|-------|-------|
| Network throughput (WAN sim) | 95.6–169.2 Mbit/s | 383–387 Mbit/s | **+127–300%** |
| Cold-start latency | 1022–1024ms | 993–1001ms | **-2.19 to -2.86%** |
| Sustained inference (warm) | 68–76 tok/s | 68–77 tok/s | flat (expected) |
| Idle power draw | ~11W | ~20W | +8–9W |

Network baseline variance is driven by CUBIC instability — the tuned (BBR) value is consistent at 383–387 Mbit/s across all runs. Higher deltas reflect weaker CUBIC baselines, not stronger tuned performance.

Cold-start improvement is entirely attributable to the GPU minimum frequency lock. Without the preset, the Arc A750 idles to ~600 MHz between inference calls. The preset floor of 2000 MHz eliminates the ramp-up cost.

Power cost is real: +8–9W at idle with C-states disabled. For 24/7 mining this is approximately $8–9/year at $0.12/kWh. Network and latency gains justify this in active mining workloads.

### 4.2 Secondary Test Rig — AMD FX-8350 + RX 580 (Stardust)

| Benchmark | Baseline | Tuned | Delta |
|-----------|---------|-------|-------|
| Network throughput (WAN sim) | 127–165 Mbit/s | 379–387 Mbit/s | **+129–203%** |
| Cold-start latency | 2475–2489ms | 2346–2376ms | **-3.99 to -15.83%** |
| Sustained inference (warm) | 19.3–19.5 tok/s | 19.3–19.5 tok/s | flat (CPU-bound) |
| Idle power draw | N/A | N/A | N/A |

Key observations for the FX-8350 rig:
- **No GPU tweaks were applied** — the RX 580 has no Intel Arc sysfs interface. All cold-start improvement came from CPU governor + C-state changes alone.
- Cold-start improvement is proportionally larger (-3.99 to -15.83%) because absolute latency is higher — the FX-8350 is slower at model loading, giving C-state latency more relative impact.
- Inference runs on CPU (ROCm not active for RX 580 / Polaris). Sustained tok/s reflects CPU performance, not GPU.

---

## 5. Mining Impact Model

A Bittensor validator query follows this path:

```
Validator sends request
  → network transit to miner
  → GPU wakes from idle          ← cold-start gap
  → model loads
  → first token generated        ← TTFT (what validator scores)
  → response transits back
Validator scores response
```

**Network throughput** does not directly affect per-request latency for small inference payloads (~1–2KB). Its impact is on:
- Model weight download time when subnets upgrade (3x faster)
- Chain sync speed (stay current with validator state)
- Batched or large-payload requests (direct throughput win)

**Cold-start latency** directly affects validator scoring. Every request that hits an idle GPU pays this cost. Results by hardware:

| Hardware | Cold-start reduction | Per-request savings |
|----------|---------------------|---------------------|
| Arc A750 | -2.19 to -2.86% | ~22–29ms |
| FX-8350 (CPU only) | -3.99 to -15.83% | ~113–142ms |

For a miner receiving 1,000 queries/day, 22ms/request = 22 seconds/day of reduced response time. At scale across many miners, this shifts the active set composition.

The FX-8350 result is strategically important: older hardware that was marginal (2.4–2.5s cold-start) gains meaningful headroom (2.3–2.35s) from CPU-only tweaks, without any GPU changes. TAO-OS does more for miners who need it most.

---

## 6. Hardware Compatibility

TAO-OS is designed to run on any Linux system. Hardware-specific tweaks are gated behind detection:

| Feature | Detection method | Fallback |
|---------|-----------------|---------|
| Intel Arc GPU tweaks | `/sys/class/drm/card*/gt/gt0/rps_min_freq_mhz` | Skip silently |
| AMD CPU boost | `/sys/devices/system/cpu/cpufreq/boost` | Skip silently |
| Energy performance preference | sysfs per-CPU path | Skip silently |
| CPU C-states | `/sys/devices/system/cpu/cpu*/cpuidle/state*/disable` | Skip silently |
| turbostat power reading | command presence check | Report N/A |

Network and memory tweaks (BBR, buffers, THP, swappiness) are universal — they apply on any Linux kernel 5.4+.

Tested configurations as of March 2026:
- AMD Ryzen 7 5700 + Intel Arc A750 (Linux Mint 22.3, kernel 6.17)
- AMD FX-8350 + RX 580 (Ubuntu 24.04, kernel 6.17)

---

## 7. Hardware Database (tao-forge)

Every test run automatically submits structured results to **tao-forge**, a hosted database tracking performance across the fleet. Data submitted per run:

- Machine fingerprint (CPU, GPU, RAM, OS, kernel)
- Preset version and wrapper version
- All benchmark results (baseline, tuned, delta for each metric)
- Timestamp

This database grows with every test run across any machine. Over time it becomes a lookup table: given a CPU and GPU, what gains should a miner expect? This is the foundation for automatic, hardware-specific preset recommendation.

---

## 8. Roadmap

### Phase 1 — Self-Fleet Validation (current)
Run on all hardware Frosty controls. Establish baseline data across diverse hardware. Target: consistent, reproducible gains across 5+ machine configurations.

### Phase 2 — Trusted Fleet (v1.5 milestone)
Expand to 5+ external miners with close supervision. Gate: clean safety record + documented ≥1.5% average mining/inference gain confirmed by external testers.

### Phase 3 — Public Release
Open the repo to the broader Bittensor mining community. The hardware database is the credibility layer — every result is verifiable.

### Phase 4 — Subnet Integration
Design a Bittensor subnet where:
- Miners submit OS optimization proposals
- Validators run benchmarks and score real gains
- TAO emissions reward the best configurations
- The network continuously improves its own infrastructure

---

## 9. Philosophy

The standard Bittensor mining guide assumes NVIDIA GPUs and leaves Linux performance on the table. TAO-OS is built on AMD CPU + Intel Arc — hardware that most guides ignore — and proves that the biggest gains are in the OS, not the GPU.

The self-improving loop is the point. Miners run TAO-OS, earn more TAO because they're faster, fund more optimization work, and the entire network improves. This is infrastructure that gets better by being used.

---

*TAO-OS is open source. Built by Frosty Condor (@frostycondor).*
*Contributions, benchmark results, and hardware reports welcome.*
*https://github.com/connormatthewdouglas/TAO-OS*
