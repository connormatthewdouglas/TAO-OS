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


# ── Direct sessions — exact cost from usage entries ─────────────────────────
# Session JSONL files (and their .bak.* compacted versions) contain exact
# usage data in message.usage.cost.total — use that directly.

def session_spend_today():
    from datetime import timezone
    today = datetime.now(timezone.utc).date()
    total_cost = 0.0
    total_input = 0
    total_output = 0
    calls = 0

    # Read both active .jsonl and compacted .bak.* / .reset.* files
    patterns = ["*.jsonl", "*.jsonl.bak.*", "*.jsonl.reset.*"]
    seen_lines = set()

    for pattern in patterns:
        for f in SESSION_DIR.glob(pattern):
            try:
                for line in f.read_text().splitlines():
                    line = line.strip()
                    if not line or line in seen_lines:
                        continue
                    seen_lines.add(line)
                    e = json.loads(line)
                    if not isinstance(e, dict):
                        continue
                    msg = e.get("message", {})
                    if not isinstance(msg, dict):
                        continue
                    u = msg.get("usage")
                    if not u:
                        continue
                    ts_str = e.get("timestamp", "")
                    if ts_str:
                        try:
                            entry_date = datetime.fromisoformat(
                                ts_str.replace("Z", "+00:00")
                            ).date()
                            if entry_date != today:
                                continue
                        except:
                            continue
                    cost = u.get("cost", {}).get("total", 0)
                    total_cost += cost
                    total_input  += u.get("input", 0) + u.get("cacheRead", 0) + u.get("cacheWrite", 0)
                    total_output += u.get("output", 0)
                    calls += 1
            except:
                pass

    return total_cost, calls, total_input, total_output


# ── Main estimate ───────────────────────────────────────────────────────────

def estimate_today_spend():
    cron_cost, cron_calls, breakdown = cron_spend_today()
    sess_cost, sess_calls, sess_input, sess_output = session_spend_today()
    total = cron_cost + sess_cost

    return {
        "date":          str(datetime.now().date()),
        "estimated_usd": round(total, 4),
        "cap_usd":       DAILY_CAP_USD,
        "pct_of_cap":    round((total / DAILY_CAP_USD) * 100, 1),
        "cron_usd":      round(cron_cost, 4),
        "session_usd":   round(sess_cost, 4),
        "cron_calls":    cron_calls,
        "session_calls": sess_calls,
        "input_tokens":  sess_input,
        "output_tokens": sess_output,
        "breakdown":     breakdown,
        "checked_at":    datetime.now().isoformat(),
        "note":          "exact costs from session usage entries",
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
        f"sessions=${est['session_usd']:.4f} ({est['session_calls']} calls, "
        f"{est['input_tokens']:,}in/{est['output_tokens']:,}out)")

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
