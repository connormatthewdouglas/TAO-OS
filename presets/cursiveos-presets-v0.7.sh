#!/usr/bin/env bash
# CursiveOS tao-os-presets-v0.7.sh
# v0.7 – 7 new tweaks on top of v0.6 (research-backed additions):
#   + tcp_rmem/tcp_wmem: close the 16MB gap (rmem_max was set, auto-tuner wasn't)
#   + C6 idle state: disable by name (robust cross-BIOS, not fragile index)
#   + kernel.numa_balancing=0 (Ryzen 5700 is single NUMA node — pure overhead)
#   + vm.compaction_proactiveness=0 (stops background THP compaction jitter)
#   + net.core.netdev_max_backlog=5000 (prevents silent packet drops under P2P load)
#   + kernel.sched_min_granularity_ns (faster scheduler response for inference threads)
#   + net.core.somaxconn=4096 (larger connection queue for validator traffic)
#
# Usage:
#   ./tao-os-presets-v0.7.sh --apply-temp   apply all tweaks (temporary)
#   ./tao-os-presets-v0.7.sh --undo         revert to saved state
#   ./tao-os-presets-v0.7.sh --dry-run      show what would change, touch nothing

set -euo pipefail

ACTION=${1:-"--help"}

if [[ -z "${TAO_SUDO_PASS:-}" ]]; then
    read -rsp "[CursiveOS] sudo password: " TAO_SUDO_PASS && echo
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

# C6 state index (varies by BIOS — detect by name, not index)
C6_IDX=""
for state_dir in /sys/devices/system/cpu/cpu0/cpuidle/state*/; do
    name=$(cat "${state_dir}name" 2>/dev/null || echo "")
    if [[ "$name" == "C6" ]]; then
        C6_IDX=$(basename "$state_dir" | sed 's/state//')
        break
    fi
done

echo "CursiveOS Presets v0.7"
echo "----------------------------------------"
[[ -n "$GPU_GT" ]]  && echo "GPU: Intel Arc detected ($GPU_GT)" \
                    || echo "GPU: Intel Arc not found – GPU/SYCL tweaks will be skipped"
[[ -f "$BOOST_PATH" ]] && echo "CPU boost: sysfs path found" \
                       || echo "CPU boost: sysfs path not found – skipping"
[[ -n "$C6_IDX" ]] && echo "CPU C6: found at state${C6_IDX}" \
                   || echo "CPU C6: not found by name – name-based disable will skip"

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
    echo "=== Inherited from v0.6 ==="
    echo "  CPU governor:                     $(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor 2>/dev/null || echo N/A) → performance"
    echo "  Energy perf preference:           $(cat /sys/devices/system/cpu/cpu0/cpufreq/energy_performance_preference 2>/dev/null || echo N/A) → performance"
    echo "  net.core.rmem_max:                $(sysctl -n net.core.rmem_max) → 16777216"
    echo "  net.core.wmem_max:                $(sysctl -n net.core.wmem_max) → 16777216"
    echo "  tcp_congestion_control:           $(sysctl -n net.ipv4.tcp_congestion_control) → bbr"
    echo "  net.core.default_qdisc:           $(sysctl -n net.core.default_qdisc) → fq"
    echo "  tcp_slow_start_after_idle:        $(sysctl -n net.ipv4.tcp_slow_start_after_idle) → 0"
    echo "  sched_autogroup_enabled:          $(sysctl -n kernel.sched_autogroup_enabled) → 0"
    echo "  vm.swappiness:                    $(sysctl -n vm.swappiness) → 10"
    echo "  kernel.nmi_watchdog:              $(sysctl -n kernel.nmi_watchdog 2>/dev/null || echo N/A) → 0"
    echo "  CPU C2 idle (index):              $(cat /sys/devices/system/cpu/cpu0/cpuidle/state2/disable 2>/dev/null || echo N/A) → 1"
    echo "  CPU C3 idle (index):              $(cat /sys/devices/system/cpu/cpu0/cpuidle/state3/disable 2>/dev/null || echo N/A) → 1"
    echo "  THP enabled:                      $(cat /sys/kernel/mm/transparent_hugepage/enabled | grep -oP '\[\K[^\]]+') → always"
    echo "  THP defrag:                       $(cat /sys/kernel/mm/transparent_hugepage/defrag | grep -oP '\[\K[^\]]+') → madvise"
    echo "  vm.dirty_ratio:                   $(sysctl -n vm.dirty_ratio) → 5"
    echo "  vm.dirty_background_ratio:        $(sysctl -n vm.dirty_background_ratio) → 2"
    echo "  vm.compaction_proactiveness:      $(sysctl -n vm.compaction_proactiveness 2>/dev/null || echo N/A) → 0"
    [[ -f "$BOOST_PATH" ]] && echo "  AMD CPU boost:                    $(cat $BOOST_PATH) → 1"
    [[ -n "$GPU_GT" ]] && echo "  GPU SLPC/min/boost (Arc only):    enabled"
    [[ -n "$GPU_GT" ]] && echo "  SYCL persistent cache (Arc only): enabled"
    echo ""
    echo "=== v0.7 new tweaks ==="
    echo "  net.ipv4.tcp_rmem:                $(sysctl -n net.ipv4.tcp_rmem) → 4096 262144 16777216"
    echo "  net.ipv4.tcp_wmem:                $(sysctl -n net.ipv4.tcp_wmem) → 4096 262144 16777216"
    [[ -n "$C6_IDX" ]] && \
    echo "  CPU C6 idle (by name, state$C6_IDX):  $(cat /sys/devices/system/cpu/cpu0/cpuidle/state${C6_IDX}/disable 2>/dev/null || echo N/A) → 1"
    echo "  kernel.numa_balancing:            $(sysctl -n kernel.numa_balancing 2>/dev/null || echo N/A) → 0"
    echo "  vm.compaction_proactiveness:      $(sysctl -n vm.compaction_proactiveness 2>/dev/null || echo N/A) → 0"
    echo "  net.core.netdev_max_backlog:      $(sysctl -n net.core.netdev_max_backlog) → 5000"
    echo "  kernel.sched_min_granularity_ns:  $(sysctl -n kernel.sched_min_granularity_ns 2>/dev/null || echo N/A) → 1000000"
    echo "  kernel.sched_wakeup_granularity:  $(sysctl -n kernel.sched_wakeup_granularity_ns 2>/dev/null || echo N/A) → 1500000"
    echo "  net.core.somaxconn:               $(sysctl -n net.core.somaxconn) → 4096"
    echo ""
    echo "DRY RUN complete. Run with --apply-temp to apply."
    exit 0
fi

STATE_FILE="$HOME/CursiveOS/preset_state_backup_v0.7.txt"
SYCL_PROFILE="/etc/profile.d/cursiveos-sycl.sh"

# ── Apply ─────────────────────────────────────────────────────────────────────
if [[ "$ACTION" == "--apply-temp" ]]; then
    echo "Applying temporary mining presets (v0.7)..."

    # ── Backup current state ─────────────────────────────────────────────────
    > "$STATE_FILE"
    echo "governor: $(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor 2>/dev/null || echo N/A)" >> "$STATE_FILE"
    echo "energy_pref: $(cat /sys/devices/system/cpu/cpu0/cpufreq/energy_performance_preference 2>/dev/null || echo N/A)" >> "$STATE_FILE"
    echo "rmem_max: $(sysctl -n net.core.rmem_max)" >> "$STATE_FILE"
    echo "wmem_max: $(sysctl -n net.core.wmem_max)" >> "$STATE_FILE"
    echo "tcp_rmem: $(sysctl -n net.ipv4.tcp_rmem | tr -s ' ')" >> "$STATE_FILE"
    echo "tcp_wmem: $(sysctl -n net.ipv4.tcp_wmem | tr -s ' ')" >> "$STATE_FILE"
    echo "tcp_congestion_control: $(sysctl -n net.ipv4.tcp_congestion_control)" >> "$STATE_FILE"
    echo "default_qdisc: $(sysctl -n net.core.default_qdisc)" >> "$STATE_FILE"
    echo "tcp_slow_start_after_idle: $(sysctl -n net.ipv4.tcp_slow_start_after_idle)" >> "$STATE_FILE"
    echo "sched_autogroup_enabled: $(sysctl -n kernel.sched_autogroup_enabled)" >> "$STATE_FILE"
    echo "nmi_watchdog: $(sysctl -n kernel.nmi_watchdog 2>/dev/null || echo N/A)" >> "$STATE_FILE"
    echo "swappiness: $(sysctl -n vm.swappiness)" >> "$STATE_FILE"
    echo "dirty_ratio: $(sysctl -n vm.dirty_ratio)" >> "$STATE_FILE"
    echo "dirty_background_ratio: $(sysctl -n vm.dirty_background_ratio)" >> "$STATE_FILE"
    echo "numa_balancing: $(sysctl -n kernel.numa_balancing 2>/dev/null || echo N/A)" >> "$STATE_FILE"
    echo "compaction_proactiveness: $(sysctl -n vm.compaction_proactiveness 2>/dev/null || echo N/A)" >> "$STATE_FILE"
    echo "netdev_max_backlog: $(sysctl -n net.core.netdev_max_backlog)" >> "$STATE_FILE"
    echo "sched_min_granularity_ns: $(sysctl -n kernel.sched_min_granularity_ns 2>/dev/null || echo N/A)" >> "$STATE_FILE"
    echo "sched_wakeup_granularity_ns: $(sysctl -n kernel.sched_wakeup_granularity_ns 2>/dev/null || echo N/A)" >> "$STATE_FILE"
    echo "somaxconn: $(sysctl -n net.core.somaxconn)" >> "$STATE_FILE"
    echo "thp_enabled: $(cat /sys/kernel/mm/transparent_hugepage/enabled | grep -oP '\[\K[^\]]+')" >> "$STATE_FILE"
    echo "thp_defrag: $(cat /sys/kernel/mm/transparent_hugepage/defrag | grep -oP '\[\K[^\]]+')" >> "$STATE_FILE"
    echo "cstate2_disabled: $(cat /sys/devices/system/cpu/cpu0/cpuidle/state2/disable 2>/dev/null || echo N/A)" >> "$STATE_FILE"
    echo "cstate3_disabled: $(cat /sys/devices/system/cpu/cpu0/cpuidle/state3/disable 2>/dev/null || echo N/A)" >> "$STATE_FILE"
    echo "c6_idx: ${C6_IDX:-N/A}" >> "$STATE_FILE"
    [[ -n "$C6_IDX" ]] && \
        echo "c6_disabled: $(cat /sys/devices/system/cpu/cpu0/cpuidle/state${C6_IDX}/disable 2>/dev/null || echo N/A)" >> "$STATE_FILE" || \
        echo "c6_disabled: N/A" >> "$STATE_FILE"
    if [[ -n "$GPU_GT" ]]; then
        echo "gpu_rps_min: $(cat $GPU_GT/rps_min_freq_mhz)" >> "$STATE_FILE"
        echo "gpu_rps_boost: $(cat $GPU_GT/rps_boost_freq_mhz)" >> "$STATE_FILE"
        echo "gpu_slpc_ignore_eff: $(cat $GPU_GT/slpc_ignore_eff_freq)" >> "$STATE_FILE"
        echo "sycl_profile_existed: $([[ -f $SYCL_PROFILE ]] && echo 1 || echo 0)" >> "$STATE_FILE"
        [[ -f "$SYCL_PROFILE" ]] && cp "$SYCL_PROFILE" "${SYCL_PROFILE}.bak" 2>/dev/null || true
    fi
    [[ -f "$BOOST_PATH" ]] && echo "cpu_boost: $(cat $BOOST_PATH)" >> "$STATE_FILE"

    # ── Inherited v0.6 tweaks ─────────────────────────────────────────────────
    if command -v cpupower &>/dev/null; then
        s cpupower frequency-set -g performance
        echo "✓ Governor: performance"
    fi
    sc 'for f in /sys/devices/system/cpu/cpu*/cpufreq/energy_performance_preference; do echo "performance" > "$f"; done'
    echo "✓ Energy perf preference: performance"
    s sysctl -w net.core.rmem_max=16777216
    s sysctl -w net.core.wmem_max=16777216
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
    sc 'for f in /sys/devices/system/cpu/cpu*/cpuidle/state2/disable; do echo 1 > "$f" 2>/dev/null || true; done'
    echo "✓ CPU C2 idle state: disabled (18μs)"
    sc 'for f in /sys/devices/system/cpu/cpu*/cpuidle/state3/disable; do echo 1 > "$f" 2>/dev/null || true; done'
    echo "✓ CPU C3 idle state: disabled (350μs)"
    sc 'echo always > /sys/kernel/mm/transparent_hugepage/enabled'
    echo "✓ Transparent Huge Pages: always"
    sc 'echo madvise > /sys/kernel/mm/transparent_hugepage/defrag'
    echo "✓ THP defrag: madvise"
    s sysctl -w vm.dirty_ratio=5
    echo "✓ vm.dirty_ratio: 5"
    s sysctl -w vm.dirty_background_ratio=2
    echo "✓ vm.dirty_background_ratio: 2"
    if [[ -f "$BOOST_PATH" ]]; then
        sc "echo 1 > $BOOST_PATH"
        echo "✓ AMD CPU boost: enabled (turbo on)"
    fi
    if [[ -n "$GPU_GT" ]]; then
        sc "echo 1 > $GPU_GT/slpc_ignore_eff_freq"
        echo "✓ GPU SLPC: efficiency hints ignored (Arc)"
        sc "echo 2000 > $GPU_GT/rps_min_freq_mhz"
        echo "✓ GPU min freq: 2000 MHz (Arc)"
        MAX_GPU=$(cat "$GPU_GT/rps_RP0_freq_mhz" 2>/dev/null || echo "2400")
        sc "echo $MAX_GPU > $GPU_GT/rps_boost_freq_mhz"
        echo "✓ GPU boost freq: ${MAX_GPU} MHz (Arc)"
        sc "cat > $SYCL_PROFILE << 'SYCL_EOF'
# CursiveOS: Intel compute environment
export SYCL_CACHE_PERSISTENT=1
SYCL_EOF"
        echo "✓ SYCL persistent cache: enabled (Arc)"
    else
        echo "  GPU GT path not found – skipping Arc GPU tweaks"
    fi

    # ── v0.7 new tweaks ───────────────────────────────────────────────────────

    # tcp_rmem/tcp_wmem: explicitly set 16MB ceiling for the TCP auto-tuner
    # Closes the gap where rmem_max=16MB but the auto-tuner was silently capped lower
    s sysctl -w net.ipv4.tcp_rmem="4096 262144 16777216" \
        && echo "✓ tcp_rmem: 4096 / 262144 / 16MB (auto-tuner ceiling now matches rmem_max)" \
        || echo "  tcp_rmem write failed – skipping"
    s sysctl -w net.ipv4.tcp_wmem="4096 262144 16777216" \
        && echo "✓ tcp_wmem: 4096 / 262144 / 16MB" \
        || echo "  tcp_wmem write failed – skipping"

    # C6 disable by name (robust cross-BIOS — doesn't assume a fixed state index)
    if [[ -n "$C6_IDX" ]]; then
        sc "for f in /sys/devices/system/cpu/cpu*/cpuidle/state${C6_IDX}/disable; do echo 1 > \"\$f\" 2>/dev/null || true; done"
        echo "✓ CPU C6 idle state: disabled by name at state${C6_IDX} (highest-latency AMD sleep)"
    else
        echo "  CPU C6 not found by name – skipping (may already be handled by C2/C3 disable)"
    fi

    # NUMA balancing: pure overhead on single-socket Ryzen (one NUMA node)
    s sysctl -w kernel.numa_balancing=0 2>/dev/null \
        && echo "✓ NUMA balancing: disabled (single NUMA node — eliminates spurious page fault overhead)" \
        || echo "  NUMA balancing sysctl not available – skipping"

    # Compaction proactiveness: stop background THP compaction causing latency spikes
    s sysctl -w vm.compaction_proactiveness=0 2>/dev/null \
        && echo "✓ THP compaction proactiveness: 0 (no background compaction jitter)" \
        || echo "  compaction_proactiveness not available – skipping"

    # Packet backlog: prevents silent drops under heavy Bittensor P2P / gossip traffic
    s sysctl -w net.core.netdev_max_backlog=5000 \
        && echo "✓ netdev_max_backlog: 5000 (prevents packet drops under validator load)" \
        || echo "  netdev_max_backlog write failed – skipping"

    # Scheduler granularity: faster wakeup for inference threads yielding on GPU wait
    s sysctl -w kernel.sched_min_granularity_ns=1000000 2>/dev/null \
        && echo "✓ sched_min_granularity_ns: 1ms (faster scheduler response for inference threads)" \
        || echo "  sched_min_granularity_ns not available – skipping"
    s sysctl -w kernel.sched_wakeup_granularity_ns=1500000 2>/dev/null \
        && echo "✓ sched_wakeup_granularity_ns: 1.5ms" \
        || echo "  sched_wakeup_granularity_ns not available – skipping"

    # Connection queue: handles many simultaneous validator inbound connections
    s sysctl -w net.core.somaxconn=4096 \
        && echo "✓ net.core.somaxconn: 4096 (larger connection queue for validator traffic)" \
        || echo "  somaxconn write failed – skipping"

    echo ""
    echo "All v0.7 presets applied (temporary — reboot or --undo to revert)."

# ── Undo ─────────────────────────────────────────────────────────────────────
elif [[ "$ACTION" == "--undo" ]]; then
    if [[ -f "$STATE_FILE" ]]; then
        echo "Reverting v0.7 presets..."

        get_val()     { grep "^$1:" "$STATE_FILE" | cut -d':' -f2- | xargs; }
        get_val_raw() { grep "^$1:" "$STATE_FILE" | cut -d':' -f2-; }

        GOV=$(get_val governor); EP=$(get_val energy_pref)
        [[ "$GOV" != "N/A" ]] && s cpupower frequency-set -g "$GOV" || true
        sc "for f in /sys/devices/system/cpu/cpu*/cpufreq/energy_performance_preference; do echo '$EP' > \"\$f\"; done" || true

        s sysctl -w net.core.rmem_max="$(get_val rmem_max)"
        s sysctl -w net.core.wmem_max="$(get_val wmem_max)"
        TCP_RMEM=$(get_val_raw tcp_rmem | xargs); [[ -n "$TCP_RMEM" ]] && s sysctl -w net.ipv4.tcp_rmem="$TCP_RMEM" || true
        TCP_WMEM=$(get_val_raw tcp_wmem | xargs); [[ -n "$TCP_WMEM" ]] && s sysctl -w net.ipv4.tcp_wmem="$TCP_WMEM" || true
        s sysctl -w net.core.default_qdisc="$(get_val default_qdisc)"
        s sysctl -w net.ipv4.tcp_congestion_control="$(get_val tcp_congestion_control)" 2>/dev/null || true
        s sysctl -w net.ipv4.tcp_slow_start_after_idle="$(get_val tcp_slow_start_after_idle)"
        s sysctl -w kernel.sched_autogroup_enabled="$(get_val sched_autogroup_enabled)"
        s sysctl -w vm.swappiness="$(get_val swappiness)"
        s sysctl -w vm.dirty_ratio="$(get_val dirty_ratio)"
        s sysctl -w vm.dirty_background_ratio="$(get_val dirty_background_ratio)"
        NMI=$(get_val nmi_watchdog); [[ "$NMI" != "N/A" ]] && s sysctl -w kernel.nmi_watchdog="$NMI" 2>/dev/null || true
        NUMA=$(get_val numa_balancing); [[ "$NUMA" != "N/A" ]] && s sysctl -w kernel.numa_balancing="$NUMA" 2>/dev/null || true
        COMP=$(get_val compaction_proactiveness); [[ "$COMP" != "N/A" ]] && s sysctl -w vm.compaction_proactiveness="$COMP" 2>/dev/null || true
        s sysctl -w net.core.netdev_max_backlog="$(get_val netdev_max_backlog)"
        SGN=$(get_val sched_min_granularity_ns); [[ "$SGN" != "N/A" ]] && s sysctl -w kernel.sched_min_granularity_ns="$SGN" 2>/dev/null || true
        SWG=$(get_val sched_wakeup_granularity_ns); [[ "$SWG" != "N/A" ]] && s sysctl -w kernel.sched_wakeup_granularity_ns="$SWG" 2>/dev/null || true
        s sysctl -w net.core.somaxconn="$(get_val somaxconn)"

        THP_EN=$(get_val thp_enabled)
        THP_DEF=$(get_val thp_defrag)
        [[ -n "$THP_EN" ]] && sc "echo '$THP_EN' > /sys/kernel/mm/transparent_hugepage/enabled" || true
        [[ -n "$THP_DEF" ]] && sc "echo '$THP_DEF' > /sys/kernel/mm/transparent_hugepage/defrag" || true

        C2=$(get_val cstate2_disabled); C3=$(get_val cstate3_disabled)
        [[ "$C2" != "N/A" ]] && sc "for f in /sys/devices/system/cpu/cpu*/cpuidle/state2/disable; do echo $C2 > \"\$f\" 2>/dev/null || true; done" || true
        [[ "$C3" != "N/A" ]] && sc "for f in /sys/devices/system/cpu/cpu*/cpuidle/state3/disable; do echo $C3 > \"\$f\" 2>/dev/null || true; done" || true

        C6_IDX_SAVED=$(get_val c6_idx); C6_VAL=$(get_val c6_disabled)
        [[ "$C6_IDX_SAVED" != "N/A" && "$C6_VAL" != "N/A" ]] && \
            sc "for f in /sys/devices/system/cpu/cpu*/cpuidle/state${C6_IDX_SAVED}/disable; do echo $C6_VAL > \"\$f\" 2>/dev/null || true; done" || true

        if [[ -n "$GPU_GT" ]]; then
            sc "echo $(get_val gpu_slpc_ignore_eff) > $GPU_GT/slpc_ignore_eff_freq" || true
            sc "echo $(get_val gpu_rps_min) > $GPU_GT/rps_min_freq_mhz" || true
            sc "echo $(get_val gpu_rps_boost) > $GPU_GT/rps_boost_freq_mhz" || true
            SYCL_EXISTED=$(get_val sycl_profile_existed)
            if [[ "$SYCL_EXISTED" == "0" ]]; then
                s rm -f "$SYCL_PROFILE" || true
            elif [[ -f "${SYCL_PROFILE}.bak" ]]; then
                sc "cp '${SYCL_PROFILE}.bak' '$SYCL_PROFILE'" || true
                s rm -f "${SYCL_PROFILE}.bak" || true
            fi
        fi

        BOOST=$(get_val cpu_boost)
        [[ -n "$BOOST" && -f "$BOOST_PATH" ]] && sc "echo $BOOST > $BOOST_PATH" 2>/dev/null || true

        rm -f "$STATE_FILE"
        echo "✓ All v0.7 settings reverted."
    else
        echo "No backup found – nothing to undo."
    fi

else
    echo "Unknown option: $ACTION"
    echo "Use --apply-temp, --undo, or --dry-run"
    exit 1
fi
