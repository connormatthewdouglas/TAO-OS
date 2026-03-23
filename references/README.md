# TAO-OS

**AI-optimized Linux for Bittensor miners. One command. Measurable results.**

---

## 🤖 AI Collaborators

This repo is worked on by two AIs. Here's who owns what:

### 🟡 Claude (Lead Dev)
| File/Dir | Purpose |
|---|---|
| `CLAUDE.md` | Claude's orientation + project context |
| `.claude/` | Claude Code settings & permissions |
| `benchmarks/` | Benchmark scripts |
| `docs/` | White paper, action plan |
| `archive/` | Historical data |
| `logs/` | Runtime logs |
| `tao-os-*.sh` | Preset + test scripts |
| `tao-forge-status.sh` | Forge status reporter |
| `setup-intel-arc.sh` | Hardware setup |

### 🟤 CopperClaw (Async Assistant — OpenClaw)
| File/Dir | Purpose |
|---|---|
| `AGENTS.md` | CopperClaw runtime instructions |
| `SOUL.md` | CopperClaw personality, values, identity |
| `USER.md` | Notes about Connor |
| `MEMORY.md` | CopperClaw long-term memory |
| `HEARTBEAT.md` | Periodic task checklist |
| `.openclaw/` | OpenClaw runtime config |
| `memory/copper/` | CopperClaw daily session logs |

### 📦 Shared
| File/Dir | Purpose |
|---|---|
| `README.md` | This file |
| `CHANGELOG.md` | Project changelog |
| `.git/` | Version control |

---

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

## Results (v0.7 presets — validated across 2 machines)

### AMD Ryzen 7 5700 · Intel Arc A750

| Benchmark | Default | TAO-OS Presets | Delta |
|-----------|---------|---------------|-------|
| **Network throughput** (WAN sim: 50ms RTT, 0.5% loss) | 140–181 Mbit/s | **~1000 Mbit/s** | **+454–616%** |
| **Cold-start latency** (GPU idle → first inference token) | 1021–1024ms | 996–997ms | **-22–27ms (-2.3 to -2.6%)** |
| Sustained inference (warm model, steady-state) | 75–76 tok/s | 76–77 tok/s | +1.2–1.5% |
| **Idle power draw** (C-states + governor) | ~6W | ~20W | +~14W |

### AMD FX-8350 · RX 580

| Benchmark | Default | TAO-OS Presets | Delta |
|-----------|---------|---------------|-------|
| **Network throughput** (WAN sim: 50ms RTT, 0.5% loss) | 171 Mbit/s | **1182 Mbit/s** | **+591%** |
| **Cold-start latency** | 2462–2493ms | 2095–2098ms | **-366–395ms (-14.9 to -15.8%)** |
| Sustained inference (warm model, CPU-bound) | 19.5 tok/s | 20.5 tok/s | +4.5–5% |

**Network is the headline.** Two bugs in default Linux cap your throughput regardless of link speed: a 212KB socket buffer (smaller than the bandwidth-delay product on any real WAN link) and CUBIC congestion control (degrades under packet loss). TAO-OS fixes both — 16MB buffers, BBR, and the v0.7 tcp_rmem/wmem fix that closes the auto-tuner ceiling gap. Result: both test rigs now saturate ~1 Gbit/s tuned vs ~380 Mbit/s on v0.6.

**Power tradeoff is real.** Disabled C-states keep the CPU in C0 continuously. Measured cost varies by system — expect +8–14W at idle. For 24/7 mining at $0.12/kWh that's ~$8–15/year. The network and latency gains justify it in active mining workloads, but it's worth knowing.

**Cold-start latency matters for mining.** Validators query miners unpredictably. Between queries, your GPU idles to 300–600 MHz. TAO-OS pins the Arc A750 to 2000 MHz minimum — 22–27ms faster on every cold request. On older CPU-only hardware (FX-8350), C-state and governor changes alone cut 366–395ms per cold request. At scale this shifts active set membership.

---

## What it does

TAO-OS applies a set of temporary, safe OS tweaks tuned for Bittensor mining workloads. Every change reverts on reboot or with `--undo`.

**25 tweaks in `tao-os-presets-v0.7.sh`:**

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

Installs Intel compute-runtime (OpenCL 3.0), Level Zero, and configures Ollama's Vulkan backend for Arc. After running, your A750 does inference at ~76 tok/s on TinyLlama.

**Vulkan backend note:** Stable for 1B models. At 3B+, ollama 0.18.1 has a precision bug on Arc — garbled output or crashes. Intel SYCL backend is the fix (in roadmap).

---

## Benchmark Tools

Each benchmark is also runnable standalone:

```bash
./benchmarks/benchmark-network-v0.1.sh ./tao-os-presets-v0.7.sh        # TCP throughput, WAN sim
./benchmarks/benchmark-inference-v0.2.sh ./tao-os-presets-v0.7.sh tinyllama  # cold-start latency
./benchmarks/benchmark-inference-v0.1.sh ./tao-os-presets-v0.7.sh tinyllama  # sustained tok/s
```

---

## Roadmap

- **Done** → Intel Arc inference stack (one-script setup)
- **Done** → Preset stack v0.5 (14 tweaks, fully reversible)
- **Done** → Network benchmark: +127% confirmed (BBR + 16MB buffers)
- **Done** → Cold-start inference benchmark: -22ms confirmed (GPU freq lock)
- **Done** → Full-test wrapper v1.2 (tao-forge auto-submit, zero setup)
- **Done** → Preset stack v0.6 (18 tweaks, --dry-run support)
- **Done** → tao-forge: live hardware database, auto-submit from any machine
- **Done** → Preset stack v0.7 (25 tweaks: +7 research-backed additions)
- **Done** → v0.7 validated: ~1 Gbit/s network on Arc A750 + RX 580 confirmed
- **Next** → Run v0.7 on remaining fleet (laptops, all-in-one, friends' PCs)
- **Next** → Intel Arc SYCL backend: stable 7B+ inference
- **v1.5** → Trusted external fleet (5+ miners, documented gains, clean safety record)
- **v2.0** → One-click pre-tuned ISO + auto-updates for miners/validators
- **v3.0+** → Full self-improving subnet (AI generates + validates tweaks, emissions for best configs)

---

## Why this hardware

Bittensor can't thrive long-term on a single vendor's silicon. TAO-OS is built and tested on **AMD CPU + Intel Arc GPU** — hardware most mining guides ignore. If you're a non-NVIDIA miner, this project is for you.

---

Built for the TAO network. Star the repo if you're a miner, validator, or believe in decentralizing AI compute.

**Got results?** Run the wrapper and they'll appear automatically in tao-forge. Or open an issue on GitHub.

Made by [@connormatthewdouglas](https://github.com/connormatthewdouglas)
