# Hardening

**Status:** ACTIVE
**Date:** 2026-04-17
**Paired documents:** [`layer5-economics-v3.3.md`](../specs/layer5-economics-v3.3.md), [`testers.md`](testers.md), [`sensor-array.md`](sensor-array.md)

This document enumerates the known risks, attack surfaces, and substrate dependencies of CursiveOS's architecture. It is written in the tradition of honest disclosure: naming load-bearing elements that cannot be fully eliminated rather than pretending the architecture has no weaknesses. The best architectures name their risks accurately; the worst pretend they have none.

---

## 1. Substrate Dependencies

Every system depends on substrates it does not fully control. CursiveOS's substrate dependencies are deliberately minimal but real.

### 1.1 Bitcoin

All settlement happens in BTC. The lifetime fitness ledger is Bitcoin-anchored. Accrual claims become Bitcoin transactions.

**Failure modes:**

- **Consensus failure.** The Bitcoin network partitions or experiences a 51% attack that invalidates recent history. Very low probability after 15 years of continuous operation; not zero.
- **Fatal protocol bug.** A previously undetected bug in Bitcoin causes catastrophic loss of funds or permanent consensus break. Low probability; Bitcoin is among the most scrutinized software in existence.
- **Regulatory capture.** A sufficiently powerful state actor makes Bitcoin transactions illegal or infeasible in most jurisdictions. Low-to-moderate probability over long horizons; variable by jurisdiction.
- **Economic collapse.** Bitcoin's market value collapses to near-zero. Hurts contributor earnings in USD terms but does not break the organism's mechanics — payments still settle, just at smaller USD values.

**Mitigation:**

There is no architectural mitigation for Bitcoin failure. The organism is Bitcoin-native by design. This is an accepted dependency, not a solvable problem. The choice of Bitcoin over alternatives (Ethereum, stablecoins, Lightning, custodial dollars) was deliberate: Bitcoin is the most battle-tested, least-governed, most-liquid settlement substrate available, and its 15-year track record of survival through hostile environments is itself a form of hardening.

### 1.2 Linux

CursiveOS inherited its founding genome from the Linux ecosystem. The kernel, toolchain, core userspace, and driver stack are all upstream. The organism cannot function without a Linux-compatible base.

**Failure modes:**

- **Upstream fragmentation.** Linux kernel development splits into incompatible forks and CursiveOS's evolved state is no longer compatible with any of them. Low probability; Linux's governance has weathered much larger stresses than this would be.
- **License change.** Linux relicenses away from GPLv2 in a way that restricts CursiveOS's ability to ship derivative works. Very low probability (requires unanimous assent from all copyright holders, effectively impossible).
- **Hostile upstream maintainers.** Key upstream maintainers actively remove features CursiveOS depends on. Moderate probability for specific features; negligible for the kernel as a whole.
- **Obsolescence.** Linux is displaced by a successor operating system over decades. Possible but slow; the organism would have time to absorb its dependencies or migrate.

**Mitigation:**

The dependency on Linux decays over time. Early in the organism's life, every kernel update, driver change, and glibc revision affects CursiveOS directly. As CursiveOS accumulates its own adaptations — preset stacks, custom kernel patches, specific hardware optimizations — the distance from pure upstream grows. In the limit, CursiveOS could carry forward its own fork of any component it needs. This is the dog/wolf relationship discussed in `biological-architecture.md` section 5: ancestry, not dependency.

Note what is **not** in this substrate-dependency list:

- No cloud provider (hub runs on standard infrastructure, replaceable).
- No hardware vendor (the organism explicitly targets multiple vendor stacks; single-vendor capture is impossible by design).
- No single funding source (revenue comes from users, distributed globally).
- No founder beyond the bootstrap phase (covered in section 3).

---

## 2. Attack Surface

This section enumerates the attack patterns considered during design and the defenses each attack runs into. It is written assuming attackers are sophisticated, patient, and well-resourced — because that's the adversary profile the architecture has to survive.

### 2.1 Spoofing: Fake Machines to Earn Lifetime Fitness

**Attack:** Attacker spins up N fake machines (different VMs, different hardware fingerprints), binds each to a different wallet, runs measurements or fabricates measurement data, accrues lifetime fitness against each wallet, earns from the lifetime stream every cycle forever.

**Why it's dangerous:** Lifetime compensation means a single successful spoof pays out indefinitely. At a 10% discount rate, a permanent stream of $X has present value $10X. The attacker only needs the attack to be positive-EV in expected-present-value terms.

**Defense:** This attack is structurally eliminated in v3.3. Testers do not earn lifetime fitness. The most the attacker can extract per fake machine is the Fast tier rebate ($2/month = $24/year per fake). At that ROI, no spoofing farm is worth building. See [`testers.md`](testers.md) section 2 for the full analysis.

**Bonus property:** A spoofer who also pays for Fast tier on their fakes (to appear more credible) is paying subscription fees into the contributor pool. They are actively funding the contributors they are trying to exploit. The attack, in its worst realistic form, is net-positive for the organism.

### 2.2 Spoofing: Fake Contributors to Game the Metabolic Sensor

**Attack:** Attacker creates many "new contributor" wallets to inflate R_meta, shifting the metabolic sensor toward the current-cycle stream and attempting to capture near-term rewards through fake identities.

**Defense:** Fake contributors must submit code that passes the regression gate and produces positive fitness. If the code is genuine, the attack produces value for the organism (the code gets merged and improves things). If the code is garbage, it fails the sensor evaluation and contributes no signal to R_meta.

The attack trap: either the fake contributors produce real value (attack fails to gain anything because the "fake" contribution is actually real) or they produce garbage (attack fails because the garbage doesn't merge). There is no configuration in which the attack extracts without also contributing.

Additionally, current-cycle rewards flow to the accepted variants that actually produced measured fitness. The attacker cannot extract through fake identity alone; they must produce mergeable, positive-fitness work. If they do, the "attack" has created value for the organism.

### 2.3 Spoofing: Fake Contributors to Game the Current-Cycle Stream

**Attack:** Attacker with existing wallets produces many small merges to drive R_meta low, shifting the split toward lifetime and benefiting themselves as an existing lifetime-fitness holder.

**Defense:** Same as 2.2 — merges must pass the regression gate and produce positive fitness. Low-value spam merges fail both. The only merges that count toward R_meta are ones that improved the organism.

The subtler variant: delay real merges to bunch them in cycles where the attacker wants to manipulate R_meta. The defense here is the 2.5-percentage-point-per-cycle rate limit on split movement, combined with the three-cycle rolling window. A single cycle of bunching moves the split by at most 2.5 points, which is probably worth less than the timing coordination cost.

### 2.4 Measurement Fabrication

**Attack:** A tester reports fabricated measurement data without running the actual sensor, collecting the Fast tier rebate for no real work.

**Defense:** Population confirmation. Fabricated measurements must align with real measurements from other machines. An attacker who doesn't actually run the sensor cannot know what the real measurement will be, so they either:

- Report something plausible (middle of the expected distribution) — which is effectively indistinguishable from a real measurement and doesn't distort the aggregate.
- Report something implausible — which is flagged by immune sensors as an outlier.
- Actually run the sensor — which defeats the purpose.

The worst case from the organism's perspective is "plausible-seeming fabrication that doesn't distort the aggregate" — and that case is operationally indistinguishable from a real measurement, so no harm is done.

### 2.5 Collusion Between Contributors and Testers

**Attack:** A contributor pays a tester off-chain to report favorable measurements for the contributor's submissions. The tester's measurements swing the aggregate, the contribution merges with inflated fitness, the attacker earns lifetime fitness.

**Defense:** Population confirmation dilutes any single tester's influence. For the collusion to affect the aggregate meaningfully, the attacker must have corrupt testers as a significant fraction of the population confirmation set. This is possible when the fleet is tiny (< 10 machines) and becomes rapidly harder as the fleet grows.

**Bootstrap-phase mitigation:** During the early low-fleet period, the founder manually reviews merges that are flagged by anomaly sensors. Immune sensor thresholds are tuned conservatively (more false positives, fewer false negatives). Once the fleet crosses a size threshold (estimated: 10-20 active testers), manual review is phased out.

**Structural backstop:** The revenue loop. If compromised sensors accept bad contributions, users experience worse software, Fast tier renewal rates drop, revenue declines, and the attack pays less over time. This feedback is lagged (6-12 months) but it closes — long-term collusion is uneconomic because it destroys the revenue it depends on.

### 2.6 Curator Capture

**Attack:** A curator introduces sensors that systematically favor their own hardware, their own prior contributions, or a specific coalition's interests.

**Defense:** Multi-layer.

- Immune sensors (section 2.3 of `sensor-array.md`) specifically detect self-dealing patterns — sensor contributions correlating with the curator's own fitness earnings, or sensor changes that advantage the curator's specific hardware fingerprint.
- Curator status is automatically revoked when anomaly flags accumulate beyond a threshold.
- Other curators (once the role is not singleton) provide peer review and can flag capture patterns manually.
- The revenue loop backstop: captured sensors eventually decorrelate from user value; revenue declines; captured curator loses income.

**Bootstrap-phase caveat:** During the single-curator phase (founder is the only curator), the immune sensors' self-dealing detection is the primary defense. All sensor code is public and auditable; the founder's sensor contributions are in the same repo as everything else, and any community member can identify patterns of self-dealing even if they can't vote to remove the curator.

### 2.7 Goodhart's Law

**Attack:** Not a malicious attack but a systemic failure mode. Contributors optimize for sensor scores in ways that diverge from underlying user value. Sensors report high fitness; users experience no improvement; the organism is drifting.

**Defense:** The revenue loop closes Goodhart automatically. If sensor scores are up but user value isn't, Fast tier renewal rates drop, revenue drops, payouts drop, contributors leave or redirect their efforts.

**Lag risk:** The revenue signal can take 6-12 months to reflect sensor gaming. That is 6-12 cycles of distorted payouts before the correction starts. This is a real cost and is disclosed honestly.

**Secondary defense:** Sensor deprecation. When immune sensors (specifically the revenue-correlation detector) flag a sensor as decorrelated from user value, that sensor is deprecated. Future fitness is no longer measured against it. Historical fitness is preserved (see `sensor-array.md` section 7.2).

**Design implication:** Sensors must be designed to stay as close as possible to actual user-experienced value. Abstract sensors (e.g., "code complexity") that do not map to concrete user outcomes are the highest Goodhart risk. Concrete sensors (e.g., "cold-start latency measured on real hardware") are the lowest risk.

### 2.8 Adversarial Selection via Sensor Gaming

**Attack:** A contributor produces submissions specifically engineered to score high on the current sensor set without providing real user value. This is the general Goodhart problem in its deliberate form.

**Defense:** Same as 2.7, plus: sensor diversity. Having multiple sensor families (performance, regression, immune, behavioral) makes it harder to game one without failing another. A submission that optimizes the network throughput sensor but introduces a regression (caught by the regression gate) or shows behavioral anomalies (flagged by the immune system) will fail the merge.

The revenue loop is the final backstop. Elaborate gaming is expensive; the organism's selection pressure eventually punishes gamers by routing revenue away from them.

### 2.9 DoS via Submission Flood

**Attack:** An attacker floods the Hub with submissions, consuming sensor array compute resources and blocking legitimate contributors.

**Defense:** Per-wallet rate limiting (no more than N submissions per cycle from a single wallet). Per-IP rate limiting at the Hub API layer. Anomaly detection on submission patterns. None of these prevent the attack entirely but they cap the damage. No lifetime-fitness is granted to failed submissions, so the attacker gains nothing.

### 2.10 DoS via Tester Flood

**Attack:** Attacker registers many tester wallets to flood the measurement infrastructure with noise.

**Defense:** Rate limiting, hardware fingerprint validation, anomaly detection. Since there is no direct economic reward for the attacker (no lifetime fitness), the attack is pure vandalism. Vandalism is bounded by the attacker's patience; defensive costs scale slower than attack costs.

### 2.11 Wallet Compromise

**Attack:** A contributor's wallet key is stolen. The attacker claims the contributor's pending accruals and redirects future claims to an attacker-controlled address.

**Defense:** Standard Bitcoin wallet hygiene — not really an organism-level attack, an individual user attack. The organism cannot prevent this; it can only support recovery.

**Recovery:** None built into v3.3. A compromised contributor's lifetime fitness stays at the compromised wallet because the lifetime ledger is Bitcoin-anchored and the ledger is the source of truth. The contributor can manually bind a new wallet and continue earning from future merges, but past fitness is effectively stuck.

This is a known limitation. A future version may add a dispute window or a multi-sig-based key rotation mechanism, but any such mechanism would have to be sensor-driven (not governance-driven) and the design is not yet clear enough to commit.

### 2.12 Fork-Based Exit Attack

**Attack:** A disgruntled contributor forks the codebase and claims the fork is the "real" CursiveOS, attempting to redirect revenue from the original to the fork.

**Defense:** The lifetime ledger is Bitcoin-anchored. A fork that uses the genome inherits the obligations — it cannot redirect payments away from existing lifetime-fitness holders because those payments are indexed by the Bitcoin ledger that both instances read from.

A fork could theoretically create its own Bitcoin-anchored ledger starting from scratch, but that would be starting a new organism with zero accumulated substrate — no accumulated codebase beyond the fork point, no sensor array beyond what the fork inherits, no lifetime ledger. The fork is competing with the original on equal footing from that point forward, not extracting value from the original.

---

## 3. Bootstrap-Phase Founder-Commitment Risk

### 3.1 The Honest Disclosure

During the bootstrap phase — the period before the organism has diversified to multiple sustained contributors — project survival is load-bearing on the founder's willingness to continue building through low-revenue or zero-revenue periods.

This cannot be eliminated by architecture. It is a feature of early-stage projects with founder-concentrated effort. No economic mechanism can pay contributors who aren't there; no incentive structure can sustain an organism that no one is building.

### 3.2 Why It Is Not Eliminated by the Lifetime Stream

The lifetime stream mitigates the risk but does not eliminate it. Work done during bootstrap earns lifetime fitness the moment it merges, and that fitness earns from every future cycle once revenue arrives. Unpaid work during bootstrap becomes permanent future claim.

But this only works if the founder keeps working through the period when there is no current reward and no near-term expectation of one. If the founder stops, no amount of architectural elegance in the lifetime stream saves the project — there is no substrate being built and no one to pay later.

### 3.3 Exit Conditions

The bootstrap phase ends when the organism reaches several emergent properties simultaneously:

1. **Multiple sustained contributors** — at least 3-5 wallets producing merges across consecutive cycles, each independently of the others.
2. **Metabolic sensor actively adjusting** — the split has begun moving from the genesis 20/80 state in response to observed recruitment/retention signal.
3. **Non-zero fixed-cost absorption** — the organism is generating enough revenue to cover essential infrastructure (Hub hosting, Bitcoin transaction fees) without founder subsidy.
4. **Single-point-of-failure removal** — the founder's absence for a multi-cycle period would not halt the organism.

None of these are governance events. They are observable states the organism can be determined to have entered.

### 3.4 Mitigation Strategy

The architectural response to bootstrap risk:

- **Minimize bootstrap duration.** Structure the project to reach the exit conditions as fast as possible. This is why the Phase 0 seed organism plan (see `white-paper.md` section 7) aims for end-to-end loop validation on a single machine in a few cycles rather than a multi-month development cycle.
- **Reduce fixed costs.** The organism runs on commodity hosting, uses no proprietary infrastructure, and has minimal external dependencies. Dry-period operating costs are as close to zero as possible.
- **Honest disclosure.** This document. Anyone considering investment of time or money in CursiveOS should know this risk exists. Hiding it would be a trust failure.

---

## 4. Founder-Concentration Legibility Risk

### 4.1 The Problem

Early in the organism's life, the founder holds most of the lifetime fitness because the founder did most of the early work. This is substantively correct. It is also legibly strange to new contributors who see a lopsided ledger and read it as extraction.

A new contributor arriving at cycle 10 who sees "founder: 95% of lifetime fitness, everyone else: 5% combined" might reasonably wonder whether they can ever earn a meaningful share, whether the system is fair, whether the founder's large position is a red flag.

### 4.2 How the Metabolic Sensor Addresses This

The metabolic sensor starts the split at 20/80 (lifetime-favored) and moves it toward current-cycle as new contributors arrive and drive R_meta up. From a new contributor's perspective, the system **visibly responds to their arrival by shifting the split in their favor**. Their first few merges directly influence the sensor, and they can see the split move.

This is the correct substantive behavior — early work is dominantly substrate-building and the split should reflect that, while the sensor's responsiveness to recruitment means new contributors are met with accommodation rather than resistance. It is also the correct messaging: the system is on the new contributor's side.

### 4.3 What Can't Be Fixed

The math of lifetime fitness is what it is. A contributor who arrives at cycle 10 is by definition 10 cycles late relative to contributors who arrived at cycle 1, and their lifetime-fitness accumulation starts from zero. Over time, their fitness share grows as the total fitness pool grows and as the original contributors' relative share dilutes. But there is no way to give a newcomer a retroactive stake in the first 10 cycles of work; doing so would require taking fitness away from people who earned it, which would be unjust and would also erase the lifetime stream's core promise (permanent, append-only, never revoked).

The honest answer to the newcomer is: "You are joining at cycle 10. You will earn from cycle 10 forward, proportional to the fitness you contribute. Over the organism's full horizon, your cumulative earnings depend on how long the organism lives and how much fitness you contribute. The math is fair going forward. It cannot be fair backward because backward would require revoking earned fitness, which is something the architecture specifically protects against."

### 4.4 Documentation Burden

Onboarding materials must explicitly name the founder-concentration situation, the metabolic sensor's response to newcomer arrival, and the math of lifetime accumulation over long horizons. A newcomer who understands the architecture will not read concentration as extraction; a newcomer who does not understand will.

This is a documentation load-bearing element and it cannot be mechanically automated. Someone has to write the onboarding, keep it updated, and make it legible. Currently that's the founder. As the organism grows, it becomes a contributor-community responsibility.

---

## 5. Risks That Are Accepted Without Mitigation

A complete honest disclosure requires naming the risks the architecture accepts without any mitigation. Pretending these are solved would be dishonest.

### 5.1 Catastrophic Upstream Bitcoin Failure

If Bitcoin fails catastrophically, the economic layer of CursiveOS does not work. There is no fallback to another settlement substrate. This is accepted.

### 5.2 Long-Duration Zero-Revenue with Founder Exit

If the founder stops working during bootstrap and no other contributors have entered, the organism stops. This is accepted. Architecture cannot compensate for founder absence during founder-concentrated phase.

### 5.3 Small-Fleet Population Confirmation Compromise

During the early tester-fleet period when fleet size is small, population confirmation is weak (N=1 or N=2). A single bad actor can swing aggregate measurements. Manual founder review mitigates this but does not eliminate it. This is accepted as a bootstrap tradeoff.

### 5.4 Long-Horizon Institutional Capture

Over decades, any sufficiently-valuable institution faces capture attempts from sophisticated adversaries (states, large corporations, organized crime). CursiveOS's defenses (measurement-driven, distributed, open) are strong against the attacks we can currently enumerate. Novel attack patterns over very long horizons are unpredictable. The best defense is keeping the architecture legible and the sensor array independently auditable, which remains in place.

### 5.5 Foundational Design Error

The architecture as specified may have a design error that neither the author nor stress-testers have identified. This is always possible in any system. The mitigation is openness to revision — v1.0 → v3.3 represents nine major revisions responding to identified problems, and the architecture will continue to evolve as Phase 0 operation surfaces issues. The change history in `docs/CHANGELOG-v2.1.md` is the honest record of what has been changed and why.

---

## 6. Change History

- **v2 (2026-04-17):** Updated for v3.3. Removed Babylon-pool risk section entirely. Added tester-related attack surface analysis and the spoofing-trap architecture. Added bootstrap-phase founder-commitment risk as explicit honest disclosure. Added founder-concentration legibility risk with metabolic sensor mitigation. Added sensor-curator capture analysis.
- **v1 (2026-04-05 era):** Original hardening doc under v3.1 economics with pool and Babylon risk sections. Obsolete.
