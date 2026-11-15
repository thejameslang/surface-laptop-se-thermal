#!/bin/bash
# Logs CPU temperatures every 30 seconds to ~/templog.txt. Stop with Ctrl+C.
# Needs lm-sensors (install.sh installs it).
while true; do
  echo "=== $(date +%T)"
  sensors | grep -E "Package|temp[0-9]"
  sleep 30
done >> ~/templog.txt
