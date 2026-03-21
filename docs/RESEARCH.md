# TAO-OS / ForgeOS — Research Library
**Maintained by:** CopperClaw (Lead Dev + PM)
**Last updated:** 2026-03-20
**Purpose:** Living reference document. Pull from here before searching the web. Organized by topic. Add new findings at the top of each section with a date.

---

## 📋 TABLE OF CONTENTS
1. [DePIN Frameworks & Incentive Layer Options](#1-depin-frameworks--incentive-layer-options)
2. [Competitive Landscape — Hardware Databases](#2-competitive-landscape--hardware-databases)
3. [Bittensor Ecosystem](#3-bittensor-ecosystem)
4. [Broader Crypto Mining — Linux Optimization](#4-broader-crypto-mining--linux-optimization)
5. [Hardware — Intel Arc](#5-hardware--intel-arc)
6. [Anti-Gaming & Verification Architecture](#6-anti-gaming--verification-architecture)
7. [Linux Kernel Tuning Reference](#7-linux-kernel-tuning-reference)
8. [Strategic & Market Research](#8-strategic--market-research)

---

## 1. DePIN Frameworks & Incentive Layer Options

> **Relevance:** Post-v1.5, we need an incentive layer for the virtuous cycle (benchmark data → optimizations → rewards → more data). We are shoe-shopping existing frameworks rather than building a new L1.

### Leading DePIN Framework: Solana
*(2026-03-20)*
- **Solana is the dominant chain for DePIN** — hosts Helium, Hivemapper, Render, Grass. Grayscale Research confirms this.
- Reasons: low transaction costs, high throughput, handles real-time data-intensive workloads
- Solana-based DePIN revenue up 33% YoY as of May 2025
- Render Network migrated FROM Ethereum TO Solana in 2024 — strong signal
- **Deployment cost is near-zero** for Solana programs vs Bittensor subnet (~$250K)
- Official DePIN quickstart: https://solana.com/developers/guides/depin/getting-started
- Token distribution tooling: Magna, Squads (free), DFNS/Fireblocks (enterprise)

### Case Studies

**Hivemapper (HONEY token)**
- Dashcam drivers collect street imagery → earn HONEY tokens
- Major logistics + ride-sharing companies BUY the data (paying fiat for token-incentivized contributions)
- Model: contribute physical-world data → earn → data sold to enterprises
- Enacted MIP-19 (Jan 2025) to raise Map Credit prices — tokenomics evolving
- **Lesson for ForgeOS:** the data buyer doesn't have to be crypto-native. Enterprise value of optimization data is real.
- Cautionary: manipulation risk — someone could fake contributions without hardware verification

**Helium (HNT/IOT/MOBILE)**
- Hotspot operators provide wireless coverage → earn tokens
- Transitioned from IoT → full MVNO (Mobile Virtual Network Operator) by 2025
- Focus on access/coverage, not data quality/reliability metrics
- **Lesson:** hardware-bound proof of contribution is the core mechanism (you can't fake a hotspot in a real location)

**Render Network (RNDR)**
- Idle GPU capacity contributed → used for rendering → contributors earn RNDR
- Migrated to Solana from Ethereum 2024
- **Most directly analogous to ForgeOS** — GPU owners contribute compute, get rewarded
- **Key difference for us:** we're not selling compute time, we're building a benchmark dataset

### DePIN Architecture Fit for ForgeOS
Our use case maps to DePIN almost exactly:
- Physical resource: Linux machines running benchmarks
- Contribution: structured benchmark data (hardware fingerprint → tweaks → deltas)
- Verification: hardware-bound submission hash (CPU microcode + GPU VBIOS + kernel hash)
- Reward: ForgeOS token
- Data consumer: AI that generates optimizations, and eventually enterprise buyers

**Open questions to research later:**
- [ ] Exact cost to deploy a Solana program for token distribution
- [ ] Whether DIMO (vehicle data DePIN) has open-source verification architecture we can borrow
- [ ] IoTeX as alternative — purpose-built for physical device data

---

## 2. Competitive Landscape — Hardware Databases

> **Relevance:** tao-forge is our moat. Understanding what exists (and what's broken) tells us how to win.

### WhatToMine
*(2026-03-20)*
- Dominant crypto mining profitability calculator
- Covers dozens of GPU models with pre-loaded hashrate data
- Users can input custom hashrates and power consumption
- Real-time profitability based on current coin prices + difficulty
- **Gap:** doesn't capture OS-level optimization deltas. Assumes hardware runs at stock performance.
- **Our opportunity:** WhatToMine shows you what to mine. ForgeOS shows you how to make your rig faster doing it.

### Minerstat
*(2026-03-20)*
- Automated benchmarking: miners test hardware, optionally share results
- Hardware database with hashrate + power data
- Mining OS + monitoring platform
- More operator-focused than WhatToMine
- **Gap:** no OS-level tuning. No before/after optimization data. No AI loop.
- URL: https://minerstat.com/hardware

### MLPerf / MLCommons
*(2026-03-20)*
- Industry standard for ML benchmarks
- Submitted by corporations in controlled lab environments
- NOT crowdsourced — no individual miners represented
- **Gap:** totally disconnected from real miner hardware (no RX 580, no Arc A750 results)
- **Our opportunity:** tao-forge is the MLPerf for the other 99% of hardware

### UserBenchmark (cautionary tale)
*(2026-03-20)*
- Amassed millions of crowdsourced CPU/GPU benchmarks
- **Destroyed credibility** by silently biasing scoring methodology to favor certain hardware
- Got banned across major community forums (r/hardware, etc.)
- **Lesson for tao-forge:** scoring methodology transparency is existential. Must be:
  - Open-source scoring algorithm
  - Hardware-bound submissions (can't fake results)
  - Statistical outlier detection
  - No hidden weighting

### miningbenchmark.net
*(2026-03-20)*
- Compares hashrate/profitability across GPU/ASIC hardware
- URL: https://www.miningbenchmark.net/
- Basic — no OS tuning layer, no AI, no structured delta data

---

## 3. Bittensor Ecosystem

> **Relevance:** Current distribution channel (Phase 1-3). Also our primary test bed and first audience.

### Network State (as of early 2026)
*(2026-03-20)*
- 128 active subnets (was 32 before dTAO launch Feb 2025)
- Max 256 UIDs per subnet (64 validators + 192 miners)
- ~32,768 theoretical active node slots
- 203,000+ wallet addresses (many passive stakers)
- 70%+ of circulating TAO (~7.5M of 10.78M) is staked
- **First halving:** Dec 14, 2025 — daily emissions cut from 7,200 → 3,600 TAO/day (~$1M/day at $250-290/TAO)
- Emissions split: 41% miners / 41% validators+delegators / 18% subnet owners
- Total subnet market cap: ~$3B
- Institutional: Grayscale TAO ETF filing, Europe's first Staked TAO ETP, DCG's Yuma Asset Management
- **Academic finding (June 2025):** stake > performance as reward predictor. <2% of wallets command 51% stake majority in most subnets.

### Subnet Scoring — Key Nuance
*(2026-03-20)*
- **No universal scoring.** Each subnet defines its own incentive function.
- Validators submit weight vectors every ~72 min (one "tempo")
- Yuma Consensus: stake-weighted aggregation of validator scores
- **Yuma itself doesn't measure latency** — it aggregates what validators report

### Subnets Relevant to ForgeOS

**SN64 — Chutes ("the Linux of AI")**
- Connor's primary target subnet
- High mindshare (2.36% as of Aug 2025, #2 overall)
- Tools: https://github.com/minersunion/sn64-tools
- Scoring: inference quality + speed
- **TAO-OS sweet spot** — cold-start latency matters here

**SN1 — Apex / Text Prompting**
- LLM inference subnet
- Validators score on semantic quality AND response speed
- Clear TAO-OS benefit: cold-start latency reduction directly affects scoring

**SN27 — Compute**
- Proof-of-GPU verification — benchmarks raw GPU capability
- Closest existing analog to our verification architecture
- Does NOT touch kernel parameters
- **Study their verification mechanism** for tao-forge anti-gaming design

**SN3 — Templar (Training)**
- Gradient quality dominates, speed secondary
- Less relevant for TAO-OS optimization pitch

### Subnet Registration Cost
*(2026-03-20)*
- ~$250,000 USD equivalent in TAO to register a new subnet
- Primary reason Connor is exploring DePIN alternatives
- This cost gates out bootstrap founders entirely

---

## 4. Broader Crypto Mining — Linux Optimization

> **Relevance:** Expanding beyond Bittensor to all crypto miners (Kaspa, ETC, Monero, Ravencoin) multiplies addressable market 10x and gives AI the hardware diversity it needs. Tool requires zero changes.

### The Universal Linux Problem
*(2026-03-20)*
- Default Linux ships with 212KB socket buffer — appropriate for 1990s modems, not 2020s WAN
- CUBIC congestion control degrades under packet loss (common on P2P networks)
- These bottlenecks affect EVERY Linux miner regardless of coin
- BBR + 16MB buffers delivers 10x performance improvements on some network paths (confirmed by ESnet testing)
- Source: https://fasterdata.es.net/host-tuning/linux/recent-tcp-enhancements/bbr-tcp/

### Mining Communities to Target (Post-v1.5)
*(2026-03-20)*
- r/gpumining — general GPU mining, hardware-diverse
- r/kaspa — Kaspa miners (KHeavyHash algo, GPU-bound)
- r/MoneroMining — CPU mining, C-state + governor tweaks most relevant
- r/EtherMining (ETC) — GPU mining
- Each community: Linux rig operators running same broken defaults

### Existing Linux Mining Optimization Resources
*(2026-03-20)*
- GitHub Gist (gboddin): "Mining optimisation under Linux" — https://gist.github.com/gboddin/bbf10dc51cd468fba93e8f4e17c51859
  - Basic sysctl tweaks, no benchmarking framework, no reversibility
  - **ForgeOS is 10x more rigorous** (benchmarked, reversible, hardware-aware)
- DigitalOcean TCP tuning guide: https://www.digitalocean.com/community/tutorials/tuning-linux-performance-optimization
  - Covers tcp_rmem/wmem, BBR — confirms our approach is correct
  - But: general guide, not mining-specific, no before/after data

---

## 5. Hardware — Intel Arc

> **Relevance:** Primary test hardware. Non-NVIDIA positioning is core to project identity.

### Arc A750/A770 Linux Status (2025-2026)
*(2026-03-20)*
- Stable out-of-the-box since Linux 6.2+ (promoted to supported)
- A-series uses older `i915` driver; B-series (Battlemage B580) uses newer `xe` driver
- **A-series on Linux: ~80% of Windows performance** (xe driver still maturing for A-series)
- B580 (Dec 2024, ~$250): better Linux support, 16GB VRAM — worth tracking
- Community signal: "I'd love that to translate over to Linux" — demand exists, driver gap is real
- Inference: OpenVINO delivers impressive speeds on A770 (16GB VRAM handles medium-sized model fine-tuning)

### Arc + Ollama Current State
*(2026-03-20)*
- Vulkan backend: stable for 1B models, crashes/garbled on 3B+ (fp16 precision bug in ollama 0.18.1)
- Intel SYCL backend: the fix, but not yet production-stable for Arc
- SYCL roadmap item in action-plan.md — parked until v1.5

### Arc B580 (Battlemage) — Future Research
*(2026-03-20)*
- Released Dec 12, 2024 (~$250 new)
- xe driver only — better Linux support than A-series
- 16GB VRAM
- **Worth a v0.7 run when available** — could become recommended hardware for bootstrapped miners

---

## 6. Anti-Gaming & Verification Architecture

> **Relevance:** Before attaching any token reward to benchmark submissions, tao-forge needs hardware-bound verification. Claude's explicit requirement for v1.4 schema.**

### The Problem
*(2026-03-20)*
- Currently anyone can submit fake benchmark results to tao-forge
- Once token rewards are attached, fake submissions become financially motivated
- Must be solved at the schema level BEFORE any incentive layer

### Claude's v1.4 Schema Requirements
*(2026-03-20)*
Hash components for hardware fingerprint:
- CPU microcode version
- GPU VBIOS hash
- Kernel version
- Together: cryptographically ties results to specific hardware instance

Additional fields:
- `stability_flag` — did system stay stable 1hr post-tweak?
- `power_idle_baseline_w`
- `power_tuned_w` (currently null — active bug)
- `thermal_headroom_c`
- `submission_timestamp`
- `kernel_version`
- `distro`

### Precedent: Tamper-Evident IoT Data
*(2026-03-20)*
- Academic paper (Dec 2025, IEEE): "Proof of Authenticity of General IoT Information with Tamper-Evident Sensors and Blockchain"
- Method: devices periodically sign readouts, link data using redundant hash chains, submit cryptographic evidence via Merkle trees
- Source: https://arxiv.org/html/2512.18560
- **Directly applicable** to tao-forge — benchmark runner signs results with hardware-derived key

### SN27 (Proof-of-GPU) as Design Reference
*(2026-03-20)*
- Bittensor SN27 does GPU verification: benchmarks raw capability to verify hardware claims
- Does NOT touch kernel params — but verification architecture is worth studying
- Key: hardware must actually perform the benchmark, not report a cached value

---

## 7. Linux Kernel Tuning Reference

> **Relevance:** Technical reference for current and future preset tweaks. Pull from here for v0.8+ research.**

### Current v0.7 Tweak Stack Summary
*(2026-03-20)*
25 tweaks across 6 categories. Full detail in `tao-os-presets-v0.7.sh` and white-paper.md.
Key breakthroughs:
- `tcp_rmem`/`tcp_wmem` explicit set (v0.7 fix) — this was the unlock to ~1 Gbit/s. Setting `rmem_max` alone leaves TCP auto-tuner silently capped.
- GPU min freq lock (2000 MHz) — eliminates idle-to-active ramp on Arc A750 (~22ms saved)
- C-state disable — eliminates 350μs-1ms wakeup jitter

### v0.8 Candidate Tweaks (from action-plan.md)
*(2026-03-20)*
High confidence:
- `vm.min_free_kbytes` = 262144 (256MB) — prevents kernel reclaiming pages mid-inference
- `tcp_fastopen` = 3 — reduces TCP setup overhead for repeated validator connections
- `tcp_notsent_lowat` = 131072 — reduces send buffer bloat under sustained load

Medium confidence:
- IRQ affinity — pin NIC IRQs to non-inference cores (complex detection needed)
- AMD P-state driver check — verify `amd_pstate` active vs `acpi_cpufreq`
- `perf_event_paranoid` = 3 — disables perf sampling overhead (minimal gain)

**Rule:** ≥2 paired runs on Arc A750 before any tweak enters preset stack.

---

## 8. Strategic & Market Research

> **Relevance:** Big picture context for pitching, positioning, and long-term vision.**

### Market Size
*(2026-03-20, from research report)*
- ~$150M/year flows to Bittensor miners post-halving
- 15,000–25,000 active miner nodes
- 10% capture at $20-50/mo = $360K–$1.5M/year (niche but viable for OSS)
- **Bittensor alone is not venture scale.** Broader crypto mining + DePIN + gaming is.

### Growth Signals
*(2026-03-20)*
- Bittensor: 32 → 128 subnets in one year
- Wallets: ~100K → 203K+
- Institutional: Grayscale TAO ETF filing, Europe's first Staked TAO ETP
- DePIN sector: 19B+ breakout in 2026, enterprise adoption accelerating (Hivemapper data used by logistics/ride-sharing companies)
- Solana DePIN revenue +33% YoY (May 2025)

### Rebrand — ForgeOS
*(2026-03-20, board decision)*
- Winner: **ForgeOS**
- Runner-ups: OptiForge, AetherForge
- Rationale: keeps forge equity, chain-agnostic, premium signal, works for mining + gaming + inference
- Private lock: do NOT touch public branding until v1.5 gate
- CLAUDE.md already notes "ForgeOS" as private shortlist winner

### Key Strategic Risks
*(2026-03-20, from research report + board)*
1. **Stake > performance** in Bittensor rewards — OS optimization ceiling is real
2. **Script defensibility** — sysctl values are public knowledge; the database is the moat
3. **Subnet security** (Phase 4+) — OS-level configs are attack surface; $8M theft in 2024 shows ecosystem is targeted
4. **Anti-gaming** — fake benchmark submissions will happen once rewards are attached
5. **Token credibility** — verification must precede incentives

### Connor's Core Insight (Worth Remembering)
*(2026-03-20)*
> "TAO was only a means to this end."

The project is fundamentally about closing the loop between AI and OS-level optimization. A living dataset that lets AI optimize any OS on any hardware, at the kernel level, for any workload. Crypto is the fuel that keeps the flywheel spinning. Any specific blockchain is just a vehicle.

---

## 🔧 Research TODO List
- [ ] Exact cost to deploy a Solana token/program for contributor rewards
- [ ] DIMO verification architecture (vehicle data DePIN) — borrow for tao-forge?
- [ ] IoTeX — purpose-built for physical device data contributions
- [ ] Intel Arc B580 (Battlemage) benchmark — worth running v0.7?
- [ ] SN27 verification mechanism deep dive — design reference for anti-gaming
- [ ] v0.8 tweak candidates: literature on `vm.min_free_kbytes` + `tcp_fastopen` + IRQ affinity
- [ ] Kaspa/Monero/ETC mining communities — best forums/repos for outreach post-v1.5

---
*Add new research at the TOP of the relevant section with a date stamp.*
*Keep entries concise — this is a reference, not an essay.*
