# Power and performance benchmark protocol

The goal is to measure the candidate against a stock Ubuntu kernel, not to
produce an attractive single-run number.

## Control variables

Hold constant across kernels:

- display brightness, refresh rate, and external displays;
- Wi-Fi, Bluetooth, USB, and other peripherals;
- charge range and battery health;
- KDE/power-profiles-daemon or PowerDevil ownership;
- background services, browser tabs, terminal workload, and network activity;
- room temperature where practical;
- kernel command-line parameters other than the kernel identity.

Reboot between kernels. Record kernel release, firmware versions, microcode,
power profile, battery percentage, and whether AC is connected.

## Idle capture

Run the same duration on each kernel, preferably after a warm-up period:

```bash
sudo turbostat --quiet --interval 1 --num_iterations 60
cat /sys/devices/system/cpu/cpuidle/current_driver
cat /sys/devices/system/cpu/cpuidle/current_governor
cat /sys/devices/system/cpu/intel_pstate/status
grep . /sys/devices/system/cpu/cpu*/cpuidle/state*/{name,usage,time} 2>/dev/null
cat /proc/interrupts
cat /proc/stat
```

Record package power, package C-state residency, CPU C-state residency,
wakeups/interrupts per second, average frequency, utilization, and discharge
rate. Package C10 reachability is a hardware/runtime result, not a Kconfig
claim.

## Workload captures

Use at least three repeated classes:

1. idle display-on;
2. light terminal/SSH/editor/browser activity;
3. a fixed CPU workload with completion time and energy recorded.

For each class report mean, standard deviation or range, and the number of
runs. Treat differences inside normal run-to-run noise as inconclusive.

## Suspend/resume

Record `/sys/power/mem_sleep`, suspend mode, wake reason, resume errors, and
post-resume Wi-Fi, NVMe, audio, graphics, TPM, and USB state. Do not force S3
when firmware advertises s2idle only. Suspend testing is a live hardware test
and must not be hidden inside a build script.

## Attribution

Separate effects from kernel configuration, firmware, userspace power policy,
device firmware, background services, and measurement noise. A kernel change
may affect whether a device can reach runtime suspend, but a userspace policy
change must not be reported as a Kconfig improvement.
