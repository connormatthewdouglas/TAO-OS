#!/usr/bin/env bash
# TAO-OS benchmark-inference-v0.2.sh
# Cold-start latency benchmark: measures GPU wakeup + model load penalty.
#
# WHY THIS MATTERS FOR MINING:
#   Validators query miners unpredictably. Between queries, the GPU idles at
#   300-600 MHz (default). The GPU min-freq preset (2000 MHz) keeps the GPU
#   ready, eliminating the frequency ramp-up penalty on every cold request.
#   Slow first response = lower score = dropped from active set.
#
# METHOD:
#   Forces model to unload after each call (keep_alive=0s).
#   Sleeps 15s between calls so GPU drops to idle freq.
#   Measures: load_duration (model load) + prompt_eval_duration (TTFT).
#   cold_start_total = load + TTFT — what the validator actually waits for.
#   Paired: baseline (no presets) then tuned (presets applied), same session.
#
# Usage: ./benchmark-inference-v0.2.sh [preset-script] [model]
#   preset-script : default ./tao-os-presets-v0.5.sh
#   model         : default tinyllama (must already be pulled)

set -euo pipefail

PRESET_SCRIPT="${1:-../tao-os-presets-v0.7.sh}"
MODEL="${2:-tinyllama}"
PASSES=5          # cold-start calls per pass
IDLE_SLEEP=15     # seconds to wait for GPU to drop to idle freq between calls
if [[ -z "${TAO_SUDO_PASS:-}" ]]; then
    read -rsp "[TAO-OS] sudo password: " TAO_SUDO_PASS && echo
fi
SP="$TAO_SUDO_PASS"
export TAO_SUDO_PASS
s() { echo "$SP" | sudo -S "$@" 2>/dev/null; }

LOG_DIR="$HOME/TAO-OS/logs"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/tao-os-coldstart-$(date +%Y%m%d-%H%M%S).log"
PASS_RESULT=""

log() { echo "$1" | tee -a "$LOG_FILE"; }

# Short prompt — minimizes generation time, isolates load+TTFT signal
PROMPT="What is Bittensor? Answer in one sentence."

# ── Preflight ─────────────────────────────────────────────────────────────────
if ! systemctl is-active --quiet ollama; then
    echo "Ollama not running. Starting..."
    s systemctl start ollama
    sleep 3
fi

if ! ollama list 2>/dev/null | grep -q "$MODEL"; then
    echo "Model '$MODEL' not found. Pull it first: ollama pull $MODEL"
    exit 1
fi

log "Ensuring clean state for baseline..."
_undo_out=$(bash "$PRESET_SCRIPT" --undo 2>/dev/null || true)
echo "$_undo_out" | grep -E "Revert|reverted|No backup" | sed 's/^/  /' >> "$LOG_FILE" || true
# Hard-reset CPU governor and GPU freq — don't rely on state file which may
# have been written when system was already tuned (ratchet bug).
log "  Hard-resetting CPU governor and GPU freq to defaults..."
if command -v cpupower &>/dev/null; then
    # Try schedutil first (unavailable on amd-pstate-epp — suppress error, fall through)
    if echo "$SP" | sudo -S cpupower frequency-set -g schedutil >/dev/null 2>&1; then
        log "    CPU governor → schedutil"
    elif echo "$SP" | sudo -S cpupower frequency-set -g powersave >/dev/null 2>&1; then
        log "    CPU governor → powersave"
    else
        log "    CPU governor reset failed — check driver ($(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_driver 2>/dev/null || echo unknown))"
    fi
fi
for card in /sys/class/drm/card*/gt/gt0; do
    [[ -f "$card/rps_min_freq_mhz" ]] && echo "$SP" | sudo -S bash -c "echo 300 > $card/rps_min_freq_mhz" 2>/dev/null \
        && log "    GPU rps_min_freq_mhz → 300 (idle default)" || true
done
sleep 2

# ── JSON parser ───────────────────────────────────────────────────────────────
parse_response() {
    python3 -c "
import json, sys
try:
    d = json.load(sys.stdin)
    load_ms  = d['load_duration']       / 1e6   # ns → ms
    ttft_ms  = d['prompt_eval_duration'] / 1e6
    cold_ms  = load_ms + ttft_ms
    tps      = d['eval_count'] / (d['eval_duration'] / 1e9)
    toks     = d['eval_count']
    print(f'{load_ms:.1f}|{ttft_ms:.1f}|{cold_ms:.1f}|{tps:.2f}|{toks}')
except Exception as e:
    print('0|0|0|0|0')
"
}

# ── Single cold-start call (model unloads after, forcing reload next time) ───
infer_cold() {
    curl -s --max-time 120 http://localhost:11434/api/generate \
        -H "Content-Type: application/json" \
        -d "{\"model\": \"$MODEL\", \"prompt\": \"$PROMPT\", \"stream\": false, \"keep_alive\": \"0s\", \"options\": {\"num_predict\": 30, \"num_ctx\": 512, \"num_batch\": 64}}"
}

# ── Run a full cold-start pass ────────────────────────────────────────────────
run_pass() {
    local label="$1"
    log ""
    log "--- $label ---"
    log "  Time:      $(date +%H:%M:%S)"

    local gov gpu_freq
    gov=$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor 2>/dev/null || echo N/A)
    gpu_freq=$(cat /sys/class/drm/card*/gt/gt0/rps_cur_freq_mhz 2>/dev/null | head -1 || echo N/A)
    log "  CPU gov:   $gov"
    log "  GPU freq:  ${gpu_freq} MHz (idle)"

    # Discard warmup: first ever model load may include one-time shader compilation.
    # Run and discard one call before starting measurements.
    log "  Warmup call (discarded — flushes shader compilation)..."
    sleep "$IDLE_SLEEP"
    infer_cold > /dev/null 2>&1 || true

    log "  Running $PASSES cold-start calls (${IDLE_SLEEP}s idle gap between each)..."
    local load_sum=0 ttft_sum=0 cold_sum=0 tps_sum=0 i=1
    local load_min=999999 cold_min=999999 load_max=0 cold_max=0

    for _ in $(seq 1 $PASSES); do
        # Ensure model is unloaded and GPU has time to drop to idle
        sleep "$IDLE_SLEEP"

        local gpu_before
        gpu_before=$(cat /sys/class/drm/card*/gt/gt0/rps_cur_freq_mhz 2>/dev/null | head -1 || echo N/A)

        local result load_ms ttft_ms cold_ms tps toks
        result=$(infer_cold | parse_response)
        load_ms=$(echo "$result" | cut -d'|' -f1)
        ttft_ms=$(echo "$result" | cut -d'|' -f2)
        cold_ms=$(echo "$result" | cut -d'|' -f3)
        tps=$(echo "$result"     | cut -d'|' -f4)
        toks=$(echo "$result"    | cut -d'|' -f5)

        log "    Call $i: GPU_before=${gpu_before}MHz | load=${load_ms}ms | TTFT=${ttft_ms}ms | cold_total=${cold_ms}ms | ${tps} tok/s | tokens:$toks"

        load_sum=$(echo "$load_sum + $load_ms"   | bc -l)
        ttft_sum=$(echo "$ttft_sum + $ttft_ms"   | bc -l)
        cold_sum=$(echo "$cold_sum + $cold_ms"   | bc -l)
        tps_sum=$(echo  "$tps_sum  + $tps"       | bc -l)
        (( $(echo "$load_ms < $load_min" | bc -l) )) && load_min=$load_ms
        (( $(echo "$load_ms > $load_max" | bc -l) )) && load_max=$load_ms
        (( $(echo "$cold_ms < $cold_min" | bc -l) )) && cold_min=$cold_ms
        (( $(echo "$cold_ms > $cold_max" | bc -l) )) && cold_max=$cold_ms
        (( i++ ))
    done

    local avg_load avg_ttft avg_cold avg_tps
    avg_load=$(echo "scale=1; $load_sum / $PASSES" | bc -l)
    avg_ttft=$(echo "scale=1; $ttft_sum / $PASSES" | bc -l)
    avg_cold=$(echo "scale=1; $cold_sum / $PASSES" | bc -l)
    avg_tps=$(echo  "scale=2; $tps_sum  / $PASSES" | bc -l)

    log "  Avg: load=${avg_load}ms | TTFT=${avg_ttft}ms | cold_total=${avg_cold}ms | ${avg_tps} tok/s"
    log "  Load range: ${load_min}ms – ${load_max}ms | Cold range: ${cold_min}ms – ${cold_max}ms"
    PASS_RESULT="$avg_cold"
}

# ── Header ────────────────────────────────────────────────────────────────────
log "TAO-OS Inference Benchmark v0.2 — Cold-Start Latency"
log "Model:      $MODEL"
log "Preset:     $PRESET_SCRIPT"
log "Passes:     $PASSES  (${IDLE_SLEEP}s idle gap between each)"
log "Started:    $(date)"
log "========================================"
log "Hardware:"
log "  CPU: $(lscpu | grep 'Model name:' | cut -d':' -f2 | xargs)"
log "  GPU: $(lspci | grep -i 'VGA\|3D\|Display' | cut -d: -f3 | xargs || echo 'N/A')"
GPU_GT=""
for card in /sys/class/drm/card*/gt/gt0; do
    [[ -f "$card/rps_min_freq_mhz" ]] && GPU_GT="$card" && break
done
if [[ -n "$GPU_GT" ]]; then
    log "  GPU min/boost: $(cat $GPU_GT/rps_min_freq_mhz)/$(cat $GPU_GT/rps_boost_freq_mhz) MHz"
fi
log "========================================"

# ── PASS 1: Baseline ──────────────────────────────────────────────────────────
log ""
log "PASS 1 — BASELINE (no presets, GPU idles to default freq)"
run_pass "BASELINE"
BASELINE="$PASS_RESULT"

# ── Apply presets ─────────────────────────────────────────────────────────────
log ""
log "Applying presets: $PRESET_SCRIPT"
_preset_out=$(bash "$PRESET_SCRIPT" --apply-temp 2>&1 || true)
echo "$_preset_out" | grep -E "✓|WARNING|skip" | sed 's/^/  /' >> "$LOG_FILE" || true
log "Presets applied."

# Restart ollama so GPU freq/power settings take effect
log "Restarting ollama..."
s systemctl restart ollama
sleep 4

# ── PASS 2: Tuned ─────────────────────────────────────────────────────────────
log ""
log "PASS 2 — TUNED (GPU pinned to min 2000 MHz)"
run_pass "TUNED"
TUNED="$PASS_RESULT"

# ── Undo presets ──────────────────────────────────────────────────────────────
log ""
log "Reverting presets..."
_revert_out=$(bash "$PRESET_SCRIPT" --undo 2>&1 || true)
echo "$_revert_out" | grep -E "✓|Revert" | sed 's/^/  /' >> "$LOG_FILE" || true

# ── Results ───────────────────────────────────────────────────────────────────
if (( $(echo "$BASELINE > 0" | bc -l) )); then
    DELTA=$(echo "scale=2; ($BASELINE - $TUNED) * 100 / $BASELINE" | bc -l | awk '{printf "%.2f", $1}')
    DELTA_LABEL="lower is better (latency)"
else
    DELTA="N/A"
    DELTA_LABEL=""
fi

log ""
log "========================================"
log "COLD-START LATENCY RESULTS"
log "  Model:            $MODEL"
log "  Baseline latency: ${BASELINE}ms  (GPU at idle freq)"
log "  Tuned latency:    ${TUNED}ms     (GPU pinned 2000 MHz)"
log "  Delta:            -${DELTA}%  ($DELTA_LABEL)"
log "========================================"
log "Log: $LOG_FILE"
log "Complete: $(date)"
