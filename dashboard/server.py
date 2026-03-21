#!/usr/bin/env python3
"""CopperClaw Dashboard Server — TAO-OS Project"""

import http.server
import json
import os
import glob
import re
from datetime import datetime
from pathlib import Path

WORKSPACE = Path.home() / "TAO-OS"
PORT = 7420

class DashboardHandler(http.server.BaseHTTPRequestHandler):
    def log_message(self, format, *args):
        pass  # suppress access logs

    def do_POST(self):
        if self.path == "/api/approvals/decide":
            length = int(self.headers.get("Content-Length", 0))
            body = json.loads(self.rfile.read(length))
            result = handle_approval(body.get("id"), body.get("decision"))
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
        elif self.path == "/api/queue":
            self.serve_json(get_queue())
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
    daily = WORKSPACE / f"memory/copper/{today}.md"
    if daily.exists():
        files["today"] = daily.read_text()

    # MEMORY.md
    mem = WORKSPACE / "MEMORY.md"
    if mem.exists():
        files["longterm"] = mem.read_text()

    return files


def get_tasks():
    """Extract TODO items from key files"""
    todos = []
    files_to_check = [
        WORKSPACE / "docs/action-plan.md",
        WORKSPACE / "memory/copper" / f"{datetime.now().strftime('%Y-%m-%d')}.md",
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


def get_queue():
    f = Path(__file__).parent / "work_queue.json"
    try:
        return json.loads(f.read_text())
    except:
        return []

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
