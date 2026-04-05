# Layer 5 Architecture v1 (Day 2 Draft)

> **SUPERSEDED** — This document reflects v1.1 service decomposition (Validator Rewards with streak/rarity/quality,
> Contributor Incentive with stake lock/slash, pool_floor enforcement). All of this has been replaced in v3.1.
> **Current reference:** `docs/specs/layer5-economics-v3.1.md` and `white-paper.md` (Section 4 — Layer 5).
> Kept as historical record only.

Status: DRAFT v1 — SUPERSEDED BY v3.1
Date: 2026-04-02
Owner: Copper Sage

## Goal
Implement Layer 5 as modular services around CursiveRoot so economics are deterministic, auditable, and safe to tune.

## Service Boundaries
1) Entitlement Service
- Owns Fast/Stable plan state per machine/user
- Emits cycle burn events for Fast plans

2) Credit Ledger Service
- Append-only event log for all credit movements
- Idempotent writes via event_id/idempotency_key
- Derived balances and pool views

3) Pool Accounting Service
- Computes per-cycle inflow/outflow/burn totals
- Enforces pool_floor before payouts
- Applies pro-rating and throttle rules

4) Validator Rewards Service
- Reads validated benchmark events
- Computes eligibility, streak, rarity, quality multipliers
- Emits payout intents

5) Contributor Incentive Service
- Manages submission stake lock/unlock/slash
- Reads oracle verdict outcomes
- Emits payout/refund/slash settlement events

6) Dispute & Appeals Service
- Opens timed appeal windows
- Records votes/challenges/evidence links
- Emits final verdict override or confirmation

7) Orchestration/Cycle Runner
- Runs each cycle in deterministic order:
  a. finalize new ledger events
  b. settle contributor decisions eligible this cycle
  c. settle validator payouts
  d. apply burns + reconciliation

## Data Flow (high level)
- Machine update cycle -> Entitlement check
- If Fast -> Burn event -> Ledger -> Pool inflow
- Benchmarks ingest -> validation pipeline -> Validator Rewards
- Contributor submission -> stake lock -> test oracle -> verdict -> pending settlement -> final settlement
- All money-like movement = ledger event

## Critical Invariants
- No direct balance mutation outside ledger events
- Every payout linked to source cycle and deterministic formula snapshot
- Reconciliation must produce zero drift or hard-fail settlement close
- Appeals may delay settlement, never bypass event trail

## Failure Domains + Fallbacks
- Oracle unavailable: hold contributor settlements as pending; do not payout
- Reconciliation drift: freeze payout execution, emit alert
- Pool floor breach projection: auto pro-rate + throttle ladder
- Duplicate hardware risk spike: validator payouts switch to hold-review mode

## Security & Abuse Controls (wired points)
- Idempotency on all settlement writes
- Rate limits per contributor account and per hardware cluster
- Stake lock escrow state required before test assignment
- Manual override requires signed admin action logged to ledger

## Observability
Minimum metrics:
- pool_open, pool_close, inflow, outflow, burn
- payout_count_validator, payout_count_contributor
- hold_count_appeals, hold_count_risk
- reconciliation_drift
- failed_settlement_jobs

## API Surface (internal)
- POST /entitlement/cycle-burn
- POST /ledger/events
- POST /rewards/validators/compute
- POST /contrib/submissions/:id/lock-stake
- POST /contrib/submissions/:id/settle
- POST /appeals/:id/open|resolve
- POST /cycles/:id/run

## Implementation Sequence (code)
1. Ledger + pool accounting primitives
2. Entitlement burn integration
3. Validator payout computation
4. Contributor settlement flow
5. Appeals + delay windows
6. Cycle runner + reconciliation hard gates

## Open Decisions for Day 3 schema freeze
- Whether entitlement lives in existing user tables vs new layer5 schema
- Whether appeal votes are weighted equally or by validator trust tier
- Whether queued contributor obligations get expiration or persistent carry-forward
