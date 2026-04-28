# Seed Organism Runbook v0.1

This runbook is the first executable path for the Phase 0 seed organism described in `docs/specs/seed-organism-v0.1.md`.

## Local mac fixture loop

Use this path while developing on macOS. It proves scoring, gating, bundle writing, ledger append, and fake payout without touching host tuning.

```bash
python3 tools/seed_organism.py init
python3 tools/seed_organism.py run-variant \
  --variant references/seed-organism/variant.example.json \
  --metrics references/seed-organism/metrics-positive.example.json \
  --cycle-id 1
python3 tools/seed_organism.py close-cycle --cycle-id 1 --revenue-sats 100000
python3 tools/seed_organism.py status
```

Local state is written under `.cursiveos/seed/` and is intentionally ignored by git.

## Linux test-host loop

Use this path on a Linux machine that can safely run the existing CursiveOS full-test harness. This is the intended non-technical tester path: open Terminal, paste one command, and let the local runner clone/update the repo before running the seed organism.

```bash
command -v curl >/dev/null 2>&1 || command -v wget >/dev/null 2>&1 || { sudo apt-get update && sudo apt-get install -y curl; }; (curl -fsSL https://raw.githubusercontent.com/connormatthewdouglas/CursiveOS/main/seed-organism-linux-test.sh || wget -qO- https://raw.githubusercontent.com/connormatthewdouglas/CursiveOS/main/seed-organism-linux-test.sh) | bash
```

The command above runs the bootstrap script at `seed-organism-linux-test.sh`. For development, the same flow can be run from an existing checkout:

```bash
python3 tools/seed_organism.py init
python3 tools/seed_organism.py run-variant \
  --variant references/seed-organism/variant.example.json \
  --execute \
  --cycle-id 1
```

The `--execute` mode is Linux-only. It runs `cursiveos-full-test-v1.4.sh` with the variant preset path, parses the produced summary log, and turns the result into the same seed organism sensor bundle used by fixture mode.

## Artifact Contract

Each evaluated variant writes an audit bundle:

- `variant.json`
- `metrics.json`
- `sensor-result.json`
- `regression-result.json`
- `bundle-manifest.json`

Accepted variants append to `.cursiveos/seed/ledger/ledger.jsonl`. All variants append sensor and regression results whether accepted, rejected, invalid, or inconclusive.

## Sensor Direction

Genesis performance scoring treats:

- higher network throughput as positive
- lower cold-start latency as positive
- higher sustained tokens/sec as positive
- higher idle power as a reported cost and optional penalty

The regression gate is separate from scoring. A variant with good performance is still rejected if the full-test, reversibility, or host-safety gate fails.

## CursiveRoot Boundary

This local implementation does not write to CursiveRoot yet. It exports production-shaped JSON artifacts so the Hub/Supabase ingestion endpoint can be added after the local loop is stable.
