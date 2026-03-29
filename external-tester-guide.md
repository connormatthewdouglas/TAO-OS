# CursiveOS External Tester Guide (Unified)

This file merges onboarding + guide content into one place.

## Quick send message (copy/paste to testers)

Hi — this is **CursiveOS**, a Linux optimization tool that delivers measurable gains for both crypto miners and local AI/LLM users. Your run helps our self-improving performance flywheel learn what works on real hardware.

```bash
command -v git >/dev/null 2>&1 || { echo "Installing git/curl..."; sudo apt update && sudo apt install -y git curl; }; git clone https://github.com/connormatthewdouglas/CursiveOS.git 2>/dev/null; git -C ~/CursiveOS pull --ff-only 2>/dev/null || echo "⚠ Local changes detected — skipping update, running your local version."; chmod +x ~/CursiveOS/cursiveos-full-test-v1.4.sh; cd ~/CursiveOS && bash cursiveos-full-test-v1.4.sh
```

You’re done when you see: `→ Results submitted to CursiveRoot.`

---

## What this run does

1. Runs baseline benchmarks
2. Applies temporary CursiveOS presets
3. Re-runs benchmarks with presets active
4. Automatically reverts presets
5. Submits benchmark metadata to CursiveRoot

Expected runtime: ~10–15 minutes.

## Safety and reversibility

- Temporary changes only
- Script auto-reverts presets at run end
- Reboot is optional fallback (extra reset if desired)
- No firewall / remote-access changes

## What gets uploaded (and why)

Uploaded to CursiveRoot:
- CPU/GPU model
- OS + kernel
- benchmark deltas (network/cold-start/sustained/power)
- one-way hardware fingerprint hash

Not uploaded:
- personal files/docs/photos
- browser history
- shell history
- private app data

Why we collect this:
- to map which optimizations work on which hardware
- to improve preset quality with real-world evidence

## Current validation proof (three rigs green)

- Ryzen 7 5700 + Intel Arc A750
- FX-8350 + RX 580 (Stardust)
- Lenovo IdeaPad Gaming 3 (11th Gen i5 + GTX laptop)

## If something fails

- Share `~/CursiveOS/logs/`
- Include last ~30 lines of terminal output
- We’ll patch quickly

Thanks — tester results directly improve CursiveOS **and Linux** for all operators.
