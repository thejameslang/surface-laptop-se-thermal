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

echo "==> Installing packages..."
apt update
apt install -y thermald sysfsutils lm-sensors

# thermald finds no thermal zones without these drivers ("No Zones present").
echo "==> Loading temperature/power drivers now and at every boot..."
printf "coretemp\nintel_rapl_msr\nx86_pkg_temp_thermal\n" > /etc/modules-load.d/thermal.conf
modprobe coretemp
modprobe intel_rapl_msr
modprobe x86_pkg_temp_thermal

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

# sysfsutils applies /etc/sysfs.conf at boot. The grep keeps this idempotent.
echo "==> Disabling turbo boost (now and permanently)..."
if ! grep -q "intel_pstate/no_turbo" /etc/sysfs.conf 2>/dev/null; then
  echo "devices/system/cpu/intel_pstate/no_turbo = 1" >> /etc/sysfs.conf
fi
echo 1 > /sys/devices/system/cpu/intel_pstate/no_turbo

echo "==> Restarting thermald..."
systemctl enable thermald
systemctl restart thermald

echo
echo "==> Checks:"
echo -n "Turbo disabled (should be 1): "
cat /sys/devices/system/cpu/intel_pstate/no_turbo
sensors | grep -q "Package id 0" && echo "CPU temperature sensor: OK" || echo "CPU temperature sensor: NOT FOUND"
journalctl -u thermald -b | grep -q "Using config file" && echo "thermald config: OK" || echo "thermald config: check 'journalctl -u thermald -b'"
echo
echo "Done. Reboot, then confirm: cat /sys/devices/system/cpu/intel_pstate/no_turbo  (should print 1)"
