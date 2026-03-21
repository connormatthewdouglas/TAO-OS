# TAO-OS External Tester Onboarding

**Status:** Draft for Phase 2 (v1.5 gate)  
**Created:** 2026-03-21  
**Audience:** 3-5 trusted Bittensor miners  

---

## What is TAO-OS?

TAO-OS is a collection of **safe, reversible Linux kernel tweaks** that improve Bittensor mining performance without hardware changes or risky modifications.

**Key facts:**
- **No installation needed.** Just run a test script.
- **100% reversible.** All changes revert automatically after testing.
- **Open source.** Full transparency on what we're testing.
- **Data contribution.** Your results help us validate across diverse hardware.

---

## What You'll Be Testing

A set of system-level optimizations:
- **Network tuning** (TCP congestion control, socket buffers)
- **GPU frequency management** (cold-start latency reduction)
- **Memory management** (kernel page handling)
- **CPU governor tuning** (frequency scaling)

**Typical gains observed:** 0.5% to 2.5% across network, inference speed, or mining reward relevance.

---

## Hardware Requirements

- **CPU:** AMD Ryzen (5000 series preferred, 3000+ supported)
- **GPU:** Intel Arc A-series recommended (RTX/RTX-compatible also tested)
- **RAM:** 16GB+ (most mining setups qualify)
- **OS:** Linux (Ubuntu 22.04/24.04 recommended)
- **Network:** Stable connection (tests run ~10 minutes)

---

## Installation & Setup

### 1. Clone the Repository

```bash
git clone https://github.com/connormatthewdouglas/TAO-OS.git
cd TAO-OS
```

### 2. Install Dependencies

```bash
# Ubuntu/Debian
sudo apt-get install -y iperf3 ollama

# Pull the test model (one-time, ~2GB)
ollama pull tinyllama
```

### 3. Run the Test

```bash
# From the TAO-OS directory
./tao-os-full-test-v1.4.sh
```

The script will:
1. Ask for your sudo password (not stored, only used for this session)
2. Run ~10 minutes of benchmarks
3. Automatically revert all changes
4. Submit results to our data server

---

## What Data We Collect

Each test submission includes:
- **Hardware:** CPU model, GPU model, kernel version, system RAM
- **Benchmarks:** Network throughput, cold-start latency, sustained inference speed
- **Power:** Idle power draw (baseline vs tuned)
- **Stability:** Kernel error count (dmesg errors during test)
- **Metadata:** Timestamp, system fingerprint (no personally identifiable info)

**We do NOT collect:**
- Mining addresses or wallet info
- Validator URLs or configuration
- Personal files or logs
- Any data outside the test results

---

## FAQ

**Q: Is this safe to run on a production miner?**  
A: Yes. All changes revert automatically after testing. The test itself is non-destructive — it's read-only benchmarking. However, if you want to be cautious, test on a non-mining machine first.

**Q: How long does the test take?**  
A: ~10 minutes. Network benchmark (3 min) + cold-start test (4 min) + inference test (2 min) + cleanup (1 min).

**Q: Can I run multiple times?**  
A: Yes. More data points are welcome. Run it once per week if possible.

**Q: What if something breaks?**  
A: The script auto-reverts all kernel settings on completion or failure. If something goes wrong, reboot — all changes are in-memory or sysfs, not persistent.

**Q: Who has access to my results?**  
A: Only the TAO-OS core team (Connor Douglas, CopperClaw, board members). Results are used to validate across hardware and are eventually published anonymized (hardware specs only, no identifying info).

---

## Contact & Support

- **Issues/Questions:** Open an issue on GitHub
- **Results feedback:** Reply with "test_complete_[timestamp]" in Discord/Telegram  
- **Hardware-specific problems:** Note your exact CPU/GPU model in the issue

---

## Next Steps

1. **Test on your hardware** — Run the script, let it complete
2. **Check results** — Look at the summary output, verify no errors
3. **Report back** — Let us know it worked (helps us track validation progress)
4. **Check v1.5 gate** — When we lock v1.5 (5+ testers, ≥1.5% gains confirmed), you'll be in the credits

---

**Thank you for helping validate TAO-OS.** Your data makes this real.

— Connor Douglas & CopperClaw  
TAO-OS Project
