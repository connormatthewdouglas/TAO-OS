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

    # If we fell back to tinyllama and a discrete GPU is present, it won't be
    # stressed enough to show a real delta. Offer to pull mistral (7B, 4.1 GB)
    # which actually fills VRAM and shows meaningful GPU freq improvements.
    if [[ "$MODEL" == "tinyllama" ]]; then
        _has_discrete_gpu=false
        lspci 2>/dev/null | grep -iE 'VGA|3D|Display' | grep -ivE 'Intel.*(HD|UHD|Iris|Core)' \
            > /dev/null 2>&1 && _has_discrete_gpu=true
        ls /sys/class/drm/card*/gt/gt0/rps_min_freq_mhz > /dev/null 2>&1 \
            && _has_discrete_gpu=true   # Intel Arc
        if [[ "$_has_discrete_gpu" == true ]]; then
            echo ""
            echo "  Only tinyllama is installed — too small to stress your GPU."
            echo "  TinyLlama hits the hardware ceiling at any governor setting,"
            echo "  so inference delta will be ~0% regardless of tuning."
            echo ""
            echo "  Recommended: mistral (7B, 4.1 GB) — fits any 8 GB+ GPU and"
            echo "  shows real improvement with GPU frequency and memory tuning."
            echo ""
            read -rp "  Download mistral now? [Y/N]: " _pull_answer </dev/tty
            if [[ "${_pull_answer,,}" == "y" ]]; then
                echo "  Pulling mistral..."
                ollama pull mistral && MODEL="mistral" \
                    && echo "  ✓ mistral ready." \
                    || echo "  Pull failed — continuing with tinyllama."
            else
                echo "  Continuing with tinyllama — inference delta may be near-zero."
            fi
            echo ""
        fi
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

# ── AMD ROCm auto-install ─────────────────────────────────────────────────────
# If an AMD GPU is present but ROCm isn't installed, offer to install it now.
# ROCm enables GPU inference on RX 470/480/570/580/590 (and newer AMD cards).
# After install, CursiveOS presets apply HSA_OVERRIDE and restart ollama —
# everything works in the same session, no reboot needed.
_amd_gpu=$(lspci 2>/dev/null | grep -iE 'VGA|3D|Display' | grep -iE 'AMD|ATI|Radeon' || true)
if [[ -n "$_amd_gpu" ]] && ! command -v rocm-smi &>/dev/null && ! [[ -d /opt/rocm ]]; then
    echo ""
    echo "  AMD GPU detected: $_amd_gpu"
    echo "  ROCm is not installed — Ollama will use CPU inference without it."
    echo ""
    read -rp "  Install ROCm now for GPU inference? [Y/N]: " _rocm_answer </dev/tty
    if [[ "${_rocm_answer,,}" == "y" ]]; then
        echo "  Installing ROCm..."
        if ! command -v apt-get &>/dev/null; then
            echo "  Auto-install requires Ubuntu/Debian (apt not found)."
            echo "  Install manually: https://rocm.docs.amd.com/en/latest/deploy/linux/quick_start.html"
        else
            _codename=$(lsb_release -cs 2>/dev/null || echo "")
            if [[ -z "$_codename" ]]; then
                echo "  Could not detect distro codename — install manually:"
                echo "  https://rocm.docs.amd.com/en/latest/deploy/linux/quick_start.html"
            else
                s apt-get install -y wget gnupg 2>/dev/null
                wget -qO /tmp/cursiveos-rocm.gpg \
                    https://repo.radeon.com/rocm/rocm.gpg.key 2>/dev/null \
                    && echo "$SP" | sudo -S gpg --batch --yes --dearmor \
                        -o /etc/apt/trusted.gpg.d/rocm.gpg \
                        /tmp/cursiveos-rocm.gpg 2>/dev/null \
                    && echo "$SP" | sudo -S bash -c \
                        "echo 'deb [arch=amd64] https://repo.radeon.com/rocm/apt/latest ${_codename} main' \
                        > /etc/apt/sources.list.d/rocm.list" \
                    && s apt-get update -qq \
                    && s apt-get install -y rocm \
                    && s usermod -aG video,render "$USER" \
                    && echo "  ✓ ROCm installed — GPU inference will be active for the tuned pass." \
                    || echo "  ROCm install failed — continuing with CPU inference."
                rm -f /tmp/cursiveos-rocm.gpg
            fi
        fi
    else
        echo "  Skipping ROCm install — inference benchmark will run on CPU."
        echo "  (Network and cold-start benchmarks are unaffected.)"
        echo ""
    fi
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

LAST_PASS_PROC=""   # set by run_pass — tracks whether last pass ran on GPU or CPU

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

    # Confirm whether model is on GPU or CPU — logged for visibility.
    # We always measure both passes; delta is suppressed later if TUNED stays on CPU.
    # (Presets may apply ROCm override + restart ollama between passes, moving an AMD
    # GPU from CPU→GPU inference — that's a real, large delta worth capturing.)
    local proc
    proc=$(ollama ps 2>/dev/null | grep "$MODEL" | grep -oP '[0-9]+% (GPU|CPU)' || echo "not loaded")
    log "  Processor: $proc"
    LAST_PASS_PROC="$proc"

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
TUNED_PROC="$LAST_PASS_PROC"   # captured after the tuned pass

if [[ "$BASELINE" == "N/A" || "$TUNED" == "N/A" ]]; then
    DELTA="N/A"
elif ! echo "$TUNED_PROC" | grep -qi "gpu"; then
    # Tuned pass still on CPU — C-state changes cause thermal variance,
    # delta is unreliable. Detect and explain.
    DELTA="N/A"
    amd_gpu=$(lspci 2>/dev/null | grep -iE 'VGA|3D|Display' | grep -iE 'AMD|ATI|Radeon' || true)
    nvidia_gpu=$(lspci 2>/dev/null | grep -iE 'VGA|3D|Display' | grep -i 'NVIDIA' || true)
    log ""
    if [[ -n "$amd_gpu" ]]; then
        log "  NOTE: AMD GPU present but Ollama used CPU for both passes."
        log "    $amd_gpu"
        log "  ROCm may not be installed. Once installed, CursiveOS presets will"
        log "  automatically apply HSA_OVERRIDE_GFX_VERSION=9.0.0 to enable GPU inference."
        log "  Install ROCm: https://rocm.docs.amd.com/en/latest/deploy/linux/quick_start.html"
    elif [[ -n "$nvidia_gpu" ]]; then
        log "  NOTE: NVIDIA GPU present but Ollama used CPU for both passes."
        log "    $nvidia_gpu"
        log "  Check: nvidia-smi  and  ollama ps  to diagnose GPU offload."
    else
        log "  (No discrete GPU — CPU inference delta suppressed due to thermal variance.)"
    fi
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
