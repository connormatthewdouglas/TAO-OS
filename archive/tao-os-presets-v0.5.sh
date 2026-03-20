#!/usr/bin/env bash
# TAO-OS tao-os-presets-v0.5.sh
# v0.5 – Added Intel Arc GPU performance mode + CPU C-state limiting + THP
#   GPU: slpc_ignore_eff_freq=1, rps_min=2000MHz, rps_boost=2400MHz
#   CPU: disable C2 (18us) + C3 (350us) idle states to eliminate latency spikes
#   Memory: THP=always for ML model loading
# Stacks on top of v0.4 (governor, energy pref, net buffers, BBR, autogroup, swappiness, NMI watchdog)
# Usage: ./tao-os-presets-v0.5.sh --apply-temp   or   --undo

set -euo pipefail

ACTION=${1:-"--help"}
if [[ -z "${TAO_SUDO_PASS:-}" ]]; then
    read -rsp "[TAO-OS] sudo password: " TAO_SUDO_PASS && echo
fi
SP="$TAO_SUDO_PASS"
export TAO_SUDO_PASS
s()  { echo "$SP" | sudo -S "$@" 2>/dev/null || true; }
sc() { echo "$SP" | sudo -S bash -c "$1" 2>/dev/null || true; }

# Detect Intel Arc GPU sysfs path
GPU_GT=""
for card in /sys/class/drm/card*/gt/gt0; do
    if [[ -f "$card/rps_min_freq_mhz" ]]; then
        GPU_GT="$card"
        break
    fi
done

echo "TAO-OS Presets v0.5"
echo "----------------------------------------"
[[ -n "$GPU_GT" ]] && echo "GPU GT path: $GPU_GT" || echo "WARNING: Intel Arc GT path not found – GPU tweaks will be skipped"

if [[ "$ACTION" == "--help" ]]; then
    echo "Usage:"
    echo "  --apply-temp   : Apply mining-friendly tweaks (temporary)"
    echo "  --undo         : Revert to saved previous state"
    exit 0
fi

STATE_FILE="$HOME/TAO-OS/preset_state_backup_v0.5.txt"

if [[ "$ACTION" == "--apply-temp" ]]; then
    echo "Applying temporary mining presets (v0.5)..."

    # ── Backup current state ─────────────────────────────────────────────────
    > "$STATE_FILE"
    echo "governor: $(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor 2>/dev/null || echo N/A)" >> "$STATE_FILE"
    echo "energy_pref: $(cat /sys/devices/system/cpu/cpu0/cpufreq/energy_performance_preference 2>/dev/null || echo N/A)" >> "$STATE_FILE"
    echo "rmem_max: $(sysctl -n net.core.rmem_max)" >> "$STATE_FILE"
    echo "wmem_max: $(sysctl -n net.core.wmem_max)" >> "$STATE_FILE"
    echo "tcp_congestion_control: $(sysctl -n net.ipv4.tcp_congestion_control)" >> "$STATE_FILE"
    echo "default_qdisc: $(sysctl -n net.core.default_qdisc)" >> "$STATE_FILE"
    echo "tcp_slow_start_after_idle: $(sysctl -n net.ipv4.tcp_slow_start_after_idle)" >> "$STATE_FILE"
    echo "sched_autogroup_enabled: $(sysctl -n kernel.sched_autogroup_enabled)" >> "$STATE_FILE"
    echo "nmi_watchdog: $(sysctl -n kernel.nmi_watchdog 2>/dev/null || echo N/A)" >> "$STATE_FILE"
    echo "swappiness: $(sysctl -n vm.swappiness)" >> "$STATE_FILE"
    echo "thp_enabled: $(cat /sys/kernel/mm/transparent_hugepage/enabled | grep -oP '\[\K[^\]]+')" >> "$STATE_FILE"
    if [[ -n "$GPU_GT" ]]; then
        echo "gpu_rps_min: $(cat $GPU_GT/rps_min_freq_mhz)" >> "$STATE_FILE"
        echo "gpu_rps_boost: $(cat $GPU_GT/rps_boost_freq_mhz)" >> "$STATE_FILE"
        echo "gpu_slpc_ignore_eff: $(cat $GPU_GT/slpc_ignore_eff_freq)" >> "$STATE_FILE"
    fi
    # Save C-state status (just cpu0 as reference — apply/undo all uniformly)
    echo "cstate2_disabled: $(cat /sys/devices/system/cpu/cpu0/cpuidle/state2/disable 2>/dev/null || echo N/A)" >> "$STATE_FILE"
    echo "cstate3_disabled: $(cat /sys/devices/system/cpu/cpu0/cpuidle/state3/disable 2>/dev/null || echo N/A)" >> "$STATE_FILE"

    # ── v0.4 tweaks ──────────────────────────────────────────────────────────
    if command -v cpupower &>/dev/null; then
        s cpupower frequency-set -g performance
        echo "✓ Governor: performance"
    fi
    sc 'for f in /sys/devices/system/cpu/cpu*/cpufreq/energy_performance_preference; do echo "performance" > "$f"; done'
    echo "✓ Energy perf preference: performance"
    s sysctl -w net.core.rmem_max=16777216; s sysctl -w net.core.wmem_max=16777216
    echo "✓ Network buffers: rmem/wmem_max = 16MB"
    s sysctl -w kernel.sched_autogroup_enabled=0
    echo "✓ Scheduler autogroup: disabled"
    s sysctl -w net.core.default_qdisc=fq
    s sysctl -w net.ipv4.tcp_congestion_control=bbr 2>/dev/null && echo "✓ TCP: BBR + fq" || echo "  BBR unavailable – skipping"
    s sysctl -w net.ipv4.tcp_slow_start_after_idle=0
    echo "✓ TCP slow start after idle: disabled"
    s sysctl -w vm.swappiness=10
    echo "✓ vm.swappiness: 10"
    s sysctl -w kernel.nmi_watchdog=0 2>/dev/null && echo "✓ NMI watchdog: disabled" || true

    # ── v0.5 new tweaks ──────────────────────────────────────────────────────

    # Intel Arc GPU: ignore efficiency hints (full performance mode)
    if [[ -n "$GPU_GT" ]]; then
        sc "echo 1 > $GPU_GT/slpc_ignore_eff_freq"
        echo "✓ GPU SLPC: efficiency hints ignored (full performance)"

        # GPU min freq → 2000 MHz (prevents drop to 300 MHz between inference calls)
        sc "echo 2000 > $GPU_GT/rps_min_freq_mhz" 2>/dev/null \
            && echo "✓ GPU min freq: 2000 MHz" \
            || echo "  GPU min freq write failed – skipping"

        # GPU boost freq → hardware max (2400 MHz)
        MAX_GPU=$(cat "$GPU_GT/rps_RP0_freq_mhz" 2>/dev/null || echo "2400")
        sc "echo $MAX_GPU > $GPU_GT/rps_boost_freq_mhz" 2>/dev/null \
            && echo "✓ GPU boost freq: ${MAX_GPU} MHz" \
            || echo "  GPU boost freq write failed – skipping"
    else
        echo "  GPU GT path not found – skipping GPU tweaks"
    fi

    # CPU C-state limiting: disable C2 (18us) and C3 (350us) to prevent latency spikes
    sc 'for f in /sys/devices/system/cpu/cpu*/cpuidle/state2/disable; do echo 1 > "$f" 2>/dev/null || true; done'
    echo "✓ CPU C2 idle state: disabled (was 18us latency)"
    sc 'for f in /sys/devices/system/cpu/cpu*/cpuidle/state3/disable; do echo 1 > "$f" 2>/dev/null || true; done'
    echo "✓ CPU C3 idle state: disabled (was 350us latency)"

    # Transparent Huge Pages → always (better for large ML model allocations)
    sc 'echo always > /sys/kernel/mm/transparent_hugepage/enabled' 2>/dev/null \
        && echo "✓ Transparent Huge Pages: always" \
        || echo "  THP write failed – skipping"

    echo ""
    echo "All v0.5 presets applied (temporary – reboot or --undo to revert)."
    echo "Run ./benchmark-v0.9-paired.sh ./tao-os-presets-v0.5.sh to measure lift."

elif [[ "$ACTION" == "--undo" ]]; then
    if [[ -f "$STATE_FILE" ]]; then
        echo "Reverting v0.5 presets..."

        get_val() { grep "^$1:" "$STATE_FILE" | cut -d' ' -f2 | xargs; }

        GOV=$(get_val governor); EP=$(get_val energy_pref)
        [[ "$GOV" != "N/A" ]] && s cpupower frequency-set -g "$GOV" || true
        sc "for f in /sys/devices/system/cpu/cpu*/cpufreq/energy_performance_preference; do echo '$EP' > \"\$f\"; done" || true

        s sysctl -w net.core.rmem_max="$(get_val rmem_max)"
        s sysctl -w net.core.wmem_max="$(get_val wmem_max)"
        s sysctl -w net.core.default_qdisc="$(get_val default_qdisc)"
        s sysctl -w net.ipv4.tcp_congestion_control="$(get_val tcp_congestion_control)" 2>/dev/null || true
        s sysctl -w net.ipv4.tcp_slow_start_after_idle="$(get_val tcp_slow_start_after_idle)"
        s sysctl -w kernel.sched_autogroup_enabled="$(get_val sched_autogroup_enabled)"
        s sysctl -w vm.swappiness="$(get_val swappiness)"
        NMI=$(get_val nmi_watchdog); [[ "$NMI" != "N/A" ]] && s sysctl -w kernel.nmi_watchdog="$NMI" 2>/dev/null || true

        # Revert THP
        THP=$(get_val thp_enabled)
        [[ -n "$THP" ]] && sc "echo '$THP' > /sys/kernel/mm/transparent_hugepage/enabled" || true

        # Revert GPU
        if [[ -n "$GPU_GT" ]]; then
            sc "echo $(get_val gpu_slpc_ignore_eff) > $GPU_GT/slpc_ignore_eff_freq" || true
            sc "echo $(get_val gpu_rps_min) > $GPU_GT/rps_min_freq_mhz" || true
            sc "echo $(get_val gpu_rps_boost) > $GPU_GT/rps_boost_freq_mhz" || true
        fi

        # Revert C-states
        C2=$(get_val cstate2_disabled); C3=$(get_val cstate3_disabled)
        [[ "$C2" != "N/A" ]] && sc "for f in /sys/devices/system/cpu/cpu*/cpuidle/state2/disable; do echo $C2 > \"\$f\" 2>/dev/null || true; done" || true
        [[ "$C3" != "N/A" ]] && sc "for f in /sys/devices/system/cpu/cpu*/cpuidle/state3/disable; do echo $C3 > \"\$f\" 2>/dev/null || true; done" || true

        rm -f "$STATE_FILE"
        echo "✓ All v0.5 settings reverted."
    else
        echo "No backup found – nothing to undo."
    fi

else
    echo "Unknown option. Use --apply-temp or --undo"
fi
