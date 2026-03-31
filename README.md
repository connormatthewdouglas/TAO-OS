# CursiveOS

**Measurement-first Linux optimization for local compute. One command. Measurable results.**

CursiveOS is built for two equal core audiences:
- crypto miners and decentralized compute operators
- local AI/LLM users running Ollama, llama.cpp, and home inference nodes

It works because the bottlenecks are the same at the OS layer: network transport ceilings, scheduler/governor latency, memory pressure, and GPU/CPU power-state behavior. CursiveOS benchmarks your machine, applies reversible presets, benchmarks again, and shows you the measured delta.

```bash
git clone https://github.com/connormatthewdouglas/CursiveOS.git 2>/dev/null; git -C ~/CursiveOS pull --ff-only 2>/dev/null || echo "⚠ Local changes detected — skipping update, running your local version."; chmod +x ~/CursiveOS/cursiveos-full-test-v1.4.sh; cd ~/CursiveOS && bash cursiveos-full-test-v1.4.sh
```

Runs all benchmarks, applies presets, shows you exactly what you gain, and reverts automatically at run end. Works whether you've cloned before or not.

**Data transparency (important):** At the end of a run, CursiveOS uploads benchmark results to **CursiveRoot** (the project’s hardware-performance database). It uploads hardware/performance metadata (CPU/GPU model, OS/kernel, and benchmark deltas) — **not** personal files, documents, browser data, or shell history. We need this data to learn which optimizations work on which hardware and improve recommendations safely over time.

**See live results from all machines:**
```bash
./scripts/cursiveroot-status.sh
```

---

## Results (v0.8-locked presets — validated across 3 machines)

### AMD Ryzen 7 5700 · Intel Arc A750

| Benchmark | Default | CursiveOS Presets | Delta |
|-----------|---------|---------------|-------|
| **Network throughput** (WAN sim: 50ms RTT, 0.5% loss) | 140–181 Mbit/s | **~1000 Mbit/s** | **+454–616%** |
| **Cold-start latency** (GPU idle → first inference token) | 1021–1024ms | 996–997ms | **-22–27ms (-2.3 to -2.6%)** |
| Sustained inference (warm model, steady-state) | 75–76 tok/s | 76–77 tok/s | +1.2–1.5% |
| **Idle power draw** (C-states + governor) | ~6W | ~20W | +~14W |

### AMD FX-8350 · RX 580

| Benchmark | Default | CursiveOS Presets | Delta |
|-----------|---------|---------------|-------|
| **Network throughput** (WAN sim: 50ms RTT, 0.5% loss) | 171 Mbit/s | **1182 Mbit/s** | **+591%** |
| **Cold-start latency** | 2462–2493ms | 2095–2098ms | **-366–395ms (-14.9 to -15.8%)** |
| Sustained inference (warm model, CPU-bound) | 19.5 tok/s | 20.5 tok/s | +4.5–5% |

### Lenovo IdeaPad Gaming 3 · 11th Gen i5 + GTX (Laptop)

| Benchmark | Default | CursiveOS Presets | Delta |
|-----------|---------|---------------|-------|
| **Network throughput** (WAN sim: 50ms RTT, 0.5% loss) | 237.8 Mbit/s | **1429.8 Mbit/s** | **+501.26%** |
| **Cold-start latency** | 889.1ms | 630.8ms | **-29.05%** |
| Sustained inference (warm model, steady-state) | 32.86 tok/s | 33.25 tok/s | +1.19% |
| **Idle power draw** | 3.48W | 4.36W | +0.9W |

**Network is the headline.** Two bugs in default Linux cap your throughput regardless of link speed: a 212KB socket buffer (smaller than the bandwidth-delay product on any real WAN link) and CUBIC congestion control (degrades under packet loss). CursiveOS fixes both — 16MB buffers, BBR, and the v0.7 tcp_rmem/wmem fix that closes the auto-tuner ceiling gap. Result: all validated rigs now show strong WAN uplift.

**Power tradeoff is real.** Disabled C-states keep the CPU in C0 continuously. Measured cost varies by system — expect +8–14W at idle. For 24/7 mining at $0.12/kWh that's ~$8–15/year. The network and latency gains justify it in active mining workloads, but it's worth knowing.

**Cold-start latency matters for mining.** Validators query miners unpredictably. Between queries, your GPU idles to 300–600 MHz. CursiveOS pins the Arc A750 to 2000 MHz minimum — 22–27ms faster on every cold request. On older CPU-only hardware (FX-8350), C-state and governor changes alone cut 366–395ms per cold request. At scale this shifts active set membership.

---

## What it does

CursiveOS applies a set of temporary, safe OS tweaks tuned for Bittensor mining workloads. The full-test script automatically reverts presets at the end of each run. Reboot or `--undo` are optional fallback paths.

**25 tweaks in `presets/cursiveos-presets-v0.7.sh`:**

| Tweak | Value | Why |
|-------|-------|-----|
| CPU governor | performance | Full clock speed, no scaling delays |
| Energy perf preference | performance | AMD/Intel power hint to hardware |
| Net buffers (rmem/wmem_max) | 16MB | Bittensor gossip + chain traffic |
| tcp_rmem / tcp_wmem | 4096 / 262144 / 16MB | Closes auto-tuner ceiling gap — unlocks full pipe |
| TCP congestion control | BBR + fq | Better sustained throughput on WAN |
| TCP slow start after idle | disabled | Throughput doesn't drop after mining pauses |
| net.core.netdev_max_backlog | 5000 | Prevents silent packet drops under P2P load |
| net.core.somaxconn | 4096 | Larger connection queue for validator traffic |
| Scheduler autogroup | disabled | Desktop grouping hurts server workloads |
| kernel.sched_min_granularity_ns | 1ms | Faster wakeup for inference threads |
| vm.swappiness | 10 | Avoid swap under sustained mining load |
| NMI watchdog | disabled | Reduces interrupt overhead |
| Transparent Huge Pages | always | Better for large ML model allocations |
| THP defrag | madvise | Targeted defrag for ML — no system-wide stall |
| vm.compaction_proactiveness | 0 | Stops background THP compaction jitter |
| vm.dirty_ratio | 5 | Start disk flushing earlier, reduce writeback stall |
| vm.dirty_background_ratio | 2 | Background IO starts sooner, smoother throughput |
| kernel.numa_balancing | 0 | Single NUMA node — eliminates spurious page fault overhead |
| AMD CPU turbo boost | enabled | Ensure boost not disabled by power profile |
| CPU C2 idle state | disabled | Eliminates 18μs wakeup latency |
| CPU C3 idle state | disabled | Eliminates 350μs wakeup latency |
| CPU C6 idle state | disabled (by name) | Cross-BIOS robust — eliminates ~1ms wakeup jitter |
| GPU SLPC efficiency hints | ignored | Arc A750 full performance mode |
| GPU min frequency | 2000 MHz | Prevents drop to 300 MHz between requests |
| SYCL persistent cache | enabled | Cache compiled GPU kernels (Arc only) |

Apply manually:
```bash
./presets/cursiveos-presets-v0.7.sh --dry-run      # preview all changes first
./presets/cursiveos-presets-v0.7.sh --apply-temp   # apply
./presets/cursiveos-presets-v0.7.sh --undo         # revert
```

---

## Intel Arc A750 — AI Inference Setup

Getting Arc running AI inference is normally a 6-step process most people never finish. One script:

```bash
./setup-intel-arc.sh
```

Installs Intel compute-runtime (OpenCL 3.0), Level Zero, and configures Ollama's Vulkan backend for Arc. After running, your A750 does inference at ~76 tok/s on TinyLlama.

**Vulkan backend note:** Stable for 1B models. At 3B+, ollama 0.18.1 has a precision bug on Arc — garbled output or crashes. Intel SYCL backend is the fix (in roadmap).

---

## Benchmark Tools

Each benchmark is also runnable standalone:

```bash
./benchmarks/benchmark-network-v0.1.sh ./presets/cursiveos-presets-v0.7.sh        # TCP throughput, WAN sim
./benchmarks/benchmark-inference-v0.2.sh ./presets/cursiveos-presets-v0.7.sh tinyllama  # cold-start latency
./benchmarks/benchmark-inference-v0.1.sh ./presets/cursiveos-presets-v0.7.sh tinyllama  # sustained tok/s
```

---

## Roadmap

- **Done** → Intel Arc inference stack (one-script setup)
- **Done** → Preset stack v0.5 (14 tweaks, fully reversible)
- **Done** → Network benchmark: +127% confirmed (BBR + 16MB buffers)
- **Done** → Cold-start inference benchmark: -22ms confirmed (GPU freq lock)
- **Done** → Full-test wrapper v1.2 (CursiveRoot auto-submit, zero setup)
- **Done** → Preset stack v0.6 (18 tweaks, --dry-run support)
- **Done** → CursiveRoot: live hardware database, auto-submit from any machine
- **Done** → Preset stack v0.7 (25 tweaks: +7 research-backed additions)
- **Done** → v0.7 validated: ~1 Gbit/s network on Arc A750 + RX 580 confirmed
- **Next** → Run v0.7 on remaining fleet (laptops, all-in-one, friends' PCs)
- **Next** → Intel Arc SYCL backend: stable 7B+ inference
- **v1.5** → Trusted external fleet (5+ miners, documented gains, clean safety record)
- **v2.0** → One-click pre-tuned ISO + auto-updates for miners/validators
- **v3.0+** → Full self-improving subnet (AI generates + validates tweaks, emissions for best configs)

---

## Why this hardware

Bittensor can't thrive long-term on a single vendor's silicon. CursiveOS is built and tested on **AMD CPU + Intel Arc GPU** — hardware most mining guides ignore. If you're a non-NVIDIA miner, this project is for you.

---

Built for the TAO network. Star the repo if you're a miner, validator, or believe in decentralizing AI compute.

**Got results?** Run the wrapper and they'll appear automatically in CursiveRoot. Or open an issue on GitHub.

Made by [@connormatthewdouglas](https://github.com/connormatthewdouglas)

---

## 🤖 AI Collaborators

This repo is built by two AIs working alongside the founder:

### 🟡 Claude (Lead Dev)
| File/Dir | Purpose |
|---|---|
| `benchmarks/` | Benchmark scripts |
| `docs/` | White paper, action plan |
| `tao-os-*.sh` | Preset + test scripts |
| `cursiveroot-status.sh` | Forge status reporter |
| `setup-intel-arc.sh` | Hardware setup |

### 🟤 CopperClaw (Async Executor — OpenClaw)
| File/Dir | Purpose |
|---|---|
| `HEARTBEAT.md` | Active task queue |
| `memory/` | CopperClaw daily session logs |
| `dashboard/` | Mission control + spend monitor |
