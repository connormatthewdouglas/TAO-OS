#!/usr/bin/env bash
# TAO-OS benchmark-v0.4-mining-sim.sh
# Purpose: Simulate Bittensor mining load (CPU + network) for 5 min × 3 runs, apply common tweaks, log results
# Version: 0.4 – auto deps + sustained load + tweaks + simple averaging

set -euo pipefail

LOG_DIR="$HOME/TAO-OS/logs"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/tao-os-bench-$(date +%Y%m%d-%H%M%S).log"

echo "TAO-OS Mining Benchmark v0.4" | tee -a "$LOG_FILE"
echo "Started: $(date)" | tee -a "$LOG_FILE"
echo "----------------------------------------" | tee -a "$LOG_FILE"

# ── 1. Dependency check & install ───────────────────────────────────────────
echo "Checking / installing dependencies..." | tee -a "$LOG_FILE"

if ! command -v sysbench &> /dev/null; then
    echo "Installing sysbench..." | tee -a "$LOG_FILE"
    sudo apt update -y && sudo apt install -y sysbench
fi

if ! command -v sensors &> /dev/null; then
    echo "Installing lm-sensors..." | tee -a "$LOG_FILE"
    sudo apt install -y lm-sensors
    sudo sensors-detect --auto || true
fi

if ! command -v bc &> /dev/null; then
    echo "Installing bc..." | tee -a "$LOG_FILE"
    sudo apt install -y bc
fi

# ── 2. Apply common mining-relevant tweaks (non-persistent) ──────────────────
echo "Applying performance tweaks (temporary)..." | tee -a "$LOG_FILE"

# CPU governor → performance
if command -v cpupower &> /dev/null; then
    sudo cpupower frequency-set -g performance || echo "cpupower not working – skipping" | tee -a "$LOG_FILE"
else
    echo "cpupower not found – skipping governor set" | tee -a "$LOG_FILE"
fi

# Intel energy bias (if Intel CPU)
if grep -qi "intel" /proc/cpuinfo; then
    echo "Setting Intel energy/performance bias to max performance..." | tee -a "$LOG_FILE"
    echo "performance" | sudo tee /sys/devices/system/cpu/cpu*/cpufreq/energy_performance_preference || true
fi

# ── 3. Run benchmark loop: 3 × 5-minute sustained loads ─────────────────────
EVENTS=()
PING_AVG_LATENCIES=()

for i in {1..3}; do
    echo "" | tee -a "$LOG_FILE"
    echo "Run $i / 3 starting at $(date +%H:%M:%S)" | tee -a "$LOG_FILE"

    # Background network stress (ping flood to simulate Bittensor gossip/chain traffic)
    sudo ping -f -c 150000 8.8.8.8 > /dev/null 2>&1 &  # -f = flood, silent
    PING_PID=$!

    # CPU stress – use all threads, sustained 300 seconds
    SYSBENCH_OUT=$(sysbench cpu --threads=$(nproc) --time=300 run 2>&1)

    # Kill ping
    sudo kill $PING_PID 2>/dev/null || true
    wait $PING_PID 2>/dev/null || true

    # Extract total number of events (higher = better)
    events_per_sec=$(echo "$SYSBENCH_OUT" | grep "events per second:" | awk '{print $4}' || echo "0")
    EVENTS+=("$events_per_sec")

    # Quick ping latency sample after load (sanity check)
    PING_SAMPLE=$(ping -c 10 8.8.8.8 | tail -1 | awk -F'/' '{print $5}' || echo "N/A")
    PING_AVG_LATENCIES+=("$PING_SAMPLE")

    echo "Run $i events/sec: $events_per_sec" | tee -a "$LOG_FILE"
    echo "Run $i avg ping latency (ms): $PING_SAMPLE" | tee -a "$LOG_FILE"
    echo "----------------------------------------" | tee -a "$LOG_FILE"
done

# ── 4. Calculate and show averages ──────────────────────────────────────────
sum_events=0
count=${#EVENTS[@]}
for val in "${EVENTS[@]}"; do
    sum_events=$(echo "$sum_events + $val" | bc -l)
done
avg_events=$(echo "scale=2; $sum_events / $count" | bc -l)

echo "" | tee -a "$LOG_FILE"
echo "FINAL RESULTS (v0.4)" | tee -a "$LOG_FILE"
echo "Average events/sec across 3 runs: $avg_events" | tee -a "$LOG_FILE"
echo "Log saved to: $LOG_FILE" | tee -a "$LOG_FILE"
echo "----------------------------------------" | tee -a "$LOG_FILE"
echo "Benchmark complete at $(date)" | tee -a "$LOG_FILE"
