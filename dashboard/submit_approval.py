#!/usr/bin/env python3
"""
CopperClaw — submit a tweak for founder approval on the dashboard.
Used at step 7 of the iteration loop after ≥2 validated paired runs.

Usage:
  python3 submit_approval.py \
    --name "vm.min_free_kbytes=262144" \
    --desc "Keeps 256MB memory headroom during model load — prevents kernel reclaiming pages mid-inference" \
    --net-baseline 143.3 --net-tuned 1237.3 \
    --cold-baseline 1020.6 --cold-tuned 1009.7 \
    --power-delta 0.5 \
    --runs 2 \
    --target-version 0.8
"""
import json, argparse, uuid
from datetime import datetime
from pathlib import Path

APPROVALS_FILE = Path(__file__).parent / "approvals.json"
COMMS_FILE = Path(__file__).parent / "comms.jsonl"

def main():
    p = argparse.ArgumentParser()
    p.add_argument("--name", required=True)
    p.add_argument("--desc", required=True)
    p.add_argument("--net-baseline", type=float, required=True)
    p.add_argument("--net-tuned", type=float, required=True)
    p.add_argument("--cold-baseline", type=float, required=True)
    p.add_argument("--cold-tuned", type=float, required=True)
    p.add_argument("--power-delta", type=float, default=0.0)
    p.add_argument("--runs", type=int, default=2)
    p.add_argument("--target-version", default="0.8")
    args = p.parse_args()

    # Calculate deltas
    net_delta = round(((args.net_tuned - args.net_baseline) / args.net_baseline) * 100, 2)
    cold_delta = round(((args.cold_tuned - args.cold_baseline) / args.cold_baseline) * 100, 2)

    # Load existing approvals
    try:
        approvals = json.loads(APPROVALS_FILE.read_text())
    except:
        approvals = []

    entry = {
        "id": str(uuid.uuid4())[:8],
        "tweak_name": args.name,
        "description": args.desc,
        "network_baseline": args.net_baseline,
        "network_tuned": args.net_tuned,
        "network_delta": net_delta,
        "coldstart_baseline": args.cold_baseline,
        "coldstart_tuned": args.cold_tuned,
        "coldstart_delta": cold_delta,
        "power_delta": args.power_delta,
        "runs": args.runs,
        "target_version": args.target_version,
        "status": "pending",
        "submitted_at": datetime.now().isoformat(),
        "decided_at": None
    }

    approvals.append(entry)
    APPROVALS_FILE.write_text(json.dumps(approvals, indent=2))

    # Log to comms feed
    comms_entry = {
        "ts": datetime.now().isoformat(),
        "from": "CopperClaw",
        "to": "Connor",
        "type": "result",
        "msg": f"Tweak ready for approval: '{args.name}' — Network {net_delta:+.1f}%, Cold-start {cold_delta:+.1f}%, Power {args.power_delta:+.1f}W. Check dashboard."
    }
    with open(COMMS_FILE, "a") as f:
        f.write(json.dumps(comms_entry) + "\n")

    print(f"✅ Submitted '{args.name}' for approval (id: {entry['id']})")
    print(f"   Network:    {net_delta:+.1f}%  ({args.net_baseline} → {args.net_tuned} Mbit/s)")
    print(f"   Cold-start: {cold_delta:+.1f}%  ({args.cold_baseline} → {args.cold_tuned} ms)")
    print(f"   Power:      {args.power_delta:+.1f}W")
    print(f"   Connor will see this in the dashboard approval panel.")

if __name__ == "__main__":
    main()
