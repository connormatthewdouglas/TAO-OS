#!/usr/bin/env bash
# CursiveOS benchmark-inference-v0.1.sh
# Measures GPU inference performance via ollama REST API.
# Paired test: baseline (no presets) vs tuned (presets applied) in same session.
# Reports: tokens/sec, time-to-first-token, GPU vs CPU confirmation.
#
# CPU inference is intentionally skipped — disabling C-states causes thermal
# buildup that makes tuned-pass results unreliable. Cold-start latency is the
# right metric for CPU-inference machines (measured separately).
#
# Usage: ./benchmark-inference-v0.1.sh [preset-script] [model]
#   preset-script : default ../cursiveos-presets-v0.8.sh
#   model         : auto-selected if omitted (prefers larger models)

set -euo pipefail

PRESET_SCRIPT="${1:-../cursiveos-presets-v0.8.sh}"

# Auto-select best available model — larger models stress VRAM/bandwidth
# where GPU freq and THP settings actually show a delta. TinyLlama is too
# small: the Arc A750 hits its hardware ceiling at any governor setting.
if [[ -n "${2:-}" ]]; then
    MODEL="$2"
else
    MODEL=""
    for m in llama3 mistral llama3.2 phi3 qwen2 tinyllama; do
        if ollama list 2>/dev/null | grep -q "^$m"; then
            MODEL="$m"
            break
        fi
    done
    if [[ -z "$MODEL" ]]; then
        echo "No supported model found. Pull one first: ollama pull tinyllama"
        exit 1
    fi
fi
PASSES=5        # inference calls per pass (more = more stable average)
WARMUP=1        # throwaway calls before measuring (GPU cold start)
if [[ -z "${TAO_SUDO_PASS:-}" ]]; then
    read -rsp "[CursiveOS] sudo password: " TAO_SUDO_PASS && echo
fi
SP="$TAO_SUDO_PASS"
export TAO_SUDO_PASS
s()  { echo "$SP" | sudo -S "$@" 2>/dev/null; }

LOG_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/logs"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/tao-os-inference-$(date +%Y%m%d-%H%M%S).log"
PASS_RESULT=""

log() { echo "$1" | tee -a "$LOG_FILE"; }

# Fixed prompt — consistent workload, generates ~80-120 tokens
PROMPT="Explain how Bittensor's proof of intelligence consensus mechanism works and why it rewards miners for useful AI computation rather than wasteful hash calculations. Be concise."

# ── Preflight checks ─────────────────────────────────────────────────────────
if ! systemctl is-active --quiet ollama; then
    echo "Ollama not running. Starting..."
    s systemctl start ollama
    sleep 3
fi

if ! ollama list 2>/dev/null | grep -q "$MODEL"; then
    echo "Model '$MODEL' not found. Pull it first: ollama pull $MODEL"
    exit 1
fi

# Ensure clean baseline — undo any previously applied presets
log "Ensuring clean state for baseline..."
bash "$PRESET_SCRIPT" --undo 2>/dev/null | grep -E "Revert|reverted|No backup" | sed 's/^/  /' || true
# Hard-reset CPU governor and GPU freq — don't rely on state file which may
# have been written when system was already tuned (ratchet bug).
log "  Hard-resetting CPU governor and GPU freq to defaults..."
if command -v cpupower &>/dev/null; then
    echo "$SP" | sudo -S cpupower frequency-set -g schedutil 2>/dev/null \
        && log "    CPU governor → schedutil" || \
    echo "$SP" | sudo -S cpupower frequency-set -g powersave 2>/dev/null \
        && log "    CPU governor → powersave" || true
fi
for card in /sys/class/drm/card*/gt/gt0; do
    [[ -f "$card/rps_min_freq_mhz" ]] && echo "$SP" | sudo -S bash -c "echo 300 > $card/rps_min_freq_mhz" 2>/dev/null \
        && log "    GPU rps_min_freq_mhz → 300 (idle default)" || true
done
sleep 2

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
# num_predict: cap output tokens (reduces Vulkan workload, improves stability on Arc)
# num_ctx: smaller context window = smaller KV cache
# num_batch: smaller batch size = less peak VRAM pressure
infer() {
    curl -s --max-time 120 http://localhost:11434/api/generate \
        -H "Content-Type: application/json" \
        -d "{\"model\": \"$MODEL\", \"prompt\": \"$PROMPT\", \"stream\": false, \"options\": {\"num_predict\": 100, \"num_ctx\": 1024, \"num_batch\": 128}}"
}

# ── Run a full pass (warmup + N measured calls) ──────────────────────────────
run_pass() {
    local label="$1"
    log ""
    log "--- $label ---"
    log "  Time: $(date +%H:%M:%S)"

    # Log current state
    local gov
    gov=$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor 2>/dev/null || echo N/A)
    log "  Governor: $gov"

    # Warmup — model loads on first call, so check GPU after
    log "  Warming up ($WARMUP call)..."
    for _ in $(seq 1 $WARMUP); do infer > /dev/null; done

    # Confirm GPU after model is loaded — abort measured passes if on CPU.
    # CPU inference cannot produce a reliable delta: disabling C-states causes
    # thermal buildup that throttles the tuned pass, producing meaningless negatives.
    local proc
    proc=$(ollama ps 2>/dev/null | grep "$MODEL" | grep -oP '[0-9]+% (GPU|CPU)' || echo "not loaded")
    log "  Processor: $proc"
    if ! echo "$proc" | grep -qi "gpu"; then
        log "  SKIP: model running on CPU — sustained inference delta suppressed."
        log "        (C-state disable causes thermal variance; see cold-start benchmark for CPU impact.)"
        # Detect why — AMD GPU present but ROCm not wired up is fixable
        local amd_gpu
        amd_gpu=$(lspci 2>/dev/null | grep -iE 'VGA|3D|Display' | grep -iE 'AMD|ATI|Radeon' || true)
        local nvidia_gpu
        nvidia_gpu=$(lspci 2>/dev/null | grep -iE 'VGA|3D|Display' | grep -i 'NVIDIA' || true)
        if [[ -n "$amd_gpu" ]]; then
            log ""
            log "  NOTE: AMD GPU detected but Ollama is not using it:"
            log "    $amd_gpu"
            log "  This is a ROCm configuration issue, not a hardware limitation."
            log "  Fix for RX 470/480/570/580/590 (gfx803 / Polaris):"
            log "    1. Install ROCm:  https://rocm.docs.amd.com/en/latest/deploy/linux/quick_start.html"
            log "    2. Add to groups: sudo usermod -aG video,render \$USER"
            log "    3. Create /etc/systemd/system/ollama.service.d/override.conf:"
            log "         [Service]"
            log "         Environment=HSA_OVERRIDE_GFX_VERSION=9.0.0"
            log "    4. sudo systemctl daemon-reload && sudo systemctl restart ollama"
        elif [[ -n "$nvidia_gpu" ]]; then
            log ""
            log "  NOTE: NVIDIA GPU detected but Ollama is not using it:"
            log "    $nvidia_gpu"
            log "  Ensure nvidia-container-toolkit is installed and ollama can see the GPU:"
            log "    nvidia-smi   (should show the GPU)"
            log "    ollama run tinyllama   (check 'ollama ps' for GPU offload)"
        else
            log "  (No discrete GPU detected — CPU inference is expected on this machine.)"
        fi
        PASS_RESULT="N/A"
        return 0
    fi

    # Measured passes
    log "  Running $PASSES inference passes..."
    local tps_sum=0 ttft_sum=0 tps_min=99999 tps_max=0 i=1
    for _ in $(seq 1 $PASSES); do
        local result tps ttft toks
        result=$(infer | parse_response) || true
        tps=$(echo "$result"  | cut -d'|' -f1)
        ttft=$(echo "$result" | cut -d'|' -f2)
        toks=$(echo "$result" | cut -d'|' -f3)
        log "    Pass $i: ${tps} tok/s | TTFT: ${ttft}s | tokens: $toks"
        tps_sum=$(echo "$tps_sum + $tps" | bc -l)
        ttft_sum=$(echo "$ttft_sum + $ttft" | bc -l)
        [[ $(echo "$tps < $tps_min" | bc -l) == 1 ]] && tps_min=$tps
        [[ $(echo "$tps > $tps_max" | bc -l) == 1 ]] && tps_max=$tps
        (( i++ )) || true
    done

    local avg_tps avg_ttft
    avg_tps=$(echo  "scale=2; $tps_sum  / $PASSES" | bc -l)
    avg_ttft=$(echo "scale=3; $ttft_sum / $PASSES" | bc -l)

    log "  Avg: ${avg_tps} tok/s | TTFT avg: ${avg_ttft}s | min: ${tps_min} | max: ${tps_max}"
    PASS_RESULT="$avg_tps"
}

# ── Header ───────────────────────────────────────────────────────────────────
log "CursiveOS Inference Benchmark v0.1"
log "Model:   $MODEL"
log "Preset:  $PRESET_SCRIPT"
log "Passes:  $PASSES  (+ $WARMUP warmup)"
log "Started: $(date)"
log "========================================"
log "Hardware:"
log "  CPU: $(lscpu | grep 'Model name:' | cut -d':' -f2 | xargs)"
log "  GPU: $(lspci | grep -i 'VGA\|3D\|Display' | cut -d: -f3 | xargs || echo 'N/A')"
VRAM_TOTAL=$(cat /sys/class/drm/card1/device/mem_info_vram_total 2>/dev/null | awk '{printf "%.1f GiB", $1/1073741824}' || echo "N/A")
log "  GPU VRAM: $VRAM_TOTAL"
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
if [[ "$BASELINE" == "N/A" || "$TUNED" == "N/A" ]]; then
    DELTA="N/A"
else
    DELTA=$(echo "scale=2; ($TUNED - $BASELINE) * 100 / $BASELINE" | bc -l | awk '{printf "%.2f", $1}')
fi

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
