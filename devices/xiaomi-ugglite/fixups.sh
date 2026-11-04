#!/bin/sh
# SPDX-FileCopyrightText: 2026 the ztos-ugglite contributors
# SPDX-License-Identifier: GPL-3.0-or-later
# Device fixes that are properties of the assembled root, not files to overlay.
#
# The postmarketOS/ztConflo pipeline copies overlay/ over a root that pacstrap
# already built; these three things cannot be expressed as a file in overlay/
# (a mode bit, an option inside a config the package owns) so they are applied
# here, after the copy, and are idempotent.
#
#   ./fixups.sh <root>   apply to an unpacked root (host or mounted userdata)
#
# 1. fusermount3 must be setuid root. It is how an unprivileged user gets a
#    FUSE mount, and the xdg document portal (flatpak file sharing) is exactly
#    that: without the bit xdg-document-portal dies at startup with
#    "fusermount3: mount failed: Operation not permitted" / exit status 6.
#    Copying a root through a transport that drops setuid leaves 0755.
# 2. pacman 7.1 sandboxes its database work. The Filesystem half needs
#    Landlock, which this kernel does not build (CONFIG_SECURITY_LANDLOCK is
#    not set), so every `pacman -Sy` fails with "restricting filesystem access
#    failed" and ztos-update-check exits 1 with nothing on stderr. Turn off only
#    the filesystem half; the syscall sandbox (seccomp) still applies.
# 3. The distro pacman.conf ships that option commented out, so it has to be
#    uncommented once per root.
set -eu

root=${1:-}
[ -n "$root" ] || { echo "usage: $0 <root>" >&2; exit 2; }
[ -d "$root" ] || { echo "$0: $root: not a directory" >&2; exit 2; }

fuse=$root/usr/bin/fusermount3
if [ -f "$fuse" ]; then
	chmod 4755 "$fuse"
fi

conf=$root/etc/pacman.conf
if [ -f "$conf" ]; then
	# Uncomment the option the package ships commented; add it if this
	# pacman.conf predates the split of DisableSandbox. awk, not sed -i:
	# this also runs from a macOS checkout, where sed -i wants an argument.
	if grep -q '^DisableSandboxFilesystem' "$conf"; then
		:
	elif grep -q '^#DisableSandboxFilesystem' "$conf"; then
		awk '{ sub(/^#DisableSandboxFilesystem/, "DisableSandboxFilesystem"); print }' \
			"$conf" > "$conf.fixup" && mv "$conf.fixup" "$conf"
	else
		awk '1; $0 == "[options]" && !seen++ { print "DisableSandboxFilesystem" }' \
			"$conf" > "$conf.fixup" && mv "$conf.fixup" "$conf"
	fi
fi

# Audio: /dev/snd nodes are root:audio 0660. logind uaccess grants an ACL for
# the seated user, but that only covers an active session; a plain group
# membership makes the PCMs reachable for user services started outside one.
group=$root/etc/group
if [ -f "$group" ]; then
	awk -F: 'BEGIN { OFS = ":" }
		$1 == "audio" && $4 !~ /(^|,)alarm(,|$)/ { $4 = ($4 == "" ? "alarm" : $4 ",alarm") }
		{ print }' "$group" > "$group.fixup" && mv "$group.fixup" "$group"
fi

# ztsettings writes the chosen ringtone to $HOME/.config/ztmetro/ringtone with
# fopen()+"rename", and never creates the directory: on a home where nothing has
# been saved yet the write fails ENOENT, is dropped without a word, and the
# picker keeps showing the built-in Nokia-Tune default. config_save() in the
# same binary shares the flaw, so the directory must exist before the first
# save. The source-side fix (mkdir on demand) is
# patches/ztsettings-config-dir-mkdir.patch, for the next rebuild.
home=$root/home/alarm
if [ -d "$home" ]; then
	install -d -m 0700 "$home/.config/ztmetro"
	ids=$(awk -F: '$1 == "alarm" { print $3 ":" $4 }' "$root/etc/passwd" 2>/dev/null)
	if [ -n "$ids" ]; then
		chown "$ids" "$home/.config/ztmetro"
	fi
fi

echo "fixups: applied to $root"
