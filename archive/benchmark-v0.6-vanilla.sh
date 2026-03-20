#!/usr/bin/env bash
# TAO-OS benchmark-v0.6-vanilla.sh
# v0.6 – Vanilla mode: NO auto-tweaks applied. Pure measurement only.
# Updated: Improved temp detection to reliably grab AMD Tctl (k10temp) or other CPU-relevant sensors
# Purpose: Standardized mining-load test (CPU + network) for Bittensor miners.

set -euo pipefail

LOG_DIR="$HOME/TAO-OS/logs"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/tao-os-bench-$(date +%Y%m%d-%H%M%S).log"
BASELINE_FILE="$HOME/TAO-OS/last_baseline.txt"

echo "TAO-OS Mining Benchmark v0.6 (Vanilla - No Tweaks)" | tee -a "$LOG_FILE"
echo "Started: $(date)" | tee -a "$LOG_FILE"
echo "----------------------------------------" | tee -a "$LOG_FILE"

# ── Hardware & Current State Detection ──────────────────────────────────────
echo "Hardware & Current State:" | tee -a "$LOG_FILE"
echo "CPU Model: $(lscpu | grep 'Model name:' | cut -d':' -f2 | xargs)" | tee -a "$LOG_FILE"
echo "Cores/Threads: $(nproc) logical CPUs" | tee -a "$LOG_FILE"
echo "RAM Total: $(free -h | grep Mem: | awk '{print $2}')" | tee -a "$LOG_FILE"
echo "Kernel: $(uname -r)" | tee -a "$LOG_FILE"
echo "Distro: $(cat /etc/os-release | grep PRETTY_NAME | cut -d'"' -f2)" | tee -a "$LOG_FILE"
echo "GPU: $(lspci | grep -i 'VGA\|3D\|Display' | cut -d: -f3 | xargs || echo 'None detected')" | tee -a "$LOG_FILE"

# Current governor (read-only)
CURRENT_GOV=$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor 2>/dev/null || echo "N/A")
echo "Current CPU Governor: $CURRENT_GOV" | tee -a "$LOG_FILE"

# Current energy perf preference (Intel/AMD)
ENERGY_PREF=$(cat /sys/devices/system/cpu/cpu0/cpufreq/energy_performance_preference 2>/dev/null || echo "N/A")
echo "Current Energy Perf Preference: $ENERGY_PREF" | tee -a "$LOG_FILE"
echo "----------------------------------------" | tee -a "$LOG_FILE"

# ── Deps Check (install if missing, no tweaks) ──────────────────────────────
echo "Checking dependencies..." | tee -a "$LOG_FILE"
for pkg in sysbench lm-sensors bc; do
    if ! command -v "$pkg" &> /dev/null; then
        echo "Installing $pkg..." | tee -a "$LOG_FILE"
        sudo apt update -y && sudo apt install -y "$pkg"
    fi
done
sudo sensors-detect --auto >/dev/null 2>&1 || true

# ── Benchmark Loop: 3 × 5 min loads with progress ───────────────────────────
EVENTS=()
PING_LATENCIES=()

for i in {1..3}; do
    echo "" | tee -a "$LOG_FILE"
    echo "Run $i / 3 starting at $(date +%H:%M:%S)" | tee -a "$LOG_FILE"

    # Network flood background
    sudo ping -f -c 150000 8.8.8.8 > /dev/null 2>&1 &
    PING_PID=$!

    # CPU stress
    echo "CPU stress started (300s) – progress every ~30s..." | tee -a "$LOG_FILE"
    start_time=$(date +%s)
    sysbench cpu --threads=$(nproc) --time=300 run > sysbench.out 2>&1 &
    SYSBENCH_PID=$!

    # Progress loop
    while kill -0 $SYSBENCH_PID 2>/dev/null; do
        elapsed=$(( $(date +%s) - start_time ))
        if (( elapsed >= 30 && elapsed % 30 == 0 )); then
            temp=$(sensors | grep -E 'Tctl|Tdie|Package id [0-9]+|k10temp|coretemp' | grep -oP '\+\K[0-9.]+' | head -1 || echo 'N/A')
            echo "Elapsed: ${elapsed}s / 300s | Temp: ${temp}°C" | tee -a "$LOG_FILE"
        fi
        sleep 5
    done
    wait $SYSBENCH_PID

    # Kill ping
    sudo kill $PING_PID 2>/dev/null || true
    wait $PING_PID 2>/dev/null || true

    events_per_sec=$(grep "events per second:" sysbench.out | awk '{print $4}' || echo "0")
    EVENTS+=("$events_per_sec")

    ping_sample=$(ping -c 10 8.8.8.8 | tail -1 | awk -F'/' '{print $5}' || echo "N/A")
    PING_LATENCIES+=("$ping_sample")

    echo "Run $i events/sec: $events_per_sec" | tee -a "$LOG_FILE"
    echo "Run $i avg ping latency (ms): $ping_sample" | tee -a "$LOG_FILE"
    echo "----------------------------------------" | tee -a "$LOG_FILE"
    rm -f sysbench.out  # cleanup
done

# ── Results & Baseline Delta ────────────────────────────────────────────────
sum=0
for val in "${EVENTS[@]}"; do sum=$(echo "$sum + $val" | bc -l); done
avg=$(echo "scale=2; $sum / ${#EVENTS[@]}" | bc -l)

echo "FINAL RESULTS (v0.6 Vanilla)" | tee -a "$LOG_FILE"
echo "Average events/sec: $avg" | tee -a "$LOG_FILE"

if [[ -f "$BASELINE_FILE" ]]; then
    prev=$(cat "$BASELINE_FILE")
    delta=$(echo "scale=2; (($avg - $prev) / $prev) * 100" | bc -l)
    echo "Previous baseline: $prev events/sec" | tee -a "$LOG_FILE"
    echo "Change: $delta% (positive = better)" | tee -a "$LOG_FILE"
else
    echo "No previous baseline – this is your first vanilla run." | tee -a "$LOG_FILE"
fi

echo "$avg" > "$BASELINE_FILE"
echo "Log: $LOG_FILE" | tee -a "$LOG_FILE"
echo "Complete at $(date)" | tee -a "$LOG_FILE"
