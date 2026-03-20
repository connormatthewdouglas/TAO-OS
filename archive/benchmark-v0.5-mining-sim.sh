#!/usr/bin/env bash
# TAO-OS benchmark-v0.5-mining-sim.sh
# v0.5 – Added: progress indicators during runs, hardware detection/logging, baseline delta prep
# Purpose: Simulate Bittensor mining load (CPU + network) for 5 min × 3 runs with better visibility

set -euo pipefail

LOG_DIR="$HOME/TAO-OS/logs"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/tao-os-bench-$(date +%Y%m%d-%H%M%S).log"
BASELINE_FILE="$HOME/TAO-OS/last_baseline.txt"  # For future % delta

echo "TAO-OS Mining Benchmark v0.5" | tee -a "$LOG_FILE"
echo "Started: $(date)" | tee -a "$LOG_FILE"
echo "----------------------------------------" | tee -a "$LOG_FILE"

# ── 0. Hardware detection (mandatory logging) ────────────────────────────────
echo "Detecting hardware..." | tee -a "$LOG_FILE"
echo "CPU Model: $(lscpu | grep 'Model name:' | cut -d':' -f2 | xargs)" | tee -a "$LOG_FILE"
echo "CPU Cores/Threads: $(nproc) / $(lscpu | grep '^Thread(s) per core:' | awk '{print $4 * $2}')" | tee -a "$LOG_FILE"  # rough threads
echo "RAM Total: $(free -h | grep Mem: | awk '{print $2}')" | tee -a "$LOG_FILE"
echo "Kernel: $(uname -r)" | tee -a "$LOG_FILE"
echo "Distro: $(cat /etc/os-release | grep PRETTY_NAME | cut -d'"' -f2)" | tee -a "$LOG_FILE"
echo "GPU (lspci quick scan): $(lspci | grep -i 'VGA\|3D\|Display' || echo 'None detected')" | tee -a "$LOG_FILE"
echo "----------------------------------------" | tee -a "$LOG_FILE"

# ── 1. Dependency check & install ───────────────────────────────────────────
echo "Checking / installing dependencies..." | tee -a "$LOG_FILE"
for pkg in sysbench lm-sensors bc; do
    if ! command -v "$pkg" &> /dev/null; then
        echo "Installing $pkg..." | tee -a "$LOG_FILE"
        sudo apt update -y && sudo apt install -y "$pkg"
    fi
done
sudo sensors-detect --auto >/dev/null 2>&1 || true

# ── 2. Apply common mining-relevant tweaks (temporary) ───────────────────────
echo "Applying performance tweaks (temporary)..." | tee -a "$LOG_FILE"
if command -v cpupower &> /dev/null; then
    sudo cpupower frequency-set -g performance || echo "cpupower issue – skipping" | tee -a "$LOG_FILE"
fi
if grep -qi "intel" /proc/cpuinfo; then
    echo "performance" | sudo tee /sys/devices/system/cpu/cpu*/cpufreq/energy_performance_preference || true
fi

# ── 3. Run benchmark loop: 3 × 5-minute loads with progress ──────────────────
EVENTS=()
PING_LATENCIES=()

for i in {1..3}; do
    echo "" | tee -a "$LOG_FILE"
    echo "Run $i / 3 starting at $(date +%H:%M:%S)" | tee -a "$LOG_FILE"

    # Background network flood
    sudo ping -f -c 150000 8.8.8.8 > /dev/null 2>&1 & 
    PING_PID=$!

    # CPU stress with progress every 30s
    echo "Starting CPU stress (300s) – progress updates every ~30s..." | tee -a "$LOG_FILE"
    start_time=$(date +%s)
    SYSBENCH_OUT=$(sysbench cpu --threads=$(nproc) --time=300 run 2>&1 & sysbench_pid=$!; 
        while kill -0 $sysbench_pid 2>/dev/null; do
            elapsed=$(( $(date +%s) - start_time ))
            if (( elapsed % 30 == 0 && elapsed > 0 )); then
                temp=$(sensors | grep -oP 'Tctl|Tdie|Package id \d+: \+\K[0-9.]+' | head -1 || echo 'N/A')
                echo "Elapsed: ${elapsed}s / 300s | Temp: ${temp}°C" | tee -a "$LOG_FILE"
            fi
            sleep 5
        done; wait $sysbench_pid)

    # Kill ping
    sudo kill $PING_PID 2>/dev/null || true
    wait $PING_PID 2>/dev/null || true

    events_per_sec=$(echo "$SYSBENCH_OUT" | grep "events per second:" | awk '{print $4}' || echo "0")
    EVENTS+=("$events_per_sec")

    ping_sample=$(ping -c 10 8.8.8.8 | tail -1 | awk -F'/' '{print $5}' || echo "N/A")
    PING_LATENCIES+=("$ping_sample")

    echo "Run $i events/sec: $events_per_sec" | tee -a "$LOG_FILE"
    echo "Run $i avg ping latency (ms): $ping_sample" | tee -a "$LOG_FILE"
    echo "----------------------------------------" | tee -a "$LOG_FILE"
done

# ── 4. Averages + baseline save + simple delta if previous exists ───────────
sum=0
for val in "${EVENTS[@]}"; do sum=$(echo "$sum + $val" | bc -l); done
avg=$(echo "scale=2; $sum / ${#EVENTS[@]}" | bc -l)

echo "" | tee -a "$LOG_FILE"
echo "FINAL RESULTS (v0.5)" | tee -a "$LOG_FILE"
echo "Average events/sec: $avg" | tee -a "$LOG_FILE"

if [[ -f "$BASELINE_FILE" ]]; then
    prev=$(cat "$BASELINE_FILE")
    delta=$(echo "scale=2; (($avg - $prev) / $prev) * 100" | bc -l)
    echo "Previous baseline: $prev events/sec" | tee -a "$LOG_FILE"
    echo "Change: $delta% (positive = better)" | tee -a "$LOG_FILE"
fi

echo "$avg" > "$BASELINE_FILE"  # Save for next run
echo "Log: $LOG_FILE" | tee -a "$LOG_FILE"
echo "Benchmark complete at $(date)" | tee -a "$LOG_FILE"
