# CursiveOS: A Self-Improving Linux Optimization Stack for Local Compute
### Technical White Paper — v1.0 (April 2026)

---

## Abstract

CursiveOS is an open-source Linux optimization stack for local compute operators — crypto miners, AI inference nodes, and anyone running demanding workloads on Linux hardware. It addresses two universal, invisible OS-level bottlenecks (network transport ceilings and GPU frequency stalls) that no default Linux distribution fixes and that every serious local compute operator hits independently.

In validated testing across three distinct hardware configurations, CursiveOS delivered **+454–616% network throughput** improvement and **-2.3–29.1% cold-start latency** reduction, with no permanent system changes.

The deeper purpose of CursiveOS is a five-layer self-improving system. The optimization scripts create immediate value. A structured benchmark database (CursiveRoot) accumulates evidence of what actually works on real hardware. An open contribution cycle lets anyone improve the system. An update pipeline validates and deploys those improvements. And an economic incentive layer — now live — makes all of it self-sustaining.

**The system is designed to get better the more it is used.** Every operator who runs it contributes to a dataset that no individual or competitor could build alone.

---

## The CursiveOS Stack

CursiveOS is organized into five interdependent layers, each building on the one below it.

### Layer 1 — The OS

The base Linux distribution itself. Kernel, drivers, system packages. The actual software that runs on hardware. This is the product that everyone uses.

CursiveOS operates as a tuning layer on top of any standard Linux distribution, not a new distribution. A single command (`./cursiveos-full-test-v1.4.sh`) applies reversible system tweaks, runs paired benchmarks, and submits structured results — all without modifying the underlying distribution.

### Layer 2 — CursiveRoot

The benchmark database. Every speed test, security test, and hardware profile from every validator across every cycle. This is the data foundation that everything else depends on. Without it, nothing above can function.

CursiveRoot captures what no existing tool does in one structured chain:

**hardware fingerprint → tweak applied → before/after measured delta → system stability**

Every submission includes a hardware fingerprint hash (SHA256 of CPU microcode + GPU VBIOS + kernel version) that cryptographically ties results to specific hardware. As the dataset grows, hardware-specific recommendations improve. The database is the project's primary strategic asset — scripts can be copied, but a years-deep cross-hardware performance dataset with a live contribution pipeline cannot.

### Layer 3 — The Recursive Loop

The open contribution cycle. Distributed contributors using any tools they choose, submitting improvements, tested against real data, results feeding back into CursiveRoot. The system improves itself through the collective intelligence of everyone who participates.

Anyone can contribute: new presets, benchmark methodology improvements, hardware-specific tuning discoveries, driver optimizations. Contributions are submitted as hashes to the Hub, tested by validators against the benchmark corpus, and accepted or rejected by democratic vote. The loop is genuinely recursive — better contributions improve CursiveRoot, which enables better contributions.

### Layer 4 — The Update Pipeline

How optimizations move from proposal to testing to deployment. The contributor submission process, the validator testing against the benchmark corpus, the acceptance or rejection of changes, the push to Stable and Fast channels.

- **Stable channel:** conservative, heavily validated preset stack
- **Fast channel:** operators who opt in receive updates earlier, pay a small fee, and contribute benchmarking data that accelerates validation

Validators are the gating mechanism. They run the benchmark suite against proposed changes and vote on acceptance. Their incentive to participate honestly comes from Layer 5.

### Layer 5 — The Economics

The incentive structure that makes Layers 1 through 4 self-sustaining. The 60/40 split, the democratic vote, the staked pool, the yield royalties, the Bitcoin base.

**This layer is now live.** See the full specification below.

---

## 1. The Problem

### 1.1 Linux ships broken for local compute

Anyone running a demanding local compute workload on Linux — whether that's Ollama, llama.cpp, an inference cluster, or a crypto miner — starts with the same two invisible performance bottlenecks baked into every default distribution.

**Network throughput**

Linux defaults to a 212KB socket buffer, appropriate for 1990s modem speeds. The bandwidth-delay product (BDP) on a modern WAN link with 50ms RTT at 400 Mbit/s is approximately 2.4MB. When the buffer is smaller than the BDP, TCP cannot fill the pipe — chain sync, model weight delivery, API traffic, and P2P gossip all run at a fraction of available bandwidth regardless of link speed.

Linux also defaults to CUBIC congestion control, which degrades aggressively under packet loss. Both public internet inference APIs and P2P mining networks operate in environments where 0.5–1% loss is normal.

**Cold-start latency**

Between inference requests or mining jobs, a GPU idles to its minimum frequency — as low as 300–600 MHz on Intel Arc hardware. When a request arrives, the GPU must ramp back to operating frequency before work can begin, adding measurable latency to every cold call. On Intel Arc A750 hardware this penalty is ~22ms per request. On older CPU-only hardware (AMD FX-8350), C-state and governor latency dominate — adding 366–395ms per cold request.

These losses are invisible in standard benchmarks and untreated in default Linux configurations across every relevant community. CursiveOS fixes both bottlenecks, on any hardware, in one command.

### 1.2 The data gap

No centralized database captures real-world Linux performance across diverse compute hardware. Users must independently research optimizations with no visibility into what actually works on hardware like theirs. The knowledge exists scattered across forum posts and GitHub gists — it has never been systematically collected, benchmarked, and made queryable.

The result: every operator individually rediscovers the same optimizations (or doesn't), applies them inconsistently, and has no mechanism to contribute findings to a shared dataset.

---

## 2. Technical Implementation

### 2.1 Preset Stack (v0.8 — 28 tweaks, reversible)

**Network (6 tweaks)**
| Tweak | Value | Mechanism |
|-------|-------|-----------|
| Socket buffers (rmem/wmem_max) | 16MB | Allows TCP to fill the BDP on WAN links |
| tcp_rmem / tcp_wmem | 4096 / 262144 / 16MB | Closes auto-tuner ceiling gap |
| TCP congestion control | BBR + fq | Better throughput under packet loss vs CUBIC |
| TCP slow start after idle | disabled | Prevents throughput reset after compute pauses |
| net.core.netdev_max_backlog | 5000 | Prevents silent packet drops under P2P load |
| net.core.somaxconn | 4096 | Larger connection queue |

**CPU (7 tweaks)**
| Tweak | Value | Mechanism |
|-------|-------|-----------|
| CPU governor | performance | Full clock speed, eliminates scaling delays |
| Energy performance preference | performance | Hardware power hint to CPU firmware |
| AMD CPU boost | enabled | Ensures turbo boost not disabled by power profiles |
| CPU C2 idle state | disabled | Eliminates 18μs wakeup latency spike |
| CPU C3 idle state | disabled | Eliminates 350μs wakeup latency spike |
| CPU C6 idle state | disabled (by name) | Cross-BIOS robust; eliminates ~1ms wakeup jitter |
| kernel.numa_balancing | 0 | Single NUMA node — pure overhead |

**GPU — Intel Arc only (3 tweaks)**
| Tweak | Value | Mechanism |
|-------|-------|-----------|
| SLPC efficiency hints | ignored | Forces Arc into full performance mode |
| GPU minimum frequency | 2000 MHz | Prevents drop to 300–600 MHz between requests |
| GPU boost frequency | hardware max | Ensures peak throughput during inference |

**Memory (5 tweaks), System (3 tweaks), Intel Compute (1 tweak)** — see `cursiveos-full-test-v1.4.sh` for complete list.

### 2.2 Benchmark Methodology

Three paired benchmarks run in the same thermal window:

- **Network benchmark** — `tc netem` WAN simulation (25ms one-way + 0.5% loss), 5 × 10s iperf3 passes, CUBIC baseline vs BBR + 16MB buffers
- **Cold-start latency benchmark** — forces model unload between calls, measures TTFT across 5 calls per pass
- **Sustained inference benchmark** — model stays warm, 5 passes, steady-state tok/s

---

## 3. Results

### 3.1 Primary Rig — AMD Ryzen 7 5700 + Intel Arc A750

| Benchmark | Baseline | Tuned | Delta |
|-----------|---------|-------|-------|
| Network throughput (WAN sim) | 139.6–181.2 Mbit/s | 999.8–1003.6 Mbit/s | **+454–616%** |
| Cold-start latency | 1020.6–1023.5ms | 996.5–996.7ms | **-2.34 to -2.63%** |
| Sustained inference | 75–76 tok/s | 76–77 tok/s | **+1.22–1.46%** |

### 3.2 Secondary Rig — AMD FX-8350 + RX 580

| Benchmark | Baseline | Tuned | Delta |
|-----------|---------|-------|-------|
| Network throughput (WAN sim) | 171 Mbit/s | 1181.9 Mbit/s | **+591%** |
| Cold-start latency | 2461.6ms | 2095.5ms | **-14.87%** |
| Sustained inference | 19.59 tok/s | 20.47 tok/s | **+4.49%** |

### 3.3 Tertiary Rig — Lenovo IdeaPad Gaming 3 (11th Gen i5 + GTX)

| Benchmark | Baseline | Tuned | Delta |
|-----------|---------|-------|-------|
| Network throughput (WAN sim) | 237.8 Mbit/s | 1429.8 Mbit/s | **+501.26%** |
| Cold-start latency | 889.1ms | 630.8ms | **-29.05%** |
| Sustained inference | 32.86 tok/s | 33.25 tok/s | **+1.19%** |

---

## 4. Layer 5 — Economics (v3.1)

### 4.1 Design Philosophy

The incentive layer has one job: make Layers 1–4 self-sustaining without creating perverse incentives, speculative pressure, or fragile token mechanics.

The design avoids:
- **Internal credit tokens** with no exit path or real-world value
- **Inflationary reward tokens** that create sell pressure and dilute early contributors
- **Stake-and-slash** contributor mechanics that punish exploration and lock out participants who can't afford the stake

The design uses:
- **Bitcoin as the base asset** — no new token, no exchange risk, no liquidity bootstrapping problem. Fast users and validators are crypto miners and AI operators who already hold BTC.
- **Babylon Protocol for yield** — trustless BTC staking, ~6–7% gross annual, 50% of pool actively staked for ~3–3.5% effective yield
- **Two contributor income streams** — immediate payout pot (resets each cycle, requires active work) and permanent yield royalties (append-only, grows with pool, never removed)
- **Democratic validator governance** — 100 vote points per eligible validator per cycle, distributed across accepted contributions

### 4.2 Revenue Flow

Every Fast user payment triggers a 60/40 split:

```
Fast user pays F_fast (BTC)
         │
    ┌────┴────┐
   60%       40%
    │         │
Payout pot   Pool principal
(resets      (locked forever,
each cycle)   earns Babylon yield)
```

- **Payout pot:** Distributed to contributors each cycle based on validator vote results. Any undistributed amount rolls into the staked pool.
- **Pool principal:** Never withdrawn. Grows with each cycle's 40% contribution. Earns Babylon yield, which flows back to contributors as yield royalties.

### 4.3 Roles

**Fast users** pay F_fast per machine per cycle. They receive the fastest benchmark updates and hardware recommendations. Primary revenue source.

**Validators** pay F_fast (same fee as a fast user) and receive a full F_fast refund at cycle end — net zero cost. In exchange, they gain voting rights: 100 points to distribute across accepted contributions each cycle. Validators who fail to complete their validation duties forfeit their F_fast (stays in the pool, not refunded). Being a validator is a responsibility, not a reward.

**Contributors** submit improvements — new presets, benchmark methodology, hardware profiles, tooling. They earn from two streams:
1. **Payout pot share** — `(cycle_votes / total_cycle_votes) × payout_pot`
2. **Yield royalty** — `(lifetime_votes / all_lifetime_votes) × cycle_yield`

The payout pot rewards active, high-quality work this cycle. The yield royalty rewards long-term contributors permanently — as the pool grows, so does the absolute value of their royalty even as new contributors dilute the share.

### 4.4 Governance — The Democratic Vote

Each eligible validator distributes 100 points across accepted contributions for the cycle. These votes serve a dual purpose:

1. **Determine payout pot distribution** — vote weight determines each contributor's share of the payout pot for that cycle
2. **Permanently add to contributor's lifetime vote ledger** — once recorded, lifetime votes cannot be removed. They determine yield royalty forever.

**The payout formula normalizes by total votes actually cast, not by 100 × validator_count.** A validator who submits only 60 points only adds 60 to the denominator. A validator who submits nothing effectively abstains and does not dilute other validators' votes.

A 1% minimum vote threshold applies: a contributor must receive at least 1% of total votes cast to receive any payout pot share or lifetime vote accrual. This prevents dust payouts and incentivizes quality over volume.

**Rate limiting:** Three consecutive cycles below the 1% threshold triggers a 5-cycle contribution cooldown. This replaces financial punishment (stakes/slashes) with a reputation-based mechanism that doesn't lock out contributors who can't afford to stake.

**Validator duties and refund forfeiture:** A validator receives their F_fast refund at cycle close if and only if they submitted a valid vote allocation for that cycle. Submitting zero votes forfeits the refund — the F_fast stays in the pool and increases that cycle's payout pot. Submitting any non-zero allocation, even partial, satisfies the duty. The refund is binary: participated → refund; didn't → forfeited.

### 4.5 Parameter Governance

Key economic parameters (`F_fast`, payout/pool split, staking fraction) can be changed by validator supermajority vote, with no admin override required.

**Mechanism:** Any validator proposes a parameter change. The proposal is open for 14 days. It passes if: (1) ≥ 50% of active validators vote (quorum), and (2) > 66% of yes+no votes are yes (supermajority, abstains excluded). Changes take effect the next cycle.

**Guardrails:** At most one open proposal per parameter at a time. Failed proposals can't be resubmitted for 3 cycles. Single-vote shifts are capped at ±10 percentage points for ratio parameters, preventing sudden structural changes.

This keeps economic control with the validator body — the people with real skin in the system — without requiring a token, a DAO, or trusted admin discretion.

**Pilot note:** During the Frosty pilot, parameter changes are made directly by the admin. Governance vote enforcement in the API is a post-pilot task.

### 4.6 Pricing (Pilot)

`F_fast = $2.00 USD` per machine per cycle (monthly), settled in BTC at the moment of payment.

At pilot scale (5 fast machines, monthly cycles):
- $10/cycle total revenue
- $6 payout pot → distributed to contributors by validator vote
- $4 pool principal → locked, earns ~0.27% per cycle (3.25% annual effective on the growing pool)
- Validators: net zero cost

The $2 price reflects current value delivery: the system is in supervised external pilot. Price will be revisited once the contribution pipeline is generating consistent, validated improvements.

### 4.7 Current Status (April 2026)

**Layer 5 backend is pilot-ready.** Implemented:
- Supabase schema: accounts, cycles, machine entitlements, credit ledger, contributor submissions, governance votes, appeals, wallet identities, action audit log, anomaly log, network lockout controls
- Hub API (`hub-api/server.js`): session auth, rate limiting, account controls, identity rail with EIP-191 wallet verification, cycle runner, rewards ledger, contribution submission, governance appeals
- Internal 3-cycle synthetic pilot (cycles 8–10): PASS
- E2E no-SQL pass: PASS
- Wallet binding + signature verification: live

**In test (supervised pilot with Connor + 1–2 friends):**
- 60/40 split mechanics
- Democratic contribution voting (100 points per validator)
- Dual contributor income streams
- Pool principal + Babylon yield simulation

---

## 5. The Virtuous Cycle

```
DATA IN
Operators run benchmarks → structured performance data submitted to CursiveRoot (Layer 2)
        ↓
DATA CONVERTED TO OPTIMIZATION
Contributors analyze dataset → submit improvements via the Recursive Loop (Layer 3)
        ↓
OPTIMIZATION VALIDATED & DEPLOYED
Validators test against benchmark corpus → democratic vote → Update Pipeline (Layer 4)
        ↓
CONTRIBUTORS REWARDED
Payout pot + yield royalties distributed → Economics layer (Layer 5)
        ↓
MORE OPERATORS JOIN
Rewarded contributors recruit peers → dataset grows → AI improves → better presets (Layer 1)
        ↑__________________________________________________________↑
```

Every component has standalone value. The scripts work without the database. The database has value without the incentive layer. The incentive layer makes the database grow faster and reach places it wouldn't otherwise. Together they compound.

---

## 6. Strategic Context

### 6.1 The data moat

The optimization scripts bundle well-understood Linux tuning knowledge. Sophisticated operators already apply some of these tweaks individually. The scripts are not the moat.

**The database is the moat.** A structured, hardware-verified, AI-ready dataset of OS performance deltas across diverse compute hardware does not exist anywhere. Building it now — before any incentive creates gaming pressure — means CursiveRoot accumulates genuine value with an established, trustworthy methodology. A competitor starting later faces a database gap, not just a code gap.

### 6.2 Hardware-bound verification

Any contribution-reward system must solve the anti-gaming problem before rewards are attached. The v1.4 schema addresses this proactively: every submission includes a hardware fingerprint hash (SHA256 of CPU microcode + GPU VBIOS + kernel version) that cryptographically ties results to specific hardware. Fake submissions from a different machine produce a different hash.

### 6.3 Why Bitcoin, not a new token

Introducing a new token would require liquidity bootstrapping, exchange listings, speculation management, and a reason for the community to hold it. BTC solves all of these by default: the target users (crypto miners, AI operators) already hold it; it has global liquidity; its value is independent of CursiveOS; and Babylon Protocol enables trustless yield on locked BTC without custodial risk.

The pool principal is locked forever — not because of arbitrary design, but because this is what makes the yield royalty stream meaningful as a long-term contributor incentive. The pool grows with usage; the yield grows with the pool; early contributors earn perpetually on their lifetime vote share.

---

## 7. Roadmap

### Phase A — Frosty Pilot (current)
Supervised external pilot with Connor + 1–2 trusted collaborators. All roles played manually: fast users, validators, contributors. Goal: validate 60/40 mechanics, democratic vote, and dual income streams work as designed before opening to the public.

### Phase B — Public Open Pilot
Open Layer 5 to the public with `F_fast = $2.00/month`. Fund the initial pool with real BTC. First real validator cohort. Contribution pipeline opens for external contributors.

### Phase C — AI Optimization Loop
Train recommendation models on CursiveRoot evidence to generate hardware-specific presets and expected outcome bands. The benchmark database becomes an active training set.

### Phase D — Distribution Expansion
Turnkey distribution options (installer/ISO/custom kernel path) once recommendation quality and safety thresholds are consistently met.

---

## 8. Philosophy

An operating system that gets better the more it is used. Local AI operators run CursiveOS and their inference gets faster. Miners run it and their rigs improve. Contributors discover better tweaks and share them. The network validates the best work. AI synthesizes the dataset into optimizations no individual would find alone.

Recursive → Cursive. The self-improving flywheel is literally recursive. The bottlenecks Linux ships with today are invisible taxes on everyone doing serious local compute. CursiveOS makes them visible, measures them, and removes them. The benchmark tool is the beginning; the economics layer is what makes it last.

---

*CursiveOS is open source. Built by Frosty Condor (@frostycondor).*
*Contributions, benchmark results, and hardware reports welcome.*
*https://github.com/connormatthewdouglas/CursiveOS*
