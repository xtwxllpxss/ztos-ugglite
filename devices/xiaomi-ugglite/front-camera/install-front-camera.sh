#!/bin/sh
# Install the permanent front-camera (S5K5E8) userspace on ugglite.
#
# Run ON THE PHONE as root from this package directory (the one that contains
# s5k5e8.ko, ugglite-front-preview and ugglite-front-camera.desktop):
#   sh install-front-camera.sh
#
# It does four things, in this order:
#   1. verifies the module SHA256 and vermagic; aborts before changing anything
#      if either does not match the on-device-proven build;
#   2. installs s5k5e8.ko under /lib/modules/$KV/kernel/drivers/media/i2c/
#      (backup of a different existing file as *.bak-ugglite-front) and depmod;
#   3. writes /etc/modules-load.d/ugglite-front-camera.conf so the module is
#      loaded at every boot by systemd-modules-load, before the GUI starts;
#   4. installs /usr/local/bin/ugglite-front-preview and its .desktop entry.
#
# Loading the module is not optional on a front-DT boot: CAMSS uses one
# v4l2-async notifier, and its complete() (which creates every sensor->csiphy
# link and registers the video nodes) runs only after ALL sensors in the DT
# bound. Without s5k5e8 the rear camera graph stays unbuilt as well.
#
# Everything is reversible with rollback-front-camera.sh. This script never
# touches /boot, the kernel, the ramdisk, the DT or the rear-camera driver.
set -eu

KV=7.1.3-msm89x7
EXPECT_KO=64b6572e8bb6675e996b80da28e2e3a51539ec8c935eaf80a00a96b79fd6de4e
here=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
die() { echo "install-front-camera: $*" >&2; exit 1; }
say() { echo "install-front-camera: $*"; }

[ "$(id -u)" = 0 ] || die "must run as root on the phone"
[ "$(uname -r)" = "$KV" ] || die "running kernel $(uname -r), package is for $KV"
ko=$here/s5k5e8.ko
[ -f "$ko" ] || ko=$here/../ko/s5k5e8.ko
[ -f "$ko" ] || die "s5k5e8.ko not found next to this script or in ../ko"
[ -f "$here/ugglite-front-preview" ] || die "ugglite-front-preview is not next to this script"
[ -f "$here/ugglite-front-camera.desktop" ] || die "desktop file is not next to this script"

echo "$EXPECT_KO  $ko" | sha256sum -c - >/dev/null || \
    die "s5k5e8.ko SHA256 does not match the proven 64b6572e build; nothing changed"
say "module SHA256 ok ($EXPECT_KO), source $ko"

if command -v modinfo >/dev/null 2>&1; then
    vermagic=$(modinfo -F vermagic "$ko")
    [ "$vermagic" = "7.1.3-msm89x7 SMP preempt mod_unload aarch64" ] || \
        die "unexpected vermagic '$vermagic'; nothing changed"
    say "vermagic ok"
fi

moddir=
for d in /lib/modules/$KV /usr/lib/modules/$KV; do
    [ -d "$d" ] && { moddir=$d; break; }
done
[ -n "$moddir" ] || die "no module tree for $KV"

target=$moddir/kernel/drivers/media/i2c/s5k5e8.ko
if [ -f "$target" ] && ! cmp -s "$target" "$ko"; then
    [ -f "$target.bak-ugglite-front" ] || cp -p "$target" "$target.bak-ugglite-front"
    say "backed up existing module to $target.bak-ugglite-front"
fi
install -Dm644 "$ko" "$target"
say "installed $target"
depmod -a "$KV"
say "depmod -a $KV ok"

conf=/etc/modules-load.d/ugglite-front-camera.conf
install -d -m755 /etc/modules-load.d
printf 's5k5e8\n' > "$conf"
say "autoload: $conf"

install -Dm755 "$here/ugglite-front-preview" /usr/local/bin/ugglite-front-preview
install -Dm644 "$here/ugglite-front-camera.desktop" \
    /usr/local/share/applications/ugglite-front-camera.desktop
say "helper and launcher installed"

if grep -q '^s5k5e8 ' /proc/modules; then
    say "module already loaded"
else
    say "loading module now so the live CAMSS graph can complete"
    modprobe s5k5e8 || say "WARNING: modprobe failed; front and rear camera stay without video nodes until it loads"
fi

# Wait briefly for async bind, then report facts rather than intentions.
i=0
while [ "$i" -lt 20 ]; do
    if ls /sys/bus/i2c/drivers/s5k5e8/*-002d >/dev/null 2>&1; then
        break
    fi
    i=$((i + 1))
    sleep 0.1 2>/dev/null || sleep 1
done
if ls /sys/bus/i2c/drivers/s5k5e8/*-002d >/dev/null 2>&1; then
    say "i2c driver bound: $(ls -d /sys/bus/i2c/drivers/s5k5e8/*-002d)"
else
    say "WARNING: i2c driver did not bind (wrong DT boot or sensor not answering)"
fi
if command -v media-ctl >/dev/null 2>&1 && [ -e /dev/media0 ]; then
    media-ctl -d /dev/media0 -p > /var/tmp/ugglite-front-install-topology.txt 2>/dev/null || true
    if grep -Fq '-> "msm_csiphy1":0 [ENABLED,IMMUTABLE]' /var/tmp/ugglite-front-install-topology.txt; then
        say "front link ok: sensor -> msm_csiphy1:0 [ENABLED,IMMUTABLE]"
    else
        say "WARNING: front link is not present; see /var/tmp/ugglite-front-install-topology.txt"
    fi
    if grep -Fq '-> "msm_csiphy0":0 [ENABLED,IMMUTABLE]' /var/tmp/ugglite-front-install-topology.txt; then
        say "rear link still built: sensor -> msm_csiphy0:0 [ENABLED,IMMUTABLE]"
    else
        say "WARNING: rear sensor->csiphy0 link is missing; rear camera graph is incomplete"
    fi
fi

say "done. Front camera desktop entry: /usr/local/share/applications/ugglite-front-camera.desktop"
say "verify one frame: ugglite-front-preview --capture /var/tmp/front640.raw  (384000 B)"
