#!/usr/bin/env bash
# TAO-OS benchmark-v0.9-paired.sh
# Paired test: runs one BASELINE pass then one TUNED pass in the same thermal
# window so ambient temperature drift cannot skew the comparison.
# Usage: ./benchmark-v0.9-paired.sh [preset-script]
#   preset-script  : path to preset applicator (default: ./tao-os-presets-v0.4.sh)
# The baseline pass runs with current system settings (should be at defaults).
# The preset script is applied between passes, then undone after.

set -euo pipefail

PRESET_SCRIPT="${1:-../tao-os-presets-v0.6.sh}"
if [[ -z "${TAO_SUDO_PASS:-}" ]]; then
    read -rsp "[TAO-OS] sudo password: " TAO_SUDO_PASS && echo
fi
SP="$TAO_SUDO_PASS"
export TAO_SUDO_PASS
s()  { echo "$SP" | sudo -S "$@" 2>/dev/null; }
sc() { echo "$SP" | sudo -S bash -c "$1" 2>/dev/null; }

RUN_SECONDS=60   # seconds per pass — increase for more stable data, 300 for final results

LOG_DIR="$HOME/TAO-OS/logs"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/tao-os-paired-$(date +%Y%m%d-%H%M%S).log"
SYSBENCH_TMP="/tmp/tao-os-sysbench-$$.out"

log() { echo "$1" | tee -a "$LOG_FILE"; }
PASS_RESULT=""  # set by run_pass, read by caller

log "TAO-OS Paired Benchmark v0.9"
log "Preset: $PRESET_SCRIPT"
log "Started: $(date)"
log "========================================"

# ── Hardware snapshot ────────────────────────────────────────────────────────
log "Hardware:"
log "  CPU:     $(lscpu | grep 'Model name:' | cut -d':' -f2 | xargs)"
log "  Threads: $(nproc)"
log "  RAM:     $(free -h | grep Mem: | awk '{print $2}')"
log "  Kernel:  $(uname -r)"
log "  GPU:     $(lspci | grep -i 'VGA\|3D\|Display' | cut -d: -f3 | xargs || echo 'None')"
log "========================================"

# ── Deps ─────────────────────────────────────────────────────────────────────
for pkg in sysbench lm-sensors bc; do
    if ! command -v "$pkg" &>/dev/null; then
        log "Installing $pkg..."
        s apt-get install -y "$pkg" >/dev/null 2>&1
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

# ── Single pass (5 min) ──────────────────────────────────────────────────────
run_pass() {
    local label="$1"
    log ""
    log "--- $label ---"
    log "  Start time: $(date +%H:%M:%S) | Idle temp: $(get_temp)°C"
    log "  Governor: $(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor 2>/dev/null || echo N/A)"
    log "  Energy pref: $(cat /sys/devices/system/cpu/cpu0/cpufreq/energy_performance_preference 2>/dev/null || echo N/A)"
    log "  TCP CC: $(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || echo N/A)"
    log "  Swappiness: $(sysctl -n vm.swappiness)"

    s ping -f -c $(( RUN_SECONDS * 500 )) 8.8.8.8 >/dev/null 2>&1 &
    PING_PID=$!

    local start_time
    start_time=$(date +%s)
    sysbench cpu --threads="$(nproc)" --time="$RUN_SECONDS" run >"$SYSBENCH_TMP" 2>&1 &
    SYSBENCH_PID=$!

    local last_print=0
    local peak_temp=0
    while kill -0 "$SYSBENCH_PID" 2>/dev/null; do
        local elapsed=$(( $(date +%s) - start_time ))
        if (( elapsed - last_print >= 30 && elapsed > 0 )); then
            local t
            t=$(get_temp)
            log "  ${elapsed}s / ${RUN_SECONDS}s | Temp: ${t}°C"
            # track peak temp
            if [[ "$t" != "N/A" ]] && (( $(echo "$t > $peak_temp" | bc -l) )); then
                peak_temp=$t
            fi
            last_print=$elapsed
        fi
        sleep 2
    done
    wait "$SYSBENCH_PID"

    s kill "$PING_PID" 2>/dev/null || true
    wait "$PING_PID" 2>/dev/null || true

    local events_per_sec
    events_per_sec=$(grep "events per second:" "$SYSBENCH_TMP" | awk '{print $4}' || echo "0")
    local ping_ms
    ping_ms=$(ping -c 10 8.8.8.8 | tail -1 | awk -F'/' '{print $5}' || echo "N/A")

    rm -f "$SYSBENCH_TMP"

    log "  Result: $events_per_sec events/sec | ping avg: ${ping_ms}ms | peak temp: ${peak_temp}°C"
    PASS_RESULT="$events_per_sec"
}

# ── PASS 1: Baseline (current settings, no presets) ─────────────────────────
log ""
log "PASS 1 — BASELINE (no presets)"
run_pass "BASELINE"
BASELINE="$PASS_RESULT"

# ── Apply presets ────────────────────────────────────────────────────────────
log ""
log "Applying presets from $PRESET_SCRIPT..."
bash "$PRESET_SCRIPT" --apply-temp 2>&1 | sed 's/^/  /' | tee -a "$LOG_FILE"
log "Presets applied. Starting tuned pass immediately..."

# ── PASS 2: Tuned (presets applied) ─────────────────────────────────────────
log ""
log "PASS 2 — TUNED (presets active)"
run_pass "TUNED"
TUNED="$PASS_RESULT"

# ── Undo presets ─────────────────────────────────────────────────────────────
log ""
log "Reverting presets..."
bash "$PRESET_SCRIPT" --undo 2>&1 | sed 's/^/  /' | tee -a "$LOG_FILE"

# ── Results ──────────────────────────────────────────────────────────────────
DELTA=$(echo "scale=4; ($TUNED - $BASELINE) * 100 / $BASELINE" | bc -l)

log ""
log "========================================"
log "PAIRED RESULTS"
log "  Baseline:  $BASELINE events/sec"
log "  Tuned:     $TUNED events/sec"
log "  Delta:     ${DELTA}%  (positive = better)"
log "========================================"
log "Log: $LOG_FILE"
log "Complete at $(date)"
