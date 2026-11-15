#!/bin/bash
# Reverses install.sh. Leaves the installed packages alone.
# Run with: sudo bash uninstall.sh
set -e

if [ "$EUID" -ne 0 ]; then
  echo "Please run with sudo: sudo bash $0"
  exit 1
fi

echo "==> Removing config files..."
rm -f /etc/modules-load.d/thermal.conf
# Put back the thermald config that install.sh backed up, if there was one.
CONF=/etc/thermald/thermal-conf.xml
if [ -f "$CONF.orig" ]; then
  mv -f "$CONF.orig" "$CONF"
  echo "Restored your previous $CONF"
else
  rm -f "$CONF"
fi

echo "==> Removing the no_turbo line from /etc/sysfs.conf..."
if [ -f /etc/sysfs.conf ]; then
  sed -i '/intel_pstate\/no_turbo/d' /etc/sysfs.conf
fi

echo "==> Turning turbo boost back on..."
if ! { echo 0 > /sys/devices/system/cpu/intel_pstate/no_turbo; } 2> /dev/null; then
  echo "Warning: could not re-enable turbo (firmware may block it)" >&2
fi

echo "==> Restarting thermald..."
if systemctl cat thermald.service > /dev/null 2>&1; then
  systemctl restart thermald
fi

echo
echo "Done. The coretemp, intel_rapl_msr and x86_pkg_temp_thermal modules stay"
echo "loaded until you reboot."
echo
echo "The packages are still installed. To remove them:"
echo "  sudo apt remove thermald sysfsutils lm-sensors"
echo "Skip any you use for something else."
