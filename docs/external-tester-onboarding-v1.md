# CursiveOS External Tester Onboarding Package v1

This package is for both **crypto miners** and **local AI/LLM operators**.

## Single copy-paste command

```bash
command -v git >/dev/null 2>&1 || { echo "Installing git/curl..."; sudo apt update && sudo apt install -y git curl; }; git clone https://github.com/connormatthewdouglas/CursiveOS.git 2>/dev/null; git -C ~/CursiveOS pull --ff-only 2>/dev/null || echo "⚠ Local changes detected — skipping update, running your local version."; chmod +x ~/CursiveOS/cursiveos-full-test-v1.4.sh; cd ~/CursiveOS && bash cursiveos-full-test-v1.4.sh
```

## What this does (10–15 min)

1. Runs baseline benchmarks
2. Applies temporary CursiveOS presets
3. Re-runs the same benchmarks
4. Reverts presets automatically
5. Submits results to CursiveRoot

## Safety + scope

- Temporary changes only (**script automatically reverts presets**)
- Reboot also returns defaults
- No firewall/remote-access changes
- Works for both audiences because bottlenecks are OS-level (network, scheduler/governor, memory behavior)

## Current validation state (three rigs green)

- **Ryzen 7 5700 + Intel Arc A750**
- **FX-8350 + RX 580 (Stardust)**
- **Lenovo IdeaPad Gaming 3 (11th Gen i5 + GTX laptop)**

## If something fails

- Share logs from: `~/CursiveOS/logs/`
- Include the final 30 lines of output
- We will diagnose and patch quickly
