# Layer 5 Economics — v3.3 (Single Source of Truth)

**Status:** ACTIVE — supersedes v3.1, v1.1, and v1.0
**Date:** 2026-04-17
**Paired document:** [`white-paper.md`](../../white-paper.md) v2.1

---

## Summary

| Parameter | Value |
|---|---|
| Base asset | Bitcoin (native BTC, no new token) |
| Yield layer | **None** (no pool, no staking, no yield mechanism) |
| Revenue distribution | Direct per-cycle, no accumulation |
| Split mechanism | Dynamic, metabolic-sensor-controlled |
| Split at genesis | 20% current-cycle / 80% lifetime |
| Split equilibrium | Emergent; no fixed target |
| Split movement rate | ≤ 2–3 percentage points per cycle |
| Split hard bounds | None; soft restoring force only |
| Fast tier fee | $2.00/month USD, settled in BTC |
| Stable tier fee | $0 |
| Cycle cadence | Monthly |
| Claim window | 2 years per accrual |
| Tester cost to organism | Net-zero (Fast tier rebate for measurement labor) |
| Tester fitness earning | None (measurement does not earn lifetime fitness) |
| Contributor vote rights | None |
| Governance mechanisms | None |
| Founder's cut | None (founder compensated as standard contributor) |

---

## 1. Participants

### 1.1 Users

Users run CursiveOS on their machines. Two tiers:

- **Stable tier** — free, receives validated releases on the slow cadence.
- **Fast tier** — $2/month, receives updates earlier, priority access to new features, and contributes to the selection pressure that shapes the organism's evolution.

A user who subscribes to Fast tier is a paying customer of the organism. Their subscription is both revenue and selection signal. When Fast tier subscribers cancel, the organism learns something is failing to deliver value, and the revenue loop constrains contributors accordingly.

### 1.2 Testers

Testers run benchmarks on their hardware and report measurement data to the sensor array. In exchange, they receive free Fast tier access. The complete exchange:

- Tester runs cycle benchmarks on their hardware.
- Measurements are recorded in CursiveRoot against the machine ID and wallet.
- Tester receives Fast tier access without charge.

Testers do not earn lifetime fitness. Testers do not receive revenue share. Testers have no governance rights (neither does anyone else — there is no governance).

See [`docs/architecture/testers.md`](../architecture/testers.md) for the full tester specification and the structural justification for this design.

### 1.3 Contributors

Contributors submit variants: proposed changes to the codebase, new sensors, new presets, new benchmark methods, new tooling. A submission that passes sensor evaluation and is merged earns the contributor **lifetime fitness** proportional to the measured improvement.

Contributors earn from both the current-cycle stream (the cycle their work is merged) and the lifetime stream (every cycle forever thereafter). The economic relationship with contributors is the organism's primary compensation channel.

A person can be all three (user, tester, contributor) simultaneously. The classes describe roles, not identities.

---

## 2. Revenue Flow

```
Fast tier users pay F_fast (USD → BTC at settlement)
                    │
                    ▼
            Cycle revenue pool
                    │
    (at cycle close, split by metabolic sensor)
                    │
       ┌────────────┴────────────┐
       ▼                         ▼
  Current-cycle stream     Lifetime stream
       │                         │
  Distributed to            Distributed to
  contributors whose        all contributors
  variants merged           weighted by cumulative
  this cycle,               lifetime fitness
  weighted by
  fitness delta
```

At cycle close:

1. Total cycle revenue R is computed from collected Fast tier subscriptions.
2. The metabolic sensor outputs split ratio s, with s_current + s_lifetime = 1.
3. Current-cycle stream C = R × s_current is distributed to contributors whose variants merged this cycle, weighted by measured fitness delta.
4. Lifetime stream L = R × s_lifetime is distributed to all contributors who have ever earned fitness, weighted by cumulative lifetime fitness.
5. Individual distributions become **accruals** recorded against each contributor's wallet. Accruals enter the claim window (section 5).

No revenue carries over to the next cycle. If a cycle collects zero revenue, zero is distributed and no state is affected.

---

## 3. Fitness

### 3.1 Fitness Measurement

When a variant is submitted, the sensor array evaluates it. The active sensor set runs the variant through its measurement protocol and each sensor returns:

- A signed delta score (or gate pass/fail for gate sensors)
- A confidence interval
- A set of hardware contexts the measurement covered

The merge decision is made by the sensor array aggregation logic (see [`docs/architecture/sensor-array.md`](../architecture/sensor-array.md)). If the variant is merged, it receives a **fitness score** equal to the aggregate signed delta weighted by confidence. The fitness score is always non-negative for merged variants — variants with zero or negative fitness do not merge.

### 3.2 Fitness Recording

Fitness is recorded in the lifetime ledger:

```
INSERT INTO l5_lifetime_fitness (
    contributor_wallet,
    variant_id,
    cycle_id,
    fitness_score,
    sensor_set_version,
    recorded_at
)
```

Each row is append-only. Lifetime fitness for a contributor is the sum of fitness_score across all their rows.

### 3.3 Sensor Deprecation

Sensors can be deprecated but not deleted. A deprecated sensor:

- Is no longer run on new submissions.
- Its historical fitness scores remain valid in the lifetime ledger.
- Its row in the sensor registry is marked `deprecated_at` but preserved for audit.

A contributor whose work earned fitness against a now-deprecated sensor retains that fitness forever. The measurement was valid when taken.

---

## 4. The Split and the Metabolic Sensor

### 4.1 The Split

The split ratio `s` = (s_current, s_lifetime) determines how each cycle's revenue is divided. At any given cycle close, revenue R is split as:

```
C = R × s_current
L = R × s_lifetime
s_current + s_lifetime = 1.0
```

The split is not chosen by governance. It is determined by the metabolic sensor.

### 4.2 The Metabolic Sensor

**Input signal:** merge velocity stratified by contributor history.

For each merge in the measurement window (default: rolling 3 cycles), compute a continuous "new-leaning weight" based on the contributor's prior merge count:

```
new_weight(n) = 1 / (1 + n)
returning_weight(n) = 1 - new_weight(n)
```

where `n` is the contributor's cumulative merge count at the time of the merge (excluding this one). Examples:

- First-time contributor: n=0 → new_weight=1.0, returning_weight=0.0
- Contributor with 1 prior merge: n=1 → new_weight=0.5, returning_weight=0.5
- Contributor with 3 prior merges: n=3 → new_weight=0.25, returning_weight=0.75
- Contributor with 9 prior merges: n=9 → new_weight=0.1, returning_weight=0.9

**Ratio:** R_meta = Σ(new_weight × fitness) / Σ(returning_weight × fitness) over the window.

**Target behavior:**

- High R_meta (recruitment-dominant) → organism is attracting new blood; shift split toward lifetime to reward returners.
- Low R_meta (retention-dominant) → organism needs fresh mutations; shift split toward current-cycle.

### 4.3 Adjustment Function

The sensor outputs a target split from R_meta. The actual split moves toward the target at a bounded rate:

```
s_target(R_meta) = clamp(f(R_meta), with soft restoring force toward neutral)
s_new = s_old + sign(s_target - s_old) × min(max_delta, |s_target - s_old|)
```

where `max_delta` is 0.025 (2.5 percentage points per cycle) and the soft restoring force is a function that makes adjustment progressively slower as the split moves farther from a neutral point. The neutral point itself is emergent — Phase 0 operation will reveal it.

**No hard floor or ceiling.** There is no enforced minimum or maximum for s_current or s_lifetime. The soft restoring force and bounded movement rate together mean extreme values are mechanically hard to reach and easy to move back from.

### 4.4 Genesis

At cycle 0:

```
s_current = 0.20
s_lifetime = 0.80
```

The lifetime-favored genesis reflects a substantive truth about bootstrap: almost all value being created early is substrate-building work whose value persists across future cycles. As the organism matures and starts producing more disposable near-term work, the metabolic sensor will move the split toward current-cycle.

**The trajectory is lifetime share decreasing over time** as new contributors arrive and recruitment signal rises. This is by design — the founder's share of the larger stream strictly decreases as contributor diversity grows, which eliminates the legibility risk of "founder's share of lifetime just went up."

### 4.5 Bootstrap Behavior

While there is only one contributor (founder-only bootstrap), the split is mathematically irrelevant — the founder receives 100% of both streams because there is no other wallet to distribute to. The metabolic sensor can be active from day one; it simply has no data to act on until a second contributor appears.

The moment a second contributor's first merge lands, the sensor has signal. R_meta will be driven by the new contributor's merges (high new_weight) and will push the split toward lifetime — but because this only happens after the new contributor has earned their own lifetime fitness, the new contributor benefits from the shift as well.

### 4.6 What the Sensor Does Not Do

The metabolic sensor does not:

- Choose which variants merge (that's the performance and regression sensors).
- Set sensor parameters (those are designed by curators and measured for effect).
- Determine contributor eligibility (that's wallet binding and submission gating).
- Apply to forks or other organisms (each organism runs its own).

---

## 5. Accruals and the Claim Window

### 5.1 Accrual Creation

At cycle close, each contributor with earnings in that cycle has an accrual recorded:

```
INSERT INTO l5_accruals (
    accrual_id,
    contributor_wallet,
    cycle_id,
    stream_type,        -- 'current' or 'lifetime'
    amount_sats,
    created_at,
    claim_deadline      -- created_at + 2 years
)
```

### 5.2 The Claim Window

Each accrual has a `claim_deadline` of `created_at + 2 years`. Before the deadline, the contributor may claim the accrual at any time. Claiming produces a Bitcoin transaction from the organism's settlement address to the contributor's bound wallet.

### 5.3 Deadline Expiry

When an accrual passes its claim deadline without being claimed, it enters the redistribution pool. At the next cycle close following expiry, expired accruals are redistributed to **active claimants** — contributors who have successfully claimed at least one accrual within the last 24 months. Redistribution follows the same weighting as the lifetime stream.

This mechanism handles dead wallets and lost keys without requiring decay or dormancy on lifetime fitness itself. A contributor's lifetime fitness is permanent. Their ability to collect a specific cycle's earnings is time-bounded.

### 5.4 Zero-Revenue Cycles

Zero-revenue cycles produce no accruals. The claim window does not tick for anyone because there is nothing to fail to claim. A contributor who is silent through a multi-year dry spell has lost nothing when revenue returns — their first accrual after return starts a fresh two-year window.

### 5.5 Active Claimant Status

A wallet is an **active claimant** if it has completed at least one successful claim within the last 24 months. Active claimants are the recipients of redistribution from expired accruals. New contributors become active claimants by making their first claim.

---

## 6. Testers: Free Fast Tier, No Lifetime Fitness

### 6.1 The Tester Exchange

A tester is any party that:

1. Has a wallet bound to the Hub.
2. Has a machine registered with a valid hardware fingerprint.
3. Reports measurements for active sensor runs each cycle.
4. Passes anomaly detection (measurements are statistically consistent with the fleet).

In exchange, the tester receives **free Fast tier access** for the duration they remain in good standing. The Fast tier fee F_fast is rebated monthly.

### 6.2 Tester Accruals

Testers do not have accruals on the lifetime stream. Testers do not have fitness scores recorded in `l5_lifetime_fitness`. The only economic record of a tester's participation is the Fast tier rebate transaction.

This is not an oversight. See [`docs/architecture/testers.md`](../architecture/testers.md) section 2 (the spoofing trap) for why.

### 6.3 Population Confirmation

A measurement influences merge decisions only when at least N independent machines have reported consistent results for the same submission. N scales with fleet size:

```
N = max(1, min(5, floor(sqrt(fleet_size))))
```

When measurements diverge (coefficient of variation above threshold), confirmation escalates to N+2. The exact threshold is a Phase 0 calibration task.

### 6.4 Tester → Contributor Path

A tester can become a contributor by submitting code (a new sensor, an improved benchmark, a new preset) that passes sensor evaluation and merges. The contributor role is independent of the tester role. Both can be held by the same wallet. Compensation mechanisms are additive.

---

## 7. Forks

Forks inherit the full genome: the codebase, the sensor array, the lifetime ledger, and the obligations. A fork that uses the CursiveOS genome owes the same lifetime fitness payments to the same contributors as the original, because the ledger is Bitcoin-anchored — the ledger exists on Bitcoin, not inside any CursiveOS instance.

Forking is structurally equivalent to speciation in biology. A fork that improves over the original by producing better selection pressure or better recruitment signal attracts contributors; a fork that does not improve does not attract contributors. The market for contributors is the analog of the market for habitat.

There is no pool to split, so there is no scenario in which a fork extracts value from the original by fracturing governance.

---

## 8. Data Model

### 8.1 New v3.3 Tables

**`l5_lifetime_fitness`** — replaces `l5_lifetime_votes_v31`
```
contributor_wallet    TEXT NOT NULL
variant_id            UUID NOT NULL
cycle_id              INTEGER NOT NULL
fitness_score         NUMERIC NOT NULL CHECK (fitness_score >= 0)
sensor_set_version    TEXT NOT NULL
recorded_at           TIMESTAMPTZ NOT NULL DEFAULT NOW()
PRIMARY KEY (variant_id)
INDEX (contributor_wallet, recorded_at)
INDEX (cycle_id)
```

**`l5_cycles`** — replaces `l5_pool_cycles`
```
cycle_id              SERIAL PRIMARY KEY
cycle_opened_at       TIMESTAMPTZ NOT NULL
cycle_closed_at       TIMESTAMPTZ
revenue_sats          BIGINT NOT NULL DEFAULT 0
split_current         NUMERIC NOT NULL          -- the s_current the metabolic sensor set
split_lifetime        NUMERIC NOT NULL
metabolic_R           NUMERIC                    -- R_meta the sensor computed
status                TEXT NOT NULL              -- 'open', 'closing', 'closed'
```

**`l5_accruals`**
```
accrual_id            UUID PRIMARY KEY
contributor_wallet    TEXT NOT NULL
cycle_id              INTEGER NOT NULL REFERENCES l5_cycles
stream_type           TEXT NOT NULL CHECK (stream_type IN ('current', 'lifetime', 'redistribution'))
amount_sats           BIGINT NOT NULL CHECK (amount_sats > 0)
created_at            TIMESTAMPTZ NOT NULL
claim_deadline        TIMESTAMPTZ NOT NULL
claimed_at            TIMESTAMPTZ
claim_tx_id           TEXT                       -- Bitcoin tx ID when claimed
INDEX (contributor_wallet, claimed_at)
INDEX (claim_deadline) WHERE claimed_at IS NULL
```

**`l5_sensors`**
```
sensor_id             TEXT PRIMARY KEY
sensor_family         TEXT NOT NULL              -- 'performance', 'regression', 'immune', 'behavioral', 'metabolic'
sensor_version        TEXT NOT NULL
code_ref              TEXT NOT NULL              -- git commit or file ref
introduced_at         TIMESTAMPTZ NOT NULL
deprecated_at         TIMESTAMPTZ
is_gate               BOOLEAN NOT NULL DEFAULT FALSE
```

**`l5_sensor_results`**
```
result_id             UUID PRIMARY KEY
submission_id         UUID NOT NULL
sensor_id             TEXT NOT NULL REFERENCES l5_sensors
machine_id            TEXT NOT NULL
delta_score           NUMERIC
gate_passed           BOOLEAN
confidence            NUMERIC
hardware_context      JSONB NOT NULL
reported_at           TIMESTAMPTZ NOT NULL DEFAULT NOW()
INDEX (submission_id)
INDEX (sensor_id, reported_at)
```

**`l5_tester_rebates`**
```
rebate_id             UUID PRIMARY KEY
tester_wallet         TEXT NOT NULL
cycle_id              INTEGER NOT NULL REFERENCES l5_cycles
amount_sats           BIGINT NOT NULL
granted_at            TIMESTAMPTZ NOT NULL DEFAULT NOW()
paid_tx_id            TEXT
```

### 8.2 Removed v3.1 Tables

The following v3.1 tables are removed in v3.3. Data that carries economic meaning should be migrated; data specific to v3.1 mechanisms (pool) can be archived and dropped.

- `l5_pool_state_v31` — pool no longer exists; drop.
- `l5_pool_cycles` — superseded by `l5_cycles`; migrate revenue history if preserved.
- `l5_contribution_votes_v31` — voting no longer exists; drop (archive for historical reference).
- `l5_lifetime_votes_v31` — superseded by `l5_lifetime_fitness`; migrate with vote_weight mapped to initial fitness_score for historical participants.
- `l5_governance_votes` — governance no longer exists; drop.
- `l5_appeals` — appeals no longer exist; drop.

### 8.3 Retained v3.1 Tables

Tables that survive the v3.3 migration unchanged or with minor schema adjustments:

- `l5_accounts` — retained.
- `l5_wallet_identities` — retained.
- `l5_auth_sessions` — retained.
- `l5_machine_entitlements` — retained.
- `l5_contributor_submissions` — retained, add `sensor_result_id` FK column.
- `l5_credit_ledger` — retained.
- `l5_hub_action_log` — retained.
- `l5_hub_anomaly_events` — retained.
- `l5_hub_network_lockouts` — retained.
- `l5_account_controls` — retained.

### 8.4 Migration Order

1. Create new tables (`l5_lifetime_fitness`, `l5_cycles`, `l5_accruals`, `l5_sensors`, `l5_sensor_results`, `l5_tester_rebates`).
2. Backfill `l5_lifetime_fitness` from `l5_lifetime_votes_v31` if any pilot data exists (each historic vote weight maps to a fitness score of equivalent magnitude for historical equivalence).
3. Add `sensor_result_id` to `l5_contributor_submissions`.
4. Cut API over to read/write new tables.
5. Stop writing to v3.1 tables.
6. Archive v3.1 tables to `archive_l5_*` namespace.
7. Drop original v3.1 tables after verification window (≥ 2 cycles).

---

## 9. What Is Not in v3.3

Explicit exclusions, called out because they were considered and rejected:

- **No pool.** No permanent capital. No principal. No staking layer. Revenue flows through each cycle.
- **No yield.** No Babylon. No stBTC. No yield-bearing anything.
- **No token.** No native token. No governance token. No utility token. Bitcoin is the base asset.
- **No votes.** No votes of any kind. No appeals. No democratic mechanisms.
- **No governance.** No DAO-style proposals. No treasury. No governance participants. The split is sensor-controlled, not governance-controlled.
- **No founder cut.** The founder is compensated through the standard contributor path — same fitness rules, same accrual rules, same claim rules — and no other mechanism.
- **No fixed split.** The 20/80 genesis is a starting state, not a designed equilibrium. The sensor drives the split.
- **No hard floor or ceiling on the split.** Soft restoring force only.
- **No contributor stakes.** No slashing. Spam is addressed via rate limiting and anomaly detection, not financial punishment.
- **No tester class with lifetime equity.** The v3.1 validator role is dissolved: judgment moves to sensors (no human judges), measurement moves to testers (no lifetime equity), and the word "validator" is not used in v3.3.

---

## 10. Open Questions (Phase 0 Empirical)

These are intentional — the architecture was designed to let the organism answer them empirically:

1. Where the metabolic sensor drives the split to, given real revenue patterns.
2. What the coefficient-of-variation threshold should be for N → N+2 population confirmation escalation.
3. What rolling window length the metabolic sensor should use (3 cycles is the starting point).
4. What neutral point the soft restoring force should pull toward (if any fixed neutral is even needed).
5. When additional sensor families (immune, behavioral) should be added and by whom.
6. What the curator succession criteria should look like once more than one curator exists.

These are measured and refined, not decided up front.

---

## 11. Change History

- **v3.3 (2026-04-17):** Removed pool, yield, Babylon. Split is now dynamic via metabolic sensor. Genesis at 20/80 lifetime-favored. Testers retained with free Fast tier exchange; no lifetime fitness for testers. Governance/voting removed entirely. Sensor array is the fitness oracle. Two-year claim window for accruals.
- **v3.2:** [Drafted but never committed to repo.] Removed pool and Babylon; otherwise similar to v3.3 but with static 70/30 split and less developed spoofing-trap analysis.
- **v3.1 (2026-04-05):** 60/40 split, validator voting, Babylon yield on pool principal, 1% threshold and cooldown. Superseded.
- **v1.1, v1.0:** Earlier iterations superseded by v3.1.
