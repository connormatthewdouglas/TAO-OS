#!/usr/bin/env bash
# TAO-OS tao-os-presets-v0.2.sh
# v0.2 – Added temporary net buffer increase (rmem/wmem_max = 16MB) for Bittensor gossip/chain traffic
# Usage: ./tao-os-presets-v0.2.sh --apply-temp   or   --undo
# All changes temporary (reset on reboot or undo)

set -euo pipefail

ACTION=${1:-"--help"}

echo "TAO-OS Presets v0.2"
echo "----------------------------------------"

if [[ "$ACTION" == "--help" ]]; then
    echo "Usage:"
    echo "  --apply-temp   : Apply mining-friendly tweaks (temporary)"
    echo "  --undo         : Revert to saved previous state"
    exit 0
fi

STATE_FILE="$HOME/TAO-OS/preset_state_backup_v0.2.txt"

if [[ "$ACTION" == "--apply-temp" ]]; then
    echo "Applying temporary mining presets (v0.2)..."

    # Backup current state
    > "$STATE_FILE"  # Clear file
    echo "Original governor: $(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor 2>/dev/null || echo N/A)" >> "$STATE_FILE"
    echo "Original energy pref: $(cat /sys/devices/system/cpu/cpu0/cpufreq/energy_performance_preference 2>/dev/null || echo N/A)" >> "$STATE_FILE"
    echo "Original net.core.rmem_max: $(sysctl -n net.core.rmem_max)" >> "$STATE_FILE"
    echo "Original net.core.wmem_max: $(sysctl -n net.core.wmem_max)" >> "$STATE_FILE"

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

    # Net buffers for better network under mining load
    sudo sysctl -w net.core.rmem_max=16777216
    sudo sysctl -w net.core.wmem_max=16777216
    echo "✓ Network buffers increased (rmem/wmem_max = 16MB)"

    echo "Presets applied (temporary)."
    echo "Next: Run ./benchmark-v0.7-vanilla.sh to measure lift!"

elif [[ "$ACTION" == "--undo" ]]; then
    if [[ -f "$STATE_FILE" ]]; then
        echo "Reverting presets (v0.2)..."
        # Revert to powersave + original buffers
        sudo cpupower frequency-set -g powersave 2>/dev/null || true
        echo "powersave" | sudo tee /sys/devices/system/cpu/cpu*/cpufreq/energy_performance_preference >/dev/null 2>&1 || true
        ORIGINAL_RMEM=$(grep "Original net.core.rmem_max" "$STATE_FILE" | cut -d: -f2 | xargs || echo 212992)
        ORIGINAL_WMEM=$(grep "Original net.core.wmem_max" "$STATE_FILE" | cut -d: -f2 | xargs || echo 212992)
        sudo sysctl -w net.core.rmem_max="$ORIGINAL_RMEM"
        sudo sysctl -w net.core.wmem_max="$ORIGINAL_WMEM"
        echo "✓ Reverted to powersave + original buffers"
        rm -f "$STATE_FILE"
    else
        echo "No backup found – nothing to undo."
    fi
else
    echo "Unknown option. Use --apply-temp or --undo"
fi
