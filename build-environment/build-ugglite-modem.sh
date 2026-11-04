#!/bin/sh
# Run in a native aarch64 Linux build environment with gcc, git and libudev headers.
# Installs only rmtfs into an existing assembled root. Services/scripts are in overlay/.
set -eu
root=${1:?usage: build-ugglite-modem.sh ROOT}
[ -d "$root" ] || { echo "root does not exist: $root" >&2; exit 2; }
case $(gcc -dumpmachine) in aarch64*) ;; *) echo 'aarch64 Linux gcc required' >&2; exit 2 ;; esac
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
for component in rmtfs qrtr; do
    case "$component" in
        rmtfs) revision=b30a3eb38f9af283f18dbd3c7755653efc52c094 ;;
        qrtr) revision=29e36ae164389580a0f8ea7a7fdb728140ae978d ;;
    esac
    git init -q "$work/$component"
    git -C "$work/$component" fetch -q --depth 1 "https://github.com/linux-msm/$component.git" "$revision"
    git -C "$work/$component" checkout -q --detach FETCH_HEAD
    [ "$(git -C "$work/$component" rev-parse HEAD)" = "$revision" ]
done
gcc -Wall -O2 -I"$work/qrtr/include" -I"$work/rmtfs" \
    "$work/rmtfs/qmi_rmtfs.c" "$work/rmtfs/rmtfs.c" \
    "$work/rmtfs/rproc.c" "$work/rmtfs/sharedmem.c" \
    "$work/rmtfs/storage.c" "$work/rmtfs/util.c" \
    "$work/qrtr/lib/qrtr.c" "$work/qrtr/lib/qmi.c" "$work/qrtr/lib/logging.c" \
    -ludev -lpthread -o "$work/ugglite-rmtfs"
install -Dm755 "$work/ugglite-rmtfs" "$root/usr/local/libexec/ugglite-rmtfs"
