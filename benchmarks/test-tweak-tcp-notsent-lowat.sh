#!/usr/bin/env bash
# Isolated tweak test: tcp_notsent_lowat=131072
# Tests this single tweak on top of the full v0.7 stack
set -euo pipefail

ACTION="${1:-}"
ORIG_VAL=$(cat /proc/sys/net/ipv4/tcp_notsent_lowat 2>/dev/null || echo "4294967295")

case "$ACTION" in
    --apply-temp)
        bash "$(dirname "$0")/../tao-os-presets-v0.7.sh" --apply-temp
        echo 131072 | sudo tee /proc/sys/net/ipv4/tcp_notsent_lowat > /dev/null
        echo "✓ tcp_notsent_lowat: 131072 (was $ORIG_VAL) — reduces send buffer bloat"
        ;;
    --undo)
        bash "$(dirname "$0")/../tao-os-presets-v0.7.sh" --undo
        echo "$ORIG_VAL" | sudo tee /proc/sys/net/ipv4/tcp_notsent_lowat > /dev/null
        echo "✓ tcp_notsent_lowat reverted to $ORIG_VAL"
        ;;
    --dry-run)
        echo "[dry-run] Would set tcp_notsent_lowat=131072 (currently $ORIG_VAL)"
        bash "$(dirname "$0")/../tao-os-presets-v0.7.sh" --dry-run
        ;;
    *)
        echo "Usage: $0 [--apply-temp|--undo|--dry-run]"; exit 1 ;;
esac
