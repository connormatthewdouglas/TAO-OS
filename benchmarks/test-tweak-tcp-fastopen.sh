#!/usr/bin/env bash
# Isolated tweak test: tcp_fastopen=3
# Tests this single tweak on top of the full v0.7 stack
set -euo pipefail

ACTION="${1:-}"
ORIG_VAL=$(cat /proc/sys/net/ipv4/tcp_fastopen 2>/dev/null || echo "1")

case "$ACTION" in
    --apply-temp)
        bash "$(dirname "$0")/../presets/cursiveos-presets-v0.7.sh" --apply-temp
        echo 3 | sudo tee /proc/sys/net/ipv4/tcp_fastopen > /dev/null
        echo "✓ tcp_fastopen: 3 (was $ORIG_VAL) — client+server TFO enabled"
        ;;
    --undo)
        bash "$(dirname "$0")/../presets/cursiveos-presets-v0.7.sh" --undo
        echo "$ORIG_VAL" | sudo tee /proc/sys/net/ipv4/tcp_fastopen > /dev/null
        echo "✓ tcp_fastopen reverted to $ORIG_VAL"
        ;;
    --dry-run)
        echo "[dry-run] Would set tcp_fastopen=3 (currently $ORIG_VAL)"
        bash "$(dirname "$0")/../presets/cursiveos-presets-v0.7.sh" --dry-run
        ;;
    *)
        echo "Usage: $0 [--apply-temp|--undo|--dry-run]"; exit 1 ;;
esac
