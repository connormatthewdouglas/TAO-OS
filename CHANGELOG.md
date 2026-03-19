# TAO-OS Changelog

## Presets

| Version | Change |
|---------|--------|
| v0.1 | CPU governor → performance, energy preference → performance |
| v0.2 | + Net buffers: rmem/wmem_max → 16MB |
| v0.3 | + Scheduler autogroup disabled, BBR+fq, swappiness=10, NMI watchdog, C2/C3 idle states disabled, THP=always, GPU SLPC+freq |
| v0.4 | Dropped CPU min-freq lock (caused thermal regression +3°C, -0.21%) |
| v0.5 | All v0.4 tweaks + GPU SLPC, min=2000MHz, boost=2400MHz, C2/C3 disable, THP |
| v0.6 | Current. + AMD CPU boost ensure-enabled, THP defrag=madvise, vm.dirty_ratio/background_ratio, SYCL persistent cache (Arc only). Added --dry-run flag. |

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
| v1.1 | Current. Points to presets v0.6, fixes hardcoded preset path in power section, auto-appends run results to hardware-profiles.json |

## Setup

| Version | Change |
|---------|--------|
| setup-intel-arc.sh | One-shot Intel Arc OpenCL + Level Zero + ollama Vulkan backend |

## Hardware Database

| Version | Change |
|---------|--------|
| hardware-profiles.json v1.0 | Initial schema. Seeded with 5 runs from Arc A750 rig (2026-03-18). Auto-populated by tao-os-full-test-v1.1.sh on each run. |

## Benchmark Results (test rig: AMD Ryzen 7 5700 · Intel Arc A750)

| Benchmark | Baseline | Tuned | Delta | Preset validated |
|-----------|---------|-------|-------|-----------------|
| Network throughput (WAN sim) | 169.2 Mbit/s | 384.4 Mbit/s | **+127%** | BBR + 16MB buffers |
| Cold-start latency | 1023.6ms | 1001.1ms | **-2.19%** | GPU min-freq 2000MHz |
| Sustained inference (warm) | 68.75 tok/s | 68.07 tok/s | -0.98% (flat, expected) | — |
