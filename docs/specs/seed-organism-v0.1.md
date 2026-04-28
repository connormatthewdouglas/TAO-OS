# CursiveOS Seed Organism Specification — v0.1

Status: Draft  
Phase: Phase 0 / Pre-Transition-One  
Scope: Founder-rig validation loop, fake-BTC economics, single-machine population confirmation  
Purpose: Define the minimum viable software organism required to validate CursiveOS as an end-to-end measurement-governed system.

---

## 1. Thesis

The seed organism is not merely the preset stack and not merely the sensor suite. Those are necessary organs, but the organism exists only when the following loop closes:

**variant proposed → preset/genome mutation applied → sensors measure phenotype delta → regression gates pass/fail → fitness is recorded → ledger updates → cycle closes → fake payout is computed → next cycle inherits the result.**

The seed organism is therefore the smallest runnable CursiveOS loop that demonstrates inheritance, selection, and metabolism in one system.

The user-facing product at this phase is still a Linux optimization layer. The organism-level system is the governance mechanism around that product: the machinery that determines which changes survive, how their measured value is recorded, and how compensation would flow once revenue exists.

---

## 2. Goals

The seed organism must prove five things end-to-end:

1. **The phenotype can be mutated reversibly.** A variant can modify the preset stack or measurement harness without making the host unrecoverable.
2. **The sensory path is deterministic.** Measurement output is produced by scripts and structured data, not by LLM judgment or human preference.
3. **Selection can happen from measurement.** A variant can be accepted, rejected, or marked inconclusive according to explicit sensor outputs.
4. **Fitness can be recorded.** A measured improvement can be converted into a ledger entry tied to a contributor identity and a specific variant.
5. **Metabolism can be simulated.** At cycle close, fake revenue can be split into current-cycle and lifetime streams according to the Layer 5 rules, proving that economic mechanics work before real BTC is introduced.

---

## 3. Non-Goals

The seed organism does not attempt to prove everything CursiveOS will become.

Out of scope for Phase 0:

- A public ISO.
- Real BTC settlement.
- Production user billing.
- Fully automated multi-machine population confirmation.
- The natural-language shell.
- Continuous background measurement daemon on every install.
- Security, code-quality, and broad compatibility sensors as merge-blocking gates.
- Autonomous governance of sensor curation.
- Claims of universal performance uplift across arbitrary Linux hosts.

Those are later organs. Phase 0 proves the core circulatory loop first.

---

## 4. Minimum Viable Organism Components

The seed organism consists of seven required components.

### 4.1 Phenotype

The phenotype is the running Linux host under test with the CursiveOS preset stack applied.

Phase 0 phenotype:

- Founder rig as the canonical seed host.
- Existing Linux distribution, not a CursiveOS ISO.
- Current canonical preset stack: `cursiveos-presets-v0.8.sh` or the current locked successor.
- Workloads under test:
  - WAN-simulated TCP throughput.
  - Cold-start inference latency.
  - Sustained inference throughput.
  - Optional idle-power measurement if available on host.

The phenotype must be restored to baseline after each test run unless the run is explicitly designated as a persistent-apply run.

### 4.2 Genome

The genome is the versioned CursiveOS repository state used to produce the phenotype and run the sensors.

Minimum genome contents:

- Preset scripts.
- Benchmark scripts.
- Full-test harness.
- Sensor manifests.
- Variant metadata schema.
- Fitness scoring function.
- Ledger schema.
- Cycle-close payout simulation.

A seed organism cannot operate from ad hoc shell commands alone. Every change under evaluation must map back to a git commit, branch, PR, or local variant ID.

### 4.3 Minimum Sensor Suite

The minimum sensor suite has two families: one scoring family and one gate family.

#### A. Performance Sensor Family — scoring

The performance sensor converts measured before/after deltas into fitness.

Genesis dimensions:

- Network throughput delta.
- Cold-start inference latency delta.
- Sustained inference throughput delta.
- Optional idle-power delta as either a penalty term or separate cost signal.

The performance sensor outputs structured JSON:

```json
{
  "variant_id": "variant identifier",
  "sensor_id": "perf.genesis.v1",
  "machine_id": "hardware fingerprint",
  "preset_version": "v0.8",
  "baseline": {
    "network_mbps": 0,
    "coldstart_ms": 0,
    "sustained_tokps": 0,
    "idle_watts": null
  },
  "variant": {
    "network_mbps": 0,
    "coldstart_ms": 0,
    "sustained_tokps": 0,
    "idle_watts": null
  },
  "delta": {
    "network_pct": 0,
    "coldstart_pct": 0,
    "sustained_pct": 0,
    "idle_power_pct": null
  },
  "confidence": 0.0,
  "fitness_score": 0.0,
  "timestamp": "ISO-8601"
}
```

#### B. Regression Gate Family — pass/fail

Regression gates do not add fitness. They only prevent bad variants from entering the lineage.

Genesis gates:

- Full-test gate: the existing full test harness must complete without new failures.
- Reversibility gate: apply → measure → undo must restore captured pre-apply values.
- Host-safety gate: variant must not require destructive or non-reversible system changes.

The regression gate outputs structured JSON:

```json
{
  "variant_id": "variant identifier",
  "sensor_id": "regression.genesis.v1",
  "machine_id": "hardware fingerprint",
  "passed": true,
  "failures": [],
  "reverted_cleanly": true,
  "timestamp": "ISO-8601"
}
```

### 4.4 Variant Runner

The variant runner executes a candidate change in a controlled sequence.

Required behavior:

1. Capture baseline system state.
2. Run baseline benchmarks.
3. Apply candidate preset or code variant.
4. Run post-variant benchmarks.
5. Run regression gates.
6. Revert system state.
7. Emit a signed or hashable result bundle.
8. Store local artifacts for audit.

The runner can be local-only in Phase 0. GitHub Actions is useful for deterministic code checks, but hardware-dependent measurement should run on the founder rig or a controlled local runner.

### 4.5 Fitness Ledger

The ledger records measured fitness as append-only state.

Minimum ledger fields:

```json
{
  "ledger_entry_id": "unique id",
  "cycle_id": "cycle number",
  "variant_id": "variant identifier",
  "contributor_id": "wallet or local identity",
  "commit_ref": "git commit sha",
  "sensor_result_refs": ["result bundle hashes"],
  "fitness_score": 0.0,
  "current_cycle_eligible": true,
  "lifetime_fitness_delta": 0.0,
  "created_at": "ISO-8601"
}
```

Fitness entries are append-only. Corrections are new entries that supersede prior entries by reference; prior entries are not deleted.

### 4.6 Metabolic Cycle Simulator

The seed organism must simulate revenue flow even before real revenue exists.

Phase 0 cycle rule:

- Cycle length: one week for simulation, or one month if matching production exactly.
- Revenue asset: fake BTC or integer test units.
- Genesis split: 20% current-cycle / 80% lifetime.
- Single-contributor behavior: metabolic sensor returns split unchanged because new-versus-returning signal is undefined.
- Payout output: generated report, not real settlement.

Minimum payout report:

```json
{
  "cycle_id": "cycle number",
  "simulated_revenue_sats": 0,
  "current_cycle_share": 0.20,
  "lifetime_share": 0.80,
  "contributors": [
    {
      "contributor_id": "wallet or local identity",
      "cycle_fitness": 0.0,
      "lifetime_fitness": 0.0,
      "current_cycle_payout_sats": 0,
      "lifetime_payout_sats": 0,
      "total_payout_sats": 0
    }
  ]
}
```

### 4.7 CursiveRoot / Hub Interface

The seed organism needs a place where results become organism state.

Minimum viable implementation:

- Local SQLite or JSONL ledger is acceptable for the first local loop.
- Hub/Supabase integration becomes required before opening Phase 0 to external testers.
- Result bundles must be exportable in the same structure that the Hub will ingest later.

Do not build Phase 0 as a throwaway toy. The first implementation may be local, but its schemas should be production-shaped.

---

## 5. Variant Lifecycle

A Phase 0 variant moves through the following states:

1. **Proposed** — variant exists as branch, PR, patch, or local variant package.
2. **Prepared** — metadata is complete: contributor ID, commit ref, declared scope, rollback method.
3. **Measured** — performance sensor has emitted a valid result bundle.
4. **Gated** — regression gates have passed, failed, or marked the run invalid.
5. **Selected** — if performance is positive and gates pass, variant is accepted into the seed lineage.
6. **Recorded** — fitness ledger entry is appended.
7. **Inherited** — accepted variant becomes part of the baseline for the next cycle.
8. **Paid in simulation** — fake cycle close computes current and lifetime payout.

Allowed terminal states:

- Accepted.
- Rejected: regression failure.
- Rejected: negative fitness.
- Inconclusive: insufficient confidence.
- Invalid: sensor failure or incomplete artifacts.

---

## 6. Fitness Scoring — Draft Model

The first scoring model should be simple, explicit, and easy to replace.

Suggested normalized terms:

- Higher network throughput is positive.
- Lower cold-start latency is positive.
- Higher sustained tok/s is positive.
- Higher idle power is negative, if measured.

Draft formula:

```text
fitness =
  (w_net × normalized_network_gain)
+ (w_cold × normalized_coldstart_gain)
+ (w_sustained × normalized_sustained_gain)
- (w_power × normalized_idle_power_cost)
```

Starting weights:

```text
w_net       = 0.40
w_cold     = 0.30
w_sustained = 0.20
w_power    = 0.10
```

The power term should be optional until idle-power measurement is stable across test hosts. If omitted, the result bundle must explicitly mark `idle_power_pct = null` rather than silently dropping the cost.

A variant should not be accepted merely because one metric explodes upward while another critical metric collapses. Any severe negative delta beyond a threshold should either trigger regression failure or require hardware/workload-scoped fitness.

---

## 7. Seed Organism Acceptance Criteria

Phase 0 is complete when the following have happened:

1. Three complete cycles have run with fake revenue.
2. At least three variants have been evaluated.
3. At least one variant has been accepted and inherited.
4. At least one variant has been rejected by a regression gate or negative fitness.
5. The ledger records fitness correctly across cycles.
6. The payout simulator computes current-cycle and lifetime payouts correctly.
7. The same accepted variant is visible as inherited baseline in the next cycle.
8. A full audit trail exists from variant → sensor result → ledger entry → payout report.
9. The system can be explained to an external tester without relying on undocumented founder knowledge.

---

## 8. What Counts as the Seed Preset Stack

The seed preset stack is the canonical v0.8 locked preset set unless superseded by a formally named successor.

It should be treated as the first phenotype, not as the whole organism.

The preset stack provides:

- The initial body under selection.
- The first mutation surface.
- The first measurable performance deltas.
- The first substrate from which future variants inherit.

The seed organism begins when this preset stack is placed inside a closed measurement and ledger loop.

---

## 9. Minimum Sensor Suite vs. Full Sensor Array

The minimum sensor suite should stay deliberately small.

Required at seed:

- Performance sensor.
- Regression/reversibility gate.

Allowed but not required at seed:

- Idle power sensor as a penalty term.
- Individual tweak-isolation sensor for debugging.
- Basic hardware fingerprinting.

Deferred until after seed loop works:

- Security sensor.
- Code quality sensor.
- Broad hardware compatibility matrix.
- Curator self-dealing sensor.
- Revenue-correlation / Goodhart sensor.
- Multi-machine anomaly detection.

The rule: do not add sensors because they are philosophically complete. Add sensors when the absence of that sensor creates a real selection error.

---

## 10. Bootstrap Honesty

In Phase 0, the founder is the contributor, curator, operator, and primary tester. This is a real concentration risk.

The seed spec does not pretend otherwise. It mitigates the concentration risk by making every action legible:

- Sensor code is public.
- Result bundles are stored.
- Fitness entries are append-only.
- Payout reports are reproducible.
- Reversibility is tested.
- External tester onboarding happens only after three clean fake cycles.

The seed organism is not decentralized. It is decentralization-shaped: built so additional contributors and testers can enter without requiring a rewrite.

---

## 11. External Tester Readiness Gate

The project is ready for the first external tester when:

- Phase 0 acceptance criteria are met.
- Result submission schema is stable.
- Hardware fingerprinting works.
- The tester guide can produce a valid sensor result without founder intervention.
- Population confirmation logic can handle fleet size 2.
- Tester compensation is simulated or clearly documented even if Fast tier billing is not live.

The first external tester should not be asked to validate the whole manifesto. They should be asked to validate a concrete path:

```text
clone repo → run full test → submit result → see result in CursiveRoot/Hub → receive tester status
```

---

## 12. Implementation Backlog

### Required for Phase 0 local loop

- `variant.json` schema.
- `sensor-result.json` schema.
- `ledger-entry.json` schema.
- Local result bundle writer.
- Fitness scoring script.
- Regression/reversibility wrapper.
- Fake cycle-close script.
- Cycle report generator.

### Required before first external tester

- Hub result ingestion endpoint.
- Hardware fingerprint normalization.
- Tester identity/wallet binding.
- Public CursiveRoot status display for submitted result.
- Failure-mode documentation.
- Privacy disclosure for submitted hardware/performance metadata.

### Required before real economics

- Real contributor wallet registration.
- BTC settlement path.
- Claim-window tracking.
- Bitcoin anchoring of ledger commitments.
- Production cycle-close job.
- Public audit view.

---

## 13. Open Questions for Phase 0

These should be answered empirically, not by founder intuition alone:

1. What minimum confidence threshold distinguishes real improvement from measurement noise?
2. Should idle power be a fitness penalty at seed or reported as a separate tradeoff?
3. How many repeated runs are needed per metric before a variant can be accepted?
4. Should individual tweak isolation be part of acceptance or only diagnostic tooling?
5. How should hardware-scoped fitness be represented when a variant helps one class of machine but hurts another?
6. Does a one-week simulated cycle produce enough signal, or should cycle simulation mirror monthly production immediately?
7. What exact result bundle is stable enough to become the Hub ingestion contract?

---

## 14. Summary

The seed organism is the minimum viable CursiveOS life cycle.

It is built from the preset stack and the minimum sensor suite, but it is not reducible to either. The organism exists only when measurement changes inheritance and inheritance changes the next measurement. The economic layer does not need real BTC yet, but it does need fake-cycle execution so metabolism is tested as machinery rather than left as prose.

The correct Phase 0 target is therefore:

**one machine, one contributor, current preset stack, two sensor families, append-only fitness ledger, fake-BTC cycle close, three successful cycles, then first external tester.**

