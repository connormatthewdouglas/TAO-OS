# TAO-OS

**AI-optimized, self-improving Linux for Bittensor miners, validators and beyond.**

The operating system built to close the loop:
Make miners faster → earn more TAO → improve the OS → repeat forever.

---

### Why TAO-OS exists

Every Bittensor subnet (especially SN64 Chutes — the "Linux of AI") runs on plain Ubuntu with no tuning.
We're fixing that. TAO-OS benchmarks, applies, and validates safe OS-level tweaks so your rig runs faster, cooler, and more profitably 24/7 — then packages everything into a one-click image.

**The hardware angle matters.** Bittensor can't thrive long-term on a single vendor's silicon. TAO-OS is built and tested on **AMD CPU + Intel Arc GPU** — hardware that most mining guides ignore. If you're a non-NVIDIA miner, this project is for you.

---

### Current State — What's Working Today

**Test rig:** AMD Ryzen 7 5700 · Intel Arc A750 · 15GB RAM · Linux Mint 22.3 · kernel 6.17

#### Intel Arc A750 — AI Inference Unlocked

Getting Arc running AI inference on Ubuntu is a 6-step process most people never complete. TAO-OS automates it:

```bash
./setup-intel-arc.sh
```

What it does: installs Intel compute-runtime (OpenCL 3.0), Level Zero, and Ollama with Vulkan backend configured for Arc. After running, your Arc A750 is doing inference.

**First benchmark result:**
| Model | Hardware | Tokens/sec |
|-------|----------|-----------|
| TinyLlama 1.1B | Intel Arc A750 (Vulkan) | ~69 tok/s |

More models and larger benchmarks in progress.

#### Performance Preset Stack (`tao-os-presets-v0.5.sh`)

A single script that applies a validated set of temporary OS tweaks tuned for Bittensor mining. All changes revert on reboot or with `--undo`.

```bash
./tao-os-presets-v0.5.sh --apply-temp   # apply
./tao-os-presets-v0.5.sh --undo         # revert
```

**What v0.5 applies:**
| Tweak | Value | Why |
|-------|-------|-----|
| CPU governor | performance | Full clock speed, no scaling delays |
| Energy perf preference | performance | AMD/Intel power hint to hardware |
| Net buffers (rmem/wmem_max) | 16MB | Bittensor gossip + chain traffic |
| TCP congestion control | BBR + fq | Better sustained network throughput |
| TCP slow start after idle | disabled | Stable throughput during mining pauses |
| Scheduler autogroup | disabled | Desktop grouping hurts server workloads |
| vm.swappiness | 10 | Avoid swap under sustained mining load |
| NMI watchdog | disabled | Reduces interrupt overhead |
| GPU SLPC efficiency hints | ignored | Arc A750 full performance mode |
| GPU min frequency | 2000 MHz | Prevents drop to 300 MHz between requests |
| GPU boost frequency | 2400 MHz | Hardware max |
| CPU C2 idle state | disabled | Eliminates 18μs wakeup latency |
| CPU C3 idle state | disabled | Eliminates 350μs wakeup latency |
| Transparent Huge Pages | always | Better for large ML model allocations |

#### Benchmark Tools

**`benchmark-v0.9-paired.sh`** — CPU/network load benchmark.
Runs baseline and tuned passes back-to-back in the same thermal window (ambient temperature drift can't skew results).

```bash
./benchmark-v0.9-paired.sh ./tao-os-presets-v0.5.sh
```

**`benchmark-inference-v0.1.sh`** — AI inference benchmark.
Uses the Ollama REST API for exact token counts and nanosecond timing. Paired test: auto-applies presets between passes.

```bash
./benchmark-inference-v0.1.sh ./tao-os-presets-v0.5.sh tinyllama
./benchmark-inference-v0.1.sh ./tao-os-presets-v0.5.sh mistral
```

---

### Roadmap

- **Done** → Intel Arc inference stack (OpenCL + Ollama + Vulkan) — one-script setup
- **Done** → Preset stack v0.5 (CPU + network + GPU + memory tuning)
- **Done** → Paired benchmark methodology (thermal-fair, same-session comparison)
- **Done** → Inference benchmark (tok/s, TTFT, GPU confirmation)
- **Next** → Larger model benchmarks (7B+), quantify preset impact on real inference workloads
- **Next** → Intel Arc OpenVINO / SYCL path for additional inference backends
- **v1.0** → One-click pre-tuned ISO + auto-updates for miners/validators
- **v2.0+** → Full self-improving subnet (AI generates + validates tweaks, emissions for best configs)

---

### Quick Start

```bash
git clone https://github.com/connormatthewdouglas/TAO-OS.git
cd TAO-OS

# 1. Set up Intel Arc for AI inference (first time only)
./setup-intel-arc.sh

# 2. Apply mining performance presets
./tao-os-presets-v0.5.sh --apply-temp

# 3. Benchmark
./benchmark-inference-v0.1.sh ./tao-os-presets-v0.5.sh tinyllama
```

---

Built with love for the TAO network.
Star the repo if you're a miner, validator, or believe in decentralizing AI compute beyond one vendor.
Contributions, hardware test results, and feedback welcome.

Made by [@connormatthewdouglas](https://github.com/connormatthewdouglas)
