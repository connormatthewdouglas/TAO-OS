#!/usr/bin/env python3
"""CopperClaw Dashboard Server — TAO-OS Project"""

import http.server
import json
import os
import glob
import re
import signal
import subprocess
import time
import urllib.request
from datetime import datetime
from pathlib import Path

WORKSPACE = Path.home() / "TAO-OS"
PORT = 7420
AUTORUN_STATE_FILE = Path(__file__).parent / "autorun.json"

SUPABASE_URL = "https://iovvktpuoinmjdgfxgvm.supabase.co"
SUPABASE_KEY = "sb_publishable_4WefsfMl0sNNo9O2c_lxnA_q2VQ01jn"

class DashboardHandler(http.server.BaseHTTPRequestHandler):
    def log_message(self, format, *args):
        pass  # suppress access logs

    def do_POST(self):
        if self.path == "/api/approvals/decide":
            length = int(self.headers.get("Content-Length", 0))
            body = json.loads(self.rfile.read(length))
            result = handle_approval(body.get("id"), body.get("decision"))
            self.serve_json(result)
        elif self.path == "/api/autorun":
            length = int(self.headers.get("Content-Length", 0))
            body = json.loads(self.rfile.read(length))
            result = set_autorun(body.get("enabled", False))
            self.serve_json(result)
        else:
            self.send_response(404)
            self.end_headers()

    def do_GET(self):
        if self.path == "/" or self.path == "/index.html":
            self.serve_file("index.html", "text/html")
        elif self.path == "/api/status":
            self.serve_json(get_status())
        elif self.path == "/api/logs":
            self.serve_json(get_logs())
        elif self.path == "/api/memory":
            self.serve_json(get_memory())
        elif self.path == "/api/tasks":
            self.serve_json(get_tasks())
        elif self.path == "/api/comms":
            self.serve_json(get_comms())
        elif self.path == "/api/approvals":
            self.serve_json(get_approvals())
        elif self.path == "/api/benchmark-progress":
            self.serve_json(get_benchmark_progress())
        elif self.path == "/api/benchmarks":
            self.serve_json(get_benchmarks())
        elif self.path == "/api/queue":
            self.serve_json(get_queue())
        elif self.path == "/api/autorun":
            self.serve_json(get_autorun())
        elif self.path == "/api/forge-runs":
            self.serve_json(get_forge_runs())
        elif self.path == "/api/spend":
            self.serve_json(get_spend())
        elif self.path == "/api/autonomy":
            self.serve_json(get_autonomy_score())
        else:
            self.send_response(404)
            self.end_headers()

    def serve_file(self, filename, content_type):
        path = Path(__file__).parent / filename
        try:
            content = path.read_bytes()
            self.send_response(200)
            self.send_header("Content-Type", content_type)
            self.send_header("Content-Length", len(content))
            self.end_headers()
            self.wfile.write(content)
        except FileNotFoundError:
            self.send_response(404)
            self.end_headers()

    def serve_json(self, data):
        content = json.dumps(data, default=str).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Content-Length", len(content))
        self.end_headers()
        self.wfile.write(content)


def get_status():
    """Project status overview"""
    # Latest benchmark result
    logs = sorted(glob.glob(str(WORKSPACE / "logs/tao-os-full-test-*.log")))
    latest_result = None
    if logs:
        try:
            content = Path(logs[-1]).read_text()
            result = {}
            for line in content.splitlines():
                if "Network throughput" in line:
                    m = re.search(r'(\d+\.?\d*)\s*Mbit.*?(\d+\.?\d*)\s*Mbit.*?([+-]\d+\.?\d*%)', line)
                    if m: result["network"] = {"baseline": m.group(1), "tuned": m.group(2), "delta": m.group(3)}
                elif "Cold-start" in line:
                    m = re.search(r'(\d+\.?\d*)ms.*?(\d+\.?\d*)ms.*?([+-]\d+\.?\d*%)', line)
                    if m: result["coldstart"] = {"baseline": m.group(1), "tuned": m.group(2), "delta": m.group(3)}
                elif "Sustained inference" in line:
                    m = re.search(r'(\d+\.?\d*)\s*tok.*?(\d+\.?\d*)\s*tok.*?([+-]?\d+\.?\d*%)', line)
                    if m: result["inference"] = {"baseline": m.group(1), "tuned": m.group(2), "delta": m.group(3)}
                elif "Hardware:" in line:
                    result["hardware_cpu"] = line.replace("Hardware:", "").strip()
                elif "Intel" in line and "Arc" in line:
                    result["hardware_gpu"] = line.strip()
            result["log_time"] = datetime.fromtimestamp(os.path.getmtime(logs[-1])).strftime("%Y-%m-%d %H:%M")
            latest_result = result
        except Exception as e:
            latest_result = {"error": str(e)}

    # Git status
    git_info = {}
    try:
        import subprocess
        r = subprocess.run(["git", "log", "--oneline", "-5"], cwd=WORKSPACE, capture_output=True, text=True)
        git_info["recent_commits"] = r.stdout.strip().splitlines()
        r2 = subprocess.run(["git", "status", "--short"], cwd=WORKSPACE, capture_output=True, text=True)
        git_info["dirty_files"] = len(r2.stdout.strip().splitlines())
    except: pass

    return {
        "project": "TAO-OS",
        "codename": "ForgeOS (private)",
        "phase": "Phase 1 — Self-Fleet Validation",
        "version": {"presets": "v0.7 (25 tweaks)", "wrapper": "v1.3"},
        "blocker": "power_idle_tuned_w null bug (turbostat capture post-C-state disable)",
        "next_action": "Fix power bug → v1.4 schema → fleet runs",
        "latest_benchmark": latest_result,
        "git": git_info,
        "timestamp": datetime.now().isoformat()
    }


def parse_benchmark_log(log_path):
    """Parse a full-test log into a structured dict."""
    text = Path(log_path).read_text()
    result = {"file": Path(log_path).name}

    # Timestamp from filename: tao-os-full-test-YYYYMMDD-HHMMSS.log
    m = re.search(r'(\d{8})-(\d{6})', Path(log_path).name)
    if m:
        dt = datetime.strptime(m.group(1) + m.group(2), "%Y%m%d%H%M%S")
        result["ts"] = dt.isoformat()
        result["label"] = dt.strftime("%m/%d %H:%M")

    for line in text.splitlines():
        mn = re.search(r'Network throughput\s+([\d.]+)\s*Mbit.*?([\d.]+)\s*Mbit.*?([+-]?[\d.]+)%', line)
        if mn:
            result["net_baseline"] = float(mn.group(1))
            result["net_tuned"]    = float(mn.group(2))
            result["net_delta"]    = float(mn.group(3))

        mc = re.search(r'Cold-start latency\s+([\d.]+)ms.*?([\d.]+)ms.*?([+-]?[\d.]+)%', line)
        if mc:
            result["cold_baseline"] = float(mc.group(1))
            result["cold_tuned"]    = float(mc.group(2))
            result["cold_delta"]    = float(mc.group(3))

        mi = re.search(r'Sustained inference\s+([\d.]+)\s*tok.*?([\d.]+)\s*tok.*?([+-]?[\d.]+)%', line)
        if mi:
            result["inf_baseline"] = float(mi.group(1))
            result["inf_tuned"]    = float(mi.group(2))
            result["inf_delta"]    = float(mi.group(3))

        mp = re.search(r'Idle power draw\s+([\d.]+)W\s+([\d.]+)W', line)
        if mp:
            result["power_baseline"] = float(mp.group(1))
            result["power_tuned"]    = float(mp.group(2))
            result["power_delta"]    = round(float(mp.group(2)) - float(mp.group(1)), 2)

        if "Hardware:" in line:
            result["hardware"] = line.replace("Hardware:", "").strip()

        if "Stability" in line:
            result["stable"] = "true" in line.lower()

    result["mtime"] = os.path.getmtime(log_path)
    return result


def get_benchmark_progress():
    """Check if a benchmark is currently running and how far along it is."""
    # run_loop.py captures stdout to heartbeat-run-*.log — that's where progress markers live.
    # tao-os-full-test-*.log only gets the final summary written at the very end.
    logs = sorted(glob.glob(str(WORKSPACE / "logs/heartbeat-run-*.log")))
    if not logs:
        return {"running": False}

    latest = logs[-1]
    age_s  = time.time() - os.path.getmtime(latest)

    # If the log hasn't been touched in 20 minutes, it's not an active run
    if age_s > 1200:
        return {"running": False}

    try:
        text = Path(latest).read_text()
    except:
        return {"running": False}

    lines = text.splitlines()

    # Determine which steps are done / in progress
    net_started  = any("[1/3]" in l or "Network throughput benchmark" in l for l in lines)
    net_done     = any("→ Network done" in l for l in lines)
    cold_started = any("[2/3]" in l for l in lines)
    cold_done    = any("→ Cold-start done" in l for l in lines)
    inf_started  = any("[3/3]" in l for l in lines)
    inf_done     = any("→ Sustained inference done" in l for l in lines)
    finishing    = any("Reading idle power with presets active" in l for l in lines)
    complete     = any("TAO-OS FULL TEST RESULTS" in l for l in lines)

    if complete:
        return {"running": False}

    # Grab the last few iperf3 run lines for live detail
    live_lines = [l.strip() for l in lines if "Run " in l and "Mbit/s" in l][-3:]

    steps = [
        {"label": "🌐 Network Throughput",  "done": net_done,  "active": net_started and not net_done},
        {"label": "⚡ Cold-Start Latency",  "done": cold_done, "active": cold_started and not cold_done},
        {"label": "🧠 Sustained Inference", "done": inf_done,  "active": inf_started and not inf_done},
        {"label": "🔋 Power + Stability",   "done": False,     "active": finishing},
    ]

    done_count = sum(1 for s in steps if s["done"])
    pct = int((done_count / len(steps)) * 100)

    return {
        "running": True,
        "log": Path(latest).name,
        "age_s": int(age_s),
        "pct": pct,
        "steps": steps,
        "live": live_lines,
    }


def get_benchmarks():
    """Return last 25 full-test benchmark logs, newest first."""
    logs = sorted(glob.glob(str(WORKSPACE / "logs/tao-os-full-test-*.log")))[-25:]
    results = []
    for log in logs:
        try:
            results.append(parse_benchmark_log(log))
        except Exception as e:
            results.append({"file": Path(log).name, "error": str(e)})
    results.sort(key=lambda x: x.get("mtime", 0), reverse=True)
    return results


def get_spend():
    """Return today's estimated cloud spend from spend_monitor state file."""
    state = Path(__file__).parent / "spend_state.json"
    try:
        return json.loads(state.read_text())
    except:
        return {"estimated_usd": None, "cap_usd": 2.00, "error": "no data yet"}


def get_forge_runs():
    """Fetch all machines + runs from tao-forge Supabase database."""
    def sb_get(table, params=""):
        url = f"{SUPABASE_URL}/rest/v1/{table}?{params}"
        req = urllib.request.Request(url, headers={
            "apikey": SUPABASE_KEY,
            "Authorization": f"Bearer {SUPABASE_KEY}",
        })
        try:
            with urllib.request.urlopen(req, timeout=8) as r:
                return json.loads(r.read())
        except Exception as e:
            return {"error": str(e)}

    machines = sb_get("machines", "order=created_at.asc")
    runs     = sb_get("runs",     "order=created_at.asc")

    if isinstance(machines, dict) and "error" in machines:
        return {"error": machines["error"], "machines": []}
    if isinstance(runs, dict) and "error" in runs:
        return {"error": runs["error"], "machines": []}

    result = []
    for m in machines:
        m_runs = [r for r in runs if r.get("machine_id") == m.get("machine_id")]
        result.append({
            "machine_id": m.get("machine_id"),
            "cpu":        m.get("cpu"),
            "gpu":        m.get("gpu"),
            "os":         m.get("os"),
            "run_count":  len(m_runs),
            "runs": [{
                "run_date":             r.get("run_date"),
                "preset_version":       r.get("preset_version"),
                "network_baseline":     r.get("network_baseline_mbit"),
                "network_tuned":        r.get("network_tuned_mbit"),
                "network_delta":        r.get("network_delta_pct"),
                "coldstart_baseline":   r.get("coldstart_baseline_ms"),
                "coldstart_tuned":      r.get("coldstart_tuned_ms"),
                "coldstart_delta":      r.get("coldstart_delta_pct"),
                "sustained_baseline":   r.get("sustained_baseline_toks"),
                "sustained_tuned":      r.get("sustained_tuned_toks"),
                "sustained_delta":      r.get("sustained_delta_pct"),
                "power_baseline":       r.get("power_idle_baseline_w"),
                "power_tuned":          r.get("power_idle_tuned_w"),
                "power_delta":          r.get("power_delta_w"),
                "notes":                r.get("notes"),
            } for r in m_runs]
        })

    return {"machines": result, "total_runs": len(runs)}


def get_logs():
    """Recent log file summaries"""
    logs = sorted(glob.glob(str(WORKSPACE / "logs/*.log")))[-20:]
    result = []
    for log in reversed(logs):
        p = Path(log)
        result.append({
            "name": p.name,
            "size": p.stat().st_size,
            "modified": datetime.fromtimestamp(p.stat().st_mtime).strftime("%Y-%m-%d %H:%M"),
            "preview": p.read_text()[:300].replace("\n", " | ")
        })
    return result


def get_memory():
    """CopperClaw memory files"""
    files = {}

    # Today's daily note
    today = datetime.now().strftime("%Y-%m-%d")
    daily = WORKSPACE / f"memory/{today}.md"
    if daily.exists():
        files["today"] = daily.read_text()

    # MEMORY.md — Copper's single memory file
    mem = WORKSPACE / "MEMORY.md"
    if mem.exists():
        files["longterm"] = mem.read_text()

    return files


def get_tasks():
    """Extract TODO items from key files"""
    todos = []
    files_to_check = [
        WORKSPACE / "docs/action-plan.md",
        WORKSPACE / "memory" / f"{datetime.now().strftime('%Y-%m-%d')}.md",
    ]
    for f in files_to_check:
        if f.exists():
            for line in f.read_text().splitlines():
                if line.strip().startswith("- [ ]"):
                    todos.append({
                        "done": False,
                        "text": line.strip()[5:].strip(),
                        "source": f.name
                    })
                elif line.strip().startswith("- [x]"):
                    todos.append({
                        "done": True,
                        "text": line.strip()[5:].strip(),
                        "source": f.name
                    })
    return todos


def get_autonomy_score():
    """Calculate Copper's autonomy score from work_queue.json"""
    AUTONOMOUS = {"passed", "committed", "dropped"}
    REVIEWED   = {"flagged", "awaiting_approval", "rejected"}
    try:
        items = json.loads((Path(__file__).parent / "work_queue.json").read_text())
    except:
        return {"score": None, "error": "no data"}

    autonomous = sum(1 for i in items if i.get("status") in AUTONOMOUS)
    reviewed   = sum(1 for i in items if i.get("status") in REVIEWED)
    total      = autonomous + reviewed
    score      = round((autonomous / total * 100), 1) if total else None

    breakdown = {}
    for i in items:
        s = i.get("status", "unknown")
        breakdown[s] = breakdown.get(s, 0) + 1

    return {
        "score":      score,
        "autonomous": autonomous,
        "reviewed":   reviewed,
        "total":      total,
        "breakdown":  breakdown,
        "label":      f"{score}%" if score is not None else "N/A",
    }


def get_queue():
    f = Path(__file__).parent / "work_queue.json"
    try:
        return json.loads(f.read_text())
    except:
        return []

def get_run_loop_pid():
    """Return PID of running run_loop.py, or None."""
    try:
        state = json.loads(AUTORUN_STATE_FILE.read_text())
        pid = state.get("pid")
        if pid and Path(f"/proc/{pid}").exists():
            return pid
    except:
        pass
    return None

def get_autorun():
    """Get current autorun state"""
    try:
        state = json.loads(AUTORUN_STATE_FILE.read_text())
        # Sync enabled flag with whether the process is actually running
        state["running"] = get_run_loop_pid() is not None
        return state
    except:
        return {"enabled": False, "running": False, "updated_at": None}

def set_autorun(enabled):
    """Set autorun state, start or stop run_loop.py accordingly."""
    try:
        pid = get_run_loop_pid()

        if enabled and pid is None:
            # Start run_loop.py in the background
            run_loop = Path(__file__).parent.parent / "dashboard" / "run_loop.py"
            proc = subprocess.Popen(
                ["python3", str(run_loop)],
                cwd=str(Path(__file__).parent.parent),
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                start_new_session=True
            )
            new_pid = proc.pid
            msg = f"🟢 Autorun ENABLED — run_loop.py started (PID {new_pid})"
        elif not enabled and pid is not None:
            # Stop the running process
            try:
                os.kill(pid, signal.SIGTERM)
            except ProcessLookupError:
                pass
            new_pid = None
            msg = f"🔴 Autorun DISABLED — run_loop.py stopped (was PID {pid})"
        else:
            new_pid = pid
            msg = f"Autorun already {'running' if enabled else 'stopped'} — no change"

        state = {
            "enabled": enabled,
            "pid": new_pid,
            "updated_at": datetime.now().isoformat()
        }
        AUTORUN_STATE_FILE.write_text(json.dumps(state, indent=2))
        log_comms("Connor", "CopperClaw", "directive", msg)

        return {"ok": True, "enabled": enabled, "pid": new_pid}
    except Exception as e:
        return {"ok": False, "error": str(e)}

def get_approvals():
    """Read pending tweak approvals"""
    f = Path(__file__).parent / "approvals.json"
    try:
        return json.loads(f.read_text())
    except:
        return []

def handle_approval(approval_id, decision):
    """Approve or reject a tweak"""
    f = Path(__file__).parent / "approvals.json"
    try:
        approvals = json.loads(f.read_text())
    except:
        approvals = []

    for a in approvals:
        if a["id"] == approval_id:
            a["status"] = decision  # "approved" or "rejected"
            a["decided_at"] = datetime.now().isoformat()
            break

    f.write_text(json.dumps(approvals, indent=2))

    # Log to comms feed
    tweak = next((a for a in approvals if a["id"] == approval_id), {})
    log_comms("Connor", "CopperClaw", "directive",
        f"Tweak '{tweak.get('tweak_name', approval_id)}' {decision.upper()}. {'Queuing commit.' if decision == 'approved' else 'Archiving.'}")

    return {"ok": True, "id": approval_id, "status": decision}


def get_comms():
    """Read comms log — conversation between CopperClaw, Claude, and other agents"""
    comms_file = Path(__file__).parent / "comms.jsonl"
    entries = []
    if comms_file.exists():
        for line in comms_file.read_text().strip().splitlines():
            line = line.strip()
            if line:
                try:
                    entries.append(json.loads(line))
                except:
                    pass
    # Return newest first, last 100
    return list(reversed(entries[-100:]))


def log_comms(from_agent, to_agent, msg_type, message):
    """Utility to append a comms entry (called externally via CLI)"""
    comms_file = Path(__file__).parent / "comms.jsonl"
    entry = {
        "ts": datetime.now().isoformat(),
        "from": from_agent,
        "to": to_agent,
        "type": msg_type,
        "msg": message
    }
    with open(comms_file, "a") as f:
        f.write(json.dumps(entry) + "\n")


if __name__ == "__main__":
    print(f"CopperClaw Dashboard running at http://0.0.0.0:{PORT}")
    server = http.server.HTTPServer(("0.0.0.0", PORT), DashboardHandler)
    server.serve_forever()
