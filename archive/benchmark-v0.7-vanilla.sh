#!/usr/bin/env bash
# TAO-OS benchmark-v0.7-vanilla.sh
# v0.7 – Fixed progress: now uses sysbench --report-interval=30 (built-in, reliable)
# Vanilla mode: NO tweaks. Pure measurement + clean 30s progress.

set -euo pipefail

LOG_DIR="$HOME/TAO-OS/logs"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/tao-os-bench-$(date +%Y%m%d-%H%M%S).log"
BASELINE_FILE="$HOME/TAO-OS/last_baseline.txt"

echo "TAO-OS Mining Benchmark v0.7 (Vanilla - No Tweaks)"
echo "Started: $(date)"
echo "----------------------------------------"

# Hardware & Current State
echo "Hardware & Current State:"
echo "CPU Model: $(lscpu | grep 'Model name:' | cut -d':' -f2 | xargs)"
echo "Cores/Threads: $(nproc) logical CPUs"
echo "RAM Total: $(free -h | grep Mem: | awk '{print $2}')"
echo "Kernel: $(uname -r)"
echo "Distro: $(cat /etc/os-release | grep PRETTY_NAME | cut -d'"' -f2)"
echo "GPU: $(lspci | grep -i 'VGA\|3D\|Display' | cut -d: -f3 | xargs || echo 'None detected')"
CURRENT_GOV=$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor 2>/dev/null || echo "N/A")
echo "Current CPU Governor: $CURRENT_GOV"
ENERGY_PREF=$(cat /sys/devices/system/cpu/cpu0/cpufreq/energy_performance_preference 2>/dev/null || echo "N/A")
echo "Current Energy Perf Preference: $ENERGY_PREF"
echo "----------------------------------------"

# Deps
echo "Checking dependencies..."
for pkg in sysbench lm-sensors bc; do
    if ! command -v "$pkg" &> /dev/null; then
        echo "Installing $pkg..."
        sudo apt update -y && sudo apt install -y "$pkg"
    fi
done
sudo sensors-detect --auto >/dev/null 2>&1 || true

# Benchmark Loop (clean progress via sysbench built-in)
EVENTS=()
for i in {1..3}; do
    echo ""
    echo "Run $i / 3 starting at $(date +%H:%M:%S)"

    sudo ping -f -c 150000 8.8.8.8 > /dev/null 2>&1 &
    PING_PID=$!

    echo "CPU stress started (300s) – progress every 30s (built-in)..."
    SYSBENCH_OUT=$(sysbench cpu --threads=$(nproc) --time=300 --report-interval=30 run 2>&1)

    sudo kill $PING_PID 2>/dev/null || true
    wait $PING_PID 2>/dev/null || true

    events_per_sec=$(echo "$SYSBENCH_OUT" | grep "events per second:" | tail -1 | awk '{print $4}' || echo "0")
    EVENTS+=("$events_per_sec")

    ping_sample=$(ping -c 10 8.8.8.8 | tail -1 | awk -F'/' '{print $5}' || echo "N/A")

    echo "Run $i events/sec: $events_per_sec"
    echo "Run $i avg ping latency (ms): $ping_sample"
    echo "----------------------------------------"
done

# Results
sum=0
for val in "${EVENTS[@]}"; do sum=$(echo "$sum + $val" | bc -l); done
avg=$(echo "scale=2; $sum / ${#EVENTS[@]}" | bc -l)

echo "FINAL RESULTS (v0.7 Vanilla)"
echo "Average events/sec: $avg"

if [[ -f "$BASELINE_FILE" ]]; then
    prev=$(cat "$BASELINE_FILE")
    delta=$(echo "scale=2; (($avg - $prev) / $prev) * 100" | bc -l)
    echo "Previous baseline: $prev events/sec"
    echo "Change: $delta% (positive = better)"
else
    echo "No previous baseline – this is your first run."
fi

echo "$avg" > "$BASELINE_FILE"
echo "Log: $LOG_FILE"
echo "Complete at $(date)"
