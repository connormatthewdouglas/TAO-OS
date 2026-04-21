> **DEPRECATED.** This spec describes the v3.1 economic layer (permanent pool, Babylon yield, validator voting, static 60/40 split). It has been superseded by [layer5-economics-v3.3.md](layer5-economics-v3.3.md), which removed the pool, removed Babylon, replaced the static split with a metabolic sensor, and removed voting. This file is preserved for historical record and research on the design journey. Do not build against this spec.
>
> See [../CHANGELOG-v2.1.md](../CHANGELOG-v2.1.md) for the full reasoning behind the transition.

---

# Layer 5 Economics — v3.1 (Single Source of Truth)
**Status:** ACTIVE — supersedes v1.0 and v1.1  
**Date:** 2026-04-05  

---

## Summary

| Parameter | Value |
|-----------|-------|
| Base asset | Bitcoin (native BTC, no new token) |
| Yield layer | Babylon Protocol (~6.5% gross annual) |
| Staking fraction | 50% of pool actively staked |
| Effective yield per cycle | ~0.27% (3.25% annual effective) |
| Revenue split | 60% payout pot / 40% pool principal |
| Fast user fee (`F_fast`) | $2.00 USD (pilot), settled in BTC |
| Cycle cadence | Monthly |
| Validator cost | Net zero (pay F_fast, receive F_fast refund) |
| Min vote threshold | 1% of total cycle votes |
| Cooldown trigger | 3 consecutive below-threshold cycles → 5-cycle cooldown |

---

## Revenue Flow

```
Fast user pays F_fast (USD → BTC at settlement)
         │
    ┌────┴────┐
   60%       40%
    │         │
Payout pot   Pool principal
(distributed  (locked forever,
each cycle,   earns Babylon yield)
then resets)
```

The pool principal is never withdrawn. It grows by 40% of every Fast user payment, forever. The Babylon yield it generates flows to contributors as yield royalties.

---

## Roles

### Fast Users
- Pay `F_fast` per machine per cycle
- Receive early access to validated optimization updates (Fast channel)
- No voting rights, no earning — pure users

### Validators
- Pay `F_fast` per cycle (same as Fast users)
- Receive a full `F_fast` refund at cycle close if they complete their validation duties
- **Net cost: zero**
- Receive 100 vote points per cycle to distribute across accepted contributions
- Validators who fail to complete validation duties: their `F_fast` stays in the pool (not refunded)

### Contributors
- Submit improvements (presets, benchmark methodology, hardware profiles, tooling)
- No mandatory stake. Participation is free.
- Earn from **two independent income streams** (see below)

---

## Contributor Income Streams

### Stream 1 — Payout Pot Share (per cycle, resets)

```
payout = (cycle_votes_received / total_cycle_votes) × payout_pot
```

- Requires ≥ 1% of total cycle votes
- Resets each cycle — requires active, quality contributions to keep earning
- Incentivizes current, relevant work

### Stream 2 — Yield Royalty (permanent, append-only)

```
royalty = (contributor_lifetime_votes / all_lifetime_votes) × cycle_yield
```

- `cycle_yield = staking_fraction × pool_principal × annual_yield / cycles_per_year`
- Lifetime votes are never removed — they accumulate on an append-only ledger
- As more contributors join, the share dilutes but the absolute value grows with the pool
- Rewards long-term contributors permanently, even if they stop submitting
- Requires ≥ 1% of total cycle votes in the cycle where votes were earned to accrue lifetime votes

---

## Governance — Democratic Vote

Each eligible validator distributes **100 points** across accepted contributions for the cycle.

**Vote allocation rules:**
- Validators may distribute their 100 points however they choose across accepted submissions
- Unallocated points are lost (not rolled over)
- **The payout formula normalizes by total votes actually cast, not by 100 × validator_count.** If a validator submits only 60 of their 100 points, only those 60 points enter the denominator. A validator who submits zero points contributes nothing to the denominator — effectively abstaining from that cycle's distribution.
- Minimum allocation to any submission that counts: none at the individual validator level — but the aggregated share across all validators must reach 1% of total votes cast for the contributor to earn

**Dual purpose of votes:**
1. Determine payout pot distribution this cycle
2. Permanently add to contributor's lifetime vote ledger

A 1% minimum vote threshold applies to both uses. A submission receiving less than 1% of total cycle votes cast receives no payout pot share and no lifetime vote accrual.

---

## Rate Limiting (replaces stake/slash)

| Condition | Effect |
|-----------|--------|
| < 1% vote share in a cycle | No payout, no lifetime vote accrual |
| 3 consecutive cycles below 1% threshold | 5-cycle cooldown |
| During cooldown | Submissions silently skipped by the pipeline |
| Cooldown completion | Contributor returns to normal standing |

This replaces financial punishment with reputation-based gating. Contributors who can't afford to stake are not excluded — they simply need to maintain quality.

---

## Babylon Yield Mechanics

- 50% of pool principal is actively staked via Babylon Protocol at any time
- 50% remains in cold storage (not staked)
- Babylon gross yield: ~6.5% annual on staked portion
- Effective annual yield on total pool: `6.5% × 50% = 3.25%`
- Effective per-cycle yield on total pool: `3.25% / 12 = 0.27%`

The yield is not immediately distributed. Each cycle, the yield earned is divided among all contributors in proportion to their lifetime vote share.

---

## Pricing

`F_fast = $2.00 USD` per machine per cycle (monthly cycle), converted to BTC at the moment of payment.

**Rationale:** Low enough to run the pilot without real money risk. Correct enough that the mechanics are real. Will be adjusted upward as the contribution pipeline demonstrably delivers value. USD pricing with BTC settlement (like a BTC payment processor) avoids BTC price volatility in the user-facing fee.

---

## Validator Duties and Refund Forfeiture

A validator receives a full `F_fast` refund at cycle close if — and only if — they submit a valid vote allocation for that cycle.

**Failed validator:** A validator who submits zero vote allocations for a given cycle has failed to complete their validation duties. Their `F_fast` for that cycle is not refunded; it stays in the pool and increases the payout pot available to contributors.

**Partial submission:** Submitting any non-zero allocation — even a single point to a single submission — satisfies the duty requirement. The validator does not need to spend all 100 points. The refund is binary: either they participated (refund issued) or they didn't (refund forfeited).

**Pilot enforcement:** During the supervised Frosty pilot, refund forfeiture is tracked manually by the admin. Automated enforcement in `close-v31` is a post-pilot task.

---

## Parameter Governance

The following parameters can be changed by validator supermajority vote:

| Parameter | Default | Constraint |
|-----------|---------|------------|
| `F_fast` (USD) | $2.00 | > $0 |
| `payout_pot_fraction` | 0.60 | 0 < x < 1; `pool_fraction = 1 − x` automatically |
| `staking_fraction` | 0.50 | 0 ≤ x ≤ 1 |

**How a governance vote works:**

1. Any validator submits a governance proposal via `POST /hub/governance/votes` with the parameter name, proposed value, and rationale.
2. The proposal is open for voting for **14 days** (approximately half a cycle).
3. All validators cast yes / no / abstain.
4. **Passes if:** votes cast ≥ 50% of active validators (quorum), AND yes votes > 66% of yes+no votes (supermajority, excluding abstains).
5. If passed, the new value takes effect starting the **next cycle** after the vote closes.

**Rate limits:**
- At most one open governance proposal per parameter at a time.
- A failed proposal cannot be resubmitted for 3 cycles.
- The 60/40 split (and staking fraction) can change by at most 10 percentage points per governance vote to prevent sudden large shifts.

**Who can propose:** Any validator (not just admins).

**Pilot note:** During the Frosty pilot, parameter changes are made directly by the admin. The governance vote mechanism is post-pilot.

---

## Open Items (pre-public launch)

1. **Babylon integration** — in the pilot, yield is simulated. Real Babylon staking is post-pilot.
2. **Automated validator refund forfeiture in `close-v31`** — currently tracked manually by admin during pilot.
3. **Governance vote enforcement in Hub API** — quorum check, proposal windows, and parameter update writes are post-pilot.

---

## What This Supersedes

- `docs/specs/layer5-economics-v1.md` — Internal credits model (retired)
- `docs/specs/layer5-economics-v1.1.md` — Extended credits model (retired)

Those files are kept as historical reference only. All implementation should reference this document.
