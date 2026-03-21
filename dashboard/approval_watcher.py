#!/usr/bin/env python3
"""
CopperClaw — Approval Watcher
Watches approvals.json for newly-approved tweaks and auto-commits them to git.
Runs as a background service alongside the dashboard server.
"""
import json, subprocess, time, sys
from datetime import datetime
from pathlib import Path

WORKSPACE = Path.home() / "TAO-OS"
APPROVALS_FILE = Path(__file__).parent / "approvals.json"
COMMS_FILE = Path(__file__).parent / "comms.jsonl"
PROCESSED_FILE = Path(__file__).parent / "processed_approvals.json"

def log_comms(from_agent, to_agent, msg_type, message):
    entry = {
        "ts": datetime.now().isoformat(),
        "from": from_agent,
        "to": to_agent,
        "type": msg_type,
        "msg": message
    }
    with open(COMMS_FILE, "a") as f:
        f.write(json.dumps(entry) + "\n")

def get_processed():
    try:
        return set(json.loads(PROCESSED_FILE.read_text()))
    except:
        return set()

def mark_processed(approval_id):
    processed = get_processed()
    processed.add(approval_id)
    PROCESSED_FILE.write_text(json.dumps(list(processed)))

def git_commit(tweak_name, description, target_version):
    """Commit the approved tweak to git"""
    try:
        # Stage relevant files
        subprocess.run(
            ["git", "add",
             "tao-os-presets-v0.7.sh",  # or whatever version is current
             f"tao-os-full-test-v1.4.sh",
             "docs/action-plan.md",
             "docs/white-paper.md",
             "CHANGELOG.md",
            ],
            cwd=WORKSPACE, capture_output=True
        )
        # Commit
        msg = f"Add approved tweak: {tweak_name} (targeting v{target_version})\n\n{description}\n\nApproved by founder via dashboard."
        r = subprocess.run(
            ["git", "commit", "-m", msg],
            cwd=WORKSPACE, capture_output=True, text=True
        )
        if r.returncode == 0:
            return True, r.stdout.strip()
        else:
            # Nothing staged or already committed
            return False, r.stderr.strip()
    except Exception as e:
        return False, str(e)

def process_approval(approval):
    """
    Approval just means the tweak is QUEUED — not committed.
    CopperClaw must run an integration test against the full stack
    and confirm it passes before committing anything to git.
    """
    aid = approval["id"]
    name = approval["tweak_name"]
    version = approval.get("target_version", "0.8")

    log_comms("CopperClaw", "Connor", "result",
        f"'{name}' approved and queued for integration test. "
        f"Will add to full preset stack, run clean benchmark, then commit if no regressions.")

    log_comms("CopperClaw", "Vega", "action",
        f"Integration test needed: add '{name}' to preset stack and run full benchmark. "
        f"Commit only if all deltas hold vs previous baseline.")

    # Write a pending integration test marker
    pending_file = Path(__file__).parent / "pending_integration.json"
    try:
        pending = json.loads(pending_file.read_text()) if pending_file.exists() else []
    except:
        pending = []

    pending.append({
        "approval_id": aid,
        "tweak_name": name,
        "target_version": version,
        "description": approval["description"],
        "queued_at": datetime.now().isoformat(),
        "status": "awaiting_integration_test"
    })
    pending_file.write_text(json.dumps(pending, indent=2))

    mark_processed(aid)

def process_rejection(approval):
    aid = approval["id"]
    name = approval["tweak_name"]
    log_comms("CopperClaw", "Research", "info",
        f"'{name}' rejected by founder. Archiving — will not add to preset stack.")
    mark_processed(aid)

SENTINEL_FILE = Path(__file__).parent / "run_complete.json"
QUEUE_FILE = Path(__file__).parent / "work_queue.json"
LAST_SENTINEL_TIME = [None]  # mutable container for closure

def get_queue():
    try:
        return json.loads(QUEUE_FILE.read_text())
    except:
        return []

def save_queue(q):
    QUEUE_FILE.write_text(json.dumps(q, indent=2))

def handle_run_complete():
    """Called when a benchmark sentinel file appears — update work queue."""
    try:
        result = json.loads(SENTINEL_FILE.read_text())
        completed_at = result.get("completed_at", "")

        # Skip if we already processed this sentinel
        if LAST_SENTINEL_TIME[0] == completed_at:
            return
        LAST_SENTINEL_TIME[0] = completed_at

        power_tuned = result.get("power_tuned", "N/A")
        net_delta = result.get("network_delta", "?")
        cold_delta = result.get("coldstart_delta", "?")
        stability = result.get("stability", "unknown")

        # Determine if power bug is fixed
        power_fixed = power_tuned not in ("N/A", "", None) and power_tuned != "N/AW"

        queue = get_queue()
        for item in queue:
            if item["status"] == "in_progress":
                item["runs_used"] = item.get("runs_used", 0) + 1
                if item["type"] == "bug_fix" and "Power" in item["title"]:
                    if power_fixed:
                        item["status"] = "passed"
                        item["result"] = f"✅ Power reading fixed: {power_tuned}W tuned. Network: {net_delta}%, Cold-start: {cold_delta}%"
                        log_comms("CopperClaw", "Connor", "result",
                            f"Power bug FIXED. Tuned reading: {power_tuned}W. Queuing commit + next iteration.")
                    else:
                        item["status"] = "failed"
                        item["result"] = f"❌ Power still N/A. Needs more investigation."
                        log_comms("CopperClaw", "Connor", "error",
                            "Power reading still failing. Will investigate and retry.")
                else:
                    # Generic tweak result
                    item["status"] = "passed" if stability == "true" else "failed"
                    item["result"] = f"Network: {net_delta}%, Cold-start: {cold_delta}%, Power: {power_tuned}W"
                break
        save_queue(queue)
        print(f"[watcher] Processed run_complete: power={'fixed' if power_fixed else 'still broken'}")

    except Exception as e:
        print(f"[watcher] Error handling sentinel: {e}")


def watch():
    print(f"[approval_watcher] Started. Watching {APPROVALS_FILE}")
    log_comms("CopperClaw", "System", "init", "Approval watcher started. Monitoring benchmarks + approvals.")

    while True:
        try:
            # Check for completed benchmark run
            if SENTINEL_FILE.exists():
                handle_run_complete()

            # Check for approval decisions
            if APPROVALS_FILE.exists():
                approvals = json.loads(APPROVALS_FILE.read_text())
                processed = get_processed()

                for a in approvals:
                    if a["id"] in processed:
                        continue
                    if a["status"] == "approved":
                        print(f"[approval_watcher] Processing approval: {a['tweak_name']}")
                        process_approval(a)
                    elif a["status"] == "rejected":
                        print(f"[approval_watcher] Processing rejection: {a['tweak_name']}")
                        process_rejection(a)
        except Exception as e:
            print(f"[approval_watcher] Error: {e}")

        time.sleep(5)

if __name__ == "__main__":
    watch()
