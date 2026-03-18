#!/usr/bin/env bash
# TAO-OS benchmark-inference-v0.1.sh
# Measures AI inference performance on Intel Arc A750 via ollama REST API.
# Paired test: baseline (no presets) vs tuned (presets applied) in same session.
# Reports: tokens/sec, time-to-first-token, GPU vs CPU confirmation.
#
# Usage: ./benchmark-inference-v0.1.sh [preset-script] [model]
#   preset-script : default ./tao-os-presets-v0.5.sh
#   model         : default tinyllama (must already be pulled)

set -euo pipefail

PRESET_SCRIPT="${1:-./tao-os-presets-v0.5.sh}"
MODEL="${2:-tinyllama}"
PASSES=5        # inference calls per pass (more = more stable average)
WARMUP=1        # throwaway calls before measuring (GPU cold start)
SP="2633"
s()  { echo "$SP" | sudo -S "$@" 2>/dev/null; }

LOG_DIR="$HOME/TAO-OS/logs"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/tao-os-inference-$(date +%Y%m%d-%H%M%S).log"
PASS_RESULT=""

log() { echo "$1" | tee -a "$LOG_FILE"; }

# Fixed prompt — consistent workload, generates ~80-120 tokens
PROMPT="Explain how Bittensor's proof of intelligence consensus mechanism works and why it rewards miners for useful AI computation rather than wasteful hash calculations. Be concise."

# ── Preflight checks ─────────────────────────────────────────────────────────
if ! systemctl is-active --quiet ollama; then
    echo "Ollama not running. Starting..."
    echo "$SP" | sudo -S systemctl start ollama
    sleep 3
fi

if ! ollama list 2>/dev/null | grep -q "$MODEL"; then
    echo "Model '$MODEL' not found. Pull it first: ollama pull $MODEL"
    exit 1
fi

# ── JSON parser ──────────────────────────────────────────────────────────────
parse_response() {
    python3 -c "
import json, sys
try:
    d = json.load(sys.stdin)
    tps  = d['eval_count'] / (d['eval_duration'] / 1e9)
    ttft = d['prompt_eval_duration'] / 1e9
    toks = d['eval_count']
    print(f'{tps:.2f}|{ttft:.3f}|{toks}')
except Exception as e:
    print(f'0|0|0')
"
}

# ── Single inference call ────────────────────────────────────────────────────
infer() {
    curl -s http://localhost:11434/api/generate \
        -H "Content-Type: application/json" \
        -d "{\"model\": \"$MODEL\", \"prompt\": \"$PROMPT\", \"stream\": false}"
}

# ── Run a full pass (warmup + N measured calls) ──────────────────────────────
run_pass() {
    local label="$1"
    log ""
    log "--- $label ---"
    log "  Time: $(date +%H:%M:%S)"

    # Log current state
    local gov proc
    gov=$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor 2>/dev/null || echo N/A)
    proc=$(ollama ps 2>/dev/null | grep "$MODEL" | grep -oP '(100%|[0-9]+%) (GPU|CPU)' || echo "not loaded")
    log "  Governor:  $gov"
    log "  Processor: $proc"

    # Confirm GPU
    if ! echo "$proc" | grep -qi "gpu"; then
        log "  WARNING: model not on GPU — results may be CPU-based"
    fi

    # Warmup
    log "  Warming up ($WARMUP call)..."
    for _ in $(seq 1 $WARMUP); do infer > /dev/null; done

    # Measured passes
    log "  Running $PASSES inference passes..."
    local tps_sum=0 ttft_sum=0 tps_min=99999 tps_max=0 i=1
    for _ in $(seq 1 $PASSES); do
        local result tps ttft toks
        result=$(infer | parse_response)
        tps=$(echo "$result"  | cut -d'|' -f1)
        ttft=$(echo "$result" | cut -d'|' -f2)
        toks=$(echo "$result" | cut -d'|' -f3)
        log "    Pass $i: ${tps} tok/s | TTFT: ${ttft}s | tokens: $toks"
        tps_sum=$(echo "$tps_sum + $tps" | bc -l)
        ttft_sum=$(echo "$ttft_sum + $ttft" | bc -l)
        (( $(echo "$tps < $tps_min" | bc -l) )) && tps_min=$tps
        (( $(echo "$tps > $tps_max" | bc -l) )) && tps_max=$tps
        (( i++ ))
    done

    local avg_tps avg_ttft
    avg_tps=$(echo  "scale=2; $tps_sum  / $PASSES" | bc -l)
    avg_ttft=$(echo "scale=3; $ttft_sum / $PASSES" | bc -l)

    log "  Avg: ${avg_tps} tok/s | TTFT avg: ${avg_ttft}s | min: ${tps_min} | max: ${tps_max}"
    PASS_RESULT="$avg_tps"
}

# ── Header ───────────────────────────────────────────────────────────────────
log "TAO-OS Inference Benchmark v0.1"
log "Model:   $MODEL"
log "Preset:  $PRESET_SCRIPT"
log "Passes:  $PASSES  (+ $WARMUP warmup)"
log "Started: $(date)"
log "========================================"
log "Hardware:"
log "  CPU: $(lscpu | grep 'Model name:' | cut -d':' -f2 | xargs)"
log "  GPU: $(lspci | grep -i 'VGA\|3D\|Display' | cut -d: -f3 | xargs || echo 'N/A')"
GPU_VRAM=$(cat /sys/class/drm/card1/gt/gt0/../../../drm/card1/../../../mem_info_vram_total 2>/dev/null || echo "N/A")
log "  GPU VRAM: $(ollama ps 2>/dev/null | grep "$MODEL" | awk '{print $3}' || echo 'check ollama ps')"
log "========================================"

# ── PASS 1: Baseline ─────────────────────────────────────────────────────────
log ""
log "PASS 1 — BASELINE (no presets)"
run_pass "BASELINE"
BASELINE="$PASS_RESULT"

# ── Apply presets ─────────────────────────────────────────────────────────────
log ""
log "Applying presets: $PRESET_SCRIPT"
bash "$PRESET_SCRIPT" --apply-temp 2>&1 | grep "✓\|WARNING\|skip" | sed 's/^/  /' | tee -a "$LOG_FILE"
log "Presets applied. Starting tuned pass..."

# Restart ollama so GPU freq/power settings take effect for inference
log "Restarting ollama to apply GPU settings..."
s systemctl restart ollama
sleep 4

# ── PASS 2: Tuned ────────────────────────────────────────────────────────────
log ""
log "PASS 2 — TUNED (presets active)"
run_pass "TUNED"
TUNED="$PASS_RESULT"

# ── Undo presets ──────────────────────────────────────────────────────────────
log ""
log "Reverting presets..."
bash "$PRESET_SCRIPT" --undo 2>&1 | grep "✓\|Revert" | sed 's/^/  /' | tee -a "$LOG_FILE"

# ── Results ───────────────────────────────────────────────────────────────────
DELTA=$(echo "scale=2; ($TUNED - $BASELINE) * 100 / $BASELINE" | bc -l)

log ""
log "========================================"
log "INFERENCE BENCHMARK RESULTS"
log "  Model:    $MODEL"
log "  Baseline: ${BASELINE} tok/s"
log "  Tuned:    ${TUNED} tok/s"
log "  Delta:    ${DELTA}%  (positive = better)"
log "========================================"
log "Log: $LOG_FILE"
log "Complete: $(date)"
