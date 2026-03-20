#!/usr/bin/env bash
# TAO-OS tao-os-presets-v0.6.sh
# v0.6 – 4 new tweaks on top of v0.5:
#   + AMD CPU boost: ensure turbo boost enabled
#   + THP defrag: madvise (targeted defrag for ML workloads, avoids stalling system)
#   + SYCL persistent kernel cache (Intel Arc only — skipped on other GPUs)
#   + vm.dirty_ratio / vm.dirty_background_ratio tuning (reduce writeback stall)
#
# Usage:
#   ./tao-os-presets-v0.6.sh --apply-temp   apply all tweaks (temporary)
#   ./tao-os-presets-v0.6.sh --undo         revert to saved state
#   ./tao-os-presets-v0.6.sh --dry-run      show what would change, touch nothing

set -euo pipefail

ACTION=${1:-"--help"}

if [[ -z "${TAO_SUDO_PASS:-}" ]]; then
    read -rsp "[TAO-OS] sudo password: " TAO_SUDO_PASS && echo
fi
SP="$TAO_SUDO_PASS"
export TAO_SUDO_PASS
s()  { echo "$SP" | sudo -S "$@" 2>/dev/null || true; }
sc() { echo "$SP" | sudo -S bash -c "$1" 2>/dev/null || true; }

# ── Hardware detection ────────────────────────────────────────────────────────

# Intel Arc GPU sysfs path
GPU_GT=""
for card in /sys/class/drm/card*/gt/gt0; do
    if [[ -f "$card/rps_min_freq_mhz" ]]; then
        GPU_GT="$card"
        break
    fi
done

# AMD CPU boost sysfs path
BOOST_PATH="/sys/devices/system/cpu/cpufreq/boost"

echo "TAO-OS Presets v0.6"
echo "----------------------------------------"
[[ -n "$GPU_GT" ]] && echo "GPU: Intel Arc detected ($GPU_GT)" || echo "GPU: Intel Arc not found – GPU/SYCL tweaks will be skipped"
[[ -f "$BOOST_PATH" ]] && echo "CPU boost: sysfs path found" || echo "CPU boost: sysfs path not found – boost tweak will be skipped"

# ── Help ──────────────────────────────────────────────────────────────────────
if [[ "$ACTION" == "--help" ]]; then
    echo ""
    echo "Usage:"
    echo "  --apply-temp   Apply mining-optimized tweaks (temporary — reboot or --undo reverts)"
    echo "  --undo         Revert to saved state"
    echo "  --dry-run      Show what would change, touch nothing"
    exit 0
fi

# ── Dry run ───────────────────────────────────────────────────────────────────
if [[ "$ACTION" == "--dry-run" ]]; then
    echo ""
    echo "DRY RUN — no changes will be made"
    echo ""
    echo "=== v0.5 tweaks (inherited) ==="
    echo "  CPU governor:                  $(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor 2>/dev/null || echo N/A) → performance"
    echo "  Energy perf preference:        $(cat /sys/devices/system/cpu/cpu0/cpufreq/energy_performance_preference 2>/dev/null || echo N/A) → performance"
    echo "  net.core.rmem_max:             $(sysctl -n net.core.rmem_max) → 16777216"
    echo "  net.core.wmem_max:             $(sysctl -n net.core.wmem_max) → 16777216"
    echo "  tcp_congestion_control:        $(sysctl -n net.ipv4.tcp_congestion_control) → bbr"
    echo "  net.core.default_qdisc:        $(sysctl -n net.core.default_qdisc) → fq"
    echo "  tcp_slow_start_after_idle:     $(sysctl -n net.ipv4.tcp_slow_start_after_idle) → 0"
    echo "  sched_autogroup_enabled:       $(sysctl -n kernel.sched_autogroup_enabled) → 0"
    echo "  vm.swappiness:                 $(sysctl -n vm.swappiness) → 10"
    echo "  kernel.nmi_watchdog:           $(sysctl -n kernel.nmi_watchdog 2>/dev/null || echo N/A) → 0"
    echo "  CPU C2 idle disable:           $(cat /sys/devices/system/cpu/cpu0/cpuidle/state2/disable 2>/dev/null || echo N/A) → 1"
    echo "  CPU C3 idle disable:           $(cat /sys/devices/system/cpu/cpu0/cpuidle/state3/disable 2>/dev/null || echo N/A) → 1"
    echo "  THP enabled:                   $(cat /sys/kernel/mm/transparent_hugepage/enabled | grep -oP '\[\K[^\]]+') → always"
    if [[ -n "$GPU_GT" ]]; then
        echo "  GPU SLPC eff hints:            $(cat $GPU_GT/slpc_ignore_eff_freq) → 1"
        echo "  GPU min freq:                  $(cat $GPU_GT/rps_min_freq_mhz) MHz → 2000 MHz"
        echo "  GPU boost freq:                $(cat $GPU_GT/rps_boost_freq_mhz) MHz → $(cat $GPU_GT/rps_RP0_freq_mhz 2>/dev/null || echo 2400) MHz"
    fi
    echo ""
    echo "=== v0.6 new tweaks ==="
    if [[ -f "$BOOST_PATH" ]]; then
        echo "  AMD CPU boost:                 $(cat $BOOST_PATH) → 1 (ensure turbo enabled)"
    fi
    echo "  THP defrag:                    $(cat /sys/kernel/mm/transparent_hugepage/defrag | grep -oP '\[\K[^\]]+') → madvise"
    echo "  vm.dirty_ratio:                $(sysctl -n vm.dirty_ratio) → 5"
    echo "  vm.dirty_background_ratio:     $(sysctl -n vm.dirty_background_ratio) → 2"
    if [[ -n "$GPU_GT" ]]; then
        echo "  SYCL persistent cache:         [write /etc/profile.d/tao-os-sycl.sh] → SYCL_CACHE_PERSISTENT=1"
    fi
    echo ""
    echo "DRY RUN complete. Run with --apply-temp to apply."
    exit 0
fi

STATE_FILE="$HOME/TAO-OS/preset_state_backup_v0.6.txt"
SYCL_PROFILE="/etc/profile.d/tao-os-sycl.sh"

# ── Apply ─────────────────────────────────────────────────────────────────────
if [[ "$ACTION" == "--apply-temp" ]]; then
    echo "Applying temporary mining presets (v0.6)..."

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
    echo "dirty_ratio: $(sysctl -n vm.dirty_ratio)" >> "$STATE_FILE"
    echo "dirty_background_ratio: $(sysctl -n vm.dirty_background_ratio)" >> "$STATE_FILE"
    echo "thp_enabled: $(cat /sys/kernel/mm/transparent_hugepage/enabled | grep -oP '\[\K[^\]]+')" >> "$STATE_FILE"
    echo "thp_defrag: $(cat /sys/kernel/mm/transparent_hugepage/defrag | grep -oP '\[\K[^\]]+')" >> "$STATE_FILE"
    if [[ -n "$GPU_GT" ]]; then
        echo "gpu_rps_min: $(cat $GPU_GT/rps_min_freq_mhz)" >> "$STATE_FILE"
        echo "gpu_rps_boost: $(cat $GPU_GT/rps_boost_freq_mhz)" >> "$STATE_FILE"
        echo "gpu_slpc_ignore_eff: $(cat $GPU_GT/slpc_ignore_eff_freq)" >> "$STATE_FILE"
        echo "sycl_profile_existed: $([[ -f $SYCL_PROFILE ]] && echo 1 || echo 0)" >> "$STATE_FILE"
        [[ -f "$SYCL_PROFILE" ]] && cp "$SYCL_PROFILE" "${SYCL_PROFILE}.bak" 2>/dev/null || true
    fi
    if [[ -f "$BOOST_PATH" ]]; then
        echo "cpu_boost: $(cat $BOOST_PATH)" >> "$STATE_FILE"
    fi
    echo "cstate2_disabled: $(cat /sys/devices/system/cpu/cpu0/cpuidle/state2/disable 2>/dev/null || echo N/A)" >> "$STATE_FILE"
    echo "cstate3_disabled: $(cat /sys/devices/system/cpu/cpu0/cpuidle/state3/disable 2>/dev/null || echo N/A)" >> "$STATE_FILE"

    # ── v0.5 tweaks ──────────────────────────────────────────────────────────
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

    # Intel Arc GPU tweaks
    if [[ -n "$GPU_GT" ]]; then
        sc "echo 1 > $GPU_GT/slpc_ignore_eff_freq"
        echo "✓ GPU SLPC: efficiency hints ignored (full performance)"
        sc "echo 2000 > $GPU_GT/rps_min_freq_mhz" 2>/dev/null \
            && echo "✓ GPU min freq: 2000 MHz" \
            || echo "  GPU min freq write failed – skipping"
        MAX_GPU=$(cat "$GPU_GT/rps_RP0_freq_mhz" 2>/dev/null || echo "2400")
        sc "echo $MAX_GPU > $GPU_GT/rps_boost_freq_mhz" 2>/dev/null \
            && echo "✓ GPU boost freq: ${MAX_GPU} MHz" \
            || echo "  GPU boost freq write failed – skipping"
    else
        echo "  GPU GT path not found – skipping Arc GPU tweaks"
    fi

    # CPU C-state limiting
    sc 'for f in /sys/devices/system/cpu/cpu*/cpuidle/state2/disable; do echo 1 > "$f" 2>/dev/null || true; done'
    echo "✓ CPU C2 idle state: disabled (was 18μs latency)"
    sc 'for f in /sys/devices/system/cpu/cpu*/cpuidle/state3/disable; do echo 1 > "$f" 2>/dev/null || true; done'
    echo "✓ CPU C3 idle state: disabled (was 350μs latency)"

    # THP
    sc 'echo always > /sys/kernel/mm/transparent_hugepage/enabled' 2>/dev/null \
        && echo "✓ Transparent Huge Pages: always" \
        || echo "  THP enabled write failed – skipping"

    # ── v0.6 new tweaks ──────────────────────────────────────────────────────

    # AMD CPU turbo boost: ensure enabled
    if [[ -f "$BOOST_PATH" ]]; then
        sc "echo 1 > $BOOST_PATH" 2>/dev/null \
            && echo "✓ AMD CPU boost: enabled (turbo on)" \
            || echo "  CPU boost write failed – skipping"
    else
        echo "  CPU boost sysfs not found – skipping (non-AMD or boost controlled elsewhere)"
    fi

    # THP defrag: madvise — only defrag for processes that opt in (madvise)
    # Better than 'always' for mixed workloads: no system-wide stalls
    sc 'echo madvise > /sys/kernel/mm/transparent_hugepage/defrag' 2>/dev/null \
        && echo "✓ THP defrag: madvise (targeted — no system-wide stall)" \
        || echo "  THP defrag write failed – skipping"

    # vm.dirty_ratio: reduce writeback stall (start flushing earlier)
    s sysctl -w vm.dirty_ratio=5 2>/dev/null \
        && echo "✓ vm.dirty_ratio: 5 (was $(grep 'dirty_ratio:' $STATE_FILE | cut -d' ' -f2))" \
        || echo "  vm.dirty_ratio write failed – skipping"
    s sysctl -w vm.dirty_background_ratio=2 2>/dev/null \
        && echo "✓ vm.dirty_background_ratio: 2 (was $(grep 'dirty_background_ratio:' $STATE_FILE | cut -d' ' -f2))" \
        || echo "  vm.dirty_background_ratio write failed – skipping"

    # SYCL persistent kernel cache (Intel Arc only)
    if [[ -n "$GPU_GT" ]]; then
        sc "cat > $SYCL_PROFILE << 'SYCL_EOF'
# TAO-OS: Intel compute environment (applied by tao-os-presets-v0.6.sh)
export SYCL_CACHE_PERSISTENT=1
SYCL_EOF" 2>/dev/null \
            && echo "✓ SYCL persistent cache: enabled (/etc/profile.d/tao-os-sycl.sh)" \
            || echo "  SYCL profile write failed – skipping"
    fi

    echo ""
    echo "All v0.6 presets applied (temporary — reboot or --undo to revert)."

# ── Undo ─────────────────────────────────────────────────────────────────────
elif [[ "$ACTION" == "--undo" ]]; then
    if [[ -f "$STATE_FILE" ]]; then
        echo "Reverting v0.6 presets..."

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
        s sysctl -w vm.dirty_ratio="$(get_val dirty_ratio)" 2>/dev/null || true
        s sysctl -w vm.dirty_background_ratio="$(get_val dirty_background_ratio)" 2>/dev/null || true
        NMI=$(get_val nmi_watchdog); [[ "$NMI" != "N/A" ]] && s sysctl -w kernel.nmi_watchdog="$NMI" 2>/dev/null || true

        # Revert THP
        THP_EN=$(get_val thp_enabled)
        THP_DEF=$(get_val thp_defrag)
        [[ -n "$THP_EN" ]] && sc "echo '$THP_EN' > /sys/kernel/mm/transparent_hugepage/enabled" || true
        [[ -n "$THP_DEF" ]] && sc "echo '$THP_DEF' > /sys/kernel/mm/transparent_hugepage/defrag" || true

        # Revert Arc GPU
        if [[ -n "$GPU_GT" ]]; then
            sc "echo $(get_val gpu_slpc_ignore_eff) > $GPU_GT/slpc_ignore_eff_freq" || true
            sc "echo $(get_val gpu_rps_min) > $GPU_GT/rps_min_freq_mhz" || true
            sc "echo $(get_val gpu_rps_boost) > $GPU_GT/rps_boost_freq_mhz" || true
        fi

        # Revert C-states
        C2=$(get_val cstate2_disabled); C3=$(get_val cstate3_disabled)
        [[ "$C2" != "N/A" ]] && sc "for f in /sys/devices/system/cpu/cpu*/cpuidle/state2/disable; do echo $C2 > \"\$f\" 2>/dev/null || true; done" || true
        [[ "$C3" != "N/A" ]] && sc "for f in /sys/devices/system/cpu/cpu*/cpuidle/state3/disable; do echo $C3 > \"\$f\" 2>/dev/null || true; done" || true

        # Revert CPU boost
        BOOST=$(get_val cpu_boost)
        [[ -n "$BOOST" && -f "$BOOST_PATH" ]] && sc "echo $BOOST > $BOOST_PATH" 2>/dev/null || true

        # Revert SYCL profile
        if [[ -n "$GPU_GT" ]]; then
            SYCL_EXISTED=$(get_val sycl_profile_existed)
            if [[ "$SYCL_EXISTED" == "0" ]]; then
                s rm -f "$SYCL_PROFILE" || true
            elif [[ -f "${SYCL_PROFILE}.bak" ]]; then
                sc "cp '${SYCL_PROFILE}.bak' '$SYCL_PROFILE'" || true
                s rm -f "${SYCL_PROFILE}.bak" || true
            fi
        fi

        rm -f "$STATE_FILE"
        echo "✓ All v0.6 settings reverted."
    else
        echo "No backup found – nothing to undo."
    fi

else
    echo "Unknown option: $ACTION"
    echo "Use --apply-temp, --undo, or --dry-run"
    exit 1
fi
