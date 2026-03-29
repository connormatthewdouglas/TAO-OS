#!/usr/bin/env bash
# Isolated tweak test: vm.swappiness=0
# Tests swappiness=0 (full disable) on top of the full v0.7 stack
# Note: v0.7 sets swappiness=10; this overrides it to 0 for comparison.
# Usage: ./tao-os-full-test-v1.4.sh benchmarks/test-tweak-swappiness-zero.sh

set -euo pipefail

ACTION="${1:-}"
ORIG_VAL=$(sysctl -n vm.swappiness 2>/dev/null || echo "60")

case "$ACTION" in
    --apply-temp)
        # Apply full v0.7 stack first (sets swappiness=10)
        bash "$(dirname "$0")/../presets/cursiveos-presets-v0.7.sh" --apply-temp

        # Override swappiness to 0 — disable swap pressure entirely
        echo "$TAO_SUDO_PASS" | sudo -S sysctl -w vm.swappiness=0 > /dev/null
        echo "✓ vm.swappiness: 0 (was $ORIG_VAL) — swap pressure fully disabled"
        ;;
    --undo)
        bash "$(dirname "$0")/../presets/cursiveos-presets-v0.7.sh" --undo
        echo "$TAO_SUDO_PASS" | sudo -S sysctl -w vm.swappiness="$ORIG_VAL" > /dev/null
        echo "✓ vm.swappiness reverted to $ORIG_VAL"
        ;;
    --dry-run)
        echo "[dry-run] Would set vm.swappiness=0 (currently $ORIG_VAL, v0.7 would set 10)"
        bash "$(dirname "$0")/../presets/cursiveos-presets-v0.7.sh" --dry-run
        ;;
    *)
        echo "Usage: $0 [--apply-temp|--undo|--dry-run]"
        exit 1
        ;;
esac
