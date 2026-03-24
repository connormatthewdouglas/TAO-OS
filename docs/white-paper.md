# ForgeOS: AI-Guided Linux Optimization for Local Compute
### Technical White Paper — v0.4 (March 2026)

---

## Abstract

ForgeOS is an open-source Linux optimization stack that delivers measurable, hardware-verified performance improvements for any local compute workload — local AI inference, crypto mining, or any P2P-networked process — through temporary, fully-reversible OS-level tuning. In validated testing across two distinct hardware configurations, ForgeOS delivered **+454–616% network throughput** and **-2.3–15.8% cold-start latency** improvement with zero permanent system changes.

The long-term vision is larger: ForgeOS is the seed of a self-improving OS flywheel. Every benchmark run contributes structured hardware performance data to **tao-forge** — a growing database of hardware profiles, applied tweaks, and measured outcomes. Over time, this dataset enables AI to generate optimized configurations for any hardware automatically, closing the loop between measurement, optimization, and reward.

The incentive layer — a decentralized "contribute data, earn rewards" mechanism — is the flywheel's fuel. The optimizations are available to everyone today, for free. The network effect of the database is the moat.

**This is fundamentally a data problem.** The benchmark tool is the data collection mechanism. The database is the asset. The AI optimization loop is the product. The token is the incentive — deployed after the database has proven its value, not before.

---

## 1. The Problem

### 1.1 Linux ships broken for local compute

Anyone running a demanding local compute workload on Linux — whether that's Ollama, llama.cpp, an inference cluster, or a crypto miner — starts with the same two invisible performance bottlenecks baked into every default distribution.

**Network throughput**

Linux defaults to a 212KB socket buffer, appropriate for 1990s modem speeds. The bandwidth-delay product (BDP) on a modern WAN link with 50ms RTT at 400 Mbit/s is approximately 2.4MB. When the buffer is smaller than the BDP, TCP cannot fill the pipe — chain sync, model weight delivery, API traffic, and P2P gossip all run at a fraction of available bandwidth regardless of link speed.

Linux also defaults to CUBIC congestion control, which degrades aggressively under packet loss. Both public internet inference APIs and P2P mining networks operate in environments where 0.5–1% loss is normal.

**Cold-start latency**

Between inference requests or mining jobs, a GPU idles to its minimum frequency — as low as 300–600 MHz on Intel Arc hardware. When a request arrives, the GPU must ramp back to operating frequency before work can begin, adding measurable latency to every cold call. On Intel Arc A750 hardware this penalty is ~22ms per request. On older CPU-only hardware (AMD FX-8350), C-state and governor latency dominate — adding 366–395ms per cold request.

These losses are invisible in standard benchmarks and untreated in default Linux configurations across every relevant community. ForgeOS fixes both bottlenecks, on any hardware, in one command. A local Ollama user, an llama.cpp cluster operator, and a Bittensor validator are solving the exact same OS-level problem.

### 1.2 The data gap

No centralized database captures real-world Linux performance across diverse compute hardware. Users must independently research optimizations with no visibility into what actually works on hardware like theirs. Tools like WhatToMine track hashrate; inference benchmarks track model speed — but the OS layer is invisible to all of them.

The result: every operator individually rediscovers the same optimizations (or doesn't), applies them inconsistently, and has no mechanism to contribute findings to a shared dataset. The knowledge exists scattered across forum posts and GitHub gists. It has never been systematically collected, benchmarked, and made queryable.

---

## 2. The ForgeOS Approach

### 2.1 Design principles

- **Temporary by default.** Every change reverts on reboot or with `--undo`. No permanent modifications.
- **Benchmarked before shipping.** No tweak enters the preset stack without a paired before/after measurement across at least two hardware configurations.
- **Hardware-aware.** The preset script detects available hardware features and skips inapplicable tweaks gracefully.
- **Single command.** `./forgeos-full-test-v1.4.sh` runs all benchmarks, applies presets, measures the delta, and submits hardware-verified results to tao-forge automatically.
- **Workload-agnostic.** The Linux bottlenecks ForgeOS fixes are universal — identical for local inference (Ollama, llama.cpp, vLLM) and any P2P-networked compute workload on Linux.

### 2.2 The Virtuous Cycle

ForgeOS is designed around a closed self-reinforcing loop:

```
DATA IN
Operators run benchmarks → structured performance data submitted to tao-forge
        ↓
DATA CONVERTED TO OPTIMIZATION  
AI + contributors analyze the dataset → generate hardware-specific optimizations
        ↓
OPTIMIZATION VALIDATED & REWARDED
Validated optimizations earn rewards via the incentive layer
        ↓
MORE DATA IN
Rewarded operators run more benchmarks → dataset grows → AI improves
        ↑__________________________________________________↑
```

The benchmark tool provides immediate zero-day value (faster machines today). The database grows with every run. The AI optimization loop compounds as the dataset expands. The incentive layer ensures contributions keep coming.

**Every component has standalone value.** The scripts work without the database. The database has value without the token. The token makes the database grow faster. Together they compound.

### 2.3 The Data Moat

tao-forge captures what no existing tool does: structured records of **hardware fingerprint → tweak applied → before/after measured delta → system stability**. As of v1.4, every submission includes:

| Field | Purpose |
|-------|---------|
| `hardware_fingerprint_hash` | SHA256 of CPU microcode + GPU VBIOS + kernel — hardware-bound, tamper-evident |
| `cpu`, `gpu`, `ram_gb`, `kernel`, `distro` | Machine profile |
| `network_baseline_mbit` / `network_tuned_mbit` / `network_delta_pct` | Network benchmark results |
| `coldstart_baseline_ms` / `coldstart_tuned_ms` / `coldstart_delta_pct` | Cold-start latency results |
| `sustained_baseline_toks` / `sustained_tuned_toks` / `sustained_delta_pct` | Inference throughput |
| `power_idle_baseline_w` / `power_idle_tuned_w` | Power consumption delta |
| `thermal_headroom_c` | CPU thermal headroom at time of test |
| `stability_flag` | System stability 60s post-tweak (dmesg error check) |
| `submission_timestamp` | ISO 8601 UTC |

This schema is designed for AI consumption from day one — every field an optimization model needs to learn which tweaks work on which hardware under which conditions. The database is being built before any incentive layer exists, which means its value is demonstrated on merit alone.

---

## 3. Technical Implementation

### 3.1 Preset Stack (v0.7 — 25 tweaks)

**Network (6 tweaks)**
| Tweak | Value | Mechanism |
|-------|-------|-----------|
| Socket buffers (rmem/wmem_max) | 16MB | Allows TCP to fill the BDP on WAN links |
| tcp_rmem / tcp_wmem | 4096 / 262144 / 16MB | Closes auto-tuner ceiling gap — the critical v0.7 breakthrough |
| TCP congestion control | BBR + fq | Better throughput under packet loss vs CUBIC |
| TCP slow start after idle | disabled | Prevents throughput reset after compute pauses |
| net.core.netdev_max_backlog | 5000 | Prevents silent packet drops under P2P load |
| net.core.somaxconn | 4096 | Larger connection queue for simultaneous connections |

**CPU (7 tweaks)**
| Tweak | Value | Mechanism |
|-------|-------|-----------|
| CPU governor | performance | Full clock speed, eliminates scaling delays |
| Energy performance preference | performance | Hardware power hint to CPU firmware |
| AMD CPU boost | enabled | Ensures turbo boost not disabled by power profiles |
| CPU C2 idle state | disabled | Eliminates 18μs wakeup latency spike |
| CPU C3 idle state | disabled | Eliminates 350μs wakeup latency spike |
| CPU C6 idle state | disabled (by name) | Cross-BIOS robust; eliminates ~1ms wakeup jitter |
| kernel.numa_balancing | 0 | Single NUMA node — NUMA balancing is pure overhead |

**GPU — Intel Arc only (3 tweaks)**
| Tweak | Value | Mechanism |
|-------|-------|-----------|
| SLPC efficiency hints | ignored | Forces Arc into full performance mode |
| GPU minimum frequency | 2000 MHz | Prevents drop to 300–600 MHz between requests |
| GPU boost frequency | hardware max | Ensures peak throughput during inference |

**Memory (5 tweaks)**
| Tweak | Value | Mechanism |
|-------|-------|-----------|
| vm.swappiness | 10 | Avoids swap under sustained compute load |
| Transparent Huge Pages | always | Reduces TLB pressure for large ML model allocations |
| THP defrag | madvise | Targeted defrag for ML workloads |
| vm.compaction_proactiveness | 0 | Stops background THP compaction latency spikes |
| NMI watchdog | disabled | Reduces interrupt overhead |

**System (3 tweaks)**
| Tweak | Value | Mechanism |
|-------|-------|-----------|
| vm.dirty_ratio | 5 | Starts disk flush earlier, reduces writeback stall |
| vm.dirty_background_ratio | 2 | Background IO starts sooner |
| kernel.sched_min_granularity_ns | 1ms | Faster wakeup for inference threads |

**Intel Compute (1 tweak — Arc only)**
| Tweak | Value | Mechanism |
|-------|-------|-----------|
| SYCL persistent kernel cache | enabled | Caches compiled GPU kernels across sessions |

### 3.2 Benchmark Methodology

Three paired benchmarks run in the same thermal window via `forgeos-full-test-v1.4.sh`:

**Network benchmark** — `tc netem` WAN simulation (25ms one-way + 0.5% loss), 5 × 10s iperf3 passes, CUBIC baseline vs BBR + 16MB buffers tuned.

**Cold-start latency benchmark** — forces model unload between calls (`keep_alive=0s` + 15s idle), measures `load_duration + prompt_eval_duration` (TTFT). 5 calls per pass.

**Sustained inference benchmark** — model stays warm, 5 passes, steady-state tok/s. Expected minimal delta (GPU-bound).

All benchmarks are measurement-only. Presets applied and reverted by the benchmark scripts as arguments.

---

## 4. Results

### 4.1 Primary Rig — AMD Ryzen 7 5700 + Intel Arc A750 (Linux Mint 22.3, kernel 6.17)

**v0.7 presets (25 tweaks) — 2 validated runs:**

| Benchmark | Baseline | Tuned | Delta |
|-----------|---------|-------|-------|
| Network throughput (WAN sim) | 139.6–181.2 Mbit/s | **999.8–1003.6 Mbit/s** | **+454–616%** |
| Cold-start latency | 1020.6–1023.5ms | 996.5–996.7ms | **-2.34 to -2.63%** |
| Sustained inference | 75–76 tok/s | 76–77 tok/s | **+1.22–1.46%** |
| Idle power draw | ~6W | ~20W | +~14W |

The network breakthrough is the `tcp_rmem/wmem` fix. Setting `rmem_max=16MB` raises the kernel's ceiling but the TCP auto-tuner's own ceiling remained at default — silently capping actual buffer allocation. v0.7 explicitly sets `tcp_rmem` and `tcp_wmem`, closing this gap. Both rigs now saturate ~1 Gbit/s tuned vs ~385 Mbit/s on v0.6.

### 4.2 Secondary Rig — AMD FX-8350 + RX 580 (Ubuntu 24.04, kernel 6.17)

**v0.7 presets — 1 confirmed run:**

| Benchmark | Baseline | Tuned | Delta |
|-----------|---------|-------|-------|
| Network throughput (WAN sim) | 171 Mbit/s | **1181.9 Mbit/s** | **+591%** |
| Cold-start latency | 2461.6ms | 2095.5ms | **-14.87%** |
| Sustained inference | 19.59 tok/s | 20.47 tok/s | **+4.49%** |

No GPU tweaks were applied — RX 580 has no Intel Arc sysfs interface. All cold-start improvement came from CPU governor + C-state changes alone. The -14.87% result is strategically important: the tool delivers its largest gains where they matter most — older, slower hardware that was marginal becomes meaningfully more competitive.

### 4.3 Why the network result matters universally

The `tcp_rmem/wmem` fix applies to any Linux system on any networked compute workload:
- **Local AI (Ollama/llama.cpp):** API traffic, model weight delivery, remote client connections
- **Inference clusters:** inter-node communication, load balancer throughput
- **Bittensor/Kaspa/Monero:** chain sync, validator gossip, P2P transaction propagation
- **Any networked process:** pool connections, share submission, distributed coordination

**The underlying Linux bottleneck is not workload-specific.** It affects any Linux machine on a WAN link. ForgeOS is the first tool to benchmark and package this fix for the local compute community at large.

---

## 5. Roadmap

### Phase 1 — Self-Fleet Validation (current)
Validate v0.7 across all hardware in the Frosty fleet. Complete tao-forge schema v1.4 (hardware-bound submissions, stability flags, thermal data). Target: consistent, reproducible gains across 5+ distinct hardware configurations.

### Phase 2 — Trusted Fleet (v1.5 milestone)
Expand to 5+ external operators with close supervision. Gate conditions:
- Clean safety record (no bricked systems)
- Documented ≥1.5% average gain confirmed by external testers
- tao-forge receiving auto-submissions from machines outside the core fleet

**At the v1.5 gate:** rebrand to a workload-agnostic identity reflecting the broader vision. The current public identity is appropriate for Phase 1–2; the rebrand aligns with the expanded local AI + compute positioning.

### Phase 3 — Public Release & Broader Compute
Open to the broader community — local AI operators, inference clusters, crypto miners. Expand tao-forge to track results across diverse hardware and workloads. The hardware database becomes the canonical reference for "what does ForgeOS deliver on my hardware?"

### Phase 4 — Incentive Layer
Deploy a contribution-reward system for the tao-forge database. The precise token mechanics are intentionally deferred: the database must demonstrate its value on merit before economic incentives are introduced. What can be committed now is the architecture — the v1.4 hardware-fingerprint schema (SHA256 of CPU microcode + GPU VBIOS + kernel) cryptographically ties submissions to specific hardware, making the verification layer tamper-evident before any reward is attached. When incentives launch, the anti-gaming infrastructure is already in place and the dataset already has real value.

**Sequencing is the strategy.** Proven database first. Incentives second.

### Phase 5 — AI Optimization Loop
With sufficient tao-forge data (target: 500+ hardware profiles), train or fine-tune models to generate hardware-specific preset recommendations automatically. Given your CPU/GPU/kernel profile, the system recommends which tweaks to apply and predicts expected gains — without running the full benchmark suite.

### Phase 6 — Full Distribution
ForgeOS as a bootable ISO with pre-applied optimizations, a custom kernel, and dedicated package repositories. The same kernel/scheduler/driver optimizations that benefit inference clusters and miners also benefit gaming rigs — the addressable market expands naturally. Goal: the default Linux for anyone who wants hardware running at its actual ceiling.

---

## 6. Strategic Context

### 6.1 Why local AI is the primary frame

The standard Linux tuning conversation happens in crypto mining communities. ForgeOS was built and validated there — but the bottlenecks it fixes are structural to the OS, not specific to any workload. Anyone running Ollama locally, deploying llama.cpp in a small cluster, or operating a self-hosted inference endpoint hits the exact same TCP buffer ceiling and GPU frequency floor.

Local AI is structurally growing; crypto mining is cyclical. Positioning ForgeOS as a hardware optimizer for local compute addresses a larger, faster-growing market without abandoning the mining community that validated the core results.

### 6.2 The data moat vs script defensibility

The optimization scripts bundle well-understood Linux tuning knowledge. Sophisticated operators already apply some of these tweaks individually. The scripts are not the moat.

**The database is the moat.** A structured, hardware-verified, AI-ready dataset of OS performance deltas across diverse compute hardware does not exist anywhere. Building it now — before any token incentive creates gaming pressure — means tao-forge accumulates genuine value with an established, trustworthy methodology. By the time incentives launch, the dataset is already defensible. A competitor starting later faces a database gap, not just a code gap.

### 6.3 Hardware-bound verification

Any contribution-reward system must solve the anti-gaming problem before rewards are attached. The v1.4 schema addresses this proactively: every submission includes a hardware fingerprint hash (SHA256 of CPU microcode + GPU VBIOS + kernel version) that cryptographically ties results to specific hardware. Fake submissions from a different machine produce a different hash. Combined with statistical outlier detection and open-source scoring, this makes the database trustworthy at scale — whether or not a token ever exists.

---

## 7. Philosophy

An operating system that gets better the more it is used. Local AI operators run ForgeOS and their inference gets faster. Miners run it and their rigs improve. Contributors discover better tweaks and share them. The network validates the best work. AI synthesizes the dataset into optimizations no individual would find alone.

The bottlenecks Linux ships with today are invisible taxes on everyone doing serious local compute. ForgeOS makes them visible, measures them, and removes them. The benchmark tool is just the beginning.

---

*ForgeOS is open source. Built by Frosty Condor (@frostycondor).*
*Contributions, benchmark results, and hardware reports welcome.*
*https://github.com/connormatthewdouglas/TAO-OS*
