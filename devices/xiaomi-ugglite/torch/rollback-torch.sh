#!/bin/sh
# rollback-torch.sh — remove the torch userspace install (rule + helper).
#
# Does not touch the boot image: after this the LED node may still exist but
# is root:root 0644 again, i.e. ztmetro's tile goes faint and writes fail.
# Run ON THE PHONE as root from this directory.
set -eu
LED=/sys/class/leds/white:torch/brightness
[ "$(id -u)" = 0 ] || { echo "rollback-torch: must run as root on the phone" >&2; exit 1; }
printf '0\n' > "$LED" 2>/dev/null || true
rm -f /etc/udev/rules.d/72-ugglite-torch.rules /usr/local/bin/zt-flashlight
udevadm control --reload-rules
echo "rollback-torch: rule and helper removed; torch forced off"
