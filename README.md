# TAO-OS

**AI-optimized Linux for Bittensor miners. One command. Measurable results.**

```bash
git clone https://github.com/connormatthewdouglas/TAO-OS.git
cd TAO-OS
./tao-os-full-test-v1.3.sh
```

Runs all benchmarks, applies presets, shows you exactly what you gain. All changes revert automatically.

**See live results from all machines:**
```bash
./tao-forge-status.sh
```

---

## Results (test rig: AMD Ryzen 7 5700 · Intel Arc A750)

| Benchmark | Default | TAO-OS Presets | Delta |
|-----------|---------|---------------|-------|
| **Network throughput** (WAN sim: 50ms RTT, 0.5% loss) | 169.2 Mbit/s | 384.4 Mbit/s | **+127%** |
| **Cold-start latency** (GPU idle → first inference token) | 1023.6ms | 1001.1ms | **-22ms (-2.19%)** |
| Sustained inference (warm model, steady-state) | 68.75 tok/s | 68.07 tok/s | flat (expected) |
| **Idle power draw** (C-states + governor) | 11.3W | 19.7W | +8.4W |

**Network is the headline.** The 212KB default Linux socket buffer is smaller than the bandwidth-delay product on any real WAN link. TAO-OS raises it to 16MB and switches to BBR congestion control — 2.3x faster chain sync, weight delivery, and Bittensor gossip traffic.

*More hardware results in [RESULTS.md](RESULTS.md). Add yours.*

**Power tradeoff is real.** The preset stack adds ~8.4W at idle (disabled C-states keep CPU in C0 continuously). For 24/7 mining that's ~$8.76/year at $0.12/kWh — worth it given the network and latency gains, but worth knowing.

**Cold-start latency matters for mining.** Validators query miners unpredictably. Between queries, your GPU idles to 300–600 MHz. TAO-OS pins the Arc A750 to 2000 MHz minimum — 22ms faster on every cold request. At scale this is the difference between making the active set or not.

---

## What it does

TAO-OS applies a set of temporary, safe OS tweaks tuned for Bittensor mining workloads. Every change reverts on reboot or with `--undo`.

**25 tweaks in `tao-os-presets-v0.7.sh`:**

| Tweak | Value | Why |
|-------|-------|-----|
| CPU governor | performance | Full clock speed, no scaling delays |
| Energy perf preference | performance | AMD/Intel power hint to hardware |
| Net buffers (rmem/wmem_max) | 16MB | Bittensor gossip + chain traffic |
| TCP congestion control | BBR + fq | Better sustained throughput on WAN |
| TCP slow start after idle | disabled | Throughput doesn't drop after mining pauses |
| Scheduler autogroup | disabled | Desktop grouping hurts server workloads |
| vm.swappiness | 10 | Avoid swap under sustained mining load |
| NMI watchdog | disabled | Reduces interrupt overhead |
| GPU SLPC efficiency hints | ignored | Arc A750 full performance mode |
| GPU min frequency | 2000 MHz | Prevents drop to 300 MHz between requests |
| GPU boost frequency | 2400 MHz | Hardware max |
| CPU C2 idle state | disabled | Eliminates 18μs wakeup latency |
| CPU C3 idle state | disabled | Eliminates 350μs wakeup latency |
| Transparent Huge Pages | always | Better for large ML model allocations |
| AMD CPU turbo boost | enabled | Ensure boost not disabled by power profile |
| THP defrag | madvise | Targeted defrag for ML — no system-wide stall |
| vm.dirty_ratio | 5 | Start disk flushing earlier, reduce writeback stall |
| vm.dirty_background_ratio | 2 | Background IO starts sooner, smoother throughput |
| SYCL persistent cache | enabled | Cache compiled GPU kernels (Arc only) |
| tcp_rmem / tcp_wmem | 4096 / 262144 / 16MB | Closes auto-tuner ceiling gap — rmem_max set but TCP auto-tuner was silently capped lower |
| C6 idle state | disabled (by name) | Cross-BIOS robust: detects C6 by name, not fragile state index. Eliminates ~1ms wakeup jitter |
| kernel.numa_balancing | 0 | Ryzen 5700 is single NUMA node — NUMA balancing is pure overhead |
| vm.compaction_proactiveness | 0 | Stops background THP compaction from causing latency spikes |
| net.core.netdev_max_backlog | 5000 | Prevents silent packet drops under heavy Bittensor P2P / gossip traffic |
| kernel.sched_min_granularity_ns | 1ms | Faster scheduler wakeup for inference threads yielding on GPU wait |
| net.core.somaxconn | 4096 | Larger connection queue for simultaneous validator inbound connections |

Apply manually:
```bash
./tao-os-presets-v0.7.sh --dry-run      # preview all changes first
./tao-os-presets-v0.7.sh --apply-temp   # apply
./tao-os-presets-v0.7.sh --undo         # revert
```

---

## Intel Arc A750 — AI Inference Setup

Getting Arc running AI inference is normally a 6-step process most people never finish. One script:

```bash
./setup-intel-arc.sh
```

Installs Intel compute-runtime (OpenCL 3.0), Level Zero, and configures Ollama's Vulkan backend for Arc. After running, your A750 does inference at ~69 tok/s on TinyLlama.

**Vulkan backend note:** Stable for 1B models. At 3B+, ollama 0.18.1 has a precision bug on Arc — garbled output or crashes. Intel SYCL backend is the fix (in roadmap).

---

## Benchmark Tools

Each benchmark is also runnable standalone:

```bash
./benchmarks/benchmark-network-v0.1.sh ./tao-os-presets-v0.7.sh        # TCP throughput, WAN sim
./benchmarks/benchmark-inference-v0.2.sh ./tao-os-presets-v0.7.sh tinyllama  # cold-start latency
./benchmarks/benchmark-inference-v0.1.sh ./tao-os-presets-v0.7.sh tinyllama  # sustained tok/s
./benchmarks/benchmark-v0.9-paired.sh ./tao-os-presets-v0.7.sh          # CPU sysbench (paired)
```

---

## Roadmap

- **Done** → Intel Arc inference stack (one-script setup)
- **Done** → Preset stack v0.5 (14 tweaks, fully reversible)
- **Done** → Network benchmark: +127% confirmed (BBR + 16MB buffers)
- **Done** → Cold-start inference benchmark: -22ms confirmed (GPU freq lock)
- **Done** → Full-test wrapper v1.1 (auto-appends results to hardware-profiles.json)
- **Done** → Preset stack v0.6 (18 tweaks, --dry-run support)
- **Done** → Hardware database: hardware-profiles.json (grows with every test run)
- **Done** → tao-forge: zero-setup Supabase backend, auto-submit from any internet-connected machine
- **Done** → Preset stack v0.7 (25 tweaks: +7 research-backed additions)
- **Next** → Fleet validation: test on RX 580, laptops, friends' PCs (v0.7)
- **Next** → Intel Arc SYCL backend: stable 7B+ inference (after fleet validation)
- **v1.0** → One-click pre-tuned ISO + auto-updates for miners/validators
- **v2.0+** → Full self-improving subnet (AI generates + validates tweaks, emissions for best configs)

---

## Why this hardware

Bittensor can't thrive long-term on a single vendor's silicon. TAO-OS is built and tested on **AMD CPU + Intel Arc GPU** — hardware most mining guides ignore. If you're a non-NVIDIA miner, this project is for you.

---

Built for the TAO network. Star the repo if you're a miner, validator, or believe in decentralizing AI compute.

**Got results?** Paste your table in [RESULTS.md](RESULTS.md) — open a PR or drop it in an issue.

Made by [@connormatthewdouglas](https://github.com/connormatthewdouglas)
