#!/usr/bin/env bash
# TAO-OS Full Test v1.2
# Single command for Bittensor miners to measure their system's baseline
# and the impact of TAO-OS performance presets.
#
# Runs three paired benchmarks (baseline → presets → baseline restored):
#   1. Network throughput  — BBR vs CUBIC on simulated WAN (50ms RTT, 0.5% loss)
#   2. Inference cold-start — model load + TTFT with GPU freq pinned vs idle
#   3. Inference sustained  — steady-state tok/s (GPU-bound baseline)
#
# Changes from v1.1:
#   - Auto-submits results to tao-forge (Supabase) after every run
#   - No git credentials needed — works from any internet-connected machine
#   - Still appends to local hardware-profiles.json as backup
#
# Requirements: ollama installed, tinyllama pulled (ollama pull tinyllama)
# Usage: ./tao-os-full-test-v1.2.sh
#
# All changes are TEMPORARY. Presets revert after each test.
# Logs saved to ~/TAO-OS/logs/

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PRESET="$SCRIPT_DIR/tao-os-presets-v0.6.sh"
MODEL="tinyllama"

LOG_DIR="$HOME/TAO-OS/logs"
mkdir -p "$LOG_DIR"
SUMMARY_LOG="$LOG_DIR/tao-os-full-test-$(date +%Y%m%d-%H%M%S).log"
HW_DB="$SCRIPT_DIR/hardware-profiles.json"

# ── tao-forge (Supabase) ──────────────────────────────────────────────────────
SUPABASE_URL="https://iovvktpuoinmjdgfxgvm.supabase.co"
SUPABASE_KEY="sb_publishable_4WefsfMl0sNNo9O2c_lxnA_q2VQ01jn"

# ── Sudo prompt (once — exported so child scripts skip re-prompting) ──────────
if [[ -z "${TAO_SUDO_PASS:-}" ]]; then
    read -rsp "[TAO-OS] sudo password: " TAO_SUDO_PASS && echo
fi
export TAO_SUDO_PASS

# ── Preflight checks ──────────────────────────────────────────────────────────
echo ""
echo "TAO-OS Full Test v1.2"
echo "======================================"

if [[ ! -f "$PRESET" ]]; then
    echo "ERROR: preset script not found: $PRESET"
    exit 1
fi

if ! command -v ollama &>/dev/null; then
    echo ""
    echo "ollama is not installed. It is required for inference benchmarks."
    read -rp "  Install ollama now? [y/N]: " INSTALL_OLLAMA
    if [[ "${INSTALL_OLLAMA,,}" == "y" ]]; then
        echo "  Installing ollama..."
        curl -fsSL https://ollama.com/install.sh | sh
        echo "  ollama installed."
    else
        echo "  Skipping ollama install. Inference benchmarks will be skipped."
        SKIP_INFERENCE=1
    fi
fi
SKIP_INFERENCE=${SKIP_INFERENCE:-0}

if ! ollama list 2>/dev/null | grep -q "$MODEL"; then
    echo "Pulling $MODEL..."
    ollama pull "$MODEL"
fi

if ! command -v iperf3 &>/dev/null; then
    echo "Installing iperf3..."
    echo "$TAO_SUDO_PASS" | sudo -S DEBIAN_FRONTEND=noninteractive apt-get install -y iperf3 -qq 2>/dev/null || true
    if ! command -v iperf3 &>/dev/null; then
        echo "ERROR: iperf3 install failed. Run manually: sudo apt-get install -y iperf3"
        exit 1
    fi
fi

CPU_MODEL=$(lscpu | grep 'Model name:' | cut -d':' -f2 | xargs)
GPU_MODEL=$(lspci 2>/dev/null | grep -i 'VGA\|3D\|Display' | cut -d: -f3 | xargs || echo 'N/A')
KERNEL=$(uname -r)
RAM_GB=$(awk '/MemTotal/ {printf "%.0f", $2/1024/1024}' /proc/meminfo)
OS_NAME=$(lsb_release -ds 2>/dev/null || echo "unknown")
CPU_CORES=$(nproc)
MACHINE_ID=$(echo "${CPU_MODEL}-$(hostname)" | tr '[:upper:]' '[:lower:]' | tr ' ' '-' | tr -cd '[:alnum:]-' | cut -c1-48)

echo "Hardware:"
echo "  CPU: $CPU_MODEL"
echo "  GPU: $GPU_MODEL"
echo "  Kernel: $KERNEL"
echo "  Date: $(date)"
echo ""
echo "Running 3 benchmarks. Total time: ~10 minutes."
echo "All presets are TEMPORARY — reverted after each test."
echo "======================================"

# ── Result variables ──────────────────────────────────────────────────────────
NET_BASELINE="" NET_TUNED="" NET_DELTA=""
COLD_BASELINE="" COLD_TUNED="" COLD_DELTA=""
WARM_BASELINE="" WARM_TUNED="" WARM_DELTA=""
PWR_IDLE="" PWR_TUNED_IDLE="" PWR_DELTA=""

# ── Power draw snapshot ───────────────────────────────────────────────────────
read_watts() {
    if command -v turbostat &>/dev/null; then
        local w
        w=$(echo "$TAO_SUDO_PASS" | sudo -S turbostat --quiet --num_iterations 1 \
            --show PkgWatt 2>/dev/null | awk 'NR==2 {print $1}')
        [[ -n "$w" ]] && echo "$w" || echo "N/A"
    else
        echo "N/A"
    fi
}

extract_network() {
    local log="$1"
    NET_BASELINE=$(grep "Baseline (CUBIC):" "$log" | grep -oP '[0-9]+\.[0-9]+' | head -1 || echo "?")
    NET_TUNED=$(grep "Tuned (BBR):" "$log"         | grep -oP '[0-9]+\.[0-9]+' | head -1 || echo "?")
    NET_DELTA=$(grep "Delta:" "$log"               | grep -oP '[+\-]?[0-9]+\.[0-9]+' | head -1 || echo "?")
}

extract_coldstart() {
    local log="$1"
    COLD_BASELINE=$(grep "Baseline latency:" "$log" | grep -oP '[0-9]+\.[0-9]+' | head -1 || echo "?")
    COLD_TUNED=$(grep "Tuned latency:" "$log"       | grep -oP '[0-9]+\.[0-9]+' | head -1 || echo "?")
    COLD_DELTA=$(grep "Delta:" "$log"               | grep -oP '[+\-]?[0-9]+\.[0-9]+' | head -1 || echo "N/A")
}

extract_sustained() {
    local log="$1"
    WARM_BASELINE=$(grep "Baseline:" "$log" | grep -oP '[0-9]+\.[0-9]+ tok/s' | head -1 || echo "?")
    WARM_TUNED=$(grep "Tuned:" "$log"       | grep -oP '[0-9]+\.[0-9]+ tok/s' | head -1 || echo "?")
    WARM_DELTA=$(grep "Delta:" "$log"       | grep -oP '[+\-]?[0-9]*\.[0-9]+%' | head -1 || echo "?")
}

# ── Idle power — baseline ─────────────────────────────────────────────────────
echo ""
echo "Reading idle power (no presets)..."
PWR_IDLE=$(read_watts)
echo "  → Idle power (baseline): ${PWR_IDLE}W"

# ── Benchmark 1: Network ──────────────────────────────────────────────────────
echo ""
echo "[1/3] Network throughput benchmark (BBR vs CUBIC, WAN simulation)..."
bash "$SCRIPT_DIR/benchmark-network-v0.1.sh" "$PRESET" 2>&1
NET_LOG=$(ls -t "$LOG_DIR"/tao-os-network-*.log 2>/dev/null | head -1)
extract_network "$NET_LOG"
echo "  → Network done."

# ── Benchmark 2: Cold-start latency ──────────────────────────────────────────
echo ""
if [[ "$SKIP_INFERENCE" == "1" ]]; then
    echo "[2/3] Cold-start latency — SKIPPED (ollama not installed)"
else
    echo "[2/3] Cold-start latency benchmark (GPU freq: idle vs pinned)..."
    bash "$SCRIPT_DIR/benchmark-inference-v0.2.sh" "$PRESET" "$MODEL" 2>&1
    COLD_LOG=$(ls -t "$LOG_DIR"/tao-os-coldstart-*.log 2>/dev/null | head -1)
    extract_coldstart "$COLD_LOG"
    echo "  → Cold-start done."
fi

# ── Benchmark 3: Sustained inference ─────────────────────────────────────────
echo ""
if [[ "$SKIP_INFERENCE" == "1" ]]; then
    echo "[3/3] Sustained inference — SKIPPED (ollama not installed)"
else
    echo "[3/3] Sustained inference benchmark (steady-state tok/s)..."
    bash "$SCRIPT_DIR/benchmark-inference-v0.1.sh" "$PRESET" "$MODEL" 2>&1
    WARM_LOG=$(ls -t "$LOG_DIR"/tao-os-inference-*.log 2>/dev/null | head -1)
    extract_sustained "$WARM_LOG"
    echo "  → Sustained inference done."
fi

# ── Idle power — tuned ────────────────────────────────────────────────────────
echo ""
echo "Reading idle power with presets active..."
bash "$PRESET" --apply-temp 2>&1 | grep "✓" | sed 's/^/  /' || true
sleep 3
PWR_TUNED_IDLE=$(read_watts)
echo "  → Idle power (tuned): ${PWR_TUNED_IDLE}W"
bash "$PRESET" --undo 2>&1 | grep -E "✓|Revert" | sed 's/^/  /' || true

if [[ "$PWR_IDLE" != "N/A" && "$PWR_TUNED_IDLE" != "N/A" ]]; then
    PWR_DELTA=$(python3 -c "print(f'{(float(\"$PWR_TUNED_IDLE\") - float(\"$PWR_IDLE\")):.1f}')" 2>/dev/null || echo "?")
else
    PWR_DELTA="N/A"
fi

# ── Summary table ─────────────────────────────────────────────────────────────
SUMMARY=$(cat <<EOF

======================================================
TAO-OS FULL TEST RESULTS — $(date +%Y-%m-%d)
======================================================
Hardware: $CPU_MODEL
          $GPU_MODEL

Benchmark              Baseline          Tuned             Delta
------------------------------------------------------
Network throughput     ${NET_BASELINE} Mbit/s      ${NET_TUNED} Mbit/s      ${NET_DELTA}%
Cold-start latency     ${COLD_BASELINE}ms           ${COLD_TUNED}ms            ${COLD_DELTA}%
Sustained inference    ${WARM_BASELINE}     ${WARM_TUNED}   ${WARM_DELTA}
Idle power draw        ${PWR_IDLE}W               ${PWR_TUNED_IDLE}W             ${PWR_DELTA}W

Note: Presets reverted — system is back to defaults.
Logs: $LOG_DIR/
======================================================
EOF
)

echo "$SUMMARY"
echo "$SUMMARY" >> "$SUMMARY_LOG"
echo ""
echo "Full summary saved: $SUMMARY_LOG"

# ── Submit to tao-forge (Supabase) ────────────────────────────────────────────
echo ""
echo "Submitting results to tao-forge..."

to_json_num() {
    local v="${1//+/}"
    [[ "$v" =~ ^-?[0-9]+(\.[0-9]+)?$ ]] && echo "$v" || echo "null"
}

NET_B=$(to_json_num "$NET_BASELINE")
NET_T=$(to_json_num "$NET_TUNED")
NET_D=$(to_json_num "$NET_DELTA")
COLD_B=$(to_json_num "$COLD_BASELINE")
COLD_T=$(to_json_num "$COLD_TUNED")
COLD_D=$(to_json_num "$COLD_DELTA")
WARM_B=$(to_json_num "${WARM_BASELINE%% *}")
WARM_T=$(to_json_num "${WARM_TUNED%% *}")
WARM_D=$(to_json_num "${WARM_DELTA%%%}")
PWR_B=$(to_json_num "$PWR_IDLE")
PWR_T=$(to_json_num "$PWR_TUNED_IDLE")
PWR_D=$(to_json_num "$PWR_DELTA")

SUPABASE_HEADERS=(
    -H "apikey: $SUPABASE_KEY"
    -H "Authorization: Bearer $SUPABASE_KEY"
    -H "Content-Type: application/json"
    -H "Prefer: resolution=merge-duplicates"
)

# Upsert machine
MACHINE_JSON=$(cat <<JSON
{
  "machine_id": "$MACHINE_ID",
  "label": "Auto-detected",
  "cpu": "$CPU_MODEL",
  "cpu_cores_logical": $CPU_CORES,
  "gpu": "$GPU_MODEL",
  "ram_gb": $RAM_GB,
  "os": "$OS_NAME",
  "kernel": "$KERNEL"
}
JSON
)

MACHINE_RESP=$(curl -s -o /dev/null -w "%{http_code}" -X POST \
    "${SUPABASE_HEADERS[@]}" \
    "$SUPABASE_URL/rest/v1/machines" \
    -d "$MACHINE_JSON" 2>/dev/null || echo "000")

# Insert run
RUN_JSON=$(cat <<JSON
{
  "machine_id": "$MACHINE_ID",
  "run_date": "$(date +%Y-%m-%d)",
  "preset_version": "v0.6",
  "wrapper_version": "v1.2",
  "network_baseline_mbit": $NET_B,
  "network_tuned_mbit": $NET_T,
  "network_delta_pct": $NET_D,
  "coldstart_baseline_ms": $COLD_B,
  "coldstart_tuned_ms": $COLD_T,
  "coldstart_delta_pct": $COLD_D,
  "sustained_baseline_toks": $WARM_B,
  "sustained_tuned_toks": $WARM_T,
  "sustained_delta_pct": $WARM_D,
  "power_idle_baseline_w": $PWR_B,
  "power_idle_tuned_w": $PWR_T,
  "power_delta_w": $PWR_D,
  "notes": ""
}
JSON
)

RUN_RESP=$(curl -s -o /dev/null -w "%{http_code}" -X POST \
    -H "apikey: $SUPABASE_KEY" \
    -H "Authorization: Bearer $SUPABASE_KEY" \
    -H "Content-Type: application/json" \
    "$SUPABASE_URL/rest/v1/runs" \
    -d "$RUN_JSON" 2>/dev/null || echo "000")

if [[ "$RUN_RESP" == "201" ]]; then
    echo "  → Results submitted to tao-forge. (machine: $MACHINE_ID)"
else
    echo "  → tao-forge submit failed (HTTP $RUN_RESP) — results saved locally only."
fi

# ── Append to local hardware-profiles.json (backup) ──────────────────────────
if [[ -f "$HW_DB" ]] && command -v python3 &>/dev/null; then
    python3 - <<PYEOF 2>/dev/null || true
import json, datetime, os

db_path = "$HW_DB"
with open(db_path) as f:
    db = json.load(f)

cpu = "$CPU_MODEL"
machine = next((m for m in db["machines"] if m["hardware"]["cpu"] == cpu), None)

if machine is None:
    machine = {
        "machine_id": "$MACHINE_ID",
        "label": "Auto-detected",
        "hardware": {
            "cpu": cpu,
            "cpu_cores_logical": os.cpu_count(),
            "gpu": "$GPU_MODEL",
            "gpu_vram_gb": None,
            "ram_gb": $RAM_GB,
            "os": "$OS_NAME",
            "kernel": "$KERNEL"
        },
        "runs": []
    }
    db["machines"].append(machine)

def to_float(s):
    try: return float(str(s).replace("+","").replace("?","").strip())
    except: return None

next_id = max((r["run_id"] for r in machine["runs"]), default=0) + 1
machine["runs"].append({
    "run_id": next_id,
    "date": datetime.date.today().isoformat(),
    "preset_version": "v0.6",
    "wrapper_version": "v1.2",
    "network": {"baseline_mbit": to_float("$NET_BASELINE"), "tuned_mbit": to_float("$NET_TUNED"), "delta_pct": to_float("$NET_DELTA")},
    "coldstart": {"baseline_ms": to_float("$COLD_BASELINE"), "tuned_ms": to_float("$COLD_TUNED"), "delta_pct": to_float("$COLD_DELTA")},
    "sustained": {"baseline_toks": to_float("${WARM_BASELINE%% *}"), "tuned_toks": to_float("${WARM_TUNED%% *}"), "delta_pct": to_float("${WARM_DELTA%%%}")},
    "power": {"idle_baseline_w": to_float("$PWR_IDLE"), "idle_tuned_w": to_float("$PWR_TUNED_IDLE"), "delta_w": to_float("$PWR_DELTA")},
    "notes": ""
})
db["last_updated"] = datetime.date.today().isoformat()

with open(db_path, "w") as f:
    json.dump(db, f, indent=2)
PYEOF
fi

echo ""
echo "https://github.com/connormatthewdouglas/TAO-OS"
echo ""
