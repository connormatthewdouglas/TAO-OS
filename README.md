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

**Sustained throughput benchmark** (`benchmark-inference-v0.1.sh`, model already warm):
| Model | Baseline | Tuned | Delta |
|-------|----------|-------|-------|
| TinyLlama 1.1B | 68.75 tok/s | 68.07 tok/s | -0.98% (flat — GPU-bound, CPU presets don't help) |

**Cold-start latency benchmark** (`benchmark-inference-v0.2.sh`, model unloaded between calls):
| Model | Baseline (GPU@600MHz idle) | Tuned (GPU@2000MHz pinned) | Delta |
|-------|---------------------------|---------------------------|-------|
| TinyLlama 1.1B | 1023.6ms | 1001.1ms | **-2.19% (-22ms per request)** |

The cold-start result is what matters for mining: validators query miners unpredictably. Without the GPU min-freq preset, the GPU drops to 600 MHz and has to ramp up on every new request. Pinning it to 2000 MHz eliminates that ramp-up — 22ms faster per cold request, load 14.5ms faster, TTFT 7.8ms faster. At scale this is the difference between making the active set or not.

**Larger model status:** Vulkan backend in ollama 0.18.1 has precision instability at 3B+ scale on Arc A750 — llama3.2:3b produces corrupted output, mistral:7b crashes with NaN assertion failure. Known upstream issue. Path forward: Intel SYCL/OpenVINO backend (in roadmap).

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

#### Network Benchmark Results (`benchmark-network-v0.1.sh`)

Simulated WAN conditions: 50ms RTT + 0.5% packet loss (representative of inter-datacenter links Bittensor miners use).

| Config | Throughput | Delta |
|--------|-----------|-------|
| CUBIC + 212KB buffers (default) | 169.2 Mbit/s | baseline |
| BBR + 16MB buffers (presets) | 384.4 Mbit/s | **+127%** |

The 212KB default socket buffer is the main bottleneck: at 50ms RTT, the bandwidth-delay product is ~2.4MB — far larger than 212KB, so Linux was forced to throttle the send window. The 16MB buffer preset eliminates this. BBR adds stability under packet loss. Together: **2.3x faster chain sync, weight delivery, and Bittensor gossip traffic.**

---

#### Benchmark Tools

**`benchmark-v0.9-paired.sh`** — CPU/network load benchmark.
Runs baseline and tuned passes back-to-back in the same thermal window (ambient temperature drift can't skew results).

```bash
./benchmark-v0.9-paired.sh ./tao-os-presets-v0.5.sh
```

**`benchmark-inference-v0.1.sh`** — Sustained inference throughput (tok/s). Model stays warm, measures steady-state GPU compute. Good for comparing model backends.

```bash
./benchmark-inference-v0.1.sh ./tao-os-presets-v0.5.sh tinyllama
```

**`benchmark-inference-v0.2.sh`** — Cold-start latency benchmark. Forces model unload between calls, 15s GPU idle gap. Measures load_duration + TTFT — what validators actually wait for. This is where the GPU min-freq preset shows its impact.

```bash
./benchmark-inference-v0.2.sh ./tao-os-presets-v0.5.sh tinyllama
```

**`benchmark-network-v0.1.sh`** — TCP throughput benchmark. Uses `tc netem` on loopback to simulate WAN conditions (50ms RTT + 0.5% loss). Compares CUBIC vs BBR + 16MB buffers.

```bash
./benchmark-network-v0.1.sh ./tao-os-presets-v0.5.sh
```

---

### Roadmap

- **Done** → Intel Arc inference stack (OpenCL + Ollama + Vulkan) — one-script setup
- **Done** → Preset stack v0.5 (CPU + network + GPU + memory tuning)
- **Done** → Paired benchmark methodology (thermal-fair, same-session comparison)
- **Done** → Inference benchmark (tok/s, TTFT, GPU confirmation) — TinyLlama confirmed 69 tok/s on GPU
- **Next** → Intel Arc SYCL/OpenVINO backend: stable 7B+ inference (Vulkan has precision bugs at 3B+)
- **Next** → Batched inference benchmark: measure GPU freq lock preset impact between requests
- **Next** → Network benchmark: quantify BBR/buffer tweaks on Bittensor gossip traffic
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
