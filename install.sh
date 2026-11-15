#!/bin/bash
# Thermal fix for the Surface Laptop SE on Debian/Ubuntu-based distros
# (tested on Linux Mint XFCE).
# Run with: sudo bash install.sh
# Safe to run more than once.
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

echo "==> Installing packages..."
apt update
apt install -y thermald sysfsutils lm-sensors

# thermald finds no thermal zones without these drivers ("No Zones present").
echo "==> Loading temperature/power drivers now and at every boot..."
printf "coretemp\nintel_rapl_msr\nx86_pkg_temp_thermal\n" > /etc/modules-load.d/thermal.conf
for mod in coretemp intel_rapl_msr x86_pkg_temp_thermal; do
  if ! modprobe "$mod"; then
    echo "Error: modprobe $mod failed." >&2
    exit 1
  fi
done

# The firmware reports no trip points, so thermald needs its own. This one
# starts throttling at a package temperature of 75C: RAPL power limit first,
# then intel_pstate. It is a safety net; turning turbo off (below) is what
# stopped the shutdowns.
echo "==> Writing thermald config (throttle at 75C)..."
cat > /etc/thermald/thermal-conf.xml << 'EOF'
<?xml version="1.0"?>
<ThermalConfiguration>
 <Platform>
  <Name>Surface Laptop SE</Name>
  <ProductName>*</ProductName>
  <Preference>QUIET</Preference>
  <ThermalZones>
   <ThermalZone>
    <Type>cpu</Type>
    <TripPoints>
     <TripPoint>
      <SensorType>x86_pkg_temp</SensorType>
      <Temperature>75000</Temperature>
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
       <type>intel_pstate</type>
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

# sysfsutils applies /etc/sysfs.conf at boot. Drop any existing no_turbo line
# first (even one set to 0), so the file ends up with exactly one, set to 1.
echo "==> Disabling turbo boost (now and permanently)..."
if [ -f /etc/sysfs.conf ]; then
  sed -i '/intel_pstate\/no_turbo/d' /etc/sysfs.conf
fi
echo "devices/system/cpu/intel_pstate/no_turbo = 1" >> /etc/sysfs.conf
echo 1 > "$NO_TURBO"

echo "==> Restarting thermald..."
systemctl enable thermald
START=$(date +%s)
systemctl restart thermald
sleep 2

echo
echo "==> Checks:"
echo -n "Turbo disabled (should be 1): "
cat "$NO_TURBO"
sensors | grep -q "Package id 0" && echo "CPU temperature sensor: OK" || echo "CPU temperature sensor: NOT FOUND"
systemctl is-active --quiet thermald && echo "thermald running: OK" || echo "thermald running: NOT ACTIVE, check 'systemctl status thermald'"
journalctl -u thermald --since "@$START" | grep -q "Using config file" && echo "thermald config: OK" || echo "thermald config: check 'journalctl -u thermald -b'"
echo
echo "Done. Reboot, then confirm: cat /sys/devices/system/cpu/intel_pstate/no_turbo  (should print 1)"
