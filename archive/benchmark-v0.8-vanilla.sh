#!/usr/bin/env bash
# TAO-OS benchmark-v0.8-vanilla.sh
# Vanilla mode: NO tweaks. Pure measurement + live progress every 30s with CPU temp.
# Fix over v0.6: progress loop uses last_print tracker (not % 30) so it never misses
# a 30s interval under load. Temp file goes to /tmp to avoid CWD issues.

set -euo pipefail

SP="2633"
s() { echo "$SP" | sudo -S "$@" 2>/dev/null; }

LOG_DIR="$HOME/TAO-OS/logs"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/tao-os-bench-$(date +%Y%m%d-%H%M%S).log"
BASELINE_FILE="$HOME/TAO-OS/last_baseline.txt"
SYSBENCH_TMP="/tmp/tao-os-sysbench-$$.out"

log() { echo "$1" | tee -a "$LOG_FILE"; }

log "TAO-OS Mining Benchmark v0.8 (Vanilla - No Tweaks)"
log "Started: $(date)"
log "----------------------------------------"

# ── Hardware & Current State ─────────────────────────────────────────────────
log "Hardware & Current State:"
log "CPU Model:               $(lscpu | grep 'Model name:' | cut -d':' -f2 | xargs)"
log "Cores/Threads:           $(nproc) logical CPUs"
log "RAM Total:               $(free -h | grep Mem: | awk '{print $2}')"
log "Kernel:                  $(uname -r)"
log "Distro:                  $(grep PRETTY_NAME /etc/os-release | cut -d'"' -f2)"
log "GPU:                     $(lspci | grep -i 'VGA\|3D\|Display' | cut -d: -f3 | xargs || echo 'None detected')"
log "CPU Governor:            $(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor 2>/dev/null || echo 'N/A')"
log "Energy Perf Preference:  $(cat /sys/devices/system/cpu/cpu0/cpufreq/energy_performance_preference 2>/dev/null || echo 'N/A')"
log "----------------------------------------"

# ── Deps ─────────────────────────────────────────────────────────────────────
log "Checking dependencies..."
for pkg in sysbench lm-sensors bc; do
    if ! command -v "$pkg" &>/dev/null; then
        log "Installing $pkg..."
        s apt update -y && s apt install -y "$pkg"
    fi
done
s sensors-detect --auto >/dev/null 2>&1 || true

# ── Temp helper ──────────────────────────────────────────────────────────────
get_temp() {
    sensors 2>/dev/null \
        | grep -E 'Tctl|Tdie|Package id [0-9]+' \
        | grep -oP '\+\K[0-9.]+' \
        | head -1 \
        || echo "N/A"
}

# ── Benchmark Loop: 3 × 5 min ────────────────────────────────────────────────
EVENTS=()
PING_LATENCIES=()

for i in {1..3}; do
    log ""
    log "Run $i / 3 starting at $(date +%H:%M:%S)"

    # Network flood (simulates Bittensor gossip/chain traffic)
    s ping -f -c 150000 8.8.8.8 >/dev/null 2>&1 &
    PING_PID=$!

    # CPU stress (all threads, 300s)
    log "CPU stress started (300s) – progress every 30s..."
    start_time=$(date +%s)
    sysbench cpu --threads="$(nproc)" --time=300 run >"$SYSBENCH_TMP" 2>&1 &
    SYSBENCH_PID=$!

    # Progress loop — last_print tracker avoids missing 30s marks under load
    last_print=0
    while kill -0 "$SYSBENCH_PID" 2>/dev/null; do
        elapsed=$(( $(date +%s) - start_time ))
        if (( elapsed - last_print >= 30 && elapsed > 0 )); then
            log "  Elapsed: ${elapsed}s / 300s | Temp: $(get_temp)°C"
            last_print=$elapsed
        fi
        sleep 2
    done
    wait "$SYSBENCH_PID"

    s kill "$PING_PID" 2>/dev/null || true
    wait "$PING_PID" 2>/dev/null || true

    events_per_sec=$(grep "events per second:" "$SYSBENCH_TMP" | awk '{print $4}' || echo "0")
    EVENTS+=("$events_per_sec")

    ping_sample=$(ping -c 10 8.8.8.8 | tail -1 | awk -F'/' '{print $5}' || echo "N/A")
    PING_LATENCIES+=("$ping_sample")

    log "Run $i result:  $events_per_sec events/sec  |  ping avg: ${ping_sample}ms"
    log "----------------------------------------"

    rm -f "$SYSBENCH_TMP"
done

# ── Results & Baseline Delta ─────────────────────────────────────────────────
sum=0
for val in "${EVENTS[@]}"; do sum=$(echo "$sum + $val" | bc -l); done
avg=$(echo "scale=2; $sum / ${#EVENTS[@]}" | bc -l)

log ""
log "FINAL RESULTS (v0.8 Vanilla)"
log "Average events/sec: $avg"

if [[ -f "$BASELINE_FILE" ]]; then
    prev=$(cat "$BASELINE_FILE")
    delta=$(echo "scale=2; ($avg - $prev) * 100 / $prev" | bc -l)
    log "Previous baseline:  $prev events/sec"
    log "Delta:              ${delta}%  (positive = better)"
else
    log "No previous baseline – this is your first run."
fi

echo "$avg" > "$BASELINE_FILE"
log "Log: $LOG_FILE"
log "Complete at $(date)"
