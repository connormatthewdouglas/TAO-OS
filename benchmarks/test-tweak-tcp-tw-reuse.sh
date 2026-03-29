#!/usr/bin/env bash
# Isolated tweak test: net.ipv4.tcp_tw_reuse=1
# Tests this single tweak on top of the full v0.7 stack
# Usage: ./tao-os-full-test-v1.4.sh benchmarks/test-tweak-tcp-tw-reuse.sh

set -euo pipefail

ACTION="${1:-}"
ORIG_VAL=$(sysctl -n net.ipv4.tcp_tw_reuse 2>/dev/null || echo "2")

case "$ACTION" in
    --apply-temp)
        # Apply full v0.7 stack first
        bash "$(dirname "$0")/../presets/cursiveos-presets-v0.7.sh" --apply-temp

        # Then add this candidate tweak on top
        echo "$TAO_SUDO_PASS" | sudo -S sysctl -w net.ipv4.tcp_tw_reuse=1 > /dev/null
        echo "✓ net.ipv4.tcp_tw_reuse: 1 (was $ORIG_VAL) — TIME_WAIT socket reuse enabled"
        ;;
    --undo)
        bash "$(dirname "$0")/../presets/cursiveos-presets-v0.7.sh" --undo
        echo "$TAO_SUDO_PASS" | sudo -S sysctl -w net.ipv4.tcp_tw_reuse="$ORIG_VAL" > /dev/null
        echo "✓ net.ipv4.tcp_tw_reuse reverted to $ORIG_VAL"
        ;;
    --dry-run)
        echo "[dry-run] Would set net.ipv4.tcp_tw_reuse=1 (currently $ORIG_VAL)"
        bash "$(dirname "$0")/../presets/cursiveos-presets-v0.7.sh" --dry-run
        ;;
    *)
        echo "Usage: $0 [--apply-temp|--undo|--dry-run]"
        exit 1
        ;;
esac
