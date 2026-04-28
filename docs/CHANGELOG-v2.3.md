# Changelog — White Paper v2.3

## Summary

v2.3 separates the technical paper from the organism theory. The root white paper now focuses on current implementation, validated results, architectural boundaries, and honest scope. The theoretical argument moves into a companion manifesto, and the Phase 0 build target is captured in a dedicated seed organism specification.

## Added

- `software-organisms-manifesto.md` — root-level manifesto defining the software organism framework and positioning CursiveOS as the first instance under construction.
- `docs/specs/seed-organism-v0.1.md` — Phase 0 minimum viable organism specification: variant runner, minimum sensor suite, append-only fitness ledger, and fake-BTC cycle close.
- `archive/white-paper-v2.2.md` — archived copy of the previous integrated white paper.

## Edited

- `white-paper.md` replaced with v2.3 technical white paper.
- `README.md` documentation index updated for the manifesto, seed organism spec, and v2.3 changelog.
- `docs/specs/layer5-economics-v3.3.md` and `docs/architecture/sensor-array.md` aligned on the metabolic sensor direction: recruitment pressure shifts toward current-cycle rewards; retention pressure shifts toward lifetime rewards.

## Unchanged

- Layer 5 remains v3.3: Bitcoin-native, no token, no capital pool, no governance, no voting, testers receive free Fast tier but no lifetime fitness, and contributor lifetime fitness is permanent once validly earned.

## Why

The previous white paper carried both the technical specification and the larger theory. That made the project feel more speculative than the current implementation requires. v2.3 makes the technical paper more legible to operators and contributors while preserving the theory in a document designed to carry it.

The seed organism spec turns Phase 0 into an executable target: one machine, one contributor, current preset stack, two sensor families, append-only fitness ledger, fake-BTC cycle close, three successful cycles, then first external tester.
