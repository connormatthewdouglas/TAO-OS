#!/usr/bin/env bash
# cursiveroot-status.sh
# Pull and display all run data from the CursiveRoot database.
# Usage: ./cursiveroot-status.sh

SUPABASE_URL="https://iovvktpuoinmjdgfxgvm.supabase.co"
SUPABASE_KEY="sb_publishable_4WefsfMl0sNNo9O2c_lxnA_q2VQ01jn"
H=(-H "apikey: $SUPABASE_KEY" -H "Authorization: Bearer $SUPABASE_KEY")

echo ""
echo "CursiveRoot database status — $(date +%Y-%m-%d)"
echo "======================================================"

python3 - <<PYEOF
import json, subprocess

url = "$SUPABASE_URL"
key = "$SUPABASE_KEY"
headers = ["-H", f"apikey: {key}", "-H", f"Authorization: Bearer {key}"]

def fetch(endpoint):
    r = subprocess.run(["curl", "-s", f"{url}/rest/v1/{endpoint}"] + headers, capture_output=True, text=True)
    return json.loads(r.stdout)

machines = fetch("machines?order=created_at.asc")
runs = fetch("runs?order=created_at.asc")  # oldest first → newest at bottom

print(f"\nMachines in database: {len(machines)}")
print(f"Total runs logged:    {len(runs)}\n")

for m in machines:
    m_runs = [r for r in runs if r["machine_id"] == m["machine_id"]]
    print(f"  ── {m['cpu']} | {m['gpu']}")
    print(f"     ID: {m['machine_id']}")
    print(f"     Runs: {len(m_runs)}")
    print()

    if m_runs:
        # Header
        print(f"     {'#':<4} {'Date':<12} {'Preset':<8} {'Network Δ':>10} {'Cold-start Δ':>13} {'Sustained Δ':>12} {'Power Δ':>9}")
        print(f"     {'-'*4} {'-'*11} {'-'*7} {'-'*10} {'-'*13} {'-'*12} {'-'*9}")
        for i, r in enumerate(m_runs, 1):
            net  = f"+{r['network_delta_pct']:.1f}%"    if r.get("network_delta_pct")   is not None else "N/A"
            cold = f"{r['coldstart_delta_pct']:.2f}%"  if r.get("coldstart_delta_pct") is not None else "N/A"
            warm = f"{r['sustained_delta_pct']:+.2f}%"  if r.get("sustained_delta_pct") is not None else "N/A"
            pwr  = f"{r['power_delta_w']:+.1f}W"        if r.get("power_delta_w")       is not None else "N/A"
            date_s   = r['run_date']     or "N/A"
            preset_s = r['preset_version'] or "N/A"
            print(f"     {i:<4} {date_s:<12} {preset_s:<8} {net:>10} {cold:>13} {warm:>12} {pwr:>9}")
        print(f"     {'':4} {'':12} {'':8} {'':>10} {'':>13} {'':>12} {'↑ newest':>9}")
    print()
PYEOF
