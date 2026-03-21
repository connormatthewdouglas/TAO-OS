#!/usr/bin/env python3
"""
CopperClaw comms logger — append an entry to the dashboard comms feed.
Usage: python3 log_comms.py <from> <to> <type> <message>
Types: directive, action, result, error, info, init
"""
import sys, json
from datetime import datetime
from pathlib import Path

COMMS_FILE = Path(__file__).parent / "comms.jsonl"

def log(from_agent, to_agent, msg_type, message):
    entry = {
        "ts": datetime.now().isoformat(),
        "from": from_agent,
        "to": to_agent,
        "type": msg_type,
        "msg": message
    }
    with open(COMMS_FILE, "a") as f:
        f.write(json.dumps(entry) + "\n")
    print(f"[comms] {from_agent} → {to_agent} ({msg_type}): {message[:60]}...")

if __name__ == "__main__":
    if len(sys.argv) < 5:
        print("Usage: log_comms.py <from> <to> <type> <message>")
        sys.exit(1)
    log(sys.argv[1], sys.argv[2], sys.argv[3], " ".join(sys.argv[4:]))
