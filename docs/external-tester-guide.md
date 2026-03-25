# CursiveOS — What It Does To Your System

**For anyone running a test on behalf of the CursiveOS project.**

---

## The short version

CursiveOS runs a set of performance tweaks on your Linux machine, measures whether they help, and uploads the results. **Every change it makes is temporary.** Nothing is permanent. If you reboot, your machine is back to exactly how it was.

---

## What it actually changes

CursiveOS adjusts settings in three areas. All of these are standard Linux tuning knobs — nothing obscure, nothing dangerous.

### Network (the big one)
Your Linux machine ships with a 212KB network buffer. That's a 2003-era default. CursiveOS bumps it to 16MB and switches your TCP congestion control from CUBIC to BBR. On most hardware this produces a 400–600% improvement in sustained network throughput under real-world conditions (packet loss, latency). This is why miners and AI users both benefit — both workloads are bottlenecked by the same default.

### CPU
CursiveOS sets your CPU governor to "performance" mode and disables some aggressive idle states (C2, C3, C6). This keeps your CPU ready to respond instead of sleeping between requests. The tradeoff: your idle power draw goes up by roughly 8–14W depending on your hardware. For a machine that's running 24/7 at $0.12/kWh, that's about $8–15/year extra. The benchmark measures this and reports it honestly.

### Memory
CursiveOS sets swappiness to 0 (never swap) and enables Transparent Huge Pages. This keeps model weights pinned in RAM and reduces memory allocation overhead during inference. On machines with plenty of RAM this is free performance. On machines with tight RAM it could cause issues — the benchmark will catch this.

---

## What it does NOT change

- Nothing permanent. No config files, no boot parameters, no package installs.
- No changes to your mining software, Ollama, or any application.
- No network configuration beyond the kernel TCP stack.
- No firewall rules, no open ports, no remote access of any kind.
- Intel Arc GPU frequency tweaks only apply if you have an Intel Arc GPU. NVIDIA and AMD GPU settings are untouched.

---

## How to run it

One command, copy-paste from the GitHub README:

```bash
git clone https://github.com/connormatthewdouglas/CursiveOS.git 2>/dev/null; git -C ~/CursiveOS pull --ff-only 2>/dev/null || echo "⚠ Local changes detected — skipping update, running your local version."; chmod +x ~/CursiveOS/cursiveos-full-test-v1.4.sh; cd ~/CursiveOS && bash cursiveos-full-test-v1.4.sh
```

It will:
1. Ask for your sudo password (needed to change kernel settings)
2. Run a baseline benchmark (~3 minutes)
3. Apply the tweaks
4. Run the same benchmark again (~3 minutes)
5. Revert everything
6. Show you the results and upload them automatically

Total time: about 10 minutes.

---

## How to undo manually (if you ever need to)

The wrapper reverts everything automatically when it finishes. If something goes wrong mid-run, just **reboot** — all changes are in-memory only and disappear on restart.

If you want to manually revert without rebooting:
```bash
cd ~/CursiveOS && bash tao-os-presets-v0.8.sh --undo
```

---

## What gets uploaded

Your benchmark results go to the CursiveOS hardware database (CursiveRoot). This includes:
- Your CPU model and core count
- Your GPU model
- Your kernel version and OS name
- Benchmark deltas (network %, cold-start ms, inference tok/s, power W)
- A hardware fingerprint hash (one-way hash of CPU microcode + GPU VBIOS + kernel — cannot be reversed to identify you)

Nothing else. No IP addresses, no usernames, no file system data.

---

## Questions or problems

Open an issue on GitHub or message the project directly. If something looks wrong with your results, the raw logs are saved in `~/CursiveOS/logs/` — share those and we can diagnose.
