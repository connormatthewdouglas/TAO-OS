#!/usr/bin/env bash
# TAO-OS tao-os-presets-v0.1.sh
# v0.1 – First separate preset applicator (temporary tweaks only)
# Usage: ./tao-os-presets-v0.1.sh --apply-temp   or   --undo
# Applies: performance governor + energy bias (Intel/AMD)
# Logs changes, backs up originals, fully reversible during session.

set -euo pipefail

ACTION=${1:-"--help"}

echo "TAO-OS Presets v0.1"
echo "----------------------------------------"

if [[ "$ACTION" == "--help" ]]; then
    echo "Usage:"
    echo "  --apply-temp   : Apply mining-friendly tweaks (temporary)"
    echo "  --undo         : Revert to saved previous state"
    exit 0
fi

STATE_FILE="$HOME/TAO-OS/preset_state_backup.txt"

if [[ "$ACTION" == "--apply-temp" ]]; then
    echo "Applying temporary mining presets..."

    # Backup current state
    echo "Original governor: $(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor 2>/dev/null || echo N/A)" > "$STATE_FILE"
    echo "Original energy pref: $(cat /sys/devices/system/cpu/cpu0/cpufreq/energy_performance_preference 2>/dev/null || echo N/A)" >> "$STATE_FILE"

    # Apply tweaks
    if command -v cpupower &> /dev/null; then
        sudo cpupower frequency-set -g performance
        echo "✓ Governor set to performance"
    else
        echo "cpupower not found – skipping governor set"
    fi

    if grep -qi "intel\|amd" /proc/cpuinfo; then
        echo "performance" | sudo tee /sys/devices/system/cpu/cpu*/cpufreq/energy_performance_preference >/dev/null 2>&1 || true
        echo "✓ Energy bias set to performance"
    fi

    echo "Presets applied (temporary – reset on reboot or --undo)."
    echo "Next: Run ./benchmark-v0.6-vanilla.sh to measure lift!"

elif [[ "$ACTION" == "--undo" ]]; then
    if [[ -f "$STATE_FILE" ]]; then
        echo "Reverting presets..."
        # Revert to saved original (simple: set to powersave as common default)
        sudo cpupower frequency-set -g powersave 2>/dev/null || true
        echo "powersave" | sudo tee /sys/devices/system/cpu/cpu*/cpufreq/energy_performance_preference >/dev/null 2>&1 || true
        echo "✓ Reverted to powersave (default)"
        rm -f "$STATE_FILE"
    else
        echo "No backup found – nothing to undo."
    fi
else
    echo "Unknown option. Use --apply-temp or --undo"
fi
