#!/bin/bash
echo "=== TAO-OS Benchmark v0.2 (AMD CPU + Intel GPU) ==="
echo "Stacking safe tweaks for Bittensor mining"
echo ""

# Baseline
echo "BASELINE:"
sensors | grep -E 'Core|Package|temp' | head -n 4 || echo "CPU temps not detected"
sysbench cpu run --threads=$(nproc) --cpu-max-prime=20000 | grep "events per second"
ping -c 3 8.8.8.8 | grep "rtt"

# Apply TAO-OS v0.2 tweaks
echo ""
echo "Applying TAO-OS v0.2 tweaks..."
echo performance | sudo tee /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor > /dev/null
echo 0 | sudo tee /sys/devices/system/cpu/cpu*/cpufreq/energy_performance_bias > /dev/null 2>&1 || echo "Energy bias tweak skipped (some AMD chips)"

# Re-test
echo ""
echo "AFTER TAO-OS v0.2:"
sensors | grep -E 'Core|Package|temp' | head -n 4 || echo "CPU temps not detected"
sysbench cpu run --threads=$(nproc) --cpu-max-prime=20000 | grep "events per second"
ping -c 3 8.8.8.8 | grep "rtt"

echo ""
echo "✅ TAO-OS v0.2 complete!"
echo "Higher events/second + lower ping = more TAO per day."
echo "Reboot to reset all changes."
