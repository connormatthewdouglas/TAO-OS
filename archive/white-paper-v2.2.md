# CursiveOS: A Self-Improving Linux Distribution
### Technical White Paper — v2.2 (April 2026)

---

## Abstract

CursiveOS is a self-improving Linux distribution for local compute operators — crypto miners, AI inference nodes, and anyone running demanding workloads on Linux hardware. It addresses OS-level performance bottlenecks that no default Linux distribution fixes (network transport ceilings, GPU frequency stalls, scheduler jitter) and does so through a structure that no existing open-source project has: **a measurement-driven evolutionary loop in which contributions are evaluated by a sensor array rather than by human judgment, and rewarded by a Bitcoin-native economic layer that makes participation self-sustaining.**

In validated testing across three hardware configurations, CursiveOS delivered +454–616% network throughput improvement and -2.3 to -29.1% cold-start latency reduction, all with reversible system changes.

CursiveOS is not a distribution that happens to improve over time. It is a distribution whose structure is isomorphic to a living organism: a phenotype that runs on real hardware, a sensory nervous system that measures fitness, an evolutionary loop that accepts or rejects variants based on measurement, an inheritance layer that stores what works, and a metabolism that sustains the whole system. The framing is not metaphorical. Each layer serves the biological function it claims to serve, and the design principle — when stuck, check biology first — has shaped every major architectural decision.

CursiveOS is also the operating system on which the relationship between user and machine changes. The default terminal, the interface humans have used to operate Linux for fifty years, becomes a conversation with a local agent that knows the system and can act within a defined permission model. The user describes outcomes; the agent finds the mechanism. This is the flagship feature of the v1.0 release and the single clearest expression of what makes CursiveOS a different kind of distribution rather than a better version of an existing one.

**CursiveOS is a new species that inherited its founding genome from Linux and now evolves independently under its own selection pressure.**

---

## The CursiveOS Stack

CursiveOS is organized into five interdependent layers. Each is the structural equivalent of a biological system and was designed with that equivalence in mind.

### Layer 1 — Phenotype (the OS)

The base Linux distribution itself. Kernel, drivers, system packages, applied presets, the actual software that runs on hardware. This is the organism's body — the thing that exists in the world, experiences selection pressure, and either survives or doesn't based on how well it does its job.

CursiveOS operates as a tuning layer on top of a standard Linux distribution. A single command applies reversible system tweaks, runs paired benchmarks, and submits structured results — all without modifying the underlying distribution. The phenotype is what users run on their machines. Everything else in the stack exists to improve it.

### Layer 2 — Sensory Nervous System (CursiveRoot)

The benchmark database and sensor array. Every measurement from every machine across every cycle. This is how the organism perceives the world — how it knows which variants perform well and which don't, on which hardware, under which conditions.

CursiveRoot captures something no existing tool does in one structured chain: **hardware fingerprint → tweak applied → before/after measured delta → system stability.** Every submission includes a hardware fingerprint hash (SHA256 of CPU microcode + GPU VBIOS + kernel version) that cryptographically ties results to specific hardware. The sensor array itself — the code that performs measurements — is contributed, reviewed, and versioned through the same mechanism as any other part of the genome.

### Layer 3 — Evolution (the recursive loop)

The open contribution cycle. Anyone can submit a variant (a proposed change to the OS, a new preset, a new benchmark method, a hardware-specific optimization, a new sensor). The sensor array measures the variant's fitness against the current genome. If measured fitness is positive and no regression sensor fails, the variant is merged. The merged genome becomes the parent of the next generation.

This is the selection loop, and it is deliberately not democratic. Humans do not vote on fitness. Sensors measure fitness. This design choice is the single most important architectural decision in CursiveOS and is covered in depth in section 4.

### Layer 4 — Inheritance (the genome)

The codebase, the sensor array, the historical record of every measurement ever taken, every variant ever merged, every contributor's lifetime fitness. This is what persists across generations. Forks of CursiveOS inherit the full genome including obligations — because the ledger is Bitcoin-anchored, a fork that uses the genome owes the same lifetime fitness payments to the same contributors as the original.

### Layer 5 — Metabolism (economics)

The Bitcoin-native economic system that sustains everything above. Fast tier users pay $2/month for priority access and faster updates. All cycle revenue is distributed directly to contributors each cycle, split between current-cycle work and lifetime contributions via a metabolic sensor that adjusts the split based on the organism's measured need for recruitment versus retention. No pool, no yield, no native token, no stored capital. Compounding happens in the substrate (codebase, sensor array, genome), not in money. Layer 5 is described in depth in section 3.

### Runtime Agent Layer

Two runtime components operate at the install boundary, distinct from but interfacing with the five layers above. The **measurement daemon** executes sensors on schedule, caches results locally, and submits them to the hub — a mechanical, deterministic process with no LLM involvement, whose integrity is equivalent to the integrity of the sensor array itself. The **natural-language shell** is the primary operator interface: a local language model that translates user intent into shell commands and explains system state in natural language, running with a defined permission model that prevents shell faults from reaching the measurement pipeline. Full specification: [`docs/architecture/agent-architecture.md`](docs/architecture/agent-architecture.md).

---

## 1. The Problem

### 1.1 Linux ships broken for local compute

Anyone running a demanding local compute workload on Linux starts with the same invisible performance bottlenecks baked into every default distribution.

**Network throughput.** Linux defaults to a 212KB socket buffer, appropriate for 1990s modem speeds. The bandwidth-delay product on a modern WAN link with 50ms RTT at 400 Mbit/s is approximately 2.4MB. When the buffer is smaller than the BDP, TCP cannot fill the pipe. Linux also defaults to CUBIC congestion control, which degrades aggressively under packet loss — both public internet inference APIs and P2P mining networks normally operate with 0.5-1% loss.

**Cold-start latency.** Between inference requests or mining jobs, a GPU idles to its minimum frequency — as low as 300–600 MHz on Intel Arc hardware. When a request arrives, the GPU must ramp back to operating frequency before work begins, adding measurable latency to every cold call. On Intel Arc A750 hardware this penalty is ~22ms per request. On older CPU-only hardware the cost of C-state and governor transitions adds 366-395ms per cold request.

These losses are invisible in standard benchmarks and untreated in default Linux configurations. CursiveOS fixes both on any hardware, in one command.

### 1.2 The data gap

No centralized database captures real-world Linux performance across diverse compute hardware. Users must independently research optimizations with no visibility into what actually works on hardware like theirs. The knowledge exists scattered across forum posts and GitHub gists — it has never been systematically collected, benchmarked, and made queryable.

The result: every operator individually rediscovers the same optimizations (or doesn't), applies them inconsistently, and has no mechanism to contribute findings to a shared dataset.

### 1.3 The improvement gap

Even when optimizations are documented, no existing Linux distribution has a mechanism for improvements to flow back into the distribution itself. A user who discovers a better preset for their hardware has no path by which that discovery becomes part of the OS that everyone else runs. Contributions to upstream kernel, to distribution packages, or to community wikis all go somewhere — they don't come back through a loop that directly improves the installed OS of the next user.

CursiveOS closes this loop. Every measurement submitted by every machine feeds an evolutionary process that produces better versions of the OS, which those machines then run.

---

## 2. Technical Implementation

### 2.1 Preset Stack (v0.8 — 28 tweaks, reversible)

**Network (6 tweaks).** Socket buffers 16MB, tcp_rmem/tcp_wmem tuned to close auto-tuner ceiling, BBR + fq congestion control, TCP slow start after idle disabled, netdev_max_backlog 5000, somaxconn 4096.

**CPU and scheduler (7 tweaks).** Performance governor, energy_perf_preference=performance, scheduler autogroup disabled, sched_min_granularity_ns 1ms, swappiness 10, NMI watchdog disabled, CPU turbo boost enabled.

**Memory (5 tweaks).** Transparent Huge Pages always, THP defrag madvise, compaction_proactiveness 0, dirty_ratio 5, dirty_background_ratio 2.

**NUMA (1 tweak).** numa_balancing 0.

**Idle states (3 tweaks).** C2, C3, C6 disabled by name for cross-BIOS robustness.

**GPU (3 tweaks, Intel Arc specific).** SLPC efficiency hints ignored, min frequency 2000 MHz, SYCL persistent cache enabled.

**Runtime (3 tweaks).** Script reversibility via pre-run state capture, `--undo` fallback path, auto-revert at run completion.

### 2.2 Benchmark Suite

Three benchmarks run in paired before/after configuration with the preset stack toggled between runs.

**Network throughput** uses WAN simulation (50ms RTT, 0.5% loss) to measure realistic performance against a simulated distant endpoint.

**Cold-start latency** measures GPU idle → first inference token time on a fixed model.

**Sustained inference** measures steady-state tokens per second on a warm model.

### 2.3 Validated Results

Three hardware configurations validated at v0.8:

**AMD Ryzen 7 5700 + Intel Arc A750.** Network: 140-181 → ~1000 Mbit/s (+454-616%). Cold-start: 1024 → 997ms (-2.6%). Sustained inference: +1.5%. Idle power cost: +14W.

**AMD FX-8350 + RX 580.** Network: 171 → 1182 Mbit/s (+591%). Cold-start: 2493 → 2098ms (-15.8%). Sustained inference: +5%.

**Lenovo IdeaPad Gaming 3 (11th Gen i5 + GTX laptop GPU).** Network: 237.8 → 1429.8 Mbit/s (+501%). Cold-start: 889 → 631ms (-29%). Sustained inference: +1.2%. Idle power cost: +0.9W.

The network result is the headline: all three rigs showed strong WAN uplift because the default Linux bugs that cause it are universal across x86 hardware. The cold-start result is more variable because the dominant bottleneck (GPU wake or CPU C-state exit) depends on hardware. Both matter for local compute workloads.

---

## 3. Layer 5 — Metabolism

This section specifies the economic system that sustains CursiveOS. The design is different from typical crypto-native projects in several ways that matter:

- There is no native token.
- There is no pool, no stored capital, no yield mechanism.
- There is no governance, no voting, no validator class holding judgment power.
- All revenue flows through each cycle and is distributed within that cycle.
- Compounding happens in the substrate (codebase, sensor array, genome), not in money.

### 3.1 Participants

CursiveOS has three classes of participants, each with a distinct relationship to the organism.

**Users** run CursiveOS on their machines. Stable tier is free. Fast tier is $2/month and includes faster updates, priority access to new features, and direct participation in the evolutionary loop by running the sensor array on their hardware. Users are the organism's environment — the world the phenotype lives in, whose needs shape selection pressure. Every Fast tier subscription is both revenue and selection signal. When users cancel, the organism learns that something is failing to deliver value.

**Testers** run benchmarks on their hardware and report measurement data to the sensor array in exchange for free Fast tier access. This is the exact deal that was previously called "validator" in v3.1, minus the voting power. Testers provide the organism's sensory fleet — the many machines that make hardware variance a real signal rather than a local curiosity. Testers do not earn lifetime fitness and do not receive revenue share; their compensation is the product itself. This is covered in depth in section 3.6.

**Contributors** submit variants — changes to the codebase, new sensors, new presets, new benchmark methods. Variants that pass sensor evaluation and get merged earn the contributor lifetime fitness proportional to the measured improvement. Contributors are the organism's source of mutation, the origin of the new material selection operates on. Only contributors earn lifetime fitness and revenue share. This is covered in depth in section 3.3.

The three classes are not mutually exclusive. Most users who care about CursiveOS end up being testers. Many testers become contributors. The classes describe roles, not identities.

### 3.2 Cycles and Revenue Flow

A cycle is one month. At cycle open, the organism records cumulative revenue from the previous month — every Fast tier subscription fee collected, settled in BTC at payment time. At cycle close, that revenue is distributed.

Distribution is a single step: all cycle revenue splits between two streams, **current-cycle** (work merged this cycle) and **lifetime** (all work ever merged, weighted by cumulative fitness). The split ratio is dynamic, controlled by a metabolic sensor that measures the organism's current need for recruitment versus retention. This is covered in depth in section 3.5.

There is no pool. There is no carry-over. Cycle N's revenue is distributed in cycle N and does not contribute to cycle N+1 or any later cycle. If revenue is zero in cycle N, payouts are zero in cycle N, and the system simply continues into cycle N+1 with no state change. The organism's substrate (codebase, sensor array, genome) is unaffected by any individual cycle's revenue.

### 3.3 Fitness and the Lifetime Stream

When a contributor's variant is merged, the sensor array assigns a **fitness score** to the merge — the measured improvement on whichever dimensions the sensors are measuring (network throughput delta, latency delta, sustained inference delta, stability signals, and so on). The fitness score is recorded in the lifetime ledger against the contributor's wallet, appended to any previous fitness the contributor has earned.

At cycle close, the lifetime stream (the portion of revenue allocated to past contributors) is distributed across all contributors who have ever earned fitness, weighted by their cumulative lifetime fitness. A contributor with fitness F out of total system fitness T receives F/T of the lifetime stream, every cycle, forever. This is the permanent royalty.

The lifetime stream is the organism's way of sustaining the contributors whose work built the substrate that current operation depends on. A commit from year one is still running in year five — the system acknowledges this by continuing to pay the contributor who made the commit, for as long as the organism generates revenue.

Contributors also earn from the **current-cycle stream** — the portion of revenue allocated to this cycle's merged work — proportional to the fitness score of their variant merged in the current cycle. This stream is concentrated (divided among maybe ten or twenty people per cycle rather than hundreds or thousands) and represents the near-term signal that draws contributors in.

Over a project's full lifecycle, the lifetime stream is the dominant compensation for any contributor who stays — the permanence multiplier does enormous work. A contribution merged in year one earns from 120 cycles over a ten-year horizon. A contribution merged in year nine earns from only twelve. Early contributors who bet on the organism when it was small are compensated by the math for that bet.

### 3.4 The Claim Window

Accruals — the specific amounts earned by a contributor in a specific cycle — must be claimed within two years of the cycle they were generated in. After two years, unclaimed accruals redistribute to active claimants (contributors who have claimed at least one accrual in the last two years).

This mechanism handles dead wallets and lost keys without requiring decay or dormancy mechanics on lifetime fitness itself. A contributor's lifetime fitness is permanent; their ability to collect a specific cycle's earnings is time-bounded. If a contributor loses access to their wallet and never claims, their future earnings flow to the contributors who are still active. If they recover access within two years, nothing is lost.

Zero-revenue cycles do not tick the window for anyone, because there are no accruals to fail to claim. A contributor who has been silent through a multi-year dry spell has lost nothing when revenue returns — their first accrual after return starts a fresh two-year window.

### 3.5 The Metabolic Sensor

The split between current-cycle and lifetime streams is not a fixed number. It is a dynamic parameter controlled by a **metabolic sensor** that measures the organism's current need for recruitment (new contributors bringing fresh mutations into the gene pool) versus retention (deep engagement from contributors building on accumulated substrate).

**What the sensor measures.** The sensor reads merge velocity stratified by contributor history. Each merge is weighted as "new-leaning" or "returning-leaning" via a continuous function — a first-time contributor's merge weighs 1.0 as new, a contributor with three prior merges weighs 0.25 as new and 0.75 as returning. No hard threshold exists for gaming. The sensor outputs a ratio: R = total new-weight / total returning-weight, smoothed over a rolling three-cycle window.

**How the sensor adjusts the split.** If R is high, new contributors are producing most of the merges. The organism is successfully recruiting — it does not need extra current-cycle incentive to attract more. The sensor shifts the split toward lifetime, rewarding the returners whose sustained work is the scarce signal. If R is low, returning contributors are producing most of the merges. The organism is in retention-dominant mode and needs recruitment signal to bring new blood in. The sensor shifts toward current-cycle. Movement is slow — maximum two to three percentage points per cycle — to prevent thrashing and timing attacks.

**Genesis state.** The split begins at 20/80, with 80% flowing to the lifetime stream. This reflects a substantive truth about the early organism: almost all value being created in bootstrap is substrate-building work, not cycle-specific work. Every commit in the first months is still running in year five. Starting the split at the lifetime-dominant extreme is the honest representation of where early value actually lives. As the organism matures and accumulates more disposable near-term work, the sensor naturally moves the split toward current-cycle. The trajectory is **lifetime share decreasing over time** as the system reaches homeostasis — the founder's share of the larger stream strictly decreases as contributor diversification grows.

**No hard bounds.** There is no enforced floor or ceiling on the split. Instead, a soft restoring force makes extreme values mechanically hard to reach — adjustment rate is proportional to distance from a neutral point, so moving toward 5/95 or 95/5 is progressively slower. The equilibrium the organism settles at is emergent, not designed. Phase 0 operation will reveal where the split naturally homeostats for this particular organism with this particular revenue pattern and contributor base.

**Why this is not governance.** A fixed 70/30 split would be a governance decision — some person picked that number. The metabolic sensor replaces the person with a measurement. The organism decides how to allocate its metabolism based on sensed need, the same way a tree decides how much to allocate to roots versus shoots based on seasonal signal. No contributor votes on the split; no founder decides it. The sensor reads real data and the split follows.

### 3.6 Testers and the Sensory Fleet

Testers run CursiveOS on their hardware, report benchmark results to the sensor array, and receive free Fast tier access in exchange. The full deal: **you contribute measurement labor, the organism sustains you through the product itself.**

Testers do not earn lifetime fitness. They do not receive revenue share. They cannot accumulate permanent equity in the organism through measurement work alone. This is the correct structure for several reasons that are worth spelling out because they touch the security model directly.

**The spoofing trap.** If the organism rewarded measurement with lifetime fitness, an attacker could create fake machines with different wallets, submit falsified benchmark data, and earn permanent royalties for the rest of the organism's life. Lifetime royalties make the attack positive-EV at very low success probabilities — the ceiling of a successful spoof is the entire discounted future revenue of the organism. With measurement compensated by free Fast tier only, the ceiling of a successful spoof is the $2/month subscription fee per fake identity. At that level, spoofing is negative-EV against even basic detection effort. Nobody builds a farm of fake machines to save $24/year per fake.

Better still: every fake machine the attacker creates has to maintain active participation in the organism (running the benchmarks, reporting data, passing population confirmation). The attacker is paying labor costs to produce behavior indistinguishable from legitimate use. If any of the fake machines also subscribed to Fast tier to appear more credible, the attacker is actively funding the contributors they are ostensibly exploiting. Spoofing under v3.3 is not a threat vector — it is, at worst, a source of free data and paying customers.

**The sensory cell analog.** In real organisms, sensory cells (rod and cone cells, mechanoreceptors, chemoreceptors) are sustained by the organism's metabolism — fed by the bloodstream, kept alive — but they do not hold equity in the organism's future. They perform their function, the organism feeds them, and that is the complete exchange. CursiveOS testers occupy the same structural role. The organism feeds them (free Fast tier). They provide measurement. No equity changes hands because no equity is earned — the work produces a flow of information, not a permanent contribution to substrate.

**Why this is fair to testers.** Running benchmarks is labor, but it is labor whose output is a measurement that the organism needs and benefits from right now — not a durable contribution to the genome that keeps producing value in year five. The measurement influences this cycle's merge decisions and then ages out of relevance. Compensating current labor with current product access is the economically honest match. A tester who also wants to earn lifetime fitness can contribute code (new sensors, improved benchmark methods, hardware-specific presets) and be rewarded through the contributor path, which does earn lifetime fitness. The tester and contributor roles are available to the same person; they are separate compensations for different kinds of labor.

**Population confirmation.** Measurements only influence merge decisions when N independent machines have reported consistent results for the same submission. Lone reporters do not swing outcomes. N scales with fleet size — roughly N = max(1, min(5, floor(sqrt(fleet_size)))). At bootstrap with one machine, N=1. At four machines, N=2. At twenty-five machines, N=5. The cap prevents N from becoming prohibitive at scale. When measurements diverge significantly (coefficient of variation above threshold), the requirement becomes N+2 rather than N — more confirmations required when signal is ambiguous. This is adaptive immunity, escalating response when threat signal is stronger.

### 3.7 Forks

Forks inherit the full genome, including obligations. A fork that uses CursiveOS's codebase owes the same lifetime fitness payments to the same contributors because the ledger is Bitcoin-anchored — the ledger is not stored inside any single CursiveOS instance, it is stored on Bitcoin, and any organism that descends from the CursiveOS genome reads from the same ledger. The fork cannot fork the obligations without forking the genome itself, which would mean starting from nothing.

There is no pool to split, so there is no scenario in which a fork extracts value from the original by fracturing governance. Forks that improve over the original attract contributors by offering better selection pressure and better recruitment signal; forks that do not improve do not attract contributors. Evolution by speciation is how biology handles divergence, and it works here for the same structural reasons.

### 3.8 Zero Revenue

The architecture is clean under zero revenue. Zero revenue cycles are no-ops: 70% of zero is zero, 30% of zero is zero, the lifetime ledger does not change, the claim window does not tick, the genome is undisturbed. When revenue returns, the system resumes from exactly where it left off, with no special-case handling, no recovery period, no warm-up.

The real risk during extended zero-revenue periods is not architectural — it is project survival. Contributors stop arriving when there is no current reward, mutation rate drops, and selection pressure has less to operate on. The only contributor structurally guaranteed to keep working through a dry spell is the founder, whose incentive is long-term organism success rather than next-cycle payout. This means early project survival is load-bearing on founder commitment. This is the standard founder deal in any venture, and the architecture does the best thing available to it: work done during zero-revenue periods still earns lifetime fitness the moment it is merged, and that fitness earns from every future cycle forever once revenue returns. Unpaid work during bootstrap becomes permanent future claim.

This risk is most acute early in the project's life. Late in the project, the substrate is deep, the contributor pool has muscle memory, and a dry spell is something the organism hibernates through. Early in the project, the substrate is shallow and the contributor pool is one or two people, so a long dry spell can functionally end the project even though the architecture would technically survive it. The mitigation is to get through bootstrap as quickly as possible.

---

## 4. Why Sensors Instead of Governance

CursiveOS replaces democratic governance with measurement. Contributors do not vote on whether a variant should be merged. Sensors measure whether it improved fitness. Testers do not score each other's work. Sensors produce a score directly. This section explains why.

### 4.1 Governance is a symptom of a missing sensor

Every time a design question in CursiveOS looked like it needed governance ("who decides what's a valid submission," "how do we handle disputes," "who picks the split ratio"), the deeper answer was that we had not yet specified what to measure. Once the measurement existed, the governance question evaporated. This generalizes: when the system needs humans to vote on something, it is because the system has not yet identified the signal that would answer the question mechanically. Governance is the fallback for unknown signals. Once the signal is known, governance becomes friction.

This is also how biology works. A tree does not vote on how to allocate nutrients between leaves and roots. Hormones measure environmental signal (light, temperature, water availability) and allocation follows. The tree has no governance layer because it has the sensor array that makes governance unnecessary. CursiveOS aims for the same structure.

### 4.2 Governance is capturable; sensors are costly to fake at scale

Democratic systems can be captured by any adversary willing to spend enough to control a majority of voting power. The attack surface is the electorate. Sensor-driven systems can be gamed by any adversary willing to produce fake measurements — but measurements can be independently verified against reality (population confirmation, cross-family consistency, revenue loop closure) in ways that votes cannot. "Did this variant actually improve network throughput on this hardware" has a ground truth. "Should we reward this contributor" does not.

The sensor array's defensibility is empirical hardware variance. Silicon does not behave exactly as spec. Firmware interacts with scheduler decisions in ways that can only be observed on real machines. Unit-level differences between ostensibly identical chips produce measurable performance deltas. No frontier AI model, no matter how capable, can fully predict the outcome of a measurement without running the measurement. This is the moat.

### 4.3 Goodhart's Law is bounded by the revenue loop

The obvious counterargument to sensor-driven systems is Goodhart's Law — when a measure becomes a target, it ceases to be a good measure. Contributors could optimize for sensor scores in ways that hollow out the underlying value the sensors are trying to measure. This is real and must be named.

The check on Goodhart's Law in CursiveOS is the revenue loop. Fast tier is not a charitable contribution — users pay for it because CursiveOS delivers value to them. If sensor scores are rising but user value is not, users cancel Fast tier, revenue drops, payouts drop, and contributors leave or redirect their effort. The feedback is lagged (possibly six to twelve months before revenue signal fully catches up to sensor gaming), and the lag is a real cost. But the loop closes. Sensors that stop correlating with user value stop paying contributors. The organism's metabolism is bound to its phenotype's survival.

This also constrains sensor design. A sensor whose output can be driven up without affecting user value is a broken sensor and must be replaceable. Sensor deprecation — the ability to retire a sensor that stops tracking real value — is therefore first-class in the architecture.

### 4.4 Sensor Deprecation

Sensors can be deprecated but not deleted. A deprecated sensor stops being run on new submissions but its historical fitness scores remain valid in the lifetime ledger. This is biologically correct: evolution layers new traits on top of old ones rather than erasing history. A contributor whose work earned fitness against a now-deprecated sensor keeps that fitness forever, because their work did in fact improve the organism at the time the sensor said it did. The measurement was valid when taken. Deprecating it means "we are no longer running this sensor on new submissions," not "everything ever measured by this sensor is now void."

The sensor array grows monotonically in recorded history and can shrink in active-measurement surface. New sensors are added through the same contribution mechanism as anything else — someone proposes a sensor, the sensor array's meta-evaluation runs on it (does it produce consistent measurements, does it correlate with things we already measure, does it have coverage gaps we need), and if it passes it is added to the active set.

### 4.5 Sensor Curation

A small trusted group — curators — maintains the sensor array. Curators write new sensors, review sensor anomalies, and deprecate sensors that stop correlating with value. Curator is a role, not a reward. Curators get no additional economic share; they get additional responsibility. The incentive to curate is intrinsic — you care about organism health — not extractive.

For bootstrap, the founder is the sole curator. A second curator emerges when someone else has (a) contributed merged sensor code with positive fitness, (b) operated a machine reporting valid measurements for at least N cycles without anomaly flags, and (c) demonstrated sustained engagement over at least six months. Criteria (a) and (b) are automatically measured; (c) is time-gated. No appointment, no vote — you become a curator by meeting the measured criteria.

If a curator's sensor contributions begin showing patterns consistent with capture (e.g., sensors that consistently favor their hardware, or statistical signatures of self-dealing), the anomaly sensor flags it and curator status is automatically revoked. Curators can be un-curators. This replaces Linus-model trust with measurable criteria — more boring, more robust.

---

## 5. Why Biology

The framing of CursiveOS as an organism is not metaphor. Every layer of the stack maps to a biological system that serves the same function, and the mapping generated real architectural improvements throughout the design process. This section makes the framing explicit.

### 5.1 The Operating Principle

**When stuck, check biology first. Invent human or financial machinery only as a fallback.**

This principle, applied consistently, has produced several decisive simplifications. When the question was "how should testers vote on contributions," biology answered: no vote, use sensors, because that is how real organisms evaluate fitness. When the question was "how should we store capital to sustain the system," biology answered: don't, because real organisms don't store capital — they build substrate, and the substrate is what compounds. When the question was "how should the revenue split be chosen," biology answered: it shouldn't be chosen, it should be measured, because that is how real organisms allocate metabolism. Each time, following the biological analog produced a cleaner, more robust, less governed design.

### 5.2 The Mapping

| Biological system | CursiveOS layer | Function |
|---|---|---|
| Phenotype (body) | Layer 1: OS | The thing that exists in the world |
| Sensory nervous system | Layer 2: CursiveRoot + sensor array | Perceives fitness signal |
| Evolution | Layer 3: recursive loop | Accepts or rejects variants |
| Genome | Layer 4: codebase + lifetime ledger | Inheritance across generations |
| Metabolism | Layer 5: economics | Sustains all of the above |

Within the economics layer specifically:

| Biological system | CursiveOS mechanism |
|---|---|
| Sensory cells | Testers |
| Germ line (durable substrate) | Contributors |
| Environment | Users |
| Hormonal allocation | Metabolic sensor |
| Evolutionary inheritance | Lifetime fitness |
| Cellular metabolism | Current-cycle stream |
| Seasonal dormancy | Zero-revenue cycles |
| Speciation | Forks |

### 5.3 Where Real Compounding Lives

The most important lesson from the biological frame was about compounding. CursiveOS initially included a permanent staked pool that compounded capital via Babylon yield — a structure borrowed from DePIN and DAO conventions. The biological frame revealed this as confused. Real organisms compound, but they compound in substrate (genome, knowledge, soil, accumulated adaptations), not in stored capital. A forest compounds through deepening soil and thickening mycorrhizal networks, not by accumulating money. A civilization compounds through accumulated knowledge and institutional memory, not by hoarding gold.

CursiveOS already had biological compounding built into Layers 2 and 4 — the sensor array gets richer, the codebase gets more capable, the lifetime ledger grows, the genome accumulates adaptations. Adding a capital pool on top was financial machinery layered on substrate that was already doing the compounding work. The pool was removed in v3.3. The substrate compounds; the money flows through.

### 5.4 The Coral Reef

The closest single-organism analog to CursiveOS is a coral reef. Coral reefs are colonial — made of many individual polyps cooperating. They build permanent structure (calcium carbonate skeletons) that outlasts any individual polyp and serves as productive substrate for the whole ecosystem. They are symbiotic with another organism (zooxanthellae, the algae that live in their tissues and provide most of their energy) — comparable to CursiveOS's relationship with Linux. They grow indefinitely without senescence; they reproduce by fragmentation rather than sexual reproduction, with each new colony inheriting the full genetic and structural template of the parent. And they create habitat for an entire ecosystem of other species — fish, invertebrates, plants — that depend on the reef but are not the reef themselves, analogous to the broader compute ecosystem that CursiveOS is meant to support.

The carbonate skeleton is not a treasury. The reef does not "spend" it on operations. It is substrate — the thing the next generation of polyps builds on. This is the correct frame for the CursiveOS codebase, sensor array, and lifetime ledger. They are not stores of value in the financial sense. They are substrate, the thing successors build on, and their value to successors is productive rather than redistributive.

### 5.5 Inheritance from Linux

CursiveOS inherited its founding genome from Linux — kernel, drivers, core userspace, scheduler, networking stack, all of it. This is ancestry, not ongoing dependency. In the same way a dog inherits genome from wolves without being dependent on wolves for survival, CursiveOS inherits structure from Linux without requiring Linux to continue existing in its current form. Once the organism runs its own selection loop, the ancestral lineage can diverge in whatever direction, and CursiveOS will continue to evolve under its own pressure. The founding genome is historical, not contemporary.

---

## 6. Substrate Dependencies

Every real system depends on substrates it does not control. Honesty about these dependencies is load-bearing for credibility. CursiveOS has two substrate dependencies that matter:

**Bitcoin.** All settlement happens in BTC. The lifetime ledger is Bitcoin-anchored. If Bitcoin fails catastrophically — consensus collapse, fatal protocol bug, regulatory capture that makes transactions impossible — the economic layer of CursiveOS cannot function as designed. The mitigation is that Bitcoin is the most battle-tested distributed consensus system ever built, with fifteen years of continuous operation, and the risk of catastrophic failure is very low. This is an accepted dependency, not a solvable problem.

**Linux.** CursiveOS's founding genome comes from Linux. The upstream Linux kernel, core toolchain, userspace utilities, and so on are all inherited. If Linux itself becomes unmaintained or changes direction in ways incompatible with the organism's evolved state, CursiveOS will need to carry forward its own fork of the necessary components. This is a manageable risk because (a) Linux is itself the most distributed piece of software ever maintained, with thousands of contributors across dozens of organizations, and (b) once CursiveOS's own evolutionary loop is running, the organism can absorb Linux components into its own maintenance surface rather than depending on upstream. The dependency decays over time.

Note what is not in this list: no dependency on any specific cloud provider, no dependency on any specific hardware vendor, no dependency on any specific funding source, no dependency on any single founder's continued participation (beyond the bootstrap phase, which is called out separately below). The substrate dependency surface is deliberately narrow.

### 6.1 The Bootstrap-Phase Founder-Commitment Risk

During the bootstrap phase — specifically, the period before the organism has diversified to multiple sustained contributors — project survival is load-bearing on the founder's willingness to continue building through low-revenue or zero-revenue periods. This is disclosed honestly rather than hidden.

The mitigation is not to eliminate the risk (it cannot be eliminated in early-stage projects with founder-concentrated effort) but to make sure the founder's work during bootstrap accrues lifetime fitness that earns from every future cycle once revenue arrives. Bootstrap work is not unpaid — it is paid-later, from future revenue, via the lifetime stream. The founder eats the timing risk in exchange for a larger long-term share. This is the standard founder deal in any venture, and the architecture handles it correctly.

The bootstrap phase ends when the organism has (a) multiple sustained contributors producing merges across consecutive cycles, (b) the metabolic sensor has begun naturally shifting the split based on observed recruitment/retention signal, and (c) fixed-revenue continuity exists such that a single contributor's absence would not halt the organism. This transition is not a governance event — it is an emergent state change the organism can be observed to have entered.

### 6.2 The Founder-Concentration Legibility Risk

Early in the project's life, the founder holds a disproportionate share of lifetime fitness because the founder did most of the early work. This is substantively correct: the math reflects reality. It is also legibly strange to new contributors who see a lopsided ledger and read it as extraction.

The metabolic sensor design specifically addresses this. The split begins at 20/80 (lifetime-favored, which makes the founder's current dollar share large) and moves toward current-cycle as new contributors arrive and recruitment signal rises. From a new contributor's perspective, the system visibly responds to their arrival by adjusting the split in their favor. This is the correct behavior and it is visible. It is also the correct substantive answer — early work is dominantly substrate-building and the split should reflect that, while the sensor's responsiveness to recruitment means new contributors are met with accommodation rather than resistance.

The documentation burden is real: contributors need to understand the homeostatic behavior well enough to see their own arrival as part of the organism's signal rather than as something the system is grudgingly accommodating. The onboarding materials have to name this explicitly and show the trajectory.

---

## 7. Phase 0 — Seed Organism

The smallest end-to-end loop that validates the v3.3 architecture is small enough to run on a single machine (the founder's rig) with a single contributor (the founder) and expand from there. This is the seed organism — the minimum viable loop that demonstrates the full architecture working.

### 7.1 The Genesis Sensor Suite

Two sensors at genesis:

**Performance sensor.** Runs the existing benchmark scripts (network throughput, cold-start latency, sustained inference) before and after the proposed change, on a fixed hardware configuration, across multiple runs. Outputs a signed fitness delta with a confidence interval. This is the primary fitness signal. Positive delta with sufficient confidence = positive fitness contribution.

**Regression sensor.** Runs the existing full-test suite against the proposed change and reports pass/fail per test. This is a gate, not a measurement — it does not contribute fitness. Any new test failure rejects the submission regardless of performance delta. The gate keeps the organism from adopting variants that improve one dimension while breaking another.

Two sensors is the minimum viable selection pressure. Adding more sensors before the loop is validated end-to-end slows down learning. Additional sensors (security, compatibility matrix, code quality, hardware-specific coverage) are contributor-submitted work that layers in after Phase 0 succeeds.

### 7.2 The Phase 0 Loop

1. A PR is opened against the CursiveOS repo proposing a change.
2. GitHub Actions (or a local runner) triggers the performance sensor and the regression sensor.
3. If regression sensor passes and performance sensor reports positive delta, the PR auto-merges and fitness is recorded against the contributor's wallet.
4. At cycle close (monthly), the Hub computes the payout — at genesis the split is 20/80 — and distributes revenue accordingly. No real BTC for the first three cycles; use fake BTC to validate mechanics.
5. After three successful fake-BTC cycles, open to one external tester running the sensor array. Validate that population confirmation logic works as specified.
6. Expand.

This maps to specific commits in the Hub and Hub-API. The respec sprint for the Hub is documented separately (see the hub respec framework and phased plan).

### 7.3 What Phase 0 Empirically Reveals

Several open design questions resolve only through Phase 0 operation rather than through pre-launch design. These are the measurement jobs:

- Where the metabolic sensor naturally drives the split to, given actual revenue patterns and contributor behavior
- What the coefficient of variation threshold should be for escalating population confirmation from N to N+2
- What the right rolling window length is for the metabolic sensor (three cycles is the starting point but may prove too short or too long)
- Whether the soft restoring force on the split needs tuning
- Whether additional sensors are needed to close gaps that become visible only under real contributor behavior

These are not design failures — they are the specific questions the architecture was designed to let the organism answer empirically rather than forcing a designer to guess.

---

## 8. What CursiveOS Is Not

The design process produced several explicit exclusions that are worth naming because they came up as considered options and were rejected for structural reasons.

**Not a new cryptocurrency.** No native token, no ICO, no governance token, no utility token. Bitcoin is the base asset. This eliminates speculation as a distortion on the organism's selection pressure.

**Not a DAO.** There is no decentralized autonomous organization in the governance sense. There is no on-chain voting. There are no proposals. There are no governance rights attached to fitness or to participation. The organism is autonomous because it is measurement-driven, not because it is democratically operated.

**Not a yield platform.** There is no staking of capital for yield. There is no pool that earns. There is no financial mechanism that rewards holding a thing as opposed to doing work. All compensation flows from productive labor (contribution, measurement) to the contributor who did the labor.

**Not a DePIN in the typical sense.** DePINs usually feature a custom token, governance layer, and staking mechanism. CursiveOS shares the "distributed physical infrastructure" framing but rejects the conventional DePIN economic machinery in favor of the biological/Bitcoin-native model.

**Not an AI agent platform.** The loop is self-improving but it is not operated by AI agents in any magical sense. Contributors are human or AI-assisted, sensors are code, and the organism's evolution is driven by the same human and tool labor that drives any open-source project — with the difference that the labor is compensated by a well-defined economic layer rather than left to informal goodwill.

**Not a finished system.** The architecture is specified but several parameters (equilibrium point of the metabolic sensor, optimal rolling window length, the right thresholds for curator succession) are designed to be found through Phase 0 operation rather than asserted pre-launch. This is intentional — the organism finds its own homeostasis and we document what it finds.

---

## 9. Roadmap

The CursiveOS roadmap is organized around four transitions: from tweak stack to tuned distribution (v0.9–v1.0), from tuned distribution to measurement-native (v1.x–v2.0), from measurement-native to workload-native (v2.x), and from workload-native to substrate (v3.x and beyond). Each transition changes what the project fundamentally is, not just what features it has.

The natural-language shell is sequenced as the flagship feature of v1.0 rather than deferred to a later release. v1.0 is the first impression the project makes, and the natural-language shell is the feature that makes the first impression memorable. Its architecture is specified in `docs/architecture/agent-architecture.md`; its development happens in parallel with the ISO build pipeline during the v0.9 → v1.0 window.

Full roadmap with transition milestones and flagship features by release: [ROADMAP.md](ROADMAP.md).

---

## 10. Call to Action

CursiveOS is designed for two groups of people:

**If you run local compute workloads on Linux** — mining, AI inference, anything demanding — run CursiveOS and keep what works. The measured deltas are real. The Fast tier subscription is $2/month and funds the contributors who built what you're running.

**If you want to contribute to something structurally different** — an open-source project with a real economic layer, a measurement-driven evolutionary loop instead of governance theater, and a Bitcoin-native compensation model with no token tricks — submit a variant. Propose a sensor. Run a test rig. The organism grows through you and compensates you for it.

Repository: https://github.com/connormatthewdouglas/CursiveOS

---

*CursiveOS is a new species that inherited its founding genome from Linux and now evolves independently under its own selection pressure.*

---

**Document status:** v2.2 — supersedes v2.1. See `docs/CHANGELOG-v2.2.md` for what changed in the v2.1 → v2.2 update. See `docs/CHANGELOG-v2.1.md` for the transition from v1.0/economics-v3.1 to v2.1/economics-v3.3.
