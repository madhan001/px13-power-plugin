# px13-power-plugin

Linux power management for the **ASUS ProArt PX13 (HN7306WU)**: Ryzen AI 9 HX 370
(Strix Point, 4 Zen 5 + 8 Zen 5c cores), RTX 4050 Laptop GPU, 13.3" OLED.
It replaces what Armoury Crate does on Windows, and every setting is backed by
measurements taken on this laptop with the included `px13-sweep` tool.

- Three power modes that follow the power source automatically: **eco** (fanless, on
  battery) and **perf** (unleashed, on AC), plus **normal** by hand
- A fix for an `amd_pstate` bug that pins every core at **2.0 GHz** after boot,
  resume or a profile change
- dGPU power: brings the RTX 4050 from **55 W back to 75–85 W** (Dynamic Boost and
  extra TGP), and live GPU Eco / Hybrid switching
- Per-mode fan curves, EPP, clock cap and Curve Optimizer (−25, stability-tested)
- Battery extras: SD reader off on battery, DialPad on/off, Wi-Fi runtime power
  management
- A KDE Plasma 6 panel widget, and `px13-sweep`, a measurement tool for power,
  efficiency, thermals and stability

> Tested on one PX13 (HX 370 + RTX 4050) with mainline kernel 7.2.6, KDE Plasma 6 and
> NVIDIA 595.99.02. Other PX13 variants (RTX 4060/4070, Strix Halo) will have different
> limits; treat the numbers as this unit's.

## Modes

| | eco | normal | perf |
|---|---|---|---|
| Used | on battery (automatic) | by hand | on AC (automatic) |
| Platform profile | quiet | balanced | performance |
| CPU sustained / slow / fast | 12 / 12 / 25 W | 20 / 20 / 35 W | 62 / 62 / 85 W (56 / 62 / 85 on battery) |
| EPP | balance_power | balance_power on battery, balance_performance on AC | performance |
| Zen 5 clock cap | 4.3 GHz | none | none |
| Fan curve | off below 70 °C, 100% at 85 °C | stock Balanced | stock shape, then 100% at 82 °C |
| dGPU extra TGP | +10 W (stock) | +10 W | +20 W on AC (85 W total) |

Every mode applies Curve Optimizer −25 to all cores and the 2 GHz clamp fix.
`px13 auto` (on by default) picks perf on AC and eco on battery. A manual choice
(the widget, KDE's power slider, Fn+F5, or `px13 eco|normal|perf`) holds until
the next plug or unplug.

### Why these values (measured on this laptop)

- **2 GHz clamp:** `cpuinfo_max_freq` and `scaling_max_freq` read 2.0 GHz while
  `amd_pstate_max_freq` reads 5.16 GHz; a single thread ran at 2.01 GHz.
  Re-registering the driver (`guided`, then `active`) fixes it, and px13 does that
  automatically.
- **Curve Optimizer −25:** at equal power it gives +6.5% all-core throughput at 12 W
  and +2.4% at 54 W. A stability screen (AVX-512 FMA, AVX2 FMA, DGEMM, AES-GCM, zlib;
  all-core 62–71 W, one core at 5.13 GHz, Zen 5c, bursts, 12 W) found zero wrong
  results and no machine-check errors. That's a screen, not hours-long proof.
- **eco 12 W:** for whole-laptop energy per task, 8–20 W is a flat optimum (above
  28 W, every workload costs more energy per task). With fans off, 12 W sustained
  levelled at about 56 °C (55.8 °C at 23 minutes into a 30-minute run). The 25 W fast limit lasts about 4 s
  through the EC, enough for page loads.
- **eco 4.3 GHz cap:** on one Zen 5 core it uses 26–36% less energy per task
  (integer, FMA, DGEMM, AES) for at most 19% more time. Short bursts are unaffected:
  under `balance_power` they never reach the cap.
- **EPP balance_power vs power:** five paired runs gave the same package power
  (0.00 ± 0.23 W) and 28 ms vs 39 ms p95 latency on 15 ms bursts.
- **normal 20 W:** against 12 W it is 47–85% faster on integer, FMA, DGEMM and AES
  work for the same or less energy per task.
- **perf 62 W:** on a warm chassis with the 100% fan curve, 54 / 62 / 70 W sustained
  gave 34.1 / 34.7 / 35.0 GB/s (SHA) and 711 / 723 / 700 GFLOP/s (AVX2 FMA). The stock
  curve tops out at 74%; at 70 W it pinned 95 °C and throttled.
- **dGPU:** `nvidia-powerd` (Dynamic Boost) fails at boot while GPU Eco has the GPU
  off, leaving the driver at its 55 W base. px13 keeps it running (75 W stock on AC).
  In a 7-minute FP16 soak, 75 W gave 25.0 TF/s; a 90 W limit gave 86 W and
  26.4 TF/s (+5.6%), held by a 2,640 MHz clock ceiling at 73 °C. Hence +20 W extra
  TGP (85 W) in perf.
- **SD reader:** the Genesys GL9755 never runtime-suspends; removing it from the PCI
  bus saved 0.26 W at idle.
- **DialPad driver:** costs about 0.5 W of CPU package power at idle (1.14 vs 0.60 W).

## Requirements

- ASUS ProArt PX13 (HN7306) with `asus-nb-wmi` and its debugfs interface
  (`/sys/kernel/debug/asus-nb-wmi`): px13 sets limits through EC WMI calls
- [RyzenAdj](https://github.com/FlyGoat/RyzenAdj) at `/usr/local/bin/ryzenadj`,
  used to read limits and set Curve Optimizer
- `power-profiles-daemon`, and `asusd`/`asusctl` for fan curves
- KDE Plasma 6 for the widget (the CLI works without it)
- For Hybrid / dGPU power: the NVIDIA driver with `nvidia-powerd`; optionally
  [EnvyControl](https://github.com/bayasdev/envycontrol)
- `px13-sweep` only: Python 3, gcc, NumPy, `python3-cryptography`

## Install

```sh
./install.sh                                   # system parts via sudo
systemctl --user restart plasma-plasmashell    # load the widget
```

The installer puts `px13` in `/usr/local/bin` and adds a sudoers rule
(`NOPASSWD: /usr/local/bin/px13`) so the widget can switch modes. It also installs
the `px13-watch` service (follows profile and power changes and re-applies limits
the firmware overrides) and a resume hook, plus a modprobe option for the
lid-flip tablet switch, a udev rule for Wi-Fi runtime PM, and the widget and its
helpers in `~/.local`.

## Usage

```sh
px13 eco | normal | perf      # pick a mode (holds until the next plug/unplug)
px13 auto [on|off]            # mode follows the power source (default on)
px13 sdcard on|off            # SD card reader (off on battery by default)
px13 hybrid | deep-eco        # dGPU on the bus, or powered off (live, no reboot)
px13 optimized                # dGPU follows power: Eco on battery, Hybrid on AC
px13 status                   # full report; `px13 state` for key=value
px13-panel-dialpad on|off     # ASUS DialPad driver (off persists across reboots)
```

`px13 state` reports, among others: `mode`, `limits`, `epp`, `max_mhz`,
`fan_curve`, `cpu_clamped`, `sdcard`, `gpu_eco` and `gpu_extra_tgp`.

## Measurement tool: px13-sweep

```sh
sudo bin/px13-sweep --phase co|curve|limits|epp|race|soak|stability [--workload ...] [--quick]
```

It stops `px13-watch` for the run and restores everything afterwards, including
on Ctrl-C. Results go to `~/px13-sweep/<timestamp>/*.csv`. Every unit of work is
checked against a reference, so an unstable undervolt shows up as errors.
Workloads: `sha`, `zlib`, `aesgcm`, `avx512fma`, `avx2fma` (a C kernel built at
run time), `dgemm`, `mem`. Run `px13-sweep --help` for the phases.

## Caveats

- **Curve Optimizer −25 is per-chip.** It passed a screen on this unit; another
  chip may need less. Edit `CO_NEG25` in `bin/px13`.
- **Low-level writes:** px13 writes EC power limits and dGPU TGP through WMI debugfs,
  and CO through RyzenAdj (which uses `/dev/mem` without `ryzen_smu`). The kernel
  logs one "ryzenadj: Unexpected write to kernel-exclusive config offset b8"
  warning per boot because of that.
- **Firmware quirks:** enabling a custom fan curve makes the EC swap in other power
  limits about a second later. px13 re-applies the mode's limits right after.
- **Dynamic Boost** is disabled by the firmware on battery and in the quiet profile.
- **Kernel:** Ubuntu 7.0.0-38 has an OLED brightness-stripes regression, unrelated
  to this tool. Mainline 7.2.6 is fine.

## Layout

```
bin/px13                 main tool (modes, clamp fix, fans, dGPU, SD reader, watcher)
bin/px13-sweep           measurement and stability tool
bin/px13-panel-*         widget helpers (run, status, battery, DialPad)
bin/px13-envycontrol     EnvyControl helper for Hybrid switches
plasmoid/                KDE Plasma 6 widget
system/                  systemd units, sleep hook, sudoers, modprobe, udev
0001-platform-x86-asus-wmi-dgpu-vivo.patch
                         kernel RFC: asus-wmi support for the Vivo/ProArt dGPU
                         disable device (0x00090120), the GPU Eco switch
```

## License

MIT; see [LICENSE](LICENSE). The exception is
`0001-platform-x86-asus-wmi-dgpu-vivo.patch`, which modifies the Linux kernel
and is therefore GPL-2.0, like the kernel itself.
