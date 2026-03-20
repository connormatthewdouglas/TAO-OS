# TAO-OS Action Plan
**Last updated:** 2026-03-20
**Current preset:** v0.7 (25 tweaks) — validated on Arc A750 + RX 580
**Current wrapper:** v1.3

---

## Where We Are

Two machines validated, tao-forge live, results auto-submitting. The tcp_rmem/wmem fix in v0.7 was the biggest single jump yet — both rigs now saturate ~1 Gbit/s tuned. Cold-start consistent across all runs. Self-fleet phase is most of the way done.

**Immediate data gaps:**
- RX 580 only has 1 v0.7 run (need ≥2 for full validation)
- Remaining fleet not yet tested: laptops, all-in-one
- `power_idle_tuned_w` is null on all tao-forge runs — wrapper bug, needs fixing

---

## Phase 1 — Complete Fleet + Fix Bugs (now)

### Data collection needed
- [ ] Second v0.7 run on RX 580 (Stardust) — completes v0.7 validation
- [ ] Run v0.7 on every remaining fleet machine (laptops, all-in-one)
- [ ] Run on 1–2 trusted friends' PCs — final pre-gate data

### Bug to fix
- [ ] **Power tuned reading is null** — `power_idle_tuned_w` never captures in the wrapper.
  The presets get applied, `sleep 3`, turbostat reads, but something in the read_watts() capture is failing after apply. Fix this before v0.8 so we have clean power data going forward.

### CLAUDE.md update
- [ ] Update CLAUDE.md to reflect v0.7 as current, v1.3 as wrapper, tao-forge as database

---

## Phase 2 — Preset v0.8 (next tweak batch)

Research-backed candidates, ordered by expected impact and simplicity:

### High confidence — easy to measure
| Tweak | Value | Why | Benchmark |
|-------|-------|-----|-----------|
| `vm.min_free_kbytes` | 262144 (256MB) | Keeps memory headroom available during model load — prevents kernel from reclaiming pages mid-inference | cold-start |
| `net.ipv4.tcp_fastopen` | 3 | Reduces TCP connection setup overhead for repeated validator connections (client + server) | network |
| `net.ipv4.tcp_notsent_lowat` | 131072 | Reduces TCP send buffer bloat, improves latency under sustained load | network |

### Medium confidence — hardware-dependent
| Tweak | Value | Why | Risk |
|-------|-------|-----|------|
| IRQ affinity | pin NIC IRQs to non-inference cores | Prevents network interrupts from preempting inference threads on multi-core CPUs | Complex — IRQ numbers vary by NIC/kernel. Needs careful detection. |
| AMD P-state driver check | verify `amd_pstate` active | Newer kernels use amd_pstate over acpi_cpufreq — better frequency response. If not active, document why. | Read-only check first |
| `kernel.perf_event_paranoid` | 3 | Disables perf sampling overhead entirely | Low risk, minimal gain |

### Rule: each tweak needs ≥2 paired runs on Arc A750 before entering preset stack.

---

## Phase 3 — Benchmark v0.3 (measurement improvements)

Current cold-start benchmark measures average over 5 calls. Validators see **tail latency** — the worst-case request, not the average. This matters for active set membership.

- [ ] **`benchmark-inference-v0.3.sh`** — add p95/p99 cold-start latency alongside average
  - Increase calls from 5 → 10 per pass for better statistics
  - Report: avg, p50, p95, p99
  - Submit p99 to tao-forge (add column to runs table)

- [ ] **Concurrent connection benchmark** (new) — validates somaxconn + netdev_max_backlog
  - Simulate N simultaneous validator connections
  - Measure connection queue depth and drop rate baseline vs tuned
  - These v0.7 tweaks currently have no dedicated benchmark

---

## Phase 4 — v1.5 Gate (external fleet)

**Gate conditions (from CLAUDE.md):**
- 5+ external miners running the wrapper
- Clean safety record (no bricked systems, no data loss)
- Documented ≥1.5% average mining/inference gain confirmed externally
- tao-forge confirmed receiving auto-submit from machines we don't control

**Prep work before opening to externals:**
- [ ] Safety audit: test `--undo` on every fleet machine, verify full revert
- [ ] Verify wrapper works cleanly on a fresh git clone (no assumptions about prior state)
- [ ] tao-forge: confirm SELECT (read) policy works for public status pull
- [ ] Write a one-page "what TAO-OS does to your system" plain-English explainer for external testers

---

## Phase 5 — v2.0 Infrastructure (post-gate)

Once external fleet is live and gate clears:

### Intel Arc SYCL backend
- llama.cpp built with Intel SYCL → stable 7B+ inference on Arc
- Current Vulkan backend crashes on 3B+ models (fp16 precision bug)
- This unlocks Arc as a serious mining GPU for larger subnets
- **Parked until v1.5 gate clears** (per kill switch rule)

### Batched inference benchmark
- Real mining workloads aren't one request at a time
- Simulate concurrent validator queries, measure throughput under load
- Validates scheduler + somaxconn tweaks under realistic conditions

### SN64 Chutes live validator test
- Run a real miner on SN64 with and without presets
- Measure actual validator scores, not simulated benchmarks
- This is the ultimate proof of concept

---

## Phase 6 — v3.0 Subnet (long term)

Design a Bittensor subnet where the flywheel runs itself:

1. **Miners submit OS optimization proposals** (sysctl values, kernel flags, driver patches)
2. **Validators run standardized benchmarks** and score real gains
3. **TAO emissions** reward highest-impact contributions
4. **tao-forge becomes the scoring layer** — every result verifiable on-chain

Infrastructure needed:
- Subnet registration on Bittensor
- Standardized benchmark protocol (validators need to run the same tests)
- Automated result verification (prevent gaming)
- Proposal format (structured tweak submission)

---

## Phase 7 — Full Distribution (v4.0+)

- TAO-OS bootable ISO with pre-applied optimizations
- Custom kernel builds (patches from subnet contributors)
- Dedicated package repositories
- Gaming optimization track (same kernel/scheduler/driver work benefits both)
- Goal: the default Linux for Bittensor mining, inference, and performance computing

---

## Scope Rules (standing)

- **Complexity Kill Switch:** >1 new package required → simplify or drop
- **Validation rule:** ≥2 paired runs before any tweak enters preset stack
- **No permanent changes:** every tweak temporary by default, --undo always works
- **Self-fleet only** until v1.5 gate — no public solicitation before then
- **NVIDIA is not the primary focus** — AMD CPU + Intel Arc first

---

## What I Need From You

| Item | Why |
|------|-----|
| Second v0.7 run on RX 580 | Complete v0.7 validation (currently 1/2) |
| v0.7 runs on laptops + all-in-one | Diverse hardware = stronger claim at v1.5 gate |
| Trusted friend machine runs | Pre-gate external data |
| Confirmation when power reading works | Need to debug turbostat capture in wrapper |
