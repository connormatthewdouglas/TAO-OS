# Layer 5 Contributor Policy v1 (Day 5 Freeze)

> **SUPERSEDED** — This document reflects v1.1 economics (stakes, slashes, credit burns, trust tiers).
> v3.1 replaces stakes/slashes with free participation + reputation cooldowns, and replaces credits with BTC.
> **Current reference:** `docs/specs/layer5-economics-v3.1.md` and `white-paper.md` (Section 4).
> Kept as historical record only.

Status: FROZEN v1 — SUPERSEDED BY v3.1
Date: 2026-04-02
Owner: Copper Sage

## Goal
Enable immediate contributor-driven velocity without opening an unbounded spam market.

## 1) Admission (v1)
- Mode: gated contributor cohort
- Entry requires:
  - known account identity
  - agreement to submission/testing policy
  - funded stake wallet/account

## 2) Submission Classes
Allowed classes:
- preset
- benchmark
- driver
- kernel
- security
- other (manual approval required)

Each submission must include:
- summary + expected impact hypothesis
- rollback path
- affected hardware classes
- risk notes

## 3) Stake Rules
- Stake per submission: 5 credits (default)
- Stake locks before testing begins
- Max 2 active submissions per contributor
- Cooldown: 12h between new submissions

## 4) Testing + Verdict
- Submission enters assigned test cohort
- Oracle runs required same-class and cross-class tests
- Verdict options:
  - positive_delta
  - flat_delta
  - negative_delta
  - inconclusive

Inconclusive path:
- one expansion run allowed
- if still inconclusive -> flat settlement

## 5) Settlement Rules
- Positive: stake refunded + payout (with payout burn)
- Flat: stake refunded minus flat fee
- Negative: full stake slashed to incentive pool
- Settlement delay: 72h appeal window

## 6) Appeals
- Validators in good standing may appeal with evidence
- Appeal fee required (refundable if upheld)
- One appeal per submission state unless materially new evidence

## 7) Abuse Controls
- Submission spam: rate-limited + hold tier
- Repeated negative submissions above threshold: temporary suspension
- Fraud/fabrication: immediate suspension pending review

## 8) Trust Tiering (v1)
- Tier 0: new (strict limits)
- Tier 1: proven (after successful settled submissions)
- Tier 2: trusted (expanded limits by policy vote/admin)

## 9) Transparency
For each settled submission, publish:
- class
- measured score
- verdict
- payout/refund/slash outcome
- appeal status

## 10) KPI focus
Primary metric: external contributor submissions that reach settled positive/flat outcomes without manual intervention.
