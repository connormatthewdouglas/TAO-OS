#!/usr/bin/env bash
# TAO-OS tao-os-presets-v0.3.sh
# v0.3 – Stacked on v0.2: scheduler tuning, CPU min-freq lock,
#         BBR congestion control, swappiness, NMI watchdog off
# Usage: ./tao-os-presets-v0.3.sh --apply-temp   or   --undo
# All changes temporary (reset on reboot or --undo)

set -euo pipefail

ACTION=${1:-"--help"}
SP="2633"  # sudo password

# Sudo helpers
s()  { echo "$SP" | sudo -S "$@" 2>/dev/null; }        # sudo command
sc() { echo "$SP" | sudo -S bash -c "$1" 2>/dev/null; } # sudo shell string

echo "TAO-OS Presets v0.3"
echo "----------------------------------------"

if [[ "$ACTION" == "--help" ]]; then
    echo "Usage:"
    echo "  --apply-temp   : Apply mining-friendly tweaks (temporary)"
    echo "  --undo         : Revert to saved previous state"
    exit 0
fi

STATE_FILE="$HOME/TAO-OS/preset_state_backup_v0.3.txt"

if [[ "$ACTION" == "--apply-temp" ]]; then
    echo "Applying temporary mining presets (v0.3)..."

    # ── Backup current state ─────────────────────────────────────────────────
    > "$STATE_FILE"
    echo "governor: $(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor 2>/dev/null || echo N/A)" >> "$STATE_FILE"
    echo "energy_pref: $(cat /sys/devices/system/cpu/cpu0/cpufreq/energy_performance_preference 2>/dev/null || echo N/A)" >> "$STATE_FILE"
    echo "scaling_min_freq: $(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_min_freq 2>/dev/null || echo N/A)" >> "$STATE_FILE"
    echo "rmem_max: $(sysctl -n net.core.rmem_max)" >> "$STATE_FILE"
    echo "wmem_max: $(sysctl -n net.core.wmem_max)" >> "$STATE_FILE"
    echo "tcp_congestion_control: $(sysctl -n net.ipv4.tcp_congestion_control)" >> "$STATE_FILE"
    echo "default_qdisc: $(sysctl -n net.core.default_qdisc)" >> "$STATE_FILE"
    echo "tcp_slow_start_after_idle: $(sysctl -n net.ipv4.tcp_slow_start_after_idle)" >> "$STATE_FILE"
    echo "sched_migration_cost_ns: $(sysctl -n kernel.sched_migration_cost_ns 2>/dev/null || echo N/A)" >> "$STATE_FILE"
    echo "sched_autogroup_enabled: $(sysctl -n kernel.sched_autogroup_enabled)" >> "$STATE_FILE"
    echo "nmi_watchdog: $(sysctl -n kernel.nmi_watchdog 2>/dev/null || echo N/A)" >> "$STATE_FILE"
    echo "swappiness: $(sysctl -n vm.swappiness)" >> "$STATE_FILE"

    # ── v0.2 tweaks ──────────────────────────────────────────────────────────

    if command -v cpupower &>/dev/null; then
        s cpupower frequency-set -g performance
        echo "✓ Governor: performance"
    else
        echo "  cpupower not found – skipping governor"
    fi

    sc 'for f in /sys/devices/system/cpu/cpu*/cpufreq/energy_performance_preference; do echo "performance" > "$f"; done'
    echo "✓ Energy perf preference: performance"

    s sysctl -w net.core.rmem_max=16777216
    s sysctl -w net.core.wmem_max=16777216
    echo "✓ Network buffers: rmem/wmem_max = 16MB"

    # ── v0.3 new tweaks ──────────────────────────────────────────────────────

    # Lock CPU min freq = max freq (no frequency drops under load)
    MAX_FREQ=$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_max_freq 2>/dev/null || echo "")
    if [[ -n "$MAX_FREQ" ]]; then
        sc "for f in /sys/devices/system/cpu/cpu*/cpufreq/scaling_min_freq; do echo $MAX_FREQ > \"\$f\"; done"
        echo "✓ CPU min freq locked to max (${MAX_FREQ} kHz)"
    else
        echo "  scaling_max_freq not available – skipping min freq lock"
    fi

    # Disable autogroup (desktop process grouping, hurts sustained mining load)
    s sysctl -w kernel.sched_autogroup_enabled=0
    echo "✓ Scheduler autogroup: disabled"

    # Increase migration cost (better cache locality, less cross-core task bouncing)
    s sysctl -w kernel.sched_migration_cost_ns=5000000 2>/dev/null \
        && echo "✓ Scheduler migration cost: 5ms" \
        || echo "  sched_migration_cost_ns not available – skipping"

    # BBR congestion control + fq qdisc (better Bittensor network throughput)
    s sysctl -w net.core.default_qdisc=fq
    s sysctl -w net.ipv4.tcp_congestion_control=bbr 2>/dev/null \
        && echo "✓ TCP: BBR congestion control + fq qdisc" \
        || echo "  BBR not available on this kernel – skipping"

    # Disable TCP slow start after idle (stable throughput during mining pauses)
    s sysctl -w net.ipv4.tcp_slow_start_after_idle=0
    echo "✓ TCP slow start after idle: disabled"

    # Reduce swappiness (avoid swap under sustained mining load)
    s sysctl -w vm.swappiness=10
    echo "✓ vm.swappiness: 10"

    # Disable NMI watchdog (reduces interrupt overhead during sustained load)
    s sysctl -w kernel.nmi_watchdog=0 2>/dev/null \
        && echo "✓ NMI watchdog: disabled" \
        || echo "  NMI watchdog not available – skipping"

    echo ""
    echo "All v0.3 presets applied (temporary – reboot or --undo to revert)."
    echo "Run ./benchmark-v0.8-vanilla.sh to measure lift."

elif [[ "$ACTION" == "--undo" ]]; then
    if [[ -f "$STATE_FILE" ]]; then
        echo "Reverting v0.3 presets..."

        get_val() { grep "^$1:" "$STATE_FILE" | cut -d' ' -f2 | xargs; }

        GOV=$(get_val governor)
        EP=$(get_val energy_pref)
        MIN_FREQ=$(get_val scaling_min_freq)

        [[ "$GOV" != "N/A" ]] && s cpupower frequency-set -g "$GOV" || true
        sc "for f in /sys/devices/system/cpu/cpu*/cpufreq/energy_performance_preference; do echo '$EP' > \"\$f\"; done" || true

        if [[ -n "$MIN_FREQ" && "$MIN_FREQ" != "N/A" ]]; then
            sc "for f in /sys/devices/system/cpu/cpu*/cpufreq/scaling_min_freq; do echo $MIN_FREQ > \"\$f\"; done" || true
        fi

        s sysctl -w net.core.rmem_max="$(get_val rmem_max)"
        s sysctl -w net.core.wmem_max="$(get_val wmem_max)"
        s sysctl -w net.core.default_qdisc="$(get_val default_qdisc)"
        s sysctl -w net.ipv4.tcp_congestion_control="$(get_val tcp_congestion_control)" 2>/dev/null || true
        s sysctl -w net.ipv4.tcp_slow_start_after_idle="$(get_val tcp_slow_start_after_idle)"
        MIG=$(get_val sched_migration_cost_ns); [[ "$MIG" != "N/A" ]] && s sysctl -w kernel.sched_migration_cost_ns="$MIG" 2>/dev/null || true
        s sysctl -w kernel.sched_autogroup_enabled="$(get_val sched_autogroup_enabled)"
        s sysctl -w vm.swappiness="$(get_val swappiness)"
        s sysctl -w kernel.nmi_watchdog="$(get_val nmi_watchdog)" 2>/dev/null || true

        rm -f "$STATE_FILE"
        echo "✓ All settings reverted to original state."
    else
        echo "No backup found – nothing to undo."
    fi

else
    echo "Unknown option. Use --apply-temp or --undo"
fi
