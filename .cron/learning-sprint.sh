#!/bin/bash
# CopperClaw Learning Sprint — Bi-daily autonomous self-optimization
# Runs every 48 hours at 6:00 AM EDT via cron
# Spawns background session to research, assess, and improve

set -euo pipefail

CYCLE_FILE="/home/connor/TAO-OS/LEARNING_CYCLE.md"
LEARNING_LOG="/home/connor/TAO-OS/LEARNING.md"

if [[ ! -f "$CYCLE_FILE" ]]; then
    echo "Error: LEARNING_CYCLE.md not found"
    exit 1
fi

# Determine which sprint number we're on (mod 4)
SPRINT_NUM=$(wc -l < "$LEARNING_LOG")
SPRINT_INDEX=$(( (SPRINT_NUM % 8) / 2 ))

case $SPRINT_INDEX in
    0) TOPIC="Token Efficiency & Context Management" ;;
    1) TOPIC="Agent Patterns & Industry Frameworks" ;;
    2) TOPIC="Performance Metrics & Speed" ;;
    3) TOPIC="Tool & File Organization" ;;
esac

# Spawn learning session
openclaw sessions spawn \
    --runtime subagent \
    --mode run \
    --model haiku \
    --timeout 600 \
    --task "Learning Sprint: $TOPIC

Research and improve. Steps:
1. Web search for latest patterns in: $TOPIC
2. Read LEARNING_CYCLE.md and LEARNING.md for context
3. Self-assess your recent performance (check memory/YYYY-MM-DD.md recent logs)
4. Identify one actionable improvement
5. Update LEARNING.md with entry:
   - Topic: $TOPIC
   - Finding: [one key insight from research]
   - Action: [what you changed/will change]
   - Commit: 'chore: learning sprint — $TOPIC'
6. Make the change and commit
7. Report: 'Learning sprint complete. Topic: $TOPIC. Finding: [key insight]. Committed.'

Be autonomous. Don't ask permission. Just improve yourself."

echo "Learning sprint spawned: $TOPIC"
