#!/usr/bin/env bash
# TAO-OS benchmark-network-v0.1.sh
# Measures TCP throughput and latency under simulated WAN conditions.
#
# WHY THIS MATTERS FOR MINING:
#   Bittensor validators/miners communicate over the internet.
#   - BBR congestion control sustains higher throughput than CUBIC on lossy links
#   - 16MB socket buffers prevent drops during burst traffic (chain sync, weight pushes)
#   - tcp_slow_start_after_idle disabled: throughput doesn't drop after mining idle periods
#
# METHOD:
#   Uses tc netem on loopback to simulate WAN: 50ms RTT + 0.5% packet loss.
#   (50ms is typical inter-datacenter RTT; 0.5% loss is moderate internet conditions.)
#   Runs iperf3 client→server through this simulated link.
#   Paired: baseline (no presets) → tuned (BBR + buffers), same session.
#   Cleans up netem rules on exit.
#
# Usage: ./benchmark-network-v0.1.sh [preset-script]

set -euo pipefail

PRESET_SCRIPT="${1:-./tao-os-presets-v0.5.sh}"
SP="2633"
s()  { echo "$SP" | sudo -S "$@" 2>/dev/null; }
sc() { echo "$SP" | sudo -S bash -c "$1"; }

DURATION=10      # iperf3 test duration per run (seconds)
RUNS=3           # runs per pass (averaged)
WAN_DELAY="25ms" # one-way delay → 50ms RTT
WAN_LOSS="0.5%"  # packet loss rate
IPERF_PORT=15201

LOG_DIR="$HOME/TAO-OS/logs"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/tao-os-network-$(date +%Y%m%d-%H%M%S).log"
PASS_RESULT=""

log() { echo "$1" | tee -a "$LOG_FILE"; }

# ── Cleanup trap ──────────────────────────────────────────────────────────────
cleanup() {
    # Remove netem rules if they exist
    sc "tc qdisc del dev lo root 2>/dev/null || true"
    # Kill any leftover iperf3 server
    pkill -f "iperf3 -s" 2>/dev/null || true
}
trap cleanup EXIT

# ── Preflight ─────────────────────────────────────────────────────────────────
log "Ensuring clean state for baseline..."
bash "$PRESET_SCRIPT" --undo 2>/dev/null | grep -E "Revert|reverted|No backup" | sed 's/^/  /' || true
sleep 2

# ── Apply WAN simulation (tc netem on loopback) ──────────────────────────────
apply_netem() {
    # Add netem to loopback: 25ms one-way = ~50ms RTT, 0.5% loss
    sc "tc qdisc replace dev lo root netem delay $WAN_DELAY loss $WAN_LOSS"
    log "  WAN sim: ${WAN_DELAY} one-way + ${WAN_LOSS} loss (loopback)"
}

remove_netem() {
    sc "tc qdisc del dev lo root 2>/dev/null || true"
}

# ── Start iperf3 server ───────────────────────────────────────────────────────
start_server() {
    pkill -f "iperf3 -s" 2>/dev/null || true
    sleep 1
    iperf3 -s -p $IPERF_PORT -D --logfile /tmp/tao-iperf3-server.log 2>/dev/null
    sleep 1
}

# ── Parse iperf3 JSON output ──────────────────────────────────────────────────
parse_iperf() {
    python3 -c "
import json, sys
try:
    d = json.load(sys.stdin)
    mbps   = d['end']['sum_received']['bits_per_second'] / 1e6
    retx   = d['end']['sum_sent'].get('retransmits', 0)
    rtt_ms = d['end']['streams'][0]['sender'].get('mean_rtt', 0) / 1000
    print(f'{mbps:.1f}|{retx}|{rtt_ms:.1f}')
except Exception as e:
    print('0|0|0')
"
}

# ── Run a pass ────────────────────────────────────────────────────────────────
run_pass() {
    local label="$1"
    log ""
    log "--- $label ---"
    log "  Time:   $(date +%H:%M:%S)"

    local cc rmem
    cc=$(cat /proc/sys/net/ipv4/tcp_congestion_control 2>/dev/null || echo N/A)
    rmem=$(cat /proc/sys/net/core/rmem_max 2>/dev/null || echo N/A)
    log "  TCP CC:    $cc"
    log "  rmem_max:  $rmem bytes ($(echo "scale=1; $rmem/1048576" | bc -l) MB)"

    apply_netem

    log "  Running $RUNS iperf3 passes (${DURATION}s each)..."
    local mbps_sum=0 retx_sum=0 rtt_sum=0 i=1
    local mbps_min=999999 mbps_max=0

    for _ in $(seq 1 $RUNS); do
        local result mbps retx rtt
        result=$(iperf3 -c 127.0.0.1 -p $IPERF_PORT -t $DURATION -J 2>/dev/null | parse_iperf)
        mbps=$(echo "$result" | cut -d'|' -f1)
        retx=$(echo "$result" | cut -d'|' -f2)
        rtt=$(echo  "$result" | cut -d'|' -f3)
        log "    Run $i: ${mbps} Mbit/s | retransmits: $retx | RTT: ${rtt}ms"
        mbps_sum=$(echo "$mbps_sum + $mbps" | bc -l)
        retx_sum=$(echo "$retx_sum + $retx" | bc -l)
        rtt_sum=$(echo  "$rtt_sum  + $rtt"  | bc -l)
        (( $(echo "$mbps < $mbps_min" | bc -l) )) && mbps_min=$mbps
        (( $(echo "$mbps > $mbps_max" | bc -l) )) && mbps_max=$mbps
        (( i++ ))
    done

    remove_netem

    local avg_mbps avg_retx avg_rtt
    avg_mbps=$(echo "scale=1; $mbps_sum / $RUNS" | bc -l)
    avg_retx=$(echo "scale=1; $retx_sum / $RUNS" | bc -l)
    avg_rtt=$(echo  "scale=1; $rtt_sum  / $RUNS" | bc -l)

    log "  Avg: ${avg_mbps} Mbit/s | retransmits: ${avg_retx} | RTT: ${avg_rtt}ms"
    log "  Range: ${mbps_min} – ${mbps_max} Mbit/s"
    PASS_RESULT="$avg_mbps"
}

# ── Header ────────────────────────────────────────────────────────────────────
log "TAO-OS Network Benchmark v0.1"
log "Preset:   $PRESET_SCRIPT"
log "WAN sim:  ${WAN_DELAY} one-way delay + ${WAN_LOSS} loss (loopback netem)"
log "Duration: ${DURATION}s per run × ${RUNS} runs"
log "Started:  $(date)"
log "========================================"
log "Hardware:"
log "  CPU: $(lscpu | grep 'Model name:' | cut -d':' -f2 | xargs)"
log "  NIC: $(ip link show | grep -v 'lo\|link' | grep '^[0-9]' | awk '{print $2}' | tr -d ':' | head -3 | tr '\n' ' ')"
log "========================================"

# Start iperf3 server once (stays up for both passes)
log ""
log "Starting iperf3 server on port $IPERF_PORT..."
start_server
log "  Server ready."

# ── PASS 1: Baseline ──────────────────────────────────────────────────────────
log ""
log "PASS 1 — BASELINE (CUBIC, default buffers)"
run_pass "BASELINE"
BASELINE="$PASS_RESULT"

# ── Apply presets ─────────────────────────────────────────────────────────────
log ""
log "Applying presets: $PRESET_SCRIPT"
bash "$PRESET_SCRIPT" --apply-temp 2>&1 | grep "✓\|WARNING\|skip" | sed 's/^/  /' | tee -a "$LOG_FILE"
log "Presets applied."

# ── PASS 2: Tuned ─────────────────────────────────────────────────────────────
log ""
log "PASS 2 — TUNED (BBR + 16MB buffers)"
run_pass "TUNED"
TUNED="$PASS_RESULT"

# ── Undo presets ──────────────────────────────────────────────────────────────
log ""
log "Reverting presets..."
bash "$PRESET_SCRIPT" --undo 2>&1 | grep "✓\|Revert" | sed 's/^/  /' | tee -a "$LOG_FILE"

# ── Results ───────────────────────────────────────────────────────────────────
if (( $(echo "$BASELINE > 0" | bc -l) )); then
    DELTA=$(echo "scale=2; ($TUNED - $BASELINE) * 100 / $BASELINE" | bc -l)
else
    DELTA="N/A"
fi

log ""
log "========================================"
log "NETWORK BENCHMARK RESULTS"
log "  WAN sim: ${WAN_DELAY} one-way + ${WAN_LOSS} loss"
log "  Baseline (CUBIC): ${BASELINE} Mbit/s"
log "  Tuned (BBR):      ${TUNED} Mbit/s"
log "  Delta:            +${DELTA}%  (positive = better)"
log "========================================"
log "Log: $LOG_FILE"
log "Complete: $(date)"
