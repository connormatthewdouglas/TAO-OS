# ForgeOS Rebrand Plan
**Status:** PREP ONLY — do not execute before v1.5 gate
**Prepared:** 2026-03-23
**Trigger:** v1.5 gate conditions met (5+ external machines, clean safety record, ≥1.5% avg gain)

---

## Rename Map

### TAO-OS → ForgeOS
| Old | New |
|-----|-----|
| `TAO-OS` (display name) | `ForgeOS` |
| `tao-os` (slug in filenames) | `forge-os` |
| `TAO_OS` (env vars) | `FORGE_OS` |
| `~/TAO-OS` (workspace dir) | `~/ForgeOS` |
| GitHub repo: `TAO-OS` | `ForgeOS` |

### tao-forge → forge-db (TBD — decide at gate)
`tao-forge` has equity as a name. Board should decide at v1.5 whether to keep it or rename. Supabase project rename is separate from code rename. **Do not rename tao-forge until board decision.**

---

## Files Requiring Changes

### Scripts (new versioned files — never overwrite)
| File | Change |
|------|--------|
| `tao-os-full-test-v1.4.sh` | New: `forge-os-full-test-v1.5.sh` — replace all TAO-OS/tao-os refs |
| `tao-os-presets-v0.8.sh` | New: `forge-os-presets-v0.9.sh` — replace header/comments |
| `tao-os-presets-integration-wq013.sh` | Archive — integration test artifact, not worth porting |
| `tao-forge-status.sh` | Rename/keep as `forge-status.sh` (or keep tao-forge if brand stays) |
| `run-full-test.sh` | Update wrapper call to new script name |
| `setup-intel-arc.sh` | Minor: update any TAO-OS path refs in comments |
| All `benchmarks/*.sh` | Update header comments only — logic unchanged |

### Dashboard
| File | Change |
|------|--------|
| `dashboard/index.html` | Title: "ForgeOS Mission Control" · all display strings |
| `dashboard/server.py` | `WORKSPACE` path if dir renamed · any string refs |
| `dashboard/spend_monitor.py` | Path refs, Telegram alert strings |
| `dashboard/session_watchdog.py` | Path refs |
| `dashboard/run_loop.py` | Path refs |
| `dashboard/approval_watcher.py` | Path refs |

### Docs / Markdown
| File | Change |
|------|--------|
| `README.md` | Full rewrite at gate (Copper docket) — new name throughout |
| `docs/white-paper.md` | Full rewrite at gate (Copper docket) — new name throughout |
| `docs/action-plan.md` | Update project name refs |
| `references/CLAUDE.md` | Update project name, last updated date |
| `references/README.md` | Update project name |
| `references/CHANGELOG.md` | Add rebrand entry |
| `MEMORY.md` | Update project name refs |
| `HEARTBEAT.md` | Update if any TAO-OS refs |
| `USER.md` | Update if any TAO-OS refs |

### Agent / Config Files
| File | Change |
|------|--------|
| `agents/specs/benchmark-agent.md` | Update script name refs |
| `agents/specs/queue-worker.md` | Update script name refs |
| `agents/handoff-schema.json` | Update any name refs |
| `.claude/settings.local.json` | Update workspace path if dir renamed |

### GitHub
| Item | Action |
|------|--------|
| Repo name | Rename `TAO-OS` → `ForgeOS` in GitHub settings |
| Repo description | Update |
| README one-liner | Update clone URL to new repo name |
| Topics/tags | Update |

---

## Execution Order (when gate is hit)

1. **Board confirms v1.5 gate met** — Connor calls it
2. **Decide tao-forge naming** — keep or rename (board vote)
3. **Create new script versions** — forge-os-full-test-v1.5.sh, forge-os-presets-v0.9.sh
4. **Update all docs** — README, white-paper, CLAUDE.md, action-plan.md
5. **Update dashboard** — index.html title + strings, server.py paths
6. **Update agent files** — specs, handoff schema
7. **Single commit** — `feat: rebrand TAO-OS → ForgeOS (v1.5 gate)`
8. **Rename GitHub repo** — settings → rename (breaks old clone URLs, README updates automatically)
9. **Update one-liner** in README with new clone URL
10. **Announce** — Connor decides channel/timing

---

## What Does NOT Change
- Supabase database (unless board decides to rename tao-forge)
- `machine_id` values in tao-forge — hardware fingerprints stay
- Benchmark methodology — nothing scientific changes
- `.openclaw/` config — Copper's runtime, not project-facing
- Archive scripts — leave as-is, they're history

---

## Notes
- GitHub repo rename automatically redirects old clone URLs for ~1 year
- `~/TAO-OS` workspace dir rename is optional — scripts use `$HOME/TAO-OS` internally; update or symlink
- Do this in one PR/commit for a clean git history entry
