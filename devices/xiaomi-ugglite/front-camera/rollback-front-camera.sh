#!/bin/sh
# Roll back install-front-camera.sh on ugglite. Run ON THE PHONE as root.
#
#   sh rollback-front-camera.sh
#
# Removes the autoload, the helper, the desktop entry and the module (restoring
# a *.bak-ugglite-front backup if one exists), then runs depmod.
#
# It deliberately does NOT rmmod s5k5e8 from the running kernel: CAMSS already
# completed its async bind and unbinding a live sensor subdev is not a safe
# operation. The rollback takes effect on the next boot (RAM boot of an image
# without the front DT, or of the accepted baseline).
set -eu
KV=7.1.3-msm89x7
say() { echo "rollback-front-camera: $*"; }

[ "$(id -u)" = 0 ] || { echo "rollback-front-camera: must run as root on the phone" >&2; exit 1; }

rm -f /etc/modules-load.d/ugglite-front-camera.conf
say "removed autoload /etc/modules-load.d/ugglite-front-camera.conf"

rm -f /usr/local/bin/ugglite-front-preview
rm -f /usr/local/share/applications/ugglite-front-camera.desktop
say "removed helper and desktop entry"

for moddir in /lib/modules/$KV /usr/lib/modules/$KV; do
    [ -d "$moddir" ] || continue
    target=$moddir/kernel/drivers/media/i2c/s5k5e8.ko
    if [ -f "$target.bak-ugglite-front" ]; then
        mv -f "$target.bak-ugglite-front" "$target"
        say "restored previous module from $target.bak-ugglite-front"
    elif [ -f "$target" ]; then
        rm -f "$target"
        say "removed $target"
    fi
    depmod -a "$KV" || say "WARNING: depmod failed"
    break
done

if grep -q '^s5k5e8 ' /proc/modules; then
    say "s5k5e8 is still loaded in this boot; rollback applies after the next boot"
else
    say "done"
fi
