# Testers

**Status:** ACTIVE
**Date:** 2026-04-17
**Paired documents:** [`layer5-economics-v3.3.md`](../specs/layer5-economics-v3.3.md), [`sensor-array.md`](sensor-array.md), [`biological-architecture.md`](biological-architecture.md)

---

## 1. What a Tester Is

A **tester** is any participant who:

1. Has a wallet bound to the Hub.
2. Has a machine registered with a valid hardware fingerprint.
3. Reports measurements from active sensor runs each cycle.
4. Passes anomaly detection (measurements are statistically consistent with the fleet).

In exchange, the tester receives **free Fast tier access** for the duration they remain in good standing. Fast tier is otherwise a paid subscription at $2/month; for testers, the subscription fee is rebated each cycle.

Testers do **not** earn lifetime fitness. Testers do **not** receive revenue share. The complete compensation for measurement labor is free product access.

This is the exact exchange that was previously called "validator" in v3.1 minus the voting power. The v3.1 validator role did two different jobs: **measurement** (running benchmarks on real hardware) and **judgment** (voting on which contributions to accept). v3.3 dissolves the voting function (sensors measure fitness, no votes are cast), but the measurement function survives intact — it was never the governance-y part. The word "validator" is retired because it implies judgment authority that no longer exists. "Tester" describes the remaining function accurately.

---

## 2. The Spoofing Trap

The most important structural reason testers do not earn lifetime fitness is defensive, and it deserves its own section because it is the single biggest security consideration in the economic architecture.

### 2.1 The Attack

Suppose testers earned lifetime fitness. An attacker could:

1. Spin up N fake machines (different VMs, different hardware fingerprints).
2. Bind each to a different wallet.
3. Run the sensor array (or a convincing simulation of it) on each.
4. Report measurements that pass population confirmation.
5. Each fake machine accrues lifetime fitness.
6. Every fake wallet earns from the lifetime stream every cycle forever.

### 2.2 Why Lifetime Compensation Breaks the Math

In a one-shot reward system, the attack ROI is bounded by what the attacker can extract this cycle. If the defenses are good enough that expected extraction per fake machine per cycle is less than the cost of maintaining the fake machine, the attack is negative-EV and doesn't happen.

Lifetime royalties change this calculation. A single successful spoof pays out for as long as the organism generates revenue — ten years, twenty years, forever. Even if the expected extraction per cycle is small, the present value of an infinite annuity at even a modest discount rate is much larger than any single-cycle extraction.

Specifically: at a 10% annual discount rate, a permanent stream of $X per year has a present value of $10X. At 5%, $20X. The attacker only needs the attack to be positive-EV in expected-present-value terms to proceed, and the permanence multiplier makes this true at much lower success probabilities than would be acceptable in a one-shot system.

Defense that relies on "make successful spoofing rare enough" fails against lifetime-compensated measurement, because "rare enough" requires much stronger defenses than it does against one-shot compensation.

### 2.3 Why Product-Access Compensation Restores the Math

When testers are compensated only with free Fast tier access ($2/month), the attack ROI per fake machine is strictly bounded:

- Maximum benefit per fake machine: $2/month in avoided subscription fees.
- Annual maximum: $24/fake/year.
- Over any horizon, discounted or not: $24/fake/year.

Compared to even a trivial spoofing defense (IP tracking, hardware fingerprint diversity requirements, measurement anomaly detection), this ROI is negative. Nobody builds a farm of fake machines to save $24/year per fake.

Better still, a tester who also wants to look credible might pay for real Fast tier subscriptions on some machines. At that point the attacker is paying $24/year per fake machine into the contributor pool — actively funding the contributors they would ostensibly be exploiting. Spoofing under v3.3 is, in the worst case, a revenue source for the organism, not a threat.

### 2.4 The Compensation-Shape Principle

The underlying principle: **match the compensation shape to the work shape.**

Measurement is a flow — information produced now that is useful now and stops being relevant relatively quickly. Old measurements age out; the organism needs fresh measurements every cycle. The work done by a tester this cycle does not compound into substrate that keeps producing value in year five.

Code contribution is a stock — durable substrate. A commit merged today is still running in year five, still contributing to fitness, still part of the genome. The work compounds.

**Compensate flows with flows; compensate stocks with stocks.** Product access is a flow (you get it while you work for it); lifetime royalties are a stock (you have equity in the organism's future). Testers produce flow; contributors produce stock. The shapes match.

Violating this principle in either direction creates distortion. If you compensated contributors with only current product access (flow), they would have no reason to build substrate — their commits would still produce value in year five but they wouldn't be paid for it, so they wouldn't make them. If you compensate testers with lifetime royalties (stock), the math of the attack surface breaks and the organism is vulnerable to spoofing.

### 2.5 The Biological Analog

In real organisms, sensory cells are sustained by metabolism — fed by the bloodstream, kept alive, temperature-regulated — for as long as they perform their sensing function. They do not hold equity in the organism's future reproduction; they are not in the germ line. When a sensory cell dies or is replaced, there is no "inheritance" event where the cell's heirs continue receiving metabolism on its behalf.

Germ-line cells (sperm and egg precursors, stem cells) are different. Their product is inheritance itself — the cell's genome contributes to future generations. The organism's entire reproductive system exists to sustain and propagate germ line.

The two compensations are structurally different because the two functions are structurally different. Testers are sensory cells. Contributors are germ line. This is not an analogy imposed on the architecture; it is the architecture.

---

## 3. Testers and Users Are Different

A tester is not a Fast tier user. A Fast tier user pays for Fast tier. A tester receives Fast tier as compensation for measurement labor.

From the revenue-flow perspective:

- **Fast tier user** → pays $2/month → revenue into cycle pool → distributed to contributors.
- **Tester** → performs measurement labor → receives $2/month rebate → no net revenue to cycle pool from this wallet.

The tester's wallet appears in both the subscription ledger (as a Fast tier user) and in the rebate ledger (as a tester being compensated). The net effect is zero — tester is net-neutral to the economic layer. The tester's contribution is the measurement data, not the subscription fee.

### 3.1 Tester vs. Fast Tier User in Practice

From the organism's perspective, most people will fall into one of three patterns:

1. **User only.** Pays for Fast tier or uses Stable tier, does not run benchmarks. Net positive revenue contributor if on Fast tier.
2. **Tester only.** Runs benchmarks, receives free Fast tier, does not also pay for Fast tier. Net-neutral revenue contribution.
3. **Contributor.** Submits code. Earns fitness. Claims accruals. Typically also a tester or a user, but the contributor role is orthogonal.

The same wallet can hold any combination of user, tester, and contributor status. A single person might use Stable tier initially, upgrade to Fast tier, become a tester to offset the Fast tier cost, and eventually become a contributor. Each transition is independent.

---

## 4. Becoming a Tester

### 4.1 Requirements

A wallet becomes a tester by:

1. Binding to the Hub (standard wallet challenge/verify flow).
2. Registering at least one machine with a valid hardware fingerprint.
3. Completing a first measurement cycle successfully — running the sensor suite, reporting results, and passing anomaly detection.
4. Maintaining the measurement cadence — reporting for active sensor runs each cycle.

No application process, no approval, no stake, no waitlist. The requirements are mechanical.

### 4.2 Hardware Fingerprint

The hardware fingerprint is SHA256 of (CPU microcode + GPU VBIOS + kernel version + motherboard serial). It cryptographically identifies the specific machine and prevents trivial machine duplication.

If a fingerprint is seen on two or more distinct wallets, immune sensors flag it. The organism allows a wallet reassignment event (a tester might rebind their primary wallet) but multiple simultaneous wallets claiming the same hardware are a spoofing signal.

### 4.3 Measurement Cadence

A tester is expected to report measurements for each active sensor run during a cycle. Missed cycles are tolerated within a window (currently: no more than 3 consecutive missed cycles without losing tester status). Missing more than the window moves the wallet to inactive status and revokes the Fast tier rebate until reactivation.

Reactivation is automatic on the next successful measurement cycle. There is no penalty beyond the temporary rebate suspension.

### 4.4 Tester Status Revocation

A tester can be revoked from active status by:

1. **Missed cycles.** Missing more than the allowed window.
2. **Anomaly flags.** Immune sensors detecting patterns consistent with fraud (reporting fabricated measurements, coordinating with other wallets to spoof, hardware fingerprint collisions).
3. **Consistent measurement outliers.** Measurements that consistently fail population confirmation (coefficient of variation above threshold compared to the fleet). Repeated outlier measurements may indicate defective hardware rather than fraud; the first response is to notify the tester, not to revoke.

Revocation is reversible. A tester can re-earn active status by meeting the requirements again. This is the same pattern as curator revocation.

---

## 5. What Testers Provide to the Organism

### 5.1 Measurement Volume

The sensor array needs measurements across real hardware. Without a fleet of testers, the array is running on one machine (the founder's rig), which is not a meaningful sensor — the whole point of empirical hardware variance is that different machines produce different results, and you need many different machines to detect the variance.

A fleet of 100 testers running on 100 different hardware configurations produces a signal that no single machine can produce. The fleet is the sensory surface of the organism.

### 5.2 Spatial Diversity

Testers are distributed geographically (different data centers, different residential ISPs, different geographies). This produces diversity in a dimension that single-machine testing cannot: network conditions, ISP behavior, routing variance. Some CursiveOS optimizations (especially the network presets) interact with upstream network conditions in ways that are only visible when measured from multiple vantage points.

### 5.3 Adversarial Coverage

A healthy tester fleet includes testers with incentives to find problems. Someone running CursiveOS on unusual hardware (ancient CPUs, rare GPUs, exotic Linux distributions) will surface issues that mainstream testers do not. The free Fast tier rebate is enough incentive for these testers to participate; the lack of lifetime fitness is not a barrier because the incentive is already sufficient.

### 5.4 Sensor-Code Verification

When contributors submit new sensors, the sensor code itself needs to be validated across real hardware. Testers are the fleet on which new sensor code is exercised. A sensor that works on the author's machine but fails silently on others needs to be caught before it enters the active set; tester fleet diversity makes this catch possible.

---

## 6. Attacks Specific to the Tester Role

Beyond the spoofing attack addressed in section 2, the tester role faces several other attack patterns. These are enumerated here for the record.

### 6.1 Measurement Fabrication

An attacker reports fabricated measurement data without actually running the sensor. Motivation: get the Fast tier rebate without the hardware cost.

Defense: population confirmation. Fabricated measurements must align with what other real machines report for the same submission on similar hardware. Since the attacker doesn't know the measurement before making it, fabrication either (a) reports something implausible (flagged by immune sensors), (b) reports something in the middle of the expected distribution (effectively indistinguishable from real, and so not actively harmful), or (c) requires running the real sensor anyway, defeating the purpose.

### 6.2 Hardware Misrepresentation

A tester reports benchmarks run on one hardware configuration while claiming another (to pad specific hardware coverage metrics). Motivation: game a hypothetical "hardware coverage" reward.

Defense: no such reward exists. Tester compensation is flat ($2/month rebate) regardless of hardware. There is no incentive to misrepresent hardware for economic gain. Misrepresentation for other reasons (vanity, sabotage) is still possible but is caught by hardware fingerprint validation.

### 6.3 Collusion with Contributors

A tester conspires with a contributor to produce favorable measurements for the contributor's submissions. Motivation: the contributor pays the tester off-chain to report favorable results.

Defense: population confirmation. Even if a corrupt tester reports favorable results, those results are averaged with other testers' reports. The corrupt tester has to move the aggregate, which requires either (a) being a majority of the population confirmation set (possible in tiny fleets, not possible at scale), or (b) reporting extreme outliers (flagged by immune sensors). Additionally, the ultimate check is the revenue loop — if sensors accept a bad contribution, users experience worse software and revenue drops.

This attack is most dangerous during early bootstrap when the fleet is small. Mitigation during bootstrap is explicit: the founder manually reviews merges during the low-tester phase, and anomaly detection is tuned more conservatively. Once the fleet grows beyond the single-corrupt-majority threshold, the attack becomes uneconomic.

### 6.4 DoS via Tester Floods

An attacker registers many tester wallets to flood the measurement infrastructure. Motivation: disrupt operation, degrade sensor quality through noise injection.

Defense: rate limiting, per-wallet submission caps, anomaly detection on registration patterns. None of these prevent the attack entirely but they make it expensive. Since there is no direct economic gain for the attacker (no lifetime fitness to accrue), the attack is pure vandalism, which is usually bounded by the attacker's patience.

---

## 7. The Tester–Contributor Path

A tester who wants to contribute code has a clear path:

1. Write code — a new sensor, an improved benchmark method, a hardware-specific preset, a new tool.
2. Submit the code through the standard contribution flow.
3. The sensor array evaluates the submission. If it passes gates and produces positive fitness, it merges.
4. The tester now has a contributor wallet entry in `l5_lifetime_fitness` and starts earning lifetime-stream accruals.

The tester's existing tester status continues in parallel — they still receive Fast tier rebates for measurement labor and now also receive lifetime and current-cycle accruals for their merged code.

This is biologically correct. A sensory cell that differentiates into a germ-line cell (in organisms where this is possible, via stem cell intermediates) gains the reproductive function without losing the sensory function. The dual role is sustained by whichever function the organism needs the cell to perform in any given moment.

### 7.1 Where Code Contribution Pays More Than Testing

Over long horizons, the lifetime stream pays substantially more than the tester rebate. A contributor with 5% of total lifetime fitness, on an organism generating $1,000/cycle in revenue with an 80/20 lifetime/current split (close to genesis), earns:

```
$1,000 × 0.80 × 0.05 = $40/cycle
```

Compared to the tester rebate of ~$2/cycle, the contributor earnings are 20× higher at this hypothetical scale. As the organism grows, the gap widens.

This is intentional. Contribution is harder work and produces durable substrate; the compensation reflects that. The tester path is lower effort with lower ceiling; the contributor path is higher effort with higher ceiling. Both are valid participation modes.

### 7.2 Testers Who Never Become Contributors

Most testers will never become contributors. That is completely acceptable. The tester role exists because the organism genuinely needs measurement labor, not as a staging area for contributors. A tester who does nothing but tester work for the life of the project has fulfilled their part of the exchange and earned their free Fast tier access.

There is no expectation that testers graduate to contributor. The design of the role does not assume graduation and does not penalize non-graduation.

---

## 8. Summary

Testers run benchmarks, report measurements, and receive free Fast tier access. They do not earn lifetime fitness. They do not receive revenue share. The compensation shape matches the work shape: measurement is flow labor compensated with flow access.

This structure is load-bearing for the organism's security model. Lifetime-compensated measurement would make spoofing positive-EV at low success probabilities; flow-compensated measurement caps spoofing ROI at $24/fake/year, making it uneconomic against any reasonable defense.

The tester role preserves the measurement function of the v3.1 validator role while retiring the judgment function (because sensors judge, not humans). This is the clean version of the v3.1 exchange — contribute real work, receive real product, no governance theater.

A tester who wants to also be a contributor has a clear path; most testers will not take it, and that is fine. The organism needs both roles, and they are structurally different functions compensated in structurally different ways.
