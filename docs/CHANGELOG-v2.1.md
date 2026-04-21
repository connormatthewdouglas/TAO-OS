# Changelog — White Paper v2.1 / Layer 5 Economics v3.3

This is not a routine version bump. The architecture changed substantially between v1.0 / v3.1 and v2.1 / v3.3 in response to stress-testing that revealed load-bearing flaws in the earlier design. This document explains what changed and why, so the historical record is clear and future readers understand which decisions were deliberately reversed and which were refinements.

## Summary of Changes

| Area | v1.0 / v3.1 | v2.1 / v3.3 |
|---|---|---|
| Reward accumulation | Permanent staked pool, never decreases | No pool; direct accrual to contributors per cycle |
| Yield source | Babylon Protocol Bitcoin staking | None |
| Split mechanism | Static 60% contributor / 40% pool | Dynamic split controlled by metabolic sensor |
| Split genesis state | N/A (static) | 20% current-cycle / 80% lifetime, moving toward homeostasis |
| Governance | One-validator-one-vote contribution approval and appeals | None; sensors replace voting |
| Validator class | Voters who also ran benchmarks; earned pool royalties | Removed as a voting class; measurement role retained as "testers" who exchange labor for free Fast tier access |
| Contributor verdict | Validator vote tallied over 5-cycle cooldown | Sensor-reported fitness per cycle |
| Appeals | 1% support threshold for founder action | None |
| Claim behavior | Implicit indefinite lifetime (via pool royalties) | Two-year rolling claim window; unclaimed earnings reclaimed by the organism |
| Fork semantics | Not explicitly specified | Forks inherit all outstanding obligations; Bitcoin anchoring is the enforcement mechanism |
| Substrate dependencies | Bitcoin, Linux, Babylon | Bitcoin, Linux only |
| Tagline | "Self-improving Linux distribution" (operational description) | "A new species that inherited its founding genome from Linux and now evolves independently under its own selection pressure" (biological framing) |

## Why the Pool Was Removed

The staked pool was the financial centerpiece of v3.1 and removing it looks drastic. The reasoning is three-layered.

**The yield did not work economically.** Babylon Protocol was yielding approximately 0.06% on staked BTC at the time of analysis. A one-million-dollar pool at that yield produces six hundred dollars per year distributed across all historical contributors by lifetime validator vote share. This is not a meaningful royalty stream. It is a rounding error presented as an income source.

**The yield was not trustless in the way we needed.** Babylon yields are paid out in altcoins from the proof-of-stake chains being secured. This means the pool was structurally exposed to altcoin counterparty risk, altcoin price volatility, and the operational complexity of continuous token conversion. A "Bitcoin-native" design cannot have its income stream denominated in things that are not Bitcoin without becoming something other than Bitcoin-native.

**The conceptual error was deeper than the numbers.** v3.1 treated capital pools as a source of compounding returns for contributors. But capital doesn't compound in any meaningful way at crypto-native yields. What actually compounds in a self-improving system is the substrate itself — the code, the benchmark database, the fleet of contributors, the ecosystem of forks. Substrate compounding is real and powerful. Capital pools were a distraction masquerading as the engine. Removing the pool doesn't remove compounding; it redirects the design's attention to where compounding actually lives.

Contributors in v3.3 are compensated from current cycle revenue via a metabolic split. Historical contributors continue earning through the lifetime stream for as long as their sensor-measured work remains deployed in the field. This provides the "ongoing royalty" property that v3.1 was trying to create with the pool, without requiring any capital buffer or external yield source.

## Why Static 60/40 Became a Dynamic Metabolic Sensor

The 60/40 split in v3.1 came from intuition. Specifically, from my intuition as the founder. This is a form of governance — a single actor deciding a parameter that affects every participant — and it smuggles in a centralized decision that the rest of the architecture is explicitly designed to avoid.

Biology does not allocate metabolism by vote. It allocates via hormonal signals that respond to the organism's state. An animal's body decides how much energy goes to immediate demands versus long-term tissue maintenance based on continuous readouts from sensors measuring current activity, reserves, and stress.

The metabolic sensor in v3.3 implements the biological pattern directly. It measures R_meta = new-contributor-leaning merges divided by returning-contributor-leaning merges, weighted continuously so there are no hard thresholds to game. If recruitment signal (R_meta) is high, the organism moves metabolism toward current-cycle rewards to attract new contributors. If retention signal is high, metabolism moves toward the lifetime stream to maintain the active base. The split is whatever the organism's actual state demands, not whatever the founder guessed.

This change is subtle but important. It removes the last piece of designed-in centralized governance from the economic layer.

## Why Genesis State Is 20/80 Lifetime-Favored

In early design discussions, I proposed starting the metabolic sensor at an equilibrium point like 65/35 with the expectation that it would fluctuate around that center. This was wrong in a specific way that I only understood after looking at the bootstrap reality clearly.

At genesis, I am the sole contributor. I receive 100% of both splits regardless of their ratio. The split is economically meaningless during bootstrap. But I also noticed that a split that starts near equilibrium and drifts upward toward lifetime as founding contributions accumulate would create a perception problem — new contributors arriving in year two would see "founder's share of lifetime just went up over time" even though the underlying reality was just homeostatic adjustment.

The cleaner approach is to start at the maximum lifetime extreme (20/80) and let the metabolic sensor work the organism down toward its natural homeostasis as new contributors arrive. This trajectory is unambiguous: lifetime share is strictly decreasing over time as the system responds to incoming contributors. Nobody can credibly claim the founder's share is growing.

This starting condition is also substantively correct, not just legibility-optimized. In the bootstrap phase, almost all value being created is legacy value — code written in month one is still running in year five. The ratio of work-that-persists to work-that-benefits-only-this-cycle is essentially 100/0 at the start and decays toward some natural equilibrium as the project accumulates more disposable near-term work. 20/80 accurately reflects this. The homeostatic decay toward a lower lifetime share reflects the organism's actual maturation.

The equilibrium point — where the sensor eventually settles — is deliberately not pre-specified. It will be whatever the organism needs once it reaches steady state. This is more honest than picking a number. It means the economics spec does not contain a smuggled-in answer to "what should the split be"; it contains only a starting condition and a restoring force.

## Why the Validator Class Was Removed, But Testers Were Retained

v3.1 had a single "validator" role that bundled three distinct functions: running benchmarks (measurement), voting on contributions (governance), and earning pool royalties weighted by voting history (capital returns). This bundle looked clean in the spec but produced contradictions under stress testing.

The governance function had to go because the whole architecture was moving toward sensor-driven measurement replacing voting. The pool royalty function had to go with the pool. That left measurement — and an open question about whether measurement should still be compensated, and if so, how.

The tempting answer was "eliminate the validator class entirely; let contributors themselves run the sensors." You pointed out the gap in this: many people run benchmarks because they want free Fast tier access and have no interest in writing code or building sensors. Eliminating the class eliminates a real and valuable participant type for no good reason.

The refinement is that the measurement role (now called "tester") is retained as a distinct participant category, but the compensation shape matches the work shape. Testers produce flows (continuous measurement), so they are compensated with flows (free Fast tier access for as long as their validated fleet runs). They do not earn lifetime fitness accruals, because their work does not produce substrate — it produces verification of substrate built by others.

This compensation-shape principle is important enough to surface here. In v3.1, validators earned lifetime royalties for measurement work, which created a spoofing attack with unbounded upside: fake a validator fleet, never contribute code, earn pool royalties in perpetuity. In v3.3, spoofing a tester saves at most $2/month per fake (the value of free Fast tier). After basic fingerprint-based detection, the attack is negative-expected-value. The change from "lifetime stock of rewards" to "ongoing flow of product access" collapses the attack economics from unbounded to trivial.

The sensory-cell analogy from biology is exact here: sensory cells are fed by the organism's metabolism but do not participate in the germ line. They receive ongoing resource to keep functioning but they are not the substrate that gets propagated forward.

## Why Governance, Voting, and Appeals Were Removed Entirely

v3.1 had one-validator-one-vote contribution approval, a 1% support threshold for founder-action appeals, and a five-cycle cooldown on tallying votes. These mechanisms were designed to distribute decision-making across the contributor base.

The deeper problem is that voting is the wrong tool for the jobs it was doing. Whether a contribution improved the organism is an empirical question answerable by measurement. Voting on it introduces social dynamics, coordination failures, and gameable thresholds into a question that sensors can answer directly. Similarly, whether a decision is legitimate is something the architecture should demonstrate through its construction, not something the contributor base should vote on after the fact.

The v3.3 position is that the project is legitimized by measurement, substrate, transparency, and fork right. Contributors who disagree with direction can fork; forks inherit obligations via Bitcoin anchoring; the market of forks expresses collective preference through the only mechanism that is actually credible in a distributed system. Voting is not added back because it is the wrong tool.

One consequence is that the founder retains effective bootstrap-phase authority over what ships as the canonical CursiveOS. This is disclosed honestly in the hardening doc. The mitigations are sensor transparency, fork right, and eventual succession of curator roles to parties demonstrating capability. They are not replaced by a voting mechanism because a voting mechanism would just move the concentration from founder to coalition-of-voters without solving the actual problem.

## Why the Claim Window Is Two Years

v1.0 implicitly assumed that contributors could claim earnings indefinitely, because pool royalties paid out automatically and there was no practical mechanism for "expiry." In v3.3 without the pool, unclaimed accruals have to go somewhere and live under some rule.

Two years is short enough to force contributors to maintain active wallet hygiene and long enough that reasonable absences (medical, travel, life events) do not cost people their earnings. Unclaimed accruals after two years are reclaimed by the organism — they flow back into the next cycle's current-cycle pot. This creates a natural pressure against stale hoarding of claim rights and against accumulated liability the organism can never discharge.

This is also a hardening feature. An attacker who compromises a contributor wallet has a two-year window to extract, not an indefinite one. A contributor who dies without revealing keys has their share returned to the organism rather than frozen forever in an unreachable address.

## Why Fork Obligations Are Inherited

A self-improving Linux with a fork-right principle but without fork obligation inheritance creates an obvious exploit: fork to escape contributor payments. This exploit was not addressed in v1.0 / v3.1 because the economic layer and the fork semantics were not thought through together.

v3.3 treats outstanding obligations — rewards owed to contributors for measured contributions — as part of the inherited state that a fork takes on along with the code. The Bitcoin anchoring makes this enforceable: the ledger of who is owed what is written to a substrate the forker cannot erase. A fork that repudiates obligations is identifiable as such, loses the trust required to attract contributors or users, and in practice cannot compete with a fork that honors them. This is consistent with how real organisms work — forks inherit both the upside of the genome and the downside of parasites, commitments, and liabilities.

## Substrate Dependencies Narrowed to Bitcoin and Linux

v3.1 depended on Babylon Protocol as a third substrate for pool yield. Every dependency is an attack surface and a load-bearing external system. Removing Babylon along with the pool reduces the substrate dependency graph to Bitcoin (for anchoring obligations and payments) and Linux (as founding genome and current operating environment).

Linux is a genome dependency, not an operational one. The organism inherited from Linux but can evolve independently. If the Linux lineage stagnates or becomes hostile, CursiveOS can diverge without losing identity. This is a different kind of dependency than Bitcoin, which is a live substrate the organism continuously anchors into. Both dependencies are named explicitly in the hardening doc along with their failure modes.

No Babylon. No Ethereum. No external bridges. No custom token. The architecture is as substrate-minimal as we could make it.

## Lessons About Design Process

The original v1.0 / v3.1 documents went public. They were wrong on load-bearing questions. This is worth saying plainly because the correction pattern was repetitive: a well-reasoned design passes plausibility checks, then fails under adversarial stress testing, and the fix requires removing rather than adding.

Each of these removals — pool, governance, static split, Babylon dependency, lifetime royalties for testers — simplified the architecture while strengthening it against attack. The consistent pattern is that what looked like sophisticated financial engineering (pool plus yield plus voting plus appeals) was actually just surface area for exploits. The simpler architecture is not simpler because we gave up on features. It is simpler because the features were creating problems they were also supposed to solve.

The operational takeaway for future work: stress-test before dependencies become load-bearing. Once a mechanism is in a public spec and people are building against it, removing it costs more than designing it right would have. v2.1 / v3.3 is the corrected design. Future changes should go through the same adversarial stress pattern before entering any spec that anyone might rely on.

## Migration Notes

The `hub/` and `hub-api/` code currently implement v3.1 semantics (pool, voting, 60/40 split, Babylon integration stubs). These do not match v3.3 docs.

Hub code migration is tracked as a separate engineering workstream beginning with a Phase 0 audit ([claude-code-phase-0-hub-audit.md](../claude-code-phase-0-hub-audit.md) in the ops tree). The audit inventories what exists before any code changes. Schema migration, backend rewrite, frontend rewrite, and launch readiness are subsequent phases with explicit gates between them.

Until hub migration completes, the docs describe the target architecture and the code describes the current implementation. This gap is acknowledged and being actively closed. Readers should treat the docs as the specification and the code as an in-progress implementation of an earlier spec transitioning to match.

## Document Status After This Release

**Current (v2.1 / v3.3):**
- `white-paper.md` (v2.1)
- `README.md`
- `docs/specs/layer5-economics-v3.3.md` (v3.3)
- `docs/architecture/biological-architecture.md`
- `docs/architecture/sensor-array.md`
- `docs/architecture/testers.md`
- `docs/architecture/hardening.md`
- `docs/CHANGELOG-v2.1.md` (this file)

**Archived (historical record):**
- `archive/white-paper-v1.0.md` (original v1.0 white paper, preserved)
- `docs/specs/layer5-economics-v3.1.md` (preserved with deprecation header pointing to v3.3)

**Operational (updated for terminology only):**
- `external-tester-guide.md` / `external-tester-onboarding-v1.md` (minimally updated: "validator" → "tester" where applicable; pool / voting references removed; operational flow unchanged)

## What This Changelog Is Not

This is not a promise that v3.3 is the final architecture. The project is young, stress-testing continues, and specific parameters (metabolic sensor equilibrium point, genesis sensor weights, population confirmation thresholds) are Phase 0 empirical questions rather than locked values.

It is a statement that the v3.3 architecture has survived the stress tests that broke v3.1, that the removals were deliberate rather than budgetary, and that future changes will be documented with the same honesty as this one — including the parts where earlier reasoning was wrong.

---

*CursiveOS is a new species that inherited its founding genome from Linux and now evolves independently under its own selection pressure.*
