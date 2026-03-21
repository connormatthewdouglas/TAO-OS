# TAO-OS Changelog

## Presets

| Version | Change |
|---------|--------|
| v0.1 | CPU governor → performance, energy preference → performance |
| v0.2 | + Net buffers: rmem/wmem_max → 16MB |
| v0.3 | + Scheduler autogroup disabled, BBR+fq, swappiness=10, NMI watchdog, C2/C3 idle states disabled, THP=always, GPU SLPC+freq |
| v0.4 | Dropped CPU min-freq lock (caused thermal regression +3°C, -0.21%) |
| v0.5 | All v0.4 tweaks + GPU SLPC, min=2000MHz, boost=2400MHz, C2/C3 disable, THP |
| v0.6 | + AMD CPU boost ensure-enabled, THP defrag=madvise, vm.dirty_ratio/background_ratio, SYCL persistent cache (Arc only). Added --dry-run flag. |
| v0.7 | Current. +7 research-backed tweaks: tcp_rmem/wmem ceiling (closes auto-tuner gap), C6 disable by name (cross-BIOS robust), NUMA balancing off (single-node Ryzen), THP compaction_proactiveness=0, netdev_max_backlog=5000, sched_min_granularity_ns=1ms, somaxconn=4096. Total: 25 tweaks. |

## Benchmarks

| Version | Change |
|---------|--------|
| benchmark-v0.1/v0.2 | Early versions with tweaks baked in — not valid baselines |
| benchmark-v0.4 | First clean CPU-only mining sim (no live progress) |
| benchmark-v0.5 | + Live progress + AMD Tctl temp — had subshell race condition |
| benchmark-v0.6 | Fixed race condition, reliable live progress + temp — best CPU reference |
| benchmark-v0.7 | Regression: sysbench output captured to variable, broke progress/temp/logging |
| benchmark-v0.8-vanilla | Fixed v0.7, `last_print` tracker for progress, sudo PIN pattern |
| benchmark-v0.9-paired | Paired baseline+tuned in same thermal window |
| benchmark-inference-v0.1 | Sustained tok/s via ollama REST API — model stays warm |
| benchmark-inference-v0.2 | Cold-start latency — model unloads between calls, GPU freq impact |
| benchmark-network-v0.1 | TCP throughput via iperf3 + tc netem WAN simulation |

## Full Test Wrapper

| Version | Change |
|---------|--------|
| v1.0 | First release — runs all 3 benchmarks, clean summary table, sudo prompt (no hardcoded PIN), turbostat idle power measurement |
| v1.1 | Points to presets v0.6, fixes hardcoded preset path in power section, auto-appends run results to hardware-profiles.json |
| v1.2 | Auto-submits to tao-forge (Supabase) after every run. Zero setup — works from any internet-connected machine. Local JSON backup retained. |
| v1.3 | Current. Points to tao-os-presets-v0.7.sh (25 tweaks). |

## Setup

| Version | Change |
|---------|--------|
| setup-intel-arc.sh | One-shot Intel Arc OpenCL + Level Zero + ollama Vulkan backend |

## Hardware Database

| Version | Change |
|---------|--------|
| hardware-profiles.json v1.0 | Initial schema. Seeded with 5 runs from Arc A750 rig (2026-03-18). Auto-populated by tao-os-full-test-v1.1.sh on each run. |

## Benchmark Results

### v0.6 presets — AMD Ryzen 7 5700 · Intel Arc A750

| Benchmark | Baseline | Tuned | Delta | Preset validated |
|-----------|---------|-------|-------|-----------------|
| Network throughput (WAN sim) | 95.6–174.1 Mbit/s | 383–388 Mbit/s | +123–301% | BBR + 16MB buffers |
| Cold-start latency | 1022–1024ms | 993–998ms | **-2.41 to -2.86%** | GPU min-freq 2000MHz |
| Sustained inference (warm) | 75–76 tok/s | 75–77 tok/s | ~flat | — |

### v0.7 presets — AMD Ryzen 7 5700 · Intel Arc A750 (2 runs, validated)

| Benchmark | Baseline | Tuned | Delta | Preset validated |
|-----------|---------|-------|-------|-----------------|
| Network throughput (WAN sim) | 139.6–181.2 Mbit/s | **999.8–1003.6 Mbit/s** | **+454–616%** | tcp_rmem/wmem ceiling fix |
| Cold-start latency | 1020.6–1023.5ms | 996.5–996.7ms | **-2.34 to -2.63%** | GPU min-freq 2000MHz |
| Sustained inference (warm) | 75–76 tok/s | 76–77 tok/s | **+1.22–1.46%** | sched_min_granularity_ns |

### v0.6 presets — AMD FX-8350 · RX 580 (Stardust)

| Benchmark | Baseline | Tuned | Delta | Preset validated |
|-----------|---------|-------|-------|-----------------|
| Network throughput (WAN sim) | 131.4 Mbit/s | 381.9 Mbit/s | **+190.6%** | BBR + 16MB buffers |
| Cold-start latency | 2493.1ms | 2098.4ms | **-15.83%** | CPU governor + C-states |
| Sustained inference (warm) | 19.49 tok/s | 20.46 tok/s | **+4.97%** | CPU governor |

### v0.7 presets — AMD FX-8350 · RX 580 (Stardust, 1 run)

| Benchmark | Baseline | Tuned | Delta | Preset validated |
|-----------|---------|-------|-------|-----------------|
| Network throughput (WAN sim) | 171 Mbit/s | **1181.9 Mbit/s** | **+591%** | tcp_rmem/wmem ceiling fix |
| Cold-start latency | 2461.6ms | 2095.5ms | **-14.87%** | CPU governor + C-states |
| Sustained inference (warm) | 19.59 tok/s | 20.47 tok/s | **+4.49%** | CPU governor |

### Approved tweak — 2026-03-20
- `vm.min_free_kbytes=262144`: Keeps 256MB memory headroom available during model load. Prevents kernel from reclaiming pages mid-inference, reducing cold-start jitter. Research-backed v0.8 candidate (Benjamin's list).
  - Network: +766.0%
  - Cold-start: -1.6%
  - Power: +0.2W
