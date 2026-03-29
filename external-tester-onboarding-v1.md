# External Tester Message (Board-Ready v1)

Hi — this is **CursiveOS**, a Linux optimization tool that delivers measurable gains for both crypto miners and local AI/LLM users. Your run helps our self-improving performance flywheel learn what works on real hardware.

**Run this one command:**
```bash
command -v git >/dev/null 2>&1 || { echo "Installing git/curl..."; sudo apt update && sudo apt install -y git curl; }; git clone https://github.com/connormatthewdouglas/CursiveOS.git 2>/dev/null; git -C ~/CursiveOS pull --ff-only 2>/dev/null || echo "⚠ Local changes detected — skipping update, running your local version."; chmod +x ~/CursiveOS/cursiveos-full-test-v1.4.sh; cd ~/CursiveOS && bash cursiveos-full-test-v1.4.sh
```

**What to expect:** ~10–15 minutes total; baseline benchmarks → tuned benchmarks → auto-revert at end. It is safe and fully reversible (script auto-reverts; reboot is optional fallback).

**Success criteria:** You’re done when you see `→ Results submitted to CursiveRoot.` and we can confirm your run in the dashboard.

**Status proof:** Already validated on 3 rigs with positive uplift: Ryzen+Arc, FX+Radeon, and IdeaPad i5+GTX laptop.

More diverse hardware data improves presets for everyone — that’s the moat.

Thanks — your results directly improve CursiveOS for all operators. We’ll follow up only if we need clarification on your logs.
