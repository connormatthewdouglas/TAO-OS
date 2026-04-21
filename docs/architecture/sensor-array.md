# Sensor Array

**Status:** ACTIVE
**Date:** 2026-04-17
**Paired documents:** [`layer5-economics-v3.3.md`](../specs/layer5-economics-v3.3.md), [`biological-architecture.md`](biological-architecture.md)

---

## 1. What the Sensor Array Is

The sensor array is CursiveOS's sensory nervous system. It is the set of code, measurement protocols, and evaluation logic that determines which contributions improve the organism and which do not. Every decision that would otherwise require governance — voting, judgment, appeal, adjudication — is instead made by the sensor array or derived from its outputs.

The sensor array is code, contributed and maintained through the same mechanism as any other part of the genome. Sensors are versioned, deprecatable, and themselves subject to sensor evaluation (meta-evaluation).

---

## 2. Sensor Families

Sensors are organized into families by function. Each family has a different relationship to fitness scoring, merge decisions, and the organism's governance-free operation.

### 2.1 Performance Sensors

Measure objective hardware and software performance delta between a baseline configuration and a proposed change. Outputs a signed numeric delta with a confidence interval. Positive delta with sufficient confidence contributes positively to fitness; negative delta contributes negatively.

Genesis set includes:

- **Network throughput sensor.** Measures TCP throughput over a simulated WAN link (50ms RTT, 0.5% loss). Detects the default Linux BDP gap and BBR/CUBIC tradeoffs.
- **Cold-start latency sensor.** Measures GPU idle → first inference token time. Detects C-state, governor, and GPU power-state impact.
- **Sustained inference sensor.** Measures steady-state tok/s on a warm model. Detects scheduler, memory, and cache effects once the system is warm.
- **Idle power sensor.** Measures wattage at idle. Captures the power cost of disabling C-states and pinning GPU frequency.

### 2.2 Regression Sensors (Gates)

Boolean pass/fail. Do not contribute fitness. Any failure gates the variant out of merge regardless of performance delta. The role is structural — preventing a variant from being adopted when it breaks something important, even if it improves something else.

Genesis set includes:

- **Full-test regression sensor.** Runs the existing `cursiveos-full-test-v1.4.sh` suite and reports pass/fail. Any new failure rejects the variant.
- **Reversibility sensor.** Applies the variant's preset changes, runs the `--undo` path, and verifies that the system returns to the pre-apply state. Non-reversible changes fail the gate.
- **Hardware compatibility gate.** Verifies the variant does not break any hardware configuration the current genome supports. Variants that improve one hardware at the cost of another require explicit hardware-scoped fitness rather than flat fitness.

### 2.3 Immune Sensors

Detect anomalies. Output signals consumed by the anomaly framework, not by the merge decision. Immune sensors are how the organism identifies spoofing attempts, measurement fraud, and behavioral patterns consistent with capture.

Examples planned for post-Phase 0:

- **Statistical outlier detection.** Flags individual measurements that diverge from the fleet consensus by more than a configurable standard deviation.
- **Coordinated behavior detection.** Flags wallets whose activity patterns correlate suspiciously (same IP ranges, same hardware fingerprints across "different" machines, same submission timing).
- **Curator self-dealing detection.** Flags sensor contributions from a curator that produce fitness patterns favoring that curator's own hardware or prior contributions.
- **Revenue-correlation detection.** Flags sensors whose output has stopped correlating with Fast tier renewal rates — the Goodhart's Law check described in [`biological-architecture.md`](biological-architecture.md) section 1.

### 2.4 Behavioral Sensors

Measure patterns of contribution and participation over time. Used for metabolic regulation, curator eligibility assessment, and tester reputation. Do not directly contribute to individual variant fitness.

- **Merge velocity tracker.** Feeds the metabolic sensor (section 4).
- **Contributor return rate.** Fraction of contributors whose first merge is followed by at least one more within N cycles.
- **Tester reliability.** Fraction of a tester's measurements that pass population confirmation.
- **Curator tenure.** Time in role, contribution count, anomaly-flag count.

### 2.5 Metabolic Sensors

Control allocation parameters within the organism. The split between current-cycle and lifetime streams is the primary example. Metabolic sensors consume signals from other sensor families and produce control outputs.

- **Stream split sensor.** Computes R_meta from contributor-stratified merge velocity, moves the split between current-cycle and lifetime toward the signal-indicated target. Fully specified in section 4.

---

## 3. The Genesis Sensor Suite

The minimum viable selection pressure is two sensors, both already mostly built:

### 3.1 Performance Sensor (Primary Fitness Signal)

Wraps the existing benchmark scripts:

```
./benchmarks/benchmark-network-v0.1.sh
./benchmarks/benchmark-inference-v0.1.sh  (sustained tok/s)
./benchmarks/benchmark-inference-v0.2.sh  (cold-start latency)
```

For each submission:

1. Run baseline (pre-change) benchmarks 3× on the target hardware.
2. Apply the change.
3. Run tuned (post-change) benchmarks 3×.
4. Revert the change.
5. Compute signed deltas for each benchmark dimension, with variance estimates.
6. Aggregate into a single fitness score using a confidence-weighted sum.

Output:

```
{
    "variant_id": "...",
    "machine_id": "...",
    "delta_network_mbps": +42.3,
    "delta_coldstart_ms": -18.1,
    "delta_sustained_tokps": +0.5,
    "confidence": 0.87,
    "aggregate_fitness": 3.2,
    "hardware_context": { "cpu": "...", "gpu": "...", ... }
}
```

### 3.2 Regression Sensor (Gate)

Runs the full-test suite against the proposed change:

```
bash cursiveos-full-test-v1.4.sh --variant <variant_id>
```

Output is boolean (pass/fail). Also records which specific subtests passed or failed for audit. No fitness contribution.

### 3.3 Why Only Two Sensors at Genesis

Adding more sensors before the full loop is validated would slow down Phase 0 learning and introduce confounds. Each additional sensor multiplies the measurement cost per submission and multiplies the potential for false negatives. Two sensors is enough to produce selection pressure that visibly distinguishes genuine improvements from noise; more can layer in after the Phase 0 loop is running correctly.

Specifically, these are the Phase 1 candidate additions:

- Security scanning sensor (detects introduction of known-vulnerable patterns)
- Hardware coverage matrix sensor (ensures the variant works across the diversity of tester fleet hardware)
- Code quality sensor (detects common anti-patterns)

These are good sensors to have but they are not required for genesis. They will be added as contributor submissions go through the curator process after Phase 0 validates the loop.

---

## 4. The Metabolic Sensor (Stream Split Controller)

This is the most load-bearing sensor in the architecture. It replaces the v3.1 fixed split with a dynamic parameter controlled by measured recruitment/retention balance.

### 4.1 What the Sensor Measures

The sensor reads merge velocity stratified by contributor history. Every merge in the measurement window (default: rolling three cycles) is characterized by the contributor's prior merge count `n` at the time the variant was merged (excluding the current merge).

Each merge contributes to two weighted sums:

```
new_weight(n) = 1 / (1 + n)
returning_weight(n) = 1 - new_weight(n)

total_new     = Σ (fitness_score × new_weight(n))
total_returning = Σ (fitness_score × returning_weight(n))

R_meta = total_new / total_returning
```

Properties of this weighting:

- **No hard threshold.** A first-time contributor's merge is 100% "new." A tenth merge is only 9% "new." There is no boundary at "n=3" or similar to attack via sock-puppet graduation.
- **Weighted by fitness.** A small merge from a new contributor counts less than a big merge from a new contributor. The organism is measuring "how much fitness is coming from each bucket," not "how many people are in each bucket."
- **Windowed.** Three cycles is the default window; the right window length is a Phase 0 calibration task.

### 4.2 How the Sensor Adjusts the Split

The sensor computes a target split from R_meta. Target behavior:

- Very high R_meta (overwhelmingly new contributors producing the merges) → recruitment is healthy and well-rewarded; target a higher lifetime share.
- Very low R_meta (overwhelmingly returning contributors producing the merges) → recruitment is failing; target a higher current-cycle share.
- R_meta near a neutral reference → target remains near current.

The exact mapping function `f(R_meta) → s_target` is tunable. The starting function is:

```
s_current_target = 0.3 + 0.3 × tanh(log(R_neutral / R_meta))
```

with `R_neutral` initially set to 1.0 (equal weighted fitness from new and returning). The tanh function bounds the target between approximately 0.0 and 0.6, with soft saturation at the extremes. Movement from the current split toward the target is rate-limited:

```
s_new = s_old + sign(s_target - s_old) × min(max_delta, |s_target - s_old|)
max_delta = 0.025  (2.5 percentage points per cycle)
```

### 4.3 Genesis

At cycle 0, the split is initialized at `(s_current, s_lifetime) = (0.20, 0.80)` — lifetime-favored.

Rationale: during bootstrap, almost all value being created is substrate-building work. Starting at the lifetime-favored extreme is the substantively correct representation of where early value lives. As new contributors arrive and drive R_meta upward, the sensor naturally moves the split — but the movement direction is toward current-cycle (benefiting the arriving contributors), which makes the organism's response to new arrivals visibly accommodating rather than grudging.

**The split's trajectory is lifetime share decreasing over time.** This is by design. The founder's share of the larger stream strictly decreases as contributor diversity grows. There is never a moment when someone can claim "the founder's share just went up."

### 4.4 No Hard Bounds

There is no enforced floor or ceiling on either stream. The sensor combined with the rate limit and the soft restoring force makes extreme values mechanically hard to reach. In practice, the split is expected to settle somewhere between 30/70 and 70/30 depending on the organism's long-run contributor dynamics. Phase 0 will reveal where.

### 4.5 Bootstrap Edge Cases

While the founder is the only contributor, R_meta is undefined (division by zero or by a single term in the denominator). In this case, the sensor returns the current split unchanged — it has no signal to act on. The split remains at 20/80 until the second contributor's first merge lands.

The first several merges by the second contributor will be heavily weighted as "new" (n=0, then n=1, then n=2) and R_meta will spike. The split will begin moving toward current-cycle. The rate limit prevents this from destabilizing — the organism adjusts over multiple cycles, not in a single step.

### 4.6 Attack Surface

The metabolic sensor is a high-value attack target. The primary attacks and their defenses:

**New-contributor farm.** Attacker creates many fake new contributors to drive R_meta high, shifting the split toward lifetime, benefiting themselves as an existing contributor. Defense: fake contributors have to produce mergeable code (positive fitness from the performance sensor, passing the regression gate) to be counted. The attack either fails (code is not mergeable) or produces genuine value for the organism (the code does improve it). Additionally, shifting toward lifetime benefits all lifetime contributors proportionally, not just the attacker, so the attacker's ROI is capped at their share of lifetime fitness.

**Returning-contributor farm.** Inverse attack — existing wallets produce many small merges to drive R_meta low, shifting toward current-cycle. Defense: same code-submission requirement. Low-value merges fail the regression gate or have near-zero fitness score.

**Merge-timing coordination.** Genuine merges delayed or bunched into specific cycles to manipulate the windowed R_meta calculation. Defense: the 2.5 percentage point per cycle rate limit combined with the three-cycle window makes single-cycle manipulations have bounded effect.

**Coalition gaming.** Multiple contributors coordinate to drive R_meta in a direction that benefits them collectively. Defense: the coalition has to produce real code to produce signal, and the split change benefits all contributors not just the coalition. Unless the coalition is a supermajority, each coalition member's net benefit is their share of the redistribution minus their full labor cost — negative-EV per member.

The design is not invulnerable to all attacks but is structured so that successful attacks either produce value for the organism or are uneconomic. See [`hardening.md`](hardening.md) for the full attack-surface analysis.

---

## 5. Population Confirmation

A single machine's measurement is not sufficient to drive a merge decision. The sensor array requires confirmation from multiple independent machines before a measurement influences fitness.

### 5.1 The Requirement

For each variant and each sensor, the aggregate fitness contribution is only recorded if **at least N independent machines have reported consistent results**, where:

```
N = max(1, min(5, floor(sqrt(fleet_size))))
```

Fleet size is the count of active testers (wallets that have reported measurements in the last 30 days). Examples:

| Fleet size | N required |
|---|---|
| 1 | 1 |
| 4 | 2 |
| 9 | 3 |
| 16 | 4 |
| 25+ | 5 |

The cap at N=5 prevents the requirement from becoming prohibitive at scale. Beyond 25 machines, additional confirmations still happen, but only 5 are required for merge.

### 5.2 Consistency Criteria

Measurements are "consistent" if their coefficient of variation (CV = σ/μ) is below a threshold. Default threshold: 0.15 (15%). When CV exceeds the threshold, the requirement escalates:

```
if CV > 0.15: required_confirmations = N + 2
```

This is adaptive immunity — when signal is ambiguous, more confirmations are required. The exact threshold is a Phase 0 calibration task.

### 5.3 Independence

"Independent machines" means:

- Distinct hardware fingerprints (SHA256 of CPU microcode + GPU VBIOS + kernel version).
- Distinct wallets.
- Distinct anomaly profiles (immune sensors have not flagged them as correlated).

If two machines that appear "different" have strongly correlated measurement patterns (immune sensor detects coordination), they may be counted as one for confirmation purposes. This is the defense against spoofing farms where an attacker spins up many fake "machines" from the same underlying hardware.

### 5.4 Single-Machine Phase 0

At genesis, fleet size is 1 (the founder's rig), so N=1 and no external confirmation is required. This is a known limitation of bootstrap — the organism must begin somewhere, and the first measurements are the founder's alone. As the tester fleet grows, confirmation requirements rise organically.

A contributor joining during Phase 0 (fleet size 2-3) will experience N=1 or N=2 confirmation. This is still vulnerable to a single bad actor, but with only 2-3 machines in the fleet the attack ROI is trivially small.

---

## 6. Sensor Curation

### 6.1 What Curators Do

Curators maintain the sensor array. Specifically:

- Write new sensors when coverage gaps are identified.
- Review anomalies flagged by immune sensors.
- Deprecate sensors that stop correlating with user value (Goodhart detection).
- Resolve conflicts between sensors (e.g., two performance sensors disagreeing on a variant).
- Tune meta-parameters (rate limits, thresholds, window lengths) informed by Phase 0 data.

Curators do **not** vote on contributions, do **not** override sensor decisions, and do **not** receive additional economic share. Curator is a role of responsibility, not a role of reward.

### 6.2 Why Curator Is Not a Reward

The incentive to curate is intrinsic — you care about organism health — not extractive. Adding a reward layer to curation would create capture incentive and violate the "no governance" principle. Curators earn through contributed sensor code (which earns fitness like any other contribution), not through the curation role itself.

### 6.3 Bootstrap: Founder as Sole Curator

During bootstrap, the founder is the sole curator. This is unavoidable. It also concentrates a real risk — a bad curator can corrupt the sensor array. Mitigations during bootstrap:

1. All sensor code is public and auditable.
2. Anomaly sensors (section 2.3) specifically detect curator self-dealing.
3. The revenue loop eventually closes Goodhart — if the founder introduces capture-favoring sensors, Fast tier revenue declines and the capture is paid for out of founder earnings.

### 6.4 Curator Succession

A second curator emerges when someone else has met measured criteria:

1. **Merged sensor code with positive fitness.** Has contributed to the sensor array themselves, and that code has passed other sensors' evaluation.
2. **Operated a valid tester machine for N cycles without anomaly flags.** At least 6 consecutive cycles of measurements that pass immune detection.
3. **Sustained engagement over ≥ 6 months.** Time-gated to prevent rapid promotion.

Criteria 1 and 2 are automatically measurable. Criterion 3 is time-gated. No appointment, no vote, no interview — curator status is claimable by meeting the criteria and is granted automatically.

The specific thresholds (N cycles, 6 months) will be refined based on Phase 0 data. These are starting values.

### 6.5 Curator Revocation

If a curator's contributions start showing patterns consistent with capture — sensors that consistently favor their own hardware, statistical signatures of self-dealing, correlation between their sensor changes and their own earnings — the anomaly sensor flags it. Flagged curator status is automatically revoked.

Revocation is reversible. A curator whose status was revoked can re-earn it by meeting the succession criteria again from scratch. This handles both false positives (curator gets their status back without drama) and genuine capture (revoked curator must rebuild trust by producing value that the sensors can measure).

### 6.6 Why Not Democratic Election

Elected curators can be captured by any adversary willing to spend enough to influence the electorate. Measured curators can be captured only by adversaries willing to produce genuine positive-fitness contributions across many cycles without triggering anomaly flags — which is indistinguishable from being a good curator, which is fine.

This is the general principle: **where a system needs to select for a trait, measure the trait rather than vote on it.** Selection on measured competence is more robust than selection on political skill.

---

## 7. Sensor Versioning and Deprecation

### 7.1 Version Registry

Every sensor has an entry in the sensor registry (`l5_sensors` in the schema):

```
sensor_id            (stable identifier, e.g., "perf.network_v1")
sensor_family        (performance | regression | immune | behavioral | metabolic)
sensor_version       (semver-like, e.g., "1.0.0")
code_ref             (git commit or file path)
introduced_at        (cycle ID when sensor became active)
deprecated_at        (cycle ID when sensor was deprecated, or NULL if still active)
is_gate              (boolean — does this sensor gate merges or just contribute fitness)
```

A sensor's identity is the `sensor_id`. A new version of an existing sensor creates a new row with the same sensor_id, a bumped sensor_version, and `introduced_at` at the current cycle. The old version's row gets `deprecated_at` set.

### 7.2 Deprecation

Sensors can be deprecated but not deleted.

**What deprecation does:**
- The sensor is no longer run on new submissions.
- The `deprecated_at` timestamp is recorded.
- Historical fitness scores from this sensor remain valid in the lifetime ledger.

**What deprecation does not do:**
- Does not invalidate past merges.
- Does not revoke past fitness.
- Does not refund past accruals.

A contributor whose work earned fitness against a now-deprecated sensor keeps that fitness forever. The measurement was valid when taken; deprecation is a forward-only event. This is biologically correct — evolution layers new traits rather than erasing old ones.

### 7.3 When to Deprecate

Deprecate a sensor when:

- **Goodhart's Law.** The sensor's output has decorrelated from user value (Fast tier renewal rates, organic growth metrics). Contributors are optimizing the measurement rather than the thing the measurement was meant to capture.
- **Hardware obsolescence.** The sensor measures a dimension that is no longer relevant (e.g., a sensor specific to a now-unsupported GPU architecture).
- **Replacement.** A new sensor version supersedes the old one and the old is redundant.

Do not deprecate a sensor merely because it has not contributed a novel signal recently. A stable dimension that few variants affect is still a valid part of the measurement surface.

---

## 8. Open Questions (Phase 0 Empirical)

These are intentional — the architecture was designed to let the organism answer them empirically rather than forcing a designer to guess:

1. **What is the right rolling window for the metabolic sensor?** Starting at 3 cycles. May need to be longer (to reduce noise) or shorter (to respond faster).
2. **What is the right CV threshold for population confirmation escalation?** Starting at 0.15. May need calibration based on observed measurement variance in real fleet operation.
3. **What is the right `R_neutral` for the metabolic sensor's target function?** Starting at 1.0 (balanced new/returning fitness). May need to be biased based on the organism's observed preferences.
4. **What is the right `max_delta` for split movement?** Starting at 0.025 per cycle. Could be faster if the sensor is too slow to respond, slower if thrashing emerges.
5. **When should the second curator role open?** 6 months of sustained engagement is the starting criterion. Could be longer if capture risk appears higher, shorter if the organism is growing faster than curation can keep up.
6. **How many additional sensors should be in the active set at each project phase?** Genesis has 2 (performance + regression). How aggressive should the expansion be?

These are measured and refined, not decided up front.
