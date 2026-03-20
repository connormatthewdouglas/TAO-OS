# TAO-OS Benchmark Results

Community results from `tao-os-full-test-v1.0.sh`.

**To add yours:** open a PR or paste your results table in a GitHub issue.

---

## How to read the table

- **Network throughput** — TCP through a simulated 50ms WAN link. Higher = better. The big win here is the 16MB socket buffer (default Linux is 212KB — a bottleneck on any real internet link).
- **Cold-start latency** — Time from idle GPU to first inference token. Lower = better. GPU freq lock keeps Arc from dropping to 600 MHz between requests.
- **Sustained inference** — Steady-state tok/s with model already warm. Flat is expected — this is GPU-bound Vulkan compute, CPU presets don't move it.
- **Idle power** — CPU package watts at idle. Presets cost ~5-8W (C-states disabled). Honest tradeoff.

---

## Results

### Run 1 — [@connormatthewdouglas](https://github.com/connormatthewdouglas)
**Hardware:** AMD Ryzen 7 5700 · Intel Arc A750 · 15GB RAM · Linux Mint 22.3 · kernel 6.17

| Benchmark | Baseline | Tuned | Delta |
|-----------|---------|-------|-------|
| Network throughput | 169–182 Mbit/s | 384–389 Mbit/s | **+110–127%** |
| Cold-start latency | 1021–1031ms | 999–1018ms | **-1.2% to -2.2%** |
| Sustained inference | 68–74 tok/s | 68–75 tok/s | ~flat |
| Idle power draw | 11.1W | 16.8–19.7W | +5–8W |

*5 runs across a single session. Network delta varies because CUBIC baseline has high variance (140–248 Mbit/s); BBR is stable at 380–390 Mbit/s. Cold-start direction is consistent across all runs.*

---

## Add your results

Copy this template and paste it as a GitHub issue or PR:

```
### Run — @yourusername
**Hardware:** [CPU] · [GPU] · [RAM] · [OS] · kernel [version]

| Benchmark | Baseline | Tuned | Delta |
|-----------|---------|-------|-------|
| Network throughput | | | |
| Cold-start latency | | | |
| Sustained inference | | | |
| Idle power draw | | | |

Notes: [anything unusual, errors, hardware differences]
```

---

*Want to see your hardware here? Run the one-liner in the README and share your table.*
