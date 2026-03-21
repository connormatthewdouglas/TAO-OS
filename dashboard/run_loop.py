#!/usr/bin/env python3
"""
CopperClaw Benchmark Orchestrator — run_loop.py
Runs through work_queue.json sequentially, respects run budget,
parses results, updates queue, submits approvals, logs to comms.

Usage: python3 run_loop.py
       TAO_SUDO_PASS=xxxx python3 run_loop.py
"""
import json, subprocess, os, re, sys, time
from datetime import datetime
from pathlib import Path

BASE = Path(__file__).parent.parent
QUEUE_FILE = BASE / "dashboard/work_queue.json"
COMMS_FILE = BASE / "dashboard/comms.jsonl"
LOG_DIR = BASE / "logs"
SCRIPT = str(BASE / "tao-os-full-test-v1.4.sh")

MAX_RUNS_TOTAL = 12
NO_RUN_START_HOUR = 4   # EDT
NO_RUN_END_HOUR = 8     # EDT

def log_comms(msg_type, message):
    entry = {
        "ts": datetime.now().isoformat(),
        "from": "CopperClaw",
        "to": "Connor",
        "type": msg_type,
        "msg": message
    }
    with open(COMMS_FILE, "a") as f:
        f.write(json.dumps(entry) + "\n")
    print(f"[comms] {msg_type}: {message}")

def load_queue():
    return json.loads(QUEUE_FILE.read_text())

def save_queue(q):
    QUEUE_FILE.write_text(json.dumps(q, indent=2))

def total_runs_used(q):
    return sum(item.get("runs_used", 0) for item in q)

def is_quiet_hours():
    h = datetime.now().hour
    return NO_RUN_START_HOUR <= h < NO_RUN_END_HOUR

def parse_log(log_path):
    """Extract key metrics from a test log."""
    text = Path(log_path).read_text()
    results = {}

    # Network throughput
    m = re.search(r'Network throughput\s+([\d.]+)\s+Mbit/s\s+([\d.]+)\s+Mbit/s\s+([+-][\d.]+)%', text)
    if m:
        results["net_baseline"] = float(m.group(1))
        results["net_tuned"] = float(m.group(2))
        results["net_delta"] = float(m.group(3))

    # Cold-start latency
    m = re.search(r'Cold-start latency\s+([\d.]+)ms\s+([\d.]+)ms\s+([+-]?[\d.]+)%', text)
    if m:
        results["cold_baseline"] = float(m.group(1))
        results["cold_tuned"] = float(m.group(2))
        results["cold_delta"] = float(m.group(3))

    # Power
    m = re.search(r'Idle power draw\s+([\d.]+)W\s+([\d.]+)W', text)
    if m:
        results["power_baseline"] = float(m.group(1))
        results["power_tuned"] = float(m.group(2))
        results["power_delta"] = round(float(m.group(2)) - float(m.group(1)), 2)

    # Stability
    results["stable"] = "Stability              true" in text or "stability_flag: true" in text

    return results

def run_benchmark(item, sudo_pass):
    """Run the benchmark script and return parsed results."""
    ts = int(time.time())
    log_path = LOG_DIR / f"heartbeat-run-{ts}.log"
    LOG_DIR.mkdir(exist_ok=True)

    env = os.environ.copy()
    env["TAO_SUDO_PASS"] = sudo_pass

    print(f"\n[run_loop] Starting benchmark for: {item['title']}")
    print(f"[run_loop] Log: {log_path}")
    log_comms("action", f"Starting benchmark run: {item['title']}")

    result = subprocess.run(
        ["bash", SCRIPT],
        env=env,
        cwd=str(BASE),
        stdout=open(log_path, "w"),
        stderr=subprocess.STDOUT
    )

    if result.returncode != 0:
        log_comms("error", f"Benchmark script exited with code {result.returncode} for: {item['title']}")
        return None, str(log_path)

    return parse_log(log_path), str(log_path)

def submit_approval(item, metrics):
    """Submit a tweak to the approval panel."""
    cmd = [
        "python3", str(BASE / "dashboard/submit_approval.py"),
        "--name", item["title"],
        "--desc", item["description"],
        "--net-baseline", str(metrics.get("net_baseline", 0)),
        "--net-tuned", str(metrics.get("net_tuned", 0)),
        "--cold-baseline", str(metrics.get("cold_baseline", 0)),
        "--cold-tuned", str(metrics.get("cold_tuned", 0)),
        "--power-delta", str(metrics.get("power_delta", 0)),
        "--runs", str(item.get("runs_used", 1) + 1),
        "--target-version", "0.8"
    ]
    subprocess.run(cmd, cwd=str(BASE))

def all_prereqs_done(queue):
    """Check if all items before integration_test are passed/awaiting/committed."""
    for item in queue:
        if item["type"] == "integration_test":
            break
        if item["status"] not in ("passed", "awaiting_approval", "committed"):
            return False
    return True

def main():
    sudo_pass = os.environ.get("TAO_SUDO_PASS", "2633")

    log_comms("info", "run_loop.py started — running through work queue")

    while True:
        if is_quiet_hours():
            log_comms("info", f"Quiet hours ({NO_RUN_START_HOUR}–{NO_RUN_END_HOUR} EDT) — stopping loop")
            print("[run_loop] Quiet hours. Stopping.")
            break

        queue = load_queue()
        used = total_runs_used(queue)

        if used >= MAX_RUNS_TOTAL:
            log_comms("info", f"Run budget exhausted ({used}/{MAX_RUNS_TOTAL}). Done for tonight.")
            print(f"[run_loop] Budget exhausted: {used}/{MAX_RUNS_TOTAL} runs used.")
            break

        # Find next item to process
        next_item = None
        next_idx = None
        for i, item in enumerate(queue):
            if item["type"] == "integration_test":
                if item["status"] == "queued" and all_prereqs_done(queue):
                    next_item = item
                    next_idx = i
                    break
            elif item["status"] == "queued":
                next_item = item
                next_idx = i
                break

        if next_item is None:
            log_comms("info", "All queue items processed or waiting on prereqs. Done.")
            print("[run_loop] Queue complete.")
            break

        # Mark in_progress
        queue[next_idx]["status"] = "in_progress"
        queue[next_idx]["updated_at"] = datetime.now().isoformat()
        save_queue(queue)

        # Run benchmark
        metrics, log_path = run_benchmark(next_item, sudo_pass)

        # Reload queue (may have been updated)
        queue = load_queue()

        if metrics is None:
            queue[next_idx]["status"] = "failed"
            queue[next_idx]["result"] = f"❌ Benchmark script failed. Check {log_path}"
            queue[next_idx]["runs_used"] = queue[next_idx].get("runs_used", 0) + 1
            queue[next_idx]["updated_at"] = datetime.now().isoformat()
            save_queue(queue)
            log_comms("error", f"Run failed for {next_item['title']} — stopping loop")
            break

        # Increment runs
        queue[next_idx]["runs_used"] = queue[next_idx].get("runs_used", 0) + 1
        queue[next_idx]["updated_at"] = datetime.now().isoformat()

        net_d = metrics.get("net_delta", 0)
        cold_d = metrics.get("cold_delta", 0)
        power_t = metrics.get("power_tuned", 0)
        stable = metrics.get("stable", False)

        item_type = next_item["type"]
        runs_used_now = queue[next_idx]["runs_used"]
        runs_budget = next_item.get("runs_budget", 2)

        if item_type == "bug_fix":
            if power_t and power_t > 0:
                queue[next_idx]["status"] = "passed"
                queue[next_idx]["result"] = f"✅ Power reading fixed: {power_t}W tuned. Network: {net_d:+.2f}%, Cold-start: {cold_d:+.2f}%"
                log_comms("result", queue[next_idx]["result"])
            else:
                queue[next_idx]["status"] = "failed"
                queue[next_idx]["result"] = f"❌ Power still N/A after fix attempt"
                log_comms("error", queue[next_idx]["result"])

        elif item_type == "tweak_candidate":
            result_str = f"Network: {net_d:+.2f}%, Cold-start: {cold_d:+.2f}%, Power: {power_t}W"

            # Check for regression
            if net_d < -1.0 or cold_d > 1.0:
                queue[next_idx]["status"] = "failed"
                queue[next_idx]["result"] = f"❌ Regression detected — {result_str}"
                log_comms("error", queue[next_idx]["result"])
            elif runs_used_now >= runs_budget:
                # Enough runs — submit for approval
                queue[next_idx]["status"] = "awaiting_approval"
                queue[next_idx]["result"] = result_str
                submit_approval(next_item, metrics)
                log_comms("result", f"Ready for approval: {next_item['title']} — {result_str}")
            else:
                # Need another run
                queue[next_idx]["status"] = "queued"
                queue[next_idx]["result"] = f"Run {runs_used_now}/{runs_budget}: {result_str}"
                log_comms("info", f"Run {runs_used_now}/{runs_budget} done for {next_item['title']}: {result_str}")

        elif item_type == "integration_test":
            if stable and net_d >= -0.5:
                queue[next_idx]["status"] = "passed"
                queue[next_idx]["result"] = f"✅ Integration passed — Network: {net_d:+.2f}%, Cold-start: {cold_d:+.2f}%"
                log_comms("result", queue[next_idx]["result"])
                # Notify Connor
                log_comms("directive", "Integration test passed! All v0.8 tweaks validated. Ready to commit.")
            else:
                queue[next_idx]["status"] = "failed"
                queue[next_idx]["result"] = f"❌ Integration regression — {result_str}"
                log_comms("error", queue[next_idx]["result"])

        save_queue(queue)

        # Brief pause between runs
        print(f"[run_loop] Run complete. Sleeping 10s before next...\n")
        time.sleep(10)

    print("[run_loop] Loop finished.")
    log_comms("info", "run_loop.py finished")

if __name__ == "__main__":
    main()
