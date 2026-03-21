#!/usr/bin/env bash
# Isolated tweak test: vm.min_free_kbytes=262144
# Tests this single tweak on top of the full v0.7 stack
# Usage: ./tao-os-full-test-v1.4.sh benchmarks/test-tweak-min-free-kbytes.sh

set -euo pipefail

ACTION="${1:-}"
ORIG_VAL=$(cat /proc/sys/vm/min_free_kbytes 2>/dev/null || echo "67584")

case "$ACTION" in
    --apply-temp)
        # Apply full v0.7 stack first
        bash "$(dirname "$0")/../tao-os-presets-v0.7.sh" --apply-temp

        # Then add this candidate tweak on top
        echo 262144 | sudo -S tee /proc/sys/vm/min_free_kbytes > /dev/null
        echo "✓ vm.min_free_kbytes: 262144 (was $ORIG_VAL)"
        ;;
    --undo)
        bash "$(dirname "$0")/../tao-os-presets-v0.7.sh" --undo
        echo "$ORIG_VAL" | sudo -S tee /proc/sys/vm/min_free_kbytes > /dev/null
        echo "✓ vm.min_free_kbytes reverted to $ORIG_VAL"
        ;;
    --dry-run)
        echo "[dry-run] Would set vm.min_free_kbytes=262144 (currently $ORIG_VAL)"
        bash "$(dirname "$0")/../tao-os-presets-v0.7.sh" --dry-run
        ;;
    *)
        echo "Usage: $0 [--apply-temp|--undo|--dry-run]"
        exit 1
        ;;
esac
