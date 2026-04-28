# CursiveOS

**A new species that inherited its founding genome from Linux and now evolves independently under its own selection pressure.**

Measurement-first Linux optimization for local compute. One command. Measurable results. A Bitcoin-native economic layer with no token tricks, no pool, and no governance theater.

CursiveOS is built for two core audiences:

- Crypto miners and decentralized compute operators
- Local AI/LLM users running Ollama, llama.cpp, and home inference nodes

The OS-layer bottlenecks are the same for both: network transport ceilings, scheduler and governor latency, memory pressure, and GPU/CPU power-state behavior. CursiveOS benchmarks your machine, applies reversible presets, benchmarks again, and shows you the measured delta.

CursiveOS is building toward a v1.0 release that ships with a **natural-language shell as the default terminal**. The interface humans have used to operate Linux for fifty years becomes a conversation with a local agent. You describe outcomes; the agent finds the mechanism. Full roadmap: [ROADMAP.md](ROADMAP.md).

## Try it now

```
git clone https://github.com/connormatthewdouglas/CursiveOS.git 2>/dev/null; git -C ~/CursiveOS pull --ff-only 2>/dev/null || echo "⚠ Local changes detected — skipping update, running your local version."; chmod +x ~/CursiveOS/cursiveos-full-test-v1.4.sh; cd ~/CursiveOS && bash cursiveos-full-test-v1.4.sh
```

Runs all benchmarks, applies presets, shows you exactly what you gain, and reverts automatically at run end. Works whether you've cloned before or not.

**Data transparency:** At the end of a run, CursiveOS uploads benchmark results to **CursiveRoot** (the project's sensor array and hardware-performance database). It uploads hardware and performance metadata (CPU/GPU model, OS/kernel version, benchmark deltas) — **not** personal files, documents, browser data, or shell history. The organism needs this data to learn which optimizations work on which hardware and to improve recommendations safely over time.

**See live results from all machines:**

```
./scripts/cursiveroot-status.sh
```

## Seed organism Linux test

This is the one-command Phase 0 organism path for a real Linux test machine. It clones or updates CursiveOS, runs the full benchmark/preset loop, writes a local seed-organism audit bundle, closes a simulated revenue cycle, uploads seed artifacts to CursiveRoot, and leaves local backups under `~/CursiveOS/.cursiveos/seed/`.

The simulated revenue cycle does not pay real money. It is an accounting rehearsal: if a variant is accepted, the `contributor_id` attached to that accepted variant receives hypothetical sats in the payout report. Benchmark testers are not paid simply for running a test unless they are also the contributor for an accepted variant.

```bash
command -v curl >/dev/null 2>&1 || command -v wget >/dev/null 2>&1 || { sudo apt-get update && sudo apt-get install -y curl; }; (curl -fsSL https://raw.githubusercontent.com/connormatthewdouglas/CursiveOS/main/seed-organism-linux-test.sh || wget -qO- https://raw.githubusercontent.com/connormatthewdouglas/CursiveOS/main/seed-organism-linux-test.sh) | bash
```

---

## Results (v0.8-locked presets — validated across 3 machines)

### AMD Ryzen 7 5700 + Intel Arc A750

| Benchmark | Default | CursiveOS Presets | Delta |
| --- | --- | --- | --- |
| **Network throughput** (WAN sim: 50ms RTT, 0.5% loss) | 140–181 Mbit/s | **~1000 Mbit/s** | **+454–616%** |
| **Cold-start latency** (GPU idle → first inference token) | 1021–1024ms | 996–997ms | **-22–27ms (-2.3 to -2.6%)** |
| Sustained inference (warm model, steady-state) | 75–76 tok/s | 76–77 tok/s | +1.2–1.5% |
| **Idle power draw** (C-states + governor) | ~6W | ~20W | +~14W |

### AMD FX-8350 + RX 580

| Benchmark | Default | CursiveOS Presets | Delta |
| --- | --- | --- | --- |
| **Network throughput** (WAN sim: 50ms RTT, 0.5% loss) | 171 Mbit/s | **1182 Mbit/s** | **+591%** |
| **Cold-start latency** | 2462–2493ms | 2095–2098ms | **-366–395ms (-14.9 to -15.8%)** |
| Sustained inference (warm model, CPU-bound) | 19.5 tok/s | 20.5 tok/s | +4.5–5% |

### Lenovo IdeaPad Gaming 3 (11th Gen i5 + GTX laptop)

| Benchmark | Default | CursiveOS Presets | Delta |
| --- | --- | --- | --- |
| **Network throughput** (WAN sim: 50ms RTT, 0.5% loss) | 237.8 Mbit/s | **1429.8 Mbit/s** | **+501%** |
| **Cold-start latency** | 889.1ms | 630.8ms | **-29%** |
| Sustained inference (warm model, steady-state) | 32.86 tok/s | 33.25 tok/s | +1.2%|
| **Idle power draw** | 3.48W | 4.36W | +0.9W |

**Network is the headline.** Two bugs in default Linux cap your throughput regardless of link speed: a 212KB socket buffer (smaller than the bandwidth-delay product on any real WAN link) and CUBIC congestion control (degrades under packet loss). CursiveOS fixes both — 16MB buffers, BBR, and the v0.7 tcp_rmem/wmem fix that closes the auto-tuner ceiling gap. Result: all validated rigs show strong WAN uplift.

**Power tradeoff is real.** Disabled C-states keep the CPU in C0 continuously. Measured cost varies by system — expect +8–14W at idle. For 24/7 mining at $0.12/kWh that's ~$8–15/year. The network and latency gains justify it in active workloads, but it's worth knowing.

**Cold-start latency matters for mining and inference.** Testers query miners unpredictably. Between queries, your GPU idles to 300–600 MHz. CursiveOS pins the Arc A750 to 2000 MHz minimum — 22–27ms faster on every cold request. On older CPU-only hardware, C-state and governor changes alone cut 366–395ms per cold request. At scale this shifts active set membership.

---

## What it does

CursiveOS applies a set of temporary, safe OS tweaks tuned for local compute workloads. The full-test script automatically reverts presets at the end of each run. Reboot or `--undo` are optional fallback paths.

**28 tweaks in `presets/cursiveos-presets-v0.7.sh`:**

| Tweak | Value | Why |
| --- | --- | --- |
| CPU governor | performance | Full clock speed, no scaling delays |
| Energy perf preference | performance | AMD/Intel power hint to hardware |
| Net buffers (rmem/wmem_max) | 16MB | Closes BDP gap on modern WAN links |
| tcp_rmem / tcp_wmem | 4096 / 262144 / 16MB | Closes auto-tuner ceiling gap |
| TCP congestion control | BBR + fq | Better sustained throughput on WAN |
| TCP slow start after idle | disabled | Throughput doesn't drop after pauses |
| net.core.netdev_max_backlog | 5000 | Prevents silent packet drops under P2P load |
| net.core.somaxconn | 4096 | Larger connection queue |
| Scheduler autogroup | disabled | Desktop grouping hurts server workloads |
| kernel.sched_min_granularity_ns | 1ms | Faster wakeup for inference threads |
| vm.swappiness | 10 | Avoid swap under sustained load |
| NMI watchdog | disabled | Reduces interrupt overhead |
| Transparent Huge Pages | always | Better for large ML model allocations |
| THP defrag | madvise | Targeted defrag for ML — no system-wide stall |
| vm.compaction_proactiveness | 0 | Stops background THP compaction jitter |
| vm.dirty_ratio | 5 | Start disk flushing earlier |
| vm.dirty_background_ratio | 2 | Background IO starts sooner |
| kernel.numa_balancing | 0 | Eliminates spurious page fault overhead |
| AMD CPU turbo boost | enabled | Ensure boost not disabled by power profile |
| CPU C2 idle state | disabled | Eliminates 18μs wakeup latency |
| CPU C3 idle state | disabled | Eliminates 350μs wakeup latency |
| CPU C6 idle state | disabled (by name) | Cross-BIOS robust — eliminates ~1ms wakeup jitter |
| GPU SLPC efficiency hints | ignored | Arc A750 full performance mode |
| GPU min frequency | 2000 MHz | Prevents drop to 300 MHz between requests |
| SYCL persistent cache | enabled | Cache compiled GPU kernels (Arc only) |

Apply manually:

```
./presets/cursiveos-presets-v0.7.sh --dry-run      # preview all changes first
./presets/cursiveos-presets-v0.7.sh --apply-temp   # apply
./presets/cursiveos-presets-v0.7.sh --undo         # revert
```

---

## Intel Arc A750 — AI Inference Setup

Getting Arc running AI inference is normally a 6-step process most people never finish. One script:

```
./setup-intel-arc.sh
```

Installs Intel compute-runtime (OpenCL 3.0), Level Zero, and configures Ollama's Vulkan backend for Arc. After running, your A750 does inference at ~76 tok/s on TinyLlama.

---

## Layer 5 — Economics (v3.3)

The incentive layer is Bitcoin-native and has no token, no pool, and no governance. See [`white-paper.md`](white-paper.md) and [`docs/specs/layer5-economics-v3.3.md`](docs/specs/layer5-economics-v3.3.md) for the full specification.

**How it works:**

- **Fast tier users** pay `$2.00/month` per machine (settled in BTC at payment time). Stable tier is free.
- **All cycle revenue** is distributed directly to contributors each cycle, split between two streams:
  - **Current-cycle stream** pays contributors whose variants were merged this cycle, weighted by measured fitness improvement.
  - **Lifetime stream** pays all contributors who have ever had work merged, weighted by cumulative lifetime fitness. Every cycle. Forever.
- **The split between streams is dynamic**, controlled by a **metabolic sensor** that measures the organism's current need for recruitment vs. retention. Genesis state is 20/80 lifetime-favored; the sensor moves it toward equilibrium as the organism matures.
- **Testers** run benchmarks on their hardware and report measurement data to the sensor array. In exchange they receive free Fast tier access. Testers do not earn lifetime fitness and do not receive revenue share — their compensation is the product itself. This is deliberate; it prevents spoofing attacks from being profitable.
- **No governance, no voting, no judgment.** Fitness is determined by sensor measurement. The sensor array replaces governance entirely.
- **Two-year claim window.** Accruals must be claimed within two years or redistribute to active claimants. Lifetime fitness itself is permanent.
- **Forks inherit obligations.** The lifetime ledger is Bitcoin-anchored; forks that use the genome owe the same payments to the same contributors.

**Current status:** v3.3 economics specified. Hub respec in progress. Phase 0 seed organism loop (single machine, fake BTC, three cycles) scheduled next.

---

## Roadmap

- **Done** → Intel Arc inference stack (one-script setup)
- **Done** → Preset stack v0.8-locked (28 tweaks, fully reversible)
- **Done** → Network: ~1 Gbit/s validated across 3 rigs (+454–616%)
- **Done** → Cold-start latency: -2.3% to -29% validated across 3 rigs
- **Done** → Full-test wrapper v1.4 (CursiveRoot auto-submit, zero setup)
- **Done** → CursiveRoot: live hardware/performance database
- **Done** → v3.3 economic architecture specified (white paper v2.3)
- **Done** → Agent architecture specified (measurement daemon + natural-language shell)
- **In progress** → Hub rebuild to v3.3 (new design system, seven-tab frontend, Supabase backend)
- **In progress** → Phase 0 seed organism (measurement-to-ledger loop on founder's rig)
- **Next** → First external tester running full sensor array; validate population confirmation
- **Next** → v0.9 ISO alpha: first installable CursiveOS with measurement daemon
- **v1.0** → Flagship release with natural-language shell as default terminal
- **v2.0** → Self-updating fleet: measurement-native installs improve automatically as the organism learns
- **v3.0** → Workload-adaptive tuning across inference, mining, build, and other workload classes

Full roadmap with transition milestones: [ROADMAP.md](ROADMAP.md).

---

## Why this hardware

Local compute can't thrive long-term on a single vendor's silicon. CursiveOS is built and validated on **AMD CPU + Intel Arc GPU**, plus Intel laptop hardware — the configurations most optimization guides ignore. If you're a non-NVIDIA miner or inference operator, this project is built with you in mind. The sensor array measures empirical hardware variance, so unusual or underserved configurations are more valuable to the organism than popular ones.

---

## Documentation

- [`ROADMAP.md`](ROADMAP.md) — four-transition roadmap with milestones and flagship features by release
- [`white-paper.md`](white-paper.md) — technical white paper (v2.3)
- [`software-organisms-manifesto.md`](software-organisms-manifesto.md) — the software organism framework and theory
- [`docs/specs/seed-organism-v0.1.md`](docs/specs/seed-organism-v0.1.md) — Phase 0 minimum viable organism specification
- [`docs/specs/layer5-economics-v3.3.md`](docs/specs/layer5-economics-v3.3.md) — authoritative economics specification
- [`docs/architecture/biological-architecture.md`](docs/architecture/biological-architecture.md) — the organism frame and biological mapping
- [`docs/architecture/agent-architecture.md`](docs/architecture/agent-architecture.md) — measurement daemon specification and natural-language shell architectural sketch
- [`docs/architecture/sensor-array.md`](docs/architecture/sensor-array.md) — sensor families, curation, genesis suite, and the metabolic sensor
- [`docs/architecture/testers.md`](docs/architecture/testers.md) — the tester tier, the free-Fast-access exchange, and the spoofing trap
- [`docs/architecture/hardening.md`](docs/architecture/hardening.md) — substrate dependencies, bootstrap risk, and attack-surface analysis
- [`docs/CHANGELOG-v2.3.md`](docs/CHANGELOG-v2.3.md) — what changed in the v2.2 → v2.3 technical/theory split
- [`docs/CHANGELOG-v2.2.md`](docs/CHANGELOG-v2.2.md) — what changed in the v2.1 → v2.2 update
- [`docs/CHANGELOG-v2.1.md`](docs/CHANGELOG-v2.1.md) — what changed in the v1.0/v3.1 → v2.1/v3.3 transition

---

Made by [@connormatthewdouglas](https://github.com/connormatthewdouglas)

**Got results?** Run the wrapper and they'll appear in CursiveRoot automatically. Or open an issue on GitHub.
