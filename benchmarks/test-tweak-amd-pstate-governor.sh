#!/usr/bin/env bash
# Isolated tweak test: amd_pstate active + cpufreq governor=performance
# Tests on top of full v0.8 stack
set -euo pipefail

ACTION="${1:-}"
ORIG_GOVERNORS=()

# Capture original governors
for f in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do
    [[ -f "$f" ]] && ORIG_GOVERNORS+=("$(cat "$f")") || ORIG_GOVERNORS+=("unknown")
    break  # just need one — they're all the same
done
ORIG_GOV="${ORIG_GOVERNORS[0]:-powersave}"

case "$ACTION" in
    --apply-temp)
        bash "$(dirname "$0")/../presets/cursiveos-presets-v0.7.sh" --apply-temp
        # Set all CPU governors to performance
        for cpu in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do
            [[ -f "$cpu" ]] && echo performance | sudo tee "$cpu" > /dev/null
        done
        echo "✓ cpufreq governor: performance (was $ORIG_GOV)"
        # Report amd_pstate status
        DRIVER=$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_driver 2>/dev/null || echo "unknown")
        echo "✓ CPU frequency driver: $DRIVER"
        ;;
    --undo)
        bash "$(dirname "$0")/../presets/cursiveos-presets-v0.7.sh" --undo
        for cpu in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do
            [[ -f "$cpu" ]] && echo "$ORIG_GOV" | sudo tee "$cpu" > /dev/null
        done
        echo "✓ cpufreq governor reverted to $ORIG_GOV"
        ;;
    --dry-run)
        DRIVER=$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_driver 2>/dev/null || echo "unknown")
        echo "[dry-run] Would set governor=performance on all CPUs (currently $ORIG_GOV)"
        echo "[dry-run] Current driver: $DRIVER"
        bash "$(dirname "$0")/../presets/cursiveos-presets-v0.7.sh" --dry-run
        ;;
    *)
        echo "Usage: $0 [--apply-temp|--undo|--dry-run]"; exit 1 ;;
esac
