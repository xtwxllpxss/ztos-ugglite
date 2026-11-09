#!/bin/sh
# install-torch.sh — userspace half of the ugglite rear torch (white:torch).
#
# The DT node (gpio-leds "white:torch" on gpio34, pinctrl gpio33/gpio34) must
# already be present in the running boot: this script only makes the node
# writable for user alarm and installs the one-shot helper. It never touches
# /boot, the kernel, the ramdisk or the DT.
#
# Run ON THE PHONE as root from this directory. No reboot. Idempotent.
set -eu
here=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
LED=/sys/class/leds/white:torch/brightness
RULE=72-ugglite-torch.rules
HELPER=zt-flashlight
die() { echo "install-torch: $*" >&2; exit 1; }

[ "$(id -u)" = 0 ] || die "must run as root on the phone"
for f in "$here/$RULE" "$here/$HELPER"; do
	[ -f "$f" ] || die "missing $f"
done

echo "== before"
ls -l "$LED" 2>/dev/null || echo "   $LED absent (DT node not in this boot)"

install -m 0644 "$here/$RULE" "/etc/udev/rules.d/$RULE"
install -m 0755 "$here/$HELPER" /usr/local/bin/$HELPER
echo "== installed /etc/udev/rules.d/$RULE and /usr/local/bin/$HELPER"

# Re-fire the "add" event so RUN+= applies to the already-created LED.
udevadm control --reload-rules
udevadm trigger --subsystem-match=leds --action=add
i=0
while [ "$i" -lt 5 ] && [ ! -e "$LED" ]; do sleep 1; i=$((i+1)); done

echo "== after"
if [ -e "$LED" ]; then
	ls -l "$LED"
	max=$(cat "${LED%/brightness}/max_brightness" 2>/dev/null || echo '?')
	[ "$max" = 1 ] || echo "   note: max_brightness=$max, expected 1 for the gpio-leds node" >&2
	/usr/local/bin/$HELPER status || true
else
	echo "   $LED still absent: gpio-leds/white:torch is not in the DT of this boot"
fi
echo "== check as alarm (must be writable, rc=0):"
su -s /bin/sh alarm -c "test -w $LED" && echo "   alarm can write $LED" || \
	echo "   alarm CANNOT write $LED (rule not applied yet)"
echo "== done. Torch off = zt-flashlight off. Rollback: rollback-torch.sh"
