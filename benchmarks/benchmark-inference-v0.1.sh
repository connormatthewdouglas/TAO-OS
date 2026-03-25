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

# ── VRAM detection ────────────────────────────────────────────────────────────
# Returns GPU VRAM in whole GiB (0 if undetectable).
# Checks NVIDIA → AMD sysfs → Intel Arc sysfs in order.
detect_vram_gb() {
    local bytes=0
    if command -v nvidia-smi &>/dev/null; then
        local mib
        mib=$(nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits \
              2>/dev/null | head -1 | tr -d ' ')
        [[ "$mib" =~ ^[0-9]+$ ]] && bytes=$(( mib * 1024 * 1024 ))
    fi
    if [[ $bytes -eq 0 ]]; then
        for f in /sys/class/drm/card*/device/mem_info_vram_total; do
            [[ -f "$f" ]] && bytes=$(cat "$f" 2>/dev/null) && break
        done
    fi
    if [[ $bytes -eq 0 ]]; then
        for f in /sys/class/drm/card*/prelim_lmem_total_bytes; do  # Intel Arc
            [[ -f "$f" ]] && bytes=$(cat "$f" 2>/dev/null) && break
        done
    fi
    echo $(( bytes / 1073741824 ))
}

# Model sizing guide (Q4_K_M approximate VRAM):
#   phi3       3.8B  ~2.2 GB  → good for 4 GB+ GPUs
#   mistral    7B    ~4.1 GB  → good for 8 GB+ GPUs
#   tinyllama  1.1B  ~0.6 GB  → too small to show GPU delta (fallback only)
_recommend_model_for_vram() {
    local vram_gb="$1"
    if   [[ $vram_gb -ge 8 ]]; then echo "mistral:4.1 GB"
    elif [[ $vram_gb -ge 4 ]]; then echo "phi3:2.2 GB"
    else                             echo ":"   # too small, no recommendation
    fi
}

# Auto-select best available model — larger models stress VRAM/bandwidth
# where GPU freq and THP settings actually show a delta. TinyLlama is too
# small: the Arc A750 hits its hardware ceiling at any governor setting.
if [[ -n "${2:-}" ]]; then
    MODEL="$2"
else
    MODEL=""
    for m in llama3 mistral llama3.2 phi3 qwen2 tinyllama; do
        if ollama list 2>/dev/null | grep -q "^$m:"; then
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
            _vram_gb=$(detect_vram_gb)
            _rec=$(_recommend_model_for_vram "$_vram_gb")
            _rec_model="${_rec%%:*}"
            _rec_size="${_rec##*:}"

            if [[ -z "$_rec_model" ]]; then
                # GPU present but VRAM too small for anything better
                echo ""
                echo "  GPU detected but VRAM appears to be ${_vram_gb} GB or less."
                echo "  TinyLlama (~0.6 GB) is the best fit — delta may be near-zero."
                echo ""
            else
                echo ""
                echo "  Only tinyllama is installed — too small to stress your GPU."
                echo "  TinyLlama hits the hardware ceiling at any governor setting,"
                echo "  so inference delta will be ~0% regardless of tuning."
                echo ""
                if [[ $_vram_gb -gt 0 ]]; then
                    echo "  GPU VRAM detected: ${_vram_gb} GB"
                fi
                echo "  Recommended: ${_rec_model} (${_rec_size}) — fits your GPU and"
                echo "  shows real improvement with frequency and memory tuning."
                echo "  Auto-installing ${_rec_model}..."
                ollama pull "$_rec_model" && MODEL="$_rec_model" \
                    && echo "  ✓ ${_rec_model} ready." \
                    || echo "  Pull failed — continuing with tinyllama."
                echo ""
            fi
        fi
    fi
fi
# ── Model validation ─────────────────────────────────────────────────────────
# Quick 5-token test to catch silent failures before wasting a full benchmark run.
# Arc A750 Vulkan bug: models 3B+ return 0 tokens silently (driver crashes internally).
# On failure: step down the preference chain, auto-pull the next model, and retry.
# Only reaches tinyllama if every larger model fails on this hardware.
_MODEL_PREF_CHAIN=(llama3 mistral llama3.2 phi3 qwen2 tinyllama)

_validate_model() {
    curl -s --max-time 30 http://localhost:11434/api/generate \
        -d "{\"model\":\"$1\",\"prompt\":\"Hi\",\"stream\":false,\"options\":{\"num_predict\":5}}" \
        | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('eval_count',0))" 2>/dev/null || echo "0"
}

if [[ "$MODEL" != "tinyllama" ]]; then
    echo "  Validating $MODEL (quick 5-token test)..."
    _tok=$(_validate_model "$MODEL")
    if [[ "$_tok" != "0" ]]; then
        echo "  ✓ $MODEL validated (${_tok} tokens)."
    else
        echo "  ✗ $MODEL returned 0 tokens — not compatible with this GPU/driver."
        echo "  (Arc A750 Vulkan driver silently crashes on 3B+ models — trying next option.)"
        _found=false
        _past_current=false
        for _fb in "${_MODEL_PREF_CHAIN[@]}"; do
            if [[ "$_fb" == "$MODEL" ]]; then _past_current=true; continue; fi
            [[ "$_past_current" == false ]] && continue
            echo "  Trying $_fb..."
            if ! ollama list 2>/dev/null | grep -q "^${_fb}:"; then
                echo "  Pulling $_fb..."
                ollama pull "$_fb" || { echo "  Pull failed — skipping."; continue; }
            fi
            _tok=$(_validate_model "$_fb")
            if [[ "$_tok" != "0" ]]; then
                MODEL="$_fb"
                echo "  ✓ $_fb works on this hardware (${_tok} tokens) — using for benchmark."
                _found=true
                break
            else
                echo "  ✗ $_fb also failed."
            fi
        done
        if [[ "$_found" == false ]]; then
            echo "  All models failed — inference delta will be minimal on this hardware."
            MODEL="tinyllama"
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
LOG_FILE="$LOG_DIR/cursiveos-inference-$(date +%Y%m%d-%H%M%S).log"
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
# If a discrete AMD GPU is present but ROCm isn't installed, offer to install it.
# Skips if: Intel Arc is present (already handling GPU inference via sysfs),
#           NVIDIA is present, or the AMD entry is an integrated GPU (iGPU).
# AMD iGPU codenames excluded: Renoir/Cezanne (5000G), Lucienne, Barcelo,
#   Raphael (7000), Rembrandt, Phoenix/Hawk Point (7040) — all share PCIe slot
#   with the CPU and can't run ROCm meaningfully alongside a discrete GPU.
_arc_present=""
ls /sys/class/drm/card*/gt/gt0/rps_min_freq_mhz > /dev/null 2>&1 && _arc_present="yes"
_nvidia_present=$(lspci 2>/dev/null | grep -iE 'VGA|3D|Display' | grep -i 'NVIDIA' || true)
_amd_gpu=$(lspci 2>/dev/null | grep -iE 'VGA|3D|Display' \
    | grep -iE 'AMD|ATI|Radeon' \
    | grep -ivE 'Renoir|Cezanne|Lucienne|Barcelo|Raphael|Rembrandt|Phoenix|Hawk' || true)
if [[ -n "$_amd_gpu" ]] \
    && [[ -z "$_arc_present" ]] \
    && [[ -z "$_nvidia_present" ]] \
    && ! command -v rocm-smi &>/dev/null \
    && ! [[ -d /opt/rocm ]]; then
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
    for _ in $(seq 1 $WARMUP); do infer > /dev/null || true; done

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
_vram_display=$(detect_vram_gb)
VRAM_TOTAL=$([ "$_vram_display" -gt 0 ] && echo "${_vram_display} GiB" || echo "N/A")
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
if [[ "$DELTA" == "N/A" ]]; then
    log "  Delta:    N/A (see notes above)"
else
    log "  Delta:    ${DELTA}%  (positive = better)"
fi
log "========================================"
log "Log: $LOG_FILE"
log "Complete: $(date)"
