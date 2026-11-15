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

1. Loads `coretemp`, `intel_rapl_msr` and `x86_pkg_temp_thermal` at every boot
   (listed in `/etc/modules-load.d/surface-se-thermal.conf`), so thermald has
   zones to watch. The list is only written once all three have loaded.
2. **Turns turbo boost off permanently** (`intel_pstate/no_turbo = 1`, applied
   at boot by sysfsutils). This was the change that stopped the shutdowns.
3. Installs thermald with a custom config that starts throttling at a package
   temperature of 75°C (2°C hysteresis), using the RAPL power limit first and
   then `cpufreq`, which only lowers `scaling_max_freq`. It's a safety net in
   case turbo off isn't enough. It also installs
   `/etc/thermald/thermal-cpu-cdev-order.xml`, which lists just those two
   devices, so thermald's built-in CPU trip point never uses `intel_pstate`
   either, even if the `x86_pkg_temp` sensor is missing.

   **Why no `intel_pstate` cooling device:** when thermald's `intel_pstate`
   device backs off, it writes `no_turbo = 0`, which turns turbo back on until
   the next reboot and undoes step 2.

   If you already have a `/etc/thermald/thermal-conf.xml` or
   `thermal-cpu-cdev-order.xml` of your own, the installer saves it as `.orig`
   first, unless a `.orig` already exists, in which case the old backup is kept.
   The uninstaller puts it back.

### Test results

| Test | Peak package temperature | Result |
|---|---|---|
| Overnight | 77°C | No shutdown. thermald stepped in at least once. |
| About 1 hour of Minecraft, uncapped FPS | 76°C | No shutdowns. |

That's about 30°C of margin below the cutoff.

**The throttling config changed after these tests.** They were recorded with an
earlier config that also used `intel_pstate` throttling. The current config uses
RAPL and `cpufreq` instead (see above), so see
[Confirm on one laptop](#confirm-on-one-laptop) below.

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
journalctl -u thermald -b | grep -E "Using config file|could not parse|Using generated"
```

The journal line should read `Using config file /etc/thermald/thermal-conf.xml`.
`could not parse` or `Using generated` means thermald ignored the config.

```sh
systemctl status thermald              # active (running)
```

To see how hot it gets under load, run the logger in a second terminal while
you play or compile:

```sh
bash tools/templog.sh
```

Run it as your normal user, without `sudo`. It writes to `~/templog.txt`, and
under `sudo` that would be root's home folder instead of yours. It appends to
the file every 30 seconds. Stop it with Ctrl+C, then read
the peak:

```sh
grep Package ~/templog.txt | awk '{print $4}' | sort -g | tail -1
```

### Uninstall

```sh
sudo bash uninstall.sh
```

This always turns turbo back on and removes any `no_turbo` line from
`/etc/sysfs.conf`, including one you added yourself. It also removes the module
list and the two thermald files, or restores your own `.orig` copies if the
installer saved them. A thermald file that isn't the one this repo wrote is left
alone, so running the uninstaller twice, or on a machine where the installer
never ran, won't delete your config. Then it restarts thermald. The packages stay
installed, and the script prints the `apt remove` command if you want them gone.

## Confirm on one laptop

The current throttling config (RAPL, then `cpufreq`) hasn't been checked on the
hardware. Whether the firmware lets RAPL change the power limit on this machine
is part of what to confirm. To check:

```sh
cat /sys/class/powercap/intel-rapl:0/constraint_0_*
journalctl -u thermald -b | grep -iE "Using config file|rapl|locked"
```

The first command shows the package's RAPL power limit, name and time window. Run
it once while the laptop is cool and again while it's hot and thermald is
throttling, to see whether the limit moves. The second shows whether thermald
loaded the config, and whether it logged anything about RAPL or a locked limit.

After an hour of normal use, check that turbo is still off:

```sh
cat /sys/devices/system/cpu/intel_pstate/no_turbo   # should still print 1
```

If it prints 0, something turned turbo back on. The journal output above is the
place to look.

## Notes

- **Capping FPS in games still helps**, because less work means less heat, but
  it isn't required with this fix. The hour-long test above ran uncapped.
- **thermald watches the CPU package temperature.** The firmware probably shuts
  down based on a chassis sensor instead. Keeping the CPU cool has kept the
  chassis cool so far, but that's inferred, not measured.

## Files

| Path | What it is |
|---|---|
| `install.sh` | Installs the packages, loads the drivers, writes the thermald config and CPU cooling order, turns turbo off (needs sudo) |
| `uninstall.sh` | Reverses `install.sh`, leaves the packages installed (needs sudo) |
| `tools/templog.sh` | Logs CPU temperatures every 30 seconds to `~/templog.txt` |

## License

[MIT](LICENSE)
