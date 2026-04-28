# CursiveOS

### Technical White Paper — v2.3 (April 2026)

**A measurement-driven Linux optimization layer for local compute workloads, with a Bitcoin-native economic architecture and a planned natural-language operator interface.**

---

## Abstract

CursiveOS is a Linux optimization layer for local compute operators — AI inference nodes, crypto miners, and other workload-specialized Linux hosts. It applies a curated stack of reversible system tweaks, measures their effect via paired before-and-after benchmarks on the host's actual hardware, and records structured results to a shared performance database (CursiveRoot). Its design separates deterministic measurement from the operator interface, enables a fully specified Bitcoin-native economic layer for contributor compensation, and is structured to grow from its current state as a tuning layer into a full distribution as the architecture matures.

On the hardware configurations validated so far, the current preset stack has produced measurable performance gains in specific benchmark scenarios — notably network throughput and cold-start inference latency. These results are directional and have been reproduced across a small number of hardware configurations. The current work is scoped honestly: the preset stack is validated on a limited hardware sample, the benchmark surface is deliberately narrow during this phase, and broader claims require broader data.

This document describes the current implementation, the validated results and their limits, the architectural design (including the fully specified economic layer), the planned agent layer (measurement daemon and natural-language shell), and the roadmap from here to a full operating system release. The conceptual framework within which this architecture was designed — the software organism frame — is described in a companion document, [Software Organisms](software-organisms-manifesto.md).

---

## 1. Problem Statement

General-purpose Linux distributions ship configurations optimized for broad compatibility. This is the correct default for distributions that target diverse workloads on diverse hardware. The tradeoff is that specific workload classes — sustained AI inference, heavy proof-of-work mining, high-throughput network node operation — can sometimes benefit from tuning that defaults do not attempt. Whether a given host actually benefits depends on hardware, kernel, workload profile, and distribution. The only reliable way to know is to measure.

The specific gap CursiveOS addresses: operators running compute-intensive workloads on consumer or prosumer hardware often lack the time, expertise, or measurement infrastructure to identify which tunings help them. Generic optimization guides are fragmented, often outdated, and rarely include reversibility or measurement. Applying tunings blindly risks system instability. Not applying them risks leaving performance unrealized.

CursiveOS provides a structured solution: a curated, reversible preset stack paired with a before-and-after benchmark harness that measures the effect on the operator's actual hardware. Results are logged structurally. The operator can verify that their specific machine benefited, keep the changes if it did, or revert cleanly if it did not. No trust in universal claims is required; the measurement is local and specific.

This is the narrow, scoped version of the project. The broader architecture — the sensor array, the economic layer, the eventual self-updating fleet — is built on this foundation but not yet fully active.

---

## 2. Design Principles

Five principles govern the current system and constrain all future architectural decisions.

**Reversibility.** Every preset change is designed to be removed or restored with minimal operator effort. System state transitions are explicit, bounded, and logged. An operator who applies a preset and dislikes the result can revert in a single command.

**Measurement before narrative.** A tuning change is justified by before-and-after evidence on the host system, not by appeal to documentation, consensus, or intuition. A change that cannot produce paired measurement evidence is not a validated change.

**Deterministic evaluation path.** The measurement pipeline is a deterministic, mechanical process. No probabilistic system — whether an LLM, a heuristic, or a manual judgment — is permitted in the path that produces a measurement result. This separation is architectural and enforced by keeping the measurement daemon and the natural-language shell in different processes with different trust models.

**Bounded operational risk.** The system prefers auditable actions, explicit state transitions, and strong rollback support over clever automation. Any operation that cannot cleanly revert is avoided; any operation that can revert is preferred.

**Incremental claims.** Claims made by the project are scoped to current evidence. Broader claims require broader evidence. Architectural designs that anticipate future scale are specified clearly but marked as specified rather than validated.

---

## 3. Current System

The current implemented system consists of three integrated components and a shared performance database.

### 3.1 Preset Layer

The preset layer applies a curated set of system-level tuning parameters. The current canonical preset (`cursiveos-presets-v0.8.sh`, 28 parameters) covers network buffer configuration, TCP behavior, scheduler parameters, memory pressure response, swap and VM tuning, and selected CPU governor settings. Each parameter is applied non-destructively with the prior value captured for rollback. Users can apply, revert, or apply-temporarily with scoped lifetime.

The preset stack is workload-targeted: it optimizes for hosts running sustained compute workloads (inference, mining, network-intensive operations) rather than for general desktop use. Applying it to a general desktop may or may not help and is not its intended use case.

### 3.2 Benchmark Layer

The benchmark layer runs paired before-and-after measurements to evaluate preset effects. The current suite includes cold-start and sustained inference latency testing, TCP throughput measurement under configured network conditions, and individual tweak-isolation tests. The top-level harness (`cursiveos-full-test-v1.4.sh`) runs the complete measurement sequence and produces a structured summary.

The benchmark surface is intentionally narrow during this phase. It is designed to detect signal on tunings that matter for compute workloads on the hardware configurations being used to develop the project. It is not a comprehensive certification suite for all possible Linux tuning decisions. Growing the benchmark surface is an explicit goal of later phases, specifically Phase 0 onward.

### 3.3 CursiveRoot

CursiveRoot is the project's shared performance database. When the benchmark harness runs with user consent, it submits structured results — hardware fingerprint, kernel and distribution version, preset version applied, measurement deltas — to the shared database. Over time this database accumulates the empirical record of which tunings produce results on which hardware configurations under which conditions. The database is the project's sensory nervous system: the mechanism by which the organism perceives what is working and where.

CursiveRoot is live and accumulating data from the hardware configurations used to develop the project. Public query access is available via `scripts/cursiveroot-status.sh`.

### 3.4 Integration

The three components operate as a single workflow. One command (`./cursiveos-full-test-v1.4.sh`) runs baseline benchmarks, applies the preset stack, re-runs the benchmarks, compares results, submits them to CursiveRoot, and reverts the system. The operator sees the measured delta on their own hardware before deciding whether to apply the presets persistently. This is the core loop the rest of the architecture is built around.

---

## 4. Architecture

CursiveOS is organized into five architectural layers. Each is a first-class component of the design, though their current implementation states vary.

**Layer 1 — Phenotype.** The running Linux system with presets applied. This is what actually executes on user hardware. In current implementation: a user's existing Linux distribution plus the applied preset stack. In future implementation (Transition 1, see Section 9): a CursiveOS ISO that boots with presets already applied.

**Layer 2 — Sensory nervous system (CursiveRoot + sensor array).** The measurement infrastructure that evaluates phenotype fitness. Currently implemented as the benchmark suite plus CursiveRoot. In future iterations, additional sensors will be added to the array as workload coverage expands.

**Layer 3 — Evolutionary loop.** The mechanism by which contributed changes are evaluated against the sensory array and accepted or rejected based on measured fitness. Currently manually operated (Connor proposes preset changes, benchmark results validate them). In Phase 0 forward, the loop becomes the formal mechanism for handling contributed changes from external contributors.

**Layer 4 — Inheritance.** The accumulated record of validated changes. Currently: version-controlled preset history and CursiveRoot's benchmark record. In future iterations: the sensor-validated lineage record that forks inherit.

**Layer 5 — Metabolism (economics).** The Bitcoin-native economic architecture compensating contributors from user revenue. Fully specified (see Section 5); not yet actively compensating because there are not yet paying users or external contributors. The economic machinery activates as population grows.

Each layer has a defined interface with adjacent layers. The architecture is sized for mature operation but currently operates in its bootstrap configuration, where the full machinery is specified but many components are dormant pending population growth. This bootstrap-phase asymmetry is disclosed explicitly in Section 10.

---

## 5. Layer 5 — Economic Architecture (v3.3)

The economic layer specifies how value flows from users to contributors, how measurement work is compensated, how the split between short-term and long-term compensation is determined, and how obligations propagate when the project is forked. This layer is substantial and is summarized here at a level sufficient for architectural understanding. The full specification is at [docs/specs/layer5-economics-v3.3.md](docs/specs/layer5-economics-v3.3.md).

### 5.1 Core Structure

The economic layer has three defining properties that differentiate it from conventional DePIN or DAO structures.

**No custom token.** User payments arrive in Bitcoin. Contributor compensation is paid in Bitcoin. There is no platform-specific token, no initial offering, no emissions schedule, and no governance token. The project is Bitcoin-native end to end.

**No capital pool.** There is no staked reserve, no yield-bearing contract, no pool principal that accumulates over time. Revenue flows directly from users to contributors per cycle. The elimination of the pool is a deliberate design decision made after stress-testing an earlier architecture that included one; the reasoning is documented in the transition history (v3.1 → v3.3).

**No voting and no appeals.** The economic layer contains no governance mechanism in the conventional sense. There are no contributor votes on whether a contribution is valuable, no one-contributor-one-vote tallying, no appeals process. Contribution value is determined by the sensor array's measurement of the contribution's effect on fitness. Whoever the sensors say produced improvement receives the corresponding compensation.

### 5.2 Revenue Flow

User payments for the Fast tier subscription (target price $2/month, architecturally flexible) accumulate within a cycle window. At cycle close, accumulated revenue is divided into two streams — a current-cycle stream paid to contributors whose work merged during this cycle, and a lifetime stream paid to contributors based on their cumulative measured fitness across all prior cycles.

The ratio between these streams is controlled by the **metabolic sensor** (Section 5.4). It is not a fixed parameter.

### 5.3 Fitness Ledger

Each contributor accumulates fitness — a measured quantity derived from sensor outputs evaluating their contributions. Fitness is cumulative, append-only, and recorded in a ledger anchored to Bitcoin. A contribution's fitness contribution is whatever the sensor array measured at merge time, weighted by confidence and recorded permanently. A contribution that improved the system in year one continues generating lifetime-stream payments in year five because its measured fitness is part of the inherited substrate. Superseding a contribution can change what the current genome runs, but it does not delete fitness that was validly earned.

This structure produces substrate-based compounding: the accumulated empirical record of what works, and the code that embodies it, grow with the project's operation. Contributors are compensated through permanent lifetime fitness, which aligns incentives with producing durable improvements rather than short-term wins.

### 5.4 The Metabolic Sensor

The split between current-cycle and lifetime streams is dynamic. A sensor measures the ratio of new-contributor-leaning merges to returning-contributor-leaning merges within a recent window, weighted continuously. When the measured signal indicates that recruitment of new contributors is the binding constraint, the split shifts toward current-cycle compensation (attracts new people). When the signal indicates retention is the binding constraint, the split shifts toward lifetime compensation (sustains the active base).

The genesis state of this sensor is 20% current-cycle / 80% lifetime. The starting position matters because the trajectory it produces is strictly decreasing in lifetime share as the organism recruits new contributors — which eliminates a legibility concern that would arise if the trajectory went the other way. The starting position is also substantively accurate: in bootstrap, almost all work being done is legacy work that will persist for years, so a heavily lifetime-weighted starting split reflects what the organism is actually producing.

The equilibrium point — where the sensor stabilizes once the organism reaches steady state — is not pre-specified. It will be whatever the metabolic sensor converges on empirically. This is deliberate: pre-specifying it would be architecture-smuggled governance. The reader should understand that the split is genuinely measurement-driven rather than having a designed target with measurement theater around it.

### 5.5 Testers and the Sensory Fleet

The project supports a separate role — "tester" — for operators who run benchmarks and contribute measurement data without otherwise contributing code. Testers compensate the project with measurement coverage across diverse hardware; the project compensates testers with free Fast tier access, granted for as long as the tester's fleet continues submitting validated measurements.

The compensation structure matches the shape of the work. Testers produce continuous flow (ongoing measurement), so they receive continuous flow (ongoing Fast tier access valued at $2/month). They do not accumulate lifetime fitness. This architectural choice collapses an attack surface that existed in an earlier economic design: if testers received lifetime compensation for measurement, a single fake tester fleet would earn unbounded compensation over time. Under the flow-matched structure, a fake tester fleet saves at most $2/month per fake identity. After basic hardware fingerprint verification, the attack becomes negative expected value.

Testers are compensated. Testers are not contributors to the genome. The distinction is structural: the measurement of fitness is a different kind of work from the production of fitness. Both are valuable. They are compensated differently because the consequences of miscompensating them differ.

### 5.6 Claim Window

Accruals to contributors are held for a two-year claim window. A contributor who does not claim a specific accrued payment within two years forfeits that payment into the next redistribution event, where it is distributed to active claimants using the lifetime-stream weighting. This is a standard hardening against stale accumulation: it bounds the liability the organism carries, prevents accruals from building up permanently on wallets whose keys are lost, and motivates contributors to maintain active connection with the project. Lifetime fitness itself is not forfeited.

### 5.7 Forks and Obligation Inheritance

The architecture explicitly supports forking. Any party can take the genome (code, sensor definitions, architectural protocols) and continue the lineage under a different stewardship. The fork inherits both the genome and the outstanding obligations — the accruals owed to contributors for measured work already delivered.

Inheritance is enforced by Bitcoin anchoring. The ledger of who is owed what is written to a substrate that the forker cannot erase. A fork that repudiates obligations is identifiable as such on-chain. Contributors owed by the original lineage retain claims against any fork that carries the genome forward. A fork that honors obligations carries forward legitimately; a fork that does not is visibly parasitic.

### 5.8 Sensor Curation

Each sensor in the array is owned by an identified curator — the contributor who designed it, tuned it, and is accountable for its integrity. Curator is a responsibility, not a separate reward class. Sensor code can earn fitness like any other contribution when it is measured to improve the organism, but the curatorship role itself carries no extra economic share. Sensors are subject to deprecation events if they stop tracking reality, either through environmental drift or corruption.

Curator succession is designed into the architecture. A curator can be replaced either voluntarily or through a structural revocation event triggered by consistent sensor anomaly. No single curator is architecturally permanent; all curatorship is earned through measured capability and is subject to removal through the same process it was earned by.

### 5.9 Substrate Dependencies

The economic architecture depends on exactly two external substrates: Bitcoin (for payment settlement and ledger anchoring) and Linux (as the genome the project inherited from). The dependency on Linux is ancestral rather than operational — the project can evolve independently of Linux's ongoing development without losing identity. The dependency on Bitcoin is operational — the project requires Bitcoin to continue functioning for its economic layer to operate as designed.

No other substrate dependencies exist. There is no dependency on Ethereum, on any Layer 2 bridge, on any proof-of-stake chain, on any staking protocol, on any external yield source. The architecture was deliberately simplified from an earlier design that included external yield sources after stress testing revealed that the yields were economically immaterial and the dependencies added attack surface without proportional benefit.

---

## 6. Agent Architecture

CursiveOS runs two agent components on installed systems. They share infrastructure but have different failure modes and are kept architecturally separate. Full specification: [docs/architecture/agent-architecture.md](docs/architecture/agent-architecture.md).

### 6.1 Measurement Daemon

The measurement daemon is a deterministic, non-LLM component that runs on every CursiveOS install (with user consent). It executes sensors on schedule and in response to workload events, caches results locally, and submits them to CursiveRoot in batched cadences. It can apply signed preset updates after running the local regression sensor to verify they do not regress the user's specific hardware.

The daemon's failure mode is a data quality problem rather than a user experience problem. For that reason, the daemon contains no probabilistic components. No LLM is present in its measurement pipeline. No heuristic judgment substitutes for a sensor result. The daemon is infrastructure, not intelligence.

The measurement daemon is fully specified. Implementation is a Phase 1 scope item (after Phase 0 validates the measurement loop on the founder's rig).

### 6.2 Natural-Language Shell (v1.0 Flagship Feature)

The natural-language shell is the planned default terminal on CursiveOS v1.0. It replaces the conventional terminal-as-command-line with a terminal-as-conversation: the operator describes what they want, a local language model translates the intent into shell commands, the commands are executed (with scope-appropriate confirmation), and the results are presented. The conventional terminal remains available for operators who prefer it; the natural-language shell is the new default.

The shell uses a tiered model approach. Entry hardware uses a small local model (4-8B parameters, handling routine command translation). Workstation hardware uses a larger local model (20-30B parameters, handling multi-step tasks). Fleet operators can configure shared inference via a workstation node. Remote model routing is available as opt-in with clear indication of what is leaving the machine.

The shell's permission model has three levels: read (no confirmation required), write (operations shown, destructive operations confirmed), and root (explicit confirmation with sudo credentials for elevated operations). The shell never caches credentials. Every command the shell executes is shown to the operator verbatim; the operator can inspect, modify, and re-run any command. The shell augments shell fluency rather than obscuring it.

Architectural specification is complete. Implementation begins during the v0.9 → v1.0 development window. The shell is deliberately flagship for v1.0 — the release where CursiveOS first becomes an installable operating system rather than a tuning layer applied on top of another distribution. This is the release that defines what CursiveOS is to new users, and the natural-language shell is what makes the first impression memorable.

### 6.3 Why the Separation Matters

A corrupted or malfunctioning natural-language shell produces a degraded user experience — annoying, potentially destructive at the user level, but recoverable. A corrupted or malfunctioning measurement daemon produces degraded fitness ledger entries — potentially invisible, potentially accumulating over time, and not recoverable after the fact. The stakes are different. The trust models are different. The architecture treats them as different by keeping them in separate processes with separate trust boundaries, separate write paths, and no mechanism by which the shell's output can enter the measurement pipeline.

---

## 7. Validated Results

The following results are reproducible on the hardware configurations they were produced on. Generalizing them requires broader data.

### 7.1 Network Throughput

On the three hardware configurations used in initial validation, the current preset stack produced measured TCP throughput gains ranging from **+454% to +616%** relative to the baseline configuration on the same machine. The test scenario uses controlled or simulated network conditions designed to expose buffer-related bottlenecks. Results depend on the specific network test conditions; real-world gains on production network paths may differ.

### 7.2 Cold-Start Inference Latency

On the same three configurations, the preset stack produced cold-start inference latency reductions ranging from **-2.3% to -29.1%** relative to baseline. Cold-start latency measures the interval between model-serving request arrival and first token production. Sustained throughput measurements are separate and less dramatic but generally positive.

### 7.3 What These Results Mean

These results are evidence that specific workloads on specific hardware configurations benefit measurably from the preset stack. They are not evidence that all Linux systems benefit, that all workloads benefit, or that any specific arbitrary system will see these exact numbers. The architectural response to this generality gap is built into the project: CursiveOS measures the user's specific machine before and after, and the user sees their specific delta before deciding whether to persist the changes. No trust in generalization is required.

### 7.4 Reproducibility

All measurements are produced by scripts in the public repository. The preset stack and benchmark harness are reproducible, and the reported hardware configurations are documented. Any operator running the same harness on the same hardware should produce measurements in the same neighborhood; deviations are themselves useful data because the sensor array wants to know when generalization breaks.

---

## 8. Implemented, Validated, Planned

A recurring source of confusion in early-stage systems is the mixing of current functionality with future direction. This section separates them.

**Implemented and operational:**
- Preset stack v0.8 (28 tweaks, reversible)
- Benchmark harness (`cursiveos-full-test-v1.4.sh`) with paired before/after measurement
- CursiveRoot performance database with auto-submit
- Public repository, documented APIs for benchmark submission
- Five-layer architectural separation

**Fully specified, implementation in progress or pending:**
- Layer 5 economic architecture (v3.3 spec complete; mechanical implementation pending contributor/user population)
- Hub rebuild to v3.3 specification (in active development)
- Phase 0 seed organism loop (in active development)
- Measurement daemon (specified; Phase 1 scope)
- Natural-language shell (architecturally sketched; v1.0 flagship implementation scope)

**Architecturally committed but not yet specified in detail:**
- ISO build pipeline and first installable release (v0.9)
- Workload detection subsystem (Transition 3 scope)
- Multi-workload sensor array expansion (Transition 3 scope)

**Explicitly outside current scope:**
- Universal claims about Linux default performance
- Guaranteed benefits on arbitrary hardware or arbitrary workloads
- Certification of production-grade reliability under adversarial conditions
- Any guarantee about the date of any future release

Every claim in this paper is intended to fall clearly within one of these categories.

---

## 9. Roadmap

The project roadmap is organized around four transitions that progressively expand what CursiveOS is. The detailed roadmap is at [ROADMAP.md](ROADMAP.md).

Summary of the transitions:
- **Transition 1 (v0.9 → v1.0):** Tweak stack becomes a tuned, installable distribution. Natural-language shell ships as the flagship v1.0 feature.
- **Transition 2 (v1.x → v2.0):** Distribution becomes measurement-native. Every install contributes sensor data and receives validated updates. The organism improves through operation.
- **Transition 3 (v2.x):** Distribution becomes workload-native. Multiple workload classes are covered by dedicated sensor families. Per-workload preset families emerge.
- **Transition 4 (v3.x and beyond):** Distribution becomes substrate — the platform other projects build against. This is an ecological transition earned through execution quality and time.

The architecture in this paper is sized for Transition 4. The current implementation is at late Transition 0 / early Transition 1. This asymmetry is deliberate: designing for the mature state produces an architecture that does not require rewrite at each stage.

---

## 10. Limitations and Honest Scoping

The work described in this paper has real limitations that matter for how the reader should evaluate it.

**Validation population.** The current validated results are from three hardware configurations — the developer's rigs. Generalization beyond this population is untested. A reader should treat the specific numbers as evidence of what is achievable under measured conditions, not as claims about what every system will see.

**Benchmark coverage.** The current benchmark suite covers network throughput and cold-start inference latency. Other workload dimensions — sustained multi-tenant throughput, memory pressure behavior under load, long-duration reliability — are not yet directly measured. Expanding the benchmark suite is an explicit goal of Transition 2 and beyond.

**Bootstrap-phase dependency on founder commitment.** The architecture's defenses against capture and drift are population-dependent. During the bootstrap phase, with one primary contributor, many of those defenses are inactive. The project is therefore load-bearing on the founder's ongoing commitment during the population-less phase. This is disclosed explicitly rather than hidden. The mitigations — sensor transparency, fork right, progressive devolution of roles — are real but partial and do not eliminate the dependency.

**Unproven at scale.** The sensor-driven selection loop described here has not yet operated at the scale the architecture is designed for. It is proved in principle, implemented partially, and in early operation. A mature software organism at scale does not yet exist; CursiveOS is the first attempt to construct one. Readers evaluating the project should calibrate expectations accordingly.

**Specific claim boundaries.** Claims in this paper are scoped to measured evidence. Where the project's documentation asserts broader claims — for instance, describing CursiveOS as a "self-improving Linux distribution" — the reader should understand those descriptions as referring to the architecture's designed properties, not to currently demonstrated operation. The architecture is designed to self-improve; the current operation is single-contributor with the improvement loop still being assembled.

---

## 11. Relationship to the Software Organisms Framework

The architectural choices described in this paper were worked out within a conceptual framework called "software organisms" — a framework that treats certain kinds of software institutions as governance structures isomorphic to living organisms, with genome, phenotype, sensory system, metabolism, immune function, homeostasis, and reproduction as first-class elements.

The software organism framework is not metaphor. It is the architectural pattern that produced the design decisions in this paper: sensors replacing governance, substrate compounding replacing capital pools, metabolic sensors replacing designed splits, flow compensation matching flow work, fork obligation inheritance enforced by Bitcoin anchoring, separation of deterministic measurement from probabilistic interface.

Readers who want to understand *why* the architecture has these specific properties — and want to evaluate whether the framework applies to other software institutions they care about — should read the companion manifesto: [Software Organisms](software-organisms-manifesto.md).

Readers who want to evaluate *what* the architecture produces in practice and whether it works on specific hardware for specific workloads can evaluate this paper, the validated results, and the public repository, without necessarily committing to the framework.

Both documents describe the same project from different angles. The framework produced the design. The design produced the implementation. The implementation produced the validated results. The results validate the framework, at the current stage, within the current scope.

---

## 12. Conclusion

CursiveOS is, today, a measurement-driven Linux optimization layer for local compute workloads. It applies reversible tunings, measures their effect on the operator's actual hardware, and records results to a shared performance database. On the hardware configurations validated so far, it produces measurable gains in specific benchmark scenarios. The current operation is honest, scoped, and reproducible.

CursiveOS is, in design, the first instance of a software organism — an institution whose continued evolution is governed by sensor-measured fitness rather than discretionary human judgment. The architecture is sized for this mature state. The implementation is in early phase and disclosed honestly.

The current work justifies continued development. The architectural framework justifies the specific design choices being made. Neither yet justifies universal claims. The project's commitment is to produce the validation through operation — expanding the benchmark surface, growing the contributor population, activating the dormant economic machinery, shipping the first installable release — while maintaining measurement rigor and honest scoping throughout.

---

*CursiveOS is a new species that inherited its founding genome from Linux and now evolves independently under its own selection pressure.*

*Companion documents: [Software Organisms manifesto](software-organisms-manifesto.md) · [Layer 5 economics specification](docs/specs/layer5-economics-v3.3.md) · [Agent architecture](docs/architecture/agent-architecture.md) · [Roadmap](ROADMAP.md)*

*Repository: [https://github.com/connormatthewdouglas/CursiveOS](https://github.com/connormatthewdouglas/CursiveOS)*
