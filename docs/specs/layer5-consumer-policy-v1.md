# Layer 5 Consumer Policy v1 (Day 6 Freeze)

> **PARTIALLY SUPERSEDED** — The Stable/Fast plan distinction and billing semantics are still correct.
> The fee model is wrong: v1 uses 5 internal credits; v3.1 uses `F_fast = $2.00 USD` settled in BTC.
> **Current reference:** `docs/specs/layer5-economics-v3.1.md` (Pricing section).
> Kept as historical record only.

Status: FROZEN v1 — FEE MODEL SUPERSEDED BY v3.1
Date: 2026-04-02
Owner: Copper Sage

## Plans

1) Stable (Free)
- Monthly update cadence
- No credit burn
- Default for new machine entitlements

2) Fast (Paid convenience lane)
- High-frequency update cadence (daily/hourly target)
- 5 credits burned per active cycle per machine
- Designed for operators who value immediate performance/security updates

## Transitions
- Stable -> Fast: allowed when account has sufficient credits
- Fast -> Stable: automatic on insufficient credits or user downgrade

## Billing Semantics
- Burn occurs once per billing cycle when machine receives Fast entitlement for that cycle
- Idempotency key required per machine+cycle to prevent double charges

## Fairness Rules
- Stable remains fully usable and free
- Fast payment buys update velocity and convenience, not ownership of base OS rights

## Abuse/Edge Handling
- Manual reinstall path is allowed; friction is accepted as tradeoff
- Entitlement checks should not block emergency security updates classified critical

## User Transparency
Each cycle expose:
- plan
- cycle fee
- burn event id
- resulting account balance
