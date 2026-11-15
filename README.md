# Surface Laptop SE thermal fix on Linux

Stops the Microsoft Surface Laptop SE from shutting itself off under sustained
load on Linux. Companion to
[surface-laptop-se-hotkeys](https://github.com/thejameslang/surface-laptop-se-hotkeys).

The Laptop SE has no fan. Its ACPI thermal zone reports no trip points
(`ACPI: thermal: [Firmware Bug]: No valid trip points!`), so Linux has nothing
to throttle the CPU against. Under sustained load (Minecraft Bedrock via
mcpelauncher), the temperature climbs until the firmware cuts power at about
105°C.

thermald is the usual answer, but it couldn't work at first. The `coretemp`,
RAPL and package-temperature drivers weren't loaded, so it reported
"No Zones present".

## What the installer does

1. Loads `coretemp`, `intel_rapl_msr` and `x86_pkg_temp_thermal` at every boot,
   so thermald has zones to watch.
2. **Turns turbo boost off permanently** (`intel_pstate/no_turbo = 1`, applied
   at boot by sysfsutils). This was the change that stopped the shutdowns.
3. Installs thermald with a custom config that starts throttling at a package
   temperature of 75°C (RAPL first, then intel_pstate). It's a safety net in
   case turbo off isn't enough.

### Test results

| Test | Peak package temperature | Result |
|---|---|---|
| Overnight | 80°C | No shutdown. thermald stepped in at least once. |
| About 1 hour of Minecraft, uncapped FPS | 76°C | No shutdowns. |

That's about 30°C of margin below the cutoff.

## Install

Needs a Debian/Ubuntu-based distro with `apt`. It was tested on Linux Mint XFCE.
It won't work as-is on immutable distros like Endless OS.

```sh
git clone https://github.com/thejameslang/surface-laptop-se-thermal
cd surface-laptop-se-thermal
sudo bash install.sh
```

The script is safe to run more than once. Reboot afterwards, then check that
turbo is still off:

```sh
cat /sys/devices/system/cpu/intel_pstate/no_turbo   # should print 1
```

### Check that it's working

```sh
sensors | grep "Package id 0"          # the CPU temperature sensor is there
journalctl -u thermald -b | grep "Using config file"   # thermald loaded the config
systemctl status thermald              # active (running)
```

To see how hot it gets under load, run the logger in a second terminal while
you play or compile:

```sh
bash tools/templog.sh
```

It appends to `~/templog.txt` every 30 seconds. Stop it with Ctrl+C, then read
the peak:

```sh
grep Package ~/templog.txt | awk '{print $4}' | sort -g | tail -1
```

### Uninstall

```sh
sudo bash uninstall.sh
```

This removes the module list, the thermald config and the `no_turbo` line in
`/etc/sysfs.conf`, turns turbo back on, and restarts thermald. The packages stay
installed. The script prints the `apt remove` command if you want them gone.

## Notes

- **Capping FPS in games still helps**, because less work means less heat, but
  it isn't required with this fix. The hour-long test above ran uncapped.
- **thermald watches the CPU package temperature.** The firmware probably shuts
  down based on a chassis sensor instead. Keeping the CPU cool has kept the
  chassis cool so far, but that's inferred, not measured.

## Files

| Path | What it is |
|---|---|
| `install.sh` | Installs the packages, loads the drivers, writes the thermald config, turns turbo off (needs sudo) |
| `uninstall.sh` | Reverses `install.sh`, leaves the packages installed (needs sudo) |
| `tools/templog.sh` | Logs CPU temperatures every 30 seconds to `~/templog.txt` |

## License

[MIT](LICENSE)
