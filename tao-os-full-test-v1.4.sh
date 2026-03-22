#!/usr/bin/env bash
# TAO-OS Full Test v1.4
# Single command for Bittensor miners to measure their system's baseline
# and the impact of TAO-OS performance presets.
#
# Runs three paired benchmarks (baseline → presets → baseline restored):
#   1. Network throughput  — BBR vs CUBIC on simulated WAN (50ms RTT, 0.5% loss)
#   2. Inference cold-start — model load + TTFT with GPU freq pinned vs idle
#   3. Inference sustained  — steady-state tok/s (GPU-bound baseline)
#
# Changes from v1.3:
#   - Fix power bug: read_watts() now robust against C-state-altered turbostat output
#     (tries numeric-grep fallback + interval-based fallback; logs reason on failure)
#   - v1.4 schema fields: hardware_fingerprint_hash, stability_flag, thermal_headroom_c,
#     kernel_version, distro, submission_timestamp + split power fields
#   - wrapper_version → v1.4
#
# Requirements: ollama installed, tinyllama pulled (ollama pull tinyllama)
# Usage: ./tao-os-full-test-v1.4.sh
#
# All changes are TEMPORARY. Presets revert after each test.
# Logs saved to ~/TAO-OS/logs/

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PRESET="$SCRIPT_DIR/tao-os-presets-v0.7.sh"
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
echo "TAO-OS Full Test v1.4"
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
SUBMISSION_TIMESTAMP=$(date -u +%Y-%m-%dT%H:%M:%SZ)

# ── v1.4: Hardware fingerprint hash ──────────────────────────────────────────
CPU_MICROCODE=$(grep -m1 'microcode' /proc/cpuinfo | awk '{print $3}' 2>/dev/null || echo "unknown")
GPU_VBIOS=$(cat /sys/class/drm/card*/device/vbios_version 2>/dev/null | head -1 || echo "unknown")
HW_FINGERPRINT=$(echo "${CPU_MICROCODE}-${GPU_VBIOS}-${KERNEL}" | sha256sum | cut -c1-16)

# ── v1.4: Thermal headroom ────────────────────────────────────────────────────
CURR_TEMP=$(cat /sys/class/thermal/thermal_zone0/temp 2>/dev/null | awk '{printf "%.0f", $1/1000}' || echo "null")
TJMAX=$(echo "$TAO_SUDO_PASS" | sudo -S turbostat --quiet --num_iterations 1 --show Tj_max 2>/dev/null \
    | grep -E '^[0-9]+' | head -1 | awk '{print int($1)}' || echo "")
[[ -z "$TJMAX" || ! "$TJMAX" =~ ^[0-9] ]] && TJMAX=100
if [[ "$CURR_TEMP" != "null" ]]; then
    THERMAL_HEADROOM=$(python3 -c "print($TJMAX - $CURR_TEMP)" 2>/dev/null || echo "null")
else
    THERMAL_HEADROOM="null"
fi

echo "Hardware:"
echo "  CPU: $CPU_MODEL"
echo "  GPU: $GPU_MODEL"
echo "  Kernel: $KERNEL"
echo "  Date: $(date)"
echo "  Fingerprint: $HW_FINGERPRINT"
echo "  Thermal headroom: ${THERMAL_HEADROOM}°C (Tjmax=${TJMAX}°C, current=${CURR_TEMP}°C)"
echo ""
echo "Running 3 benchmarks. Total time: ~10 minutes."
echo "All presets are TEMPORARY — reverted after each test."
echo "======================================"

# ── Result variables ──────────────────────────────────────────────────────────
NET_BASELINE="" NET_TUNED="" NET_DELTA=""
COLD_BASELINE="" COLD_TUNED="" COLD_DELTA=""
WARM_BASELINE="" WARM_TUNED="" WARM_DELTA=""
PWR_IDLE="" PWR_TUNED_IDLE="" PWR_DELTA=""
STABILITY_FLAG="true"

# ── Power draw snapshot (v1.4: robust multi-fallback) ────────────────────────
# Root cause of v1.3 bug: after C-state disable, turbostat output row structure
# changes — blank lines or reordered rows break 'awk NR==2'. Fix: grep for any
# read_watts: use RAPL energy counters (works even with C-states disabled).
# Turbostat fails with "Insanely slow TSC rate" when C-states are off — RAPL is immune.
read_watts() {
    local rapl="/sys/devices/virtual/powercap/intel-rapl/intel-rapl:0/energy_uj"

    # Primary: RAPL energy counter delta over 1 second (works with or without C-states)
    if [[ -f "$rapl" ]]; then
        local e1 e2 watts
        # Read energy before
        e1=$(echo "$TAO_SUDO_PASS" | sudo -S cat "$rapl" 2>/dev/null)
        if [[ -z "$e1" || ! "$e1" =~ ^[0-9]+$ ]]; then
            echo "N/A"
            return
        fi
        sleep 1
        # Read energy after
        e2=$(echo "$TAO_SUDO_PASS" | sudo -S cat "$rapl" 2>/dev/null)
        if [[ -z "$e2" || ! "$e2" =~ ^[0-9]+$ ]]; then
            echo "N/A"
            return
        fi
        # Calculate watts (convert microjoules to watts over 1 second)
        watts=$(python3 -c "print(f'{($e2 - $e1) / 1_000_000:.2f}')" 2>/dev/null)
        if [[ -n "$watts" && "$watts" =~ ^[0-9] ]]; then
            echo "$watts"
            return
        fi
    fi

    # Fallback: turbostat (only works when C-states are enabled)
    if command -v turbostat &>/dev/null; then
        local w
        w=$(echo "$TAO_SUDO_PASS" | sudo -S turbostat --quiet --num_iterations 1 \
            --show PkgWatt 2>/dev/null \
            | grep -E '^[0-9]*\.[0-9]+' | grep -v '^0\.00$' | tail -1 | awk '{print $1}')
        if [[ -n "$w" && "$w" =~ ^[0-9] ]]; then
            echo "$w"
            return
        fi
    fi

    echo "N/A"
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
bash "$SCRIPT_DIR/benchmarks/benchmark-network-v0.1.sh" "$PRESET" 2>&1
NET_LOG=$(ls -t "$LOG_DIR"/tao-os-network-*.log 2>/dev/null | head -1)
extract_network "$NET_LOG"
echo "  → Network done."

# ── Benchmark 2: Cold-start latency ──────────────────────────────────────────
echo ""
if [[ "$SKIP_INFERENCE" == "1" ]]; then
    echo "[2/3] Cold-start latency — SKIPPED (ollama not installed)"
else
    echo "[2/3] Cold-start latency benchmark (GPU freq: idle vs pinned)..."
    bash "$SCRIPT_DIR/benchmarks/benchmark-inference-v0.2.sh" "$PRESET" "$MODEL" 2>&1
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
    bash "$SCRIPT_DIR/benchmarks/benchmark-inference-v0.1.sh" "$PRESET" "$MODEL" 2>&1
    WARM_LOG=$(ls -t "$LOG_DIR"/tao-os-inference-*.log 2>/dev/null | head -1)
    extract_sustained "$WARM_LOG"
    echo "  → Sustained inference done."
fi

# ── Idle power — tuned + stability check ─────────────────────────────────────
echo ""
echo "Reading idle power with presets active..."
bash "$PRESET" --apply-temp 2>&1 | grep "✓" | sed 's/^/  /' || true
sleep 3
PWR_TUNED_IDLE=$(read_watts)
echo "  → Idle power (tuned): ${PWR_TUNED_IDLE}W"

# v1.4: Stability check — dmesg errors since presets were applied
STABILITY_ERRORS=$(dmesg --since "1 minute ago" 2>/dev/null | grep -ci "error\|panic\|oops\|BUG" 2>/dev/null || true)
STABILITY_ERRORS="${STABILITY_ERRORS:-0}"
STABILITY_ERRORS=$(echo "$STABILITY_ERRORS" | tr -d '[:space:]')
if [[ "$STABILITY_ERRORS" =~ ^[0-9]+$ ]] && [[ "$STABILITY_ERRORS" -eq 0 ]]; then
    STABILITY_FLAG="true"
else
    STABILITY_FLAG="false"
fi
echo "  → Stability flag: $STABILITY_FLAG (dmesg errors in last minute: $STABILITY_ERRORS)"

# Revert presets (must happen after stability check)
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
Fingerprint: $HW_FINGERPRINT
Thermal headroom: ${THERMAL_HEADROOM}°C

Benchmark              Baseline          Tuned             Delta
------------------------------------------------------
Network throughput     ${NET_BASELINE} Mbit/s      ${NET_TUNED} Mbit/s      ${NET_DELTA}%
Cold-start latency     ${COLD_BASELINE}ms           ${COLD_TUNED}ms            ${COLD_DELTA}%
Sustained inference    ${WARM_BASELINE}     ${WARM_TUNED}   ${WARM_DELTA}
Idle power draw        ${PWR_IDLE}W               ${PWR_TUNED_IDLE}W             ${PWR_DELTA}W
Stability              ${STABILITY_FLAG} (dmesg errors: ${STABILITY_ERRORS})

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

to_json_bool() {
    [[ "$1" == "true" ]] && echo "true" || echo "false"
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
THERM=$(to_json_num "$THERMAL_HEADROOM")
STAB=$(to_json_bool "$STABILITY_FLAG")

SUPABASE_HEADERS=(
    -H "apikey: $SUPABASE_KEY"
    -H "Authorization: Bearer $SUPABASE_KEY"
    -H "Content-Type: application/json"
)

# Upsert machine — check first, insert only if not exists
MACHINE_EXISTS=$(curl -s \
    -H "apikey: $SUPABASE_KEY" \
    -H "Authorization: Bearer $SUPABASE_KEY" \
    "$SUPABASE_URL/rest/v1/machines?machine_id=eq.$MACHINE_ID&select=machine_id" 2>/dev/null)

if [[ "$MACHINE_EXISTS" == "[]" ]]; then
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
        -H "Prefer: return=minimal" \
        "$SUPABASE_URL/rest/v1/machines" \
        -d "$MACHINE_JSON" 2>/dev/null || echo "000")
else
    MACHINE_RESP="200"  # already exists, skip insert
fi

# Insert run (columns matching current DB schema)
RUN_JSON=$(cat <<JSON
{
  "machine_id": "$MACHINE_ID",
  "run_date": "$(date +%Y-%m-%d)",
  "preset_version": "v0.7",
  "wrapper_version": "v1.4",
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
  "notes": "hw:$HW_FINGERPRINT stability:$STAB thermal:${THERM}C kernel:$KERNEL"
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

def to_bool(s):
    return s.lower() == "true"

def to_int(s):
    try: return int(s)
    except: return None

next_id = max((r["run_id"] for r in machine["runs"]), default=0) + 1
machine["runs"].append({
    "run_id": next_id,
    "date": datetime.date.today().isoformat(),
    "submission_timestamp": "$SUBMISSION_TIMESTAMP",
    "preset_version": "v0.7",
    "wrapper_version": "v1.4",
    "hardware_fingerprint_hash": "$HW_FINGERPRINT",
    "stability_flag": to_bool("$STABILITY_FLAG"),
    "thermal_headroom_c": to_int("$THERMAL_HEADROOM"),
    "kernel_version": "$KERNEL",
    "distro": "$OS_NAME",
    "network": {"baseline_mbit": to_float("$NET_BASELINE"), "tuned_mbit": to_float("$NET_TUNED"), "delta_pct": to_float("$NET_DELTA")},
    "coldstart": {"baseline_ms": to_float("$COLD_BASELINE"), "tuned_ms": to_float("$COLD_TUNED"), "delta_pct": to_float("$COLD_DELTA")},
    "sustained": {"baseline_toks": to_float("${WARM_BASELINE%% *}"), "tuned_toks": to_float("${WARM_TUNED%% *}"), "delta_pct": to_float("${WARM_DELTA%%%}")},
    "power": {
        "idle_baseline_w": to_float("$PWR_IDLE"),
        "idle_tuned_w": to_float("$PWR_TUNED_IDLE"),
        "delta_w": to_float("$PWR_DELTA")
    },
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

# ── Notify CopperClaw that the run is complete ────────────────────────────────
SENTINEL_DIR="$SCRIPT_DIR/dashboard"
SENTINEL_FILE="$SENTINEL_DIR/run_complete.json"
python3 - <<PYEOF 2>/dev/null || true
import json, datetime, pathlib

sentinel = {
    "completed_at": datetime.datetime.now().isoformat(),
    "log": "$SUMMARY_LOG",
    "network_delta": "$NET_DELTA",
    "coldstart_delta": "$COLD_DELTA",
    "power_baseline": "$PWR_IDLE",
    "power_tuned": "$PWR_TUNED_IDLE",
    "stability": "$STABILITY_FLAG",
    "fingerprint": "$HW_FINGERPRINT"
}
pathlib.Path("$SENTINEL_FILE").write_text(json.dumps(sentinel, indent=2))

# Also append to comms feed
comms = {
    "ts": datetime.datetime.now().isoformat(),
    "from": "Vega",
    "to": "CopperClaw",
    "type": "result",
    "msg": f"Benchmark complete. Network: $NET_DELTA%, Cold-start: $COLD_DELTA%, Power: $PWR_IDLE → $PWR_TUNED_IDLE W, Stability: $STABILITY_FLAG"
}
comms_file = pathlib.Path("$SENTINEL_DIR/comms.jsonl")
with open(comms_file, "a") as f:
    f.write(json.dumps(comms) + "\n")
PYEOF
