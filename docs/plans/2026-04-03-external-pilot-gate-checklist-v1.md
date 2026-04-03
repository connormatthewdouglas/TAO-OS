# External Pilot Gate Checklist (MVP-6)

Date: 2026-04-03
Owner: Copper Sage
Status: In progress

## Gate criteria

1) Install path is user-facing in Hub
- Status: PASS
- Evidence: Install tab + one-command script shown in Hub.

2) Account/wallet identity connection exists
- Status: PASS (verified path live)
- Current: session-token identity scoping + wallet bind + challenge/signature verify endpoints/UI.
- Notes: EIP-191 message signing flow marks wallet as verified after signature validation.

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
- Status: PASS (strict token-mode)
- Current: admin-only cycle run, owner/admin plan guard, actor-match checks, session token -> account mapping, strict token-required access for `/hub/*` (except session bootstrap/create), per-route rate limit, audit action trail endpoint.
- Missing (post-pilot hardening): richer anomaly controls (IP/account anomaly alerts, bans/slow mode).

7) No-SQL operator journey validated
- Status: PASS
- Evidence: no-SQL E2E report completed.

8) Operator-facing docs ready
- Status: PASS
- Evidence: incentive-layer detailed doc + onboarding draft.

## Blockers before external pilot
1) None for MVP rail-mode gate.

## Re-evaluation (2026-04-03)
- No-SQL E2E pass #2 complete (admin + non-admin):
  - consumer cycle run blocked with `forbidden_admin_only`.
  - missing token blocked with `unauthorized_session_required`.
  - token/account query mismatch blocked with `forbidden_account_scope_mismatch`.
  - consumer wallet bind succeeds as `unverified` and is visible in identity.
  - consumer audit log only shows own actions; admin sees global action trail.
- Gate decision: GO for supervised external pilot (rail mode).

## Next execution order
1) Run supervised pilot cohort and monitor action trail/rate-limit behavior.
2) Add richer abuse controls (IP/account anomaly alerts, ban/slow mode).
3) Reassess GO/NO-GO for broader public rollout.
4) Prepare migration to stronger auth provider once pilot behavior data is stable.
5) Define token-rail activation policy gates tied to abuse metrics.
