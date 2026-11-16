#!/bin/bash
# Thermal fix for the Surface Laptop SE on Debian/Ubuntu-based distros
# (tested on Linux Mint XFCE).
# Run with: sudo bash install.sh
# Safe to run more than once.
# Exit status: 0 if everything checked out, 1 if it couldn't install, and 2 if
# it installed but a final check reported a problem (thermald not active, or
# the thermald config FAILED, NOT CONFIRMED or NOT APPLIED).
set -e

if [ "$EUID" -ne 0 ]; then
  echo "Please run with sudo: sudo bash $0"
  exit 1
fi

# Turbo is turned off through intel_pstate. Check that it's there before
# changing anything, so a failure doesn't leave half the config written.
NO_TURBO=/sys/devices/system/cpu/intel_pstate/no_turbo
if [ ! -e "$NO_TURBO" ] || [ ! -w "$NO_TURBO" ]; then
  echo "Error: intel_pstate not active; turbo can't be disabled this way." >&2
  echo "($NO_TURBO is missing or not writable.)" >&2
  exit 1
fi

# The product name thermald has to match. It is used for <ProductName> in the
# config below and for the check here, so the two can't drift apart.
CONFIGURED_PRODUCT="Surface Laptop SE"
# thermald removes every space, tab, CR and LF from both names before it
# compares them, and treats * as matching any machine. Do the same here.
squash() { tr -d ' \t\r\n'; }
PRODUCT_RAW=$(tr -d '\r\n' < /sys/class/dmi/id/product_name 2>/dev/null || true)
PRODUCT_MATCHED=0
if [ "$(printf '%s' "$CONFIGURED_PRODUCT" | squash)" = "*" ] ||
   [ "$(printf '%s' "$PRODUCT_RAW" | squash)" = "$(printf '%s' "$CONFIGURED_PRODUCT" | squash)" ]; then
  PRODUCT_MATCHED=1
fi
# thermald logs "Using config file" before it matches the product name, so a
# mismatch would not show up in the checks at the end. Say so now, and again
# in the checks.
NOT_APPLIED_MSG="thermald config: NOT APPLIED (DMI product name '$PRODUCT_RAW' doesn't match '$CONFIGURED_PRODUCT'). thermald falls back to its built-in trip, still without intel_pstate.
That trip is likely near 100C on this chip, close to the ~105C firmware cutoff, so the 75C safety net isn't active. Turbo is still turned off."
if [ "$PRODUCT_MATCHED" = 0 ]; then
  echo "Warning: the DMI product name is \"$PRODUCT_RAW\", which doesn't match \"$CONFIGURED_PRODUCT\" (ignoring whitespace)." >&2
  echo "thermald will ignore the throttling config this script writes. Turbo is still" >&2
  echo "turned off. To apply the config anyway, set CONFIGURED_PRODUCT near the top of" >&2
  echo "this script to * (matches any machine) and run it again." >&2
fi

CONF=/etc/thermald/thermal-conf.xml
ORDER=/etc/thermald/thermal-cpu-cdev-order.xml
MODULES_CONF=/etc/modules-load.d/surface-se-thermal.conf
OLD_MODULES_CONF=/etc/modules-load.d/thermal.conf

# Save a file that isn't ours as FILE.orig, so uninstall.sh can restore it.
# $1 = file, $2 = text that only our version contains.
# An existing .orig is never overwritten, so the first backup always survives.
backup_foreign() {
  [ -f "$1" ] || return 0
  grep -qF "$2" "$1" && return 0
  if [ -e "$1.orig" ]; then
    echo "Warning: $1.orig already exists, so it is kept and $1 is overwritten without a new backup." >&2
  else
    echo "==> Backing up existing $1 to $1.orig"
    cp -p "$1" "$1.orig"
  fi
}

echo "==> Installing packages..."
apt update
apt install -y thermald sysfsutils lm-sensors

# thermald finds no thermal zones without these drivers ("No Zones present").
echo "==> Loading temperature/power drivers now and at every boot..."
for mod in coretemp intel_rapl_msr x86_pkg_temp_thermal; do
  if ! modprobe "$mod"; then
    echo "Error: modprobe $mod failed." >&2
    exit 1
  fi
done
# intel_powerclamp is the second cooling device. It's optional: warn if it
# can't load, and only list it for boot if it did.
modules_list="coretemp\nintel_rapl_msr\nx86_pkg_temp_thermal\n"
if modprobe intel_powerclamp; then
  modules_list="${modules_list}intel_powerclamp\n"
else
  echo "Warning: modprobe intel_powerclamp failed. thermald will throttle with RAPL only." >&2
fi
printf '%b' "$modules_list" > "$MODULES_CONF"
# Earlier versions of this script wrote thermal.conf. Remove it if it holds
# exactly our three modules, so they aren't listed twice.
if [ -f "$OLD_MODULES_CONF" ] && [ "$(cat "$OLD_MODULES_CONF")" = "$(printf 'coretemp\nintel_rapl_msr\nx86_pkg_temp_thermal')" ]; then
  rm -f "$OLD_MODULES_CONF"
fi

# The firmware reports no trip points, so thermald needs its own. This one
# starts throttling at a package temperature of 75C, using the RAPL power
# limit first and then intel_powerclamp (idle injection). It is a safety net;
# turning turbo off (below) is what stopped the shutdowns.
# There is deliberately no intel_pstate cooling device: when it backs off,
# thermald writes no_turbo=0, which turns turbo back on until the next reboot
# and undoes the turbo-off fix.
# There is no cpufreq device either: thermald only registers it when
# cpu0/cpufreq/scaling_available_frequencies exists, and intel_pstate never
# creates that file. intel_powerclamp is present on the Surface Laptop SE and
# never touches no_turbo.
# ProductName must match /sys/class/dmi/id/product_name, ignoring whitespace.
# Use * to match any machine if that ever fails on some firmware. This heredoc
# is unquoted so that $CONFIGURED_PRODUCT is filled in; the XML has no other
# $, backticks or backslashes.
# Hyst is in thousandths of a degree C (2000 = 2C).
echo "==> Writing thermald config (throttle at 75C)..."
backup_foreign "$CONF" "<Name>Surface Laptop SE</Name>"
cat > "$CONF" << EOF
<?xml version="1.0"?>
<ThermalConfiguration>
 <Platform>
  <Name>Surface Laptop SE</Name>
  <ProductName>$CONFIGURED_PRODUCT</ProductName>
  <Preference>ENERGY_CONSERVE</Preference>
  <ThermalZones>
   <ThermalZone>
    <Type>cpu</Type>
    <TripPoints>
     <TripPoint>
      <SensorType>x86_pkg_temp</SensorType>
      <Temperature>75000</Temperature>
      <Hyst>2000</Hyst>
      <type>passive</type>
      <ControlType>SEQUENTIAL</ControlType>
      <CoolingDevice>
       <index>1</index>
       <type>rapl_controller</type>
       <influence>100</influence>
       <SamplingPeriod>5</SamplingPeriod>
      </CoolingDevice>
      <CoolingDevice>
       <index>2</index>
       <type>intel_powerclamp</type>
       <influence>50</influence>
       <SamplingPeriod>5</SamplingPeriod>
      </CoolingDevice>
     </TripPoint>
    </TripPoints>
   </ThermalZone>
  </ThermalZones>
 </Platform>
</ThermalConfiguration>
EOF

# thermald's built-in CPU trip point tries intel_pstate by default. It is what
# thermald falls back to whenever the product name doesn't match <ProductName>
# above, or the x86_pkg_temp sensor is missing. This list leaves intel_pstate
# out of it. Newer
# thermald versions only read this file (and thermal-conf.xml) if it is owned
# by root and not writable by group or others; older ones don't check. Mode 644
# owned by root, which is what this script creates, satisfies both.
backup_foreign "$ORDER" "surface-laptop-se-thermal"
cat > "$ORDER" << 'EOF'
<?xml version="1.0"?>
<!-- Installed by surface-laptop-se-thermal. Cooling order for thermald's
     built-in CPU trip point: no intel_pstate, which would re-enable turbo. -->
<CoolingDeviceOrder>
	<CoolingDevice>rapl_controller</CoolingDevice>
	<CoolingDevice>intel_powerclamp</CoolingDevice>
</CoolingDeviceOrder>
EOF
chmod 644 "$CONF" "$ORDER"

# sysfsutils applies /etc/sysfs.conf at boot. Drop any existing no_turbo line
# first (even one set to 0), so the file ends up with exactly one, set to 1.
echo "==> Disabling turbo boost (now and permanently)..."
if [ -f /etc/sysfs.conf ]; then
  sed -i '/intel_pstate\/no_turbo/d' /etc/sysfs.conf
fi
# If the file doesn't end with a newline, add one so our line starts on its own.
if [ -s /etc/sysfs.conf ] && [ -n "$(tail -c1 /etc/sysfs.conf)" ]; then
  echo >> /etc/sysfs.conf
fi
echo "devices/system/cpu/intel_pstate/no_turbo = 1" >> /etc/sysfs.conf
echo 1 > "$NO_TURBO"

echo "==> Restarting thermald..."
systemctl enable thermald
START=$(date +%s)
# If thermald fails to start, carry on so the checks below can report it.
systemctl restart thermald || true
sleep 2

echo
echo "==> Checks:"
echo -n "Turbo disabled (should be 1): "
cat "$NO_TURBO"
sensors | grep -q "Package id 0" && echo "CPU temperature sensor: OK" || echo "CPU temperature sensor: NOT FOUND"
problems=0
if systemctl is-active --quiet thermald; then
  echo "thermald running: OK"
else
  echo "thermald running: NOT ACTIVE, check 'systemctl status thermald'"
  problems=1
fi
THERMALD_LOG=$(journalctl -u thermald --since "@$START" --no-pager)
if echo "$THERMALD_LOG" | grep -qiE "could not parse|Using generated"; then
  echo "thermald config: FAILED, thermald did not use our config. Check 'journalctl -u thermald -b'"
  problems=1
elif echo "$THERMALD_LOG" | grep -q "Using config file $CONF"; then
  if [ "$PRODUCT_MATCHED" = 1 ]; then
    echo "thermald config: OK"
  else
    echo "$NOT_APPLIED_MSG"
    problems=1
  fi
else
  echo "thermald config: NOT CONFIRMED, check 'journalctl -u thermald -b'"
  problems=1
fi
echo
echo "Done. Reboot, then confirm: cat /sys/devices/system/cpu/intel_pstate/no_turbo  (should print 1)"
if [ "$PRODUCT_MATCHED" = 0 ]; then
  echo
  echo "$NOT_APPLIED_MSG" >&2
fi
if [ "$problems" != 0 ]; then
  echo
  echo "Finished with problems. See the checks above." >&2
  exit 2
fi
