#!/bin/sh
# SPDX-FileCopyrightText: 2026 the ztos-ugglite contributors
# SPDX-License-Identifier: GPL-3.0-or-later
# ztOS device layer: Xiaomi Redmi Note 5A (ugglite), MSM8917.
#
# The pipeline that exists today is the postmarketOS one: ztConflo generates
# /vendor/ztos/manifest.toml from device.toml (ial.manifest) and copies
# <registry entry>/overlay/. over the assembled root in build_gsi step 5. That
# is the whole layer for this phone, so no tarball is built and none is shipped:
# `ztconflo build --device-layer <tar>` is only read for origin = "native"
# (ial.install_native), and build.py refuses a native entry outright until the
# ztOS pacman repository exists. A hand-kept vendor/ztos/manifest.toml would be
# dead data today and would drift from the generated one.
#
#   layer.sh apply <root>   copy overlay/ into an already unpacked root, exactly
#                           as build_gsi step 5 does, for inspecting the layer
#                           outside ztConflo.
#
# The root must already exist: this only adds files to a root that is there, it
# never creates one, so a mistyped path fails instead of leaving a stray tree.
set -eu

DEVSRC=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)

usage() {
	cat <<'EOF'
usage: layer.sh apply <root>

  apply   copy overlay/ into <root>, which must already exist
          (the same copy ztConflo's GSI pipeline makes in step 5)
EOF
}

case ${1:-} in
apply)
	[ $# -eq 2 ] || { usage >&2; exit 2; }
	root=$2
	[ -d "$root" ] || {
		printf 'layer.sh: %s: not a directory (apply never creates a root)\n' "$root" >&2
		exit 2
	}
	cp -a "$DEVSRC/overlay/." "$root/"
	printf 'layer.sh: applied overlay to %s\n' "$root"
	;;
*)
	usage >&2
	exit 2
	;;
esac
