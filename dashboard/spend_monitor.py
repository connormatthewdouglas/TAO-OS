#!/usr/bin/env python3
"""
TAO-OS Spend Monitor
Reads actual token counts from OpenClaw cron run files (exact).
Estimates direct-session spend from session file sizes (proxy).
Pauses openclaw-gateway + Telegrams Connor if $2/day cap is hit.

Run via cron every 30 minutes.
"""

import json
import os
import subprocess
import sys
import urllib.request
from datetime import datetime
from pathlib import Path

# ── Config ─────────────────────────────────────────────────────────────────
DAILY_CAP_USD  = 2.00
CRON_RUN_DIR   = Path.home() / ".openclaw/cron/runs"
SESSION_DIR    = Path.home() / ".openclaw/agents/main/sessions"
WORKSPACE      = Path.home() / "TAO-OS"
STATE_FILE     = WORKSPACE / "dashboard/spend_state.json"
LOG_FILE       = WORKSPACE / "logs/spend_monitor.log"

# Pricing per 1M tokens
PRICING = {
    "haiku":  {"in": 0.80, "out": 4.00},
    "sonnet": {"in": 3.00, "out": 15.00},
    "opus":   {"in": 15.0, "out": 75.00},
}

# Telegram
BOT_TOKEN = "8629267826:AAFLdnMtGkWxT2D7AYr_SUO6bRvC8Wl8-xk"
CHAT_ID   = "6626145695"

# ── Helpers ─────────────────────────────────────────────────────────────────

def log(msg):
    ts = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    line = f"[{ts}] {msg}"
    print(line)
    with open(LOG_FILE, "a") as f:
        f.write(line + "\n")


def model_pricing(model_str):
    m = (model_str or "").lower()
    if "haiku" in m:   return PRICING["haiku"]
    if "sonnet" in m:  return PRICING["sonnet"]
    if "opus" in m:    return PRICING["opus"]
    return PRICING["haiku"]  # safe default


def cost_from_tokens(input_tokens, output_tokens, model):
    p = model_pricing(model)
    return (input_tokens * p["in"] + output_tokens * p["out"]) / 1_000_000


# ── Cron runs — exact token counts ─────────────────────────────────────────

def cron_spend_today():
    today = datetime.now().date()
    total_cost = 0.0
    calls = 0
    breakdown = []

    for f in CRON_RUN_DIR.glob("*.jsonl"):
        try:
            for line in f.read_text().splitlines():
                line = line.strip()
                if not line:
                    continue
                e = json.loads(line)
                ts_sec = e.get("ts", 0) / 1000
                if datetime.fromtimestamp(ts_sec).date() != today:
                    continue
                u = e.get("usage", {})
                if not u:
                    continue
                model = e.get("model", "")
                # total_tokens = full context sent; output_tokens = generation
                inp = u.get("total_tokens", 0)
                out = u.get("output_tokens", 0)
                cost = cost_from_tokens(inp, out, model)
                total_cost += cost
                calls += 1
                breakdown.append({
                    "source": "cron",
                    "model":  model.split("/")[-1][:30],
                    "input":  inp,
                    "output": out,
                    "cost":   round(cost, 4),
                    "job":    f.stem[:8],
                })
        except Exception as ex:
            log(f"WARN cron {f.name}: {ex}")

    return total_cost, calls, breakdown


# ── Direct sessions — proxy from file size ─────────────────────────────────
# Cron jobs have their own session files (included in cron_spend_today).
# Direct sessions (heartbeats, user messages) don't log token counts.
# We estimate: 1 KB of session file ≈ 60 tokens at ~$0.048/session for Haiku.

BYTES_PER_TOKEN   = 16   # conservative: JSON overhead + content
HAIKU_INPUT_COST  = PRICING["haiku"]["in"]
HAIKU_OUTPUT_COST = PRICING["haiku"]["out"]
AVG_OUTPUT_RATIO  = 0.10  # ~10% of tokens are output

def session_spend_today():
    today = datetime.now().date()

    # Collect session IDs already counted via cron runs
    cron_session_ids = set()
    for f in CRON_RUN_DIR.glob("*.jsonl"):
        try:
            for line in f.read_text().splitlines():
                e = json.loads(line)
                sid = e.get("sessionId") or e.get("sessionKey", "")
                if sid:
                    cron_session_ids.add(sid.split(":")[-1])
        except:
            pass

    total_cost = 0.0
    sessions = 0
    for f in SESSION_DIR.glob("*.jsonl"):
        try:
            mtime = datetime.fromtimestamp(f.stat().st_mtime).date()
            if mtime != today:
                continue
            # Skip if this session was spawned by a cron job
            if f.stem in cron_session_ids:
                continue
            size_bytes = f.stat().st_size
            total_tokens = size_bytes / BYTES_PER_TOKEN
            out_tokens = total_tokens * AVG_OUTPUT_RATIO
            inp_tokens = total_tokens - out_tokens
            cost = cost_from_tokens(inp_tokens, out_tokens, "haiku")
            total_cost += cost
            sessions += 1
        except:
            pass

    return total_cost, sessions


# ── Main estimate ───────────────────────────────────────────────────────────

def estimate_today_spend():
    cron_cost, cron_calls, breakdown = cron_spend_today()
    sess_cost, sess_count = session_spend_today()
    total = cron_cost + sess_cost

    return {
        "date":            str(datetime.now().date()),
        "estimated_usd":   round(total, 4),
        "cap_usd":         DAILY_CAP_USD,
        "pct_of_cap":      round((total / DAILY_CAP_USD) * 100, 1),
        "cron_usd":        round(cron_cost, 4),
        "session_usd":     round(sess_cost, 4),
        "cron_calls":      cron_calls,
        "direct_sessions": sess_count,
        "breakdown":       breakdown,
        "checked_at":      datetime.now().isoformat(),
        "note":            "cron=exact tokens; sessions=size estimate",
    }


def gateway_running():
    r = subprocess.run(
        ["systemctl", "--user", "is-active", "openclaw-gateway.service"],
        capture_output=True, text=True
    )
    return r.stdout.strip() == "active"


def pause_gateway():
    subprocess.run(["systemctl", "--user", "stop", "openclaw-gateway.service"])
    log("PAUSED openclaw-gateway.service — daily cap hit.")


def telegram_alert(msg):
    try:
        url = f"https://api.telegram.org/bot{BOT_TOKEN}/sendMessage"
        payload = json.dumps({
            "chat_id": CHAT_ID,
            "text": msg,
            "parse_mode": "Markdown"
        }).encode()
        req = urllib.request.Request(
            url, data=payload,
            headers={"Content-Type": "application/json"}
        )
        urllib.request.urlopen(req, timeout=10)
    except Exception as ex:
        log(f"Telegram alert failed: {ex}")


def log_comms(message):
    comms = WORKSPACE / "dashboard/comms.jsonl"
    entry = {
        "ts":   datetime.now().isoformat(),
        "from": "SpendMonitor",
        "to":   "Connor",
        "type": "alert",
        "msg":  message,
    }
    with open(comms, "a") as f:
        f.write(json.dumps(entry) + "\n")


def save_state(data):
    STATE_FILE.write_text(json.dumps(data, indent=2))


# ── Entry point ─────────────────────────────────────────────────────────────

def main():
    est = estimate_today_spend()
    save_state(est)

    log(f"Spend: ${est['estimated_usd']:.4f} / ${DAILY_CAP_USD:.2f} "
        f"({est['pct_of_cap']}%) — "
        f"cron=${est['cron_usd']:.4f} ({est['cron_calls']} calls) + "
        f"sessions=${est['session_usd']:.4f} ({est['direct_sessions']} sessions)")

    if est["estimated_usd"] >= DAILY_CAP_USD:
        msg = (
            f"🚨 *TAO-OS Spend Cap Hit*\n\n"
            f"Estimated daily cloud spend: *${est['estimated_usd']:.3f}*\n"
            f"Cap: ${DAILY_CAP_USD:.2f}\n"
            f"Cron jobs: ${est['cron_usd']:.3f} ({est['cron_calls']} calls)\n"
            f"Sessions: ${est['session_usd']:.3f}\n\n"
            f"Copper has been *paused*.\n"
            f"Restart: `systemctl --user start openclaw-gateway.service`"
        )
        if gateway_running():
            pause_gateway()
        telegram_alert(msg)
        log_comms(f"SPEND CAP HIT — ${est['estimated_usd']:.3f} >= ${DAILY_CAP_USD:.2f}. Gateway paused.")
        sys.exit(0)

    if est["pct_of_cap"] >= 80:
        msg = (
            f"⚠️ *TAO-OS Spend Warning*\n\n"
            f"At *{est['pct_of_cap']}%* of daily cap.\n"
            f"Estimated: ${est['estimated_usd']:.3f} / ${DAILY_CAP_USD:.2f}\n"
            f"Cron jobs: ${est['cron_usd']:.3f} ({est['cron_calls']} calls)\n"
            f"Largest jobs today:\n"
            + "\n".join(
                f"  • {b['model'][:20]}: ${b['cost']:.4f}"
                for b in sorted(est['breakdown'], key=lambda x: x['cost'], reverse=True)[:3]
            )
        )
        telegram_alert(msg)
        log_comms(f"SPEND WARNING — {est['pct_of_cap']}% of cap (${est['estimated_usd']:.3f})")


if __name__ == "__main__":
    main()
