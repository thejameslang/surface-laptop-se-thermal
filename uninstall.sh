#!/bin/bash
# Reverses install.sh. Leaves the installed packages alone.
# Run with: sudo bash uninstall.sh
# Only touches files that install.sh wrote. Safe to run more than once.
set -e

if [ "$EUID" -ne 0 ]; then
  echo "Please run with sudo: sudo bash $0"
  exit 1
fi

CONF=/etc/thermald/thermal-conf.xml
ORDER=/etc/thermald/thermal-cpu-cdev-order.xml
MODULES_CONF=/etc/modules-load.d/surface-se-thermal.conf
OLD_MODULES_CONF=/etc/modules-load.d/thermal.conf

# Put back the file install.sh backed up, if there is one. Otherwise delete
# the file, but only if it's ours.
# $1 = file, $2 = text that only our version contains.
restore_or_remove() {
  if [ -f "$1.orig" ]; then
    mv -f "$1.orig" "$1"
    echo "Restored your previous $1"
  elif [ -f "$1" ] && grep -qF "$2" "$1"; then
    rm -f "$1"
  elif [ -f "$1" ]; then
    echo "Leaving $1 alone: it isn't the one install.sh wrote."
  fi
}

echo "==> Removing config files..."
rm -f "$MODULES_CONF"
# Earlier versions of install.sh wrote thermal.conf. Only remove it if it
# holds exactly our three modules.
if [ -f "$OLD_MODULES_CONF" ] && [ "$(cat "$OLD_MODULES_CONF")" = "$(printf 'coretemp\nintel_rapl_msr\nx86_pkg_temp_thermal')" ]; then
  rm -f "$OLD_MODULES_CONF"
fi
restore_or_remove "$CONF" "<Name>Surface Laptop SE</Name>"
restore_or_remove "$ORDER" "surface-laptop-se-thermal"

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
echo "Done. The coretemp, intel_rapl_msr, x86_pkg_temp_thermal and"
echo "intel_powerclamp modules stay loaded until you reboot."
echo
echo "The packages are still installed. To remove them:"
echo "  sudo apt remove thermald sysfsutils lm-sensors"
echo "Skip any you use for something else."
