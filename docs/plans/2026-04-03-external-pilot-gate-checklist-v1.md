# External Pilot Gate Checklist (MVP-6)

Date: 2026-04-03
Owner: Copper Sage
Status: In progress

## Gate criteria

1) Install path is user-facing in Hub
- Status: PASS
- Evidence: Install tab + one-command script shown in Hub.

2) Account/wallet identity connection exists
- Status: PASS (MVP rail-mode)
- Current: account scoping via account_id/session bootstrap + wallet bind endpoint/UI.
- Notes: wallet stays explicitly unverified until signature flow is added.

3) User can see machine, plan, cycle, rewards
- Status: PASS
- Evidence: Machines/Rewards/Cycle card wired to API.

4) User can submit + track contribution outcome
- Status: PASS (MVP baseline)
- Evidence: contribution create/list endpoints + UI.

5) User can open appeals + vote
- Status: PASS (MVP baseline)
- Evidence: appeals and votes endpoints + UI.

6) Permission safety
- Status: PARTIAL
- Current: admin-only cycle run, owner/admin plan guard, actor-match checks.
- Missing: stronger role policy map and token-backed identity.

7) No-SQL operator journey validated
- Status: PASS
- Evidence: no-SQL E2E report completed.

8) Operator-facing docs ready
- Status: PASS
- Evidence: incentive-layer detailed doc + onboarding draft.

## Blockers before external pilot
1) Replace account_id query/header scoping with real auth session token mapping.
2) Add minimal abuse controls (rate limits + action logging visibility in Hub).
3) Run second no-SQL E2E with non-admin + admin accounts and record evidence.

## Next execution order
1) Add auth-lite token flow for Hub API (session token -> account_id mapping).
2) Add abuse controls and activity visibility (rate limit + request/action trail).
3) Run second no-SQL E2E with non-admin + admin accounts.
4) Re-evaluate gate and mark GO/NO-GO.
5) Queue post-pilot hardening: signature-based wallet verification.
