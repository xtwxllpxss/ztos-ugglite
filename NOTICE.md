# Notices: scope, provenance and exclusions

This file states what is in the repository, under which licence, and what was
deliberately left out. It is the authoritative map for licensing questions.

## Licence scope by area

| Area | Files | Licence | Basis |
|---|---|---|---|
| Device layer and docs (original work) | `device.toml`, `layer.sh`, `fixups.sh`, `packages.txt`, `overlay/**`, `docs/**`, `README*`, this file, `CONTRIBUTING.md` | GPL-3.0-or-later | Written for this adaptation; same licence family as the ztOS tree the layer plugs into. |
| Patches against ztOS userspace | the five `.patch` files under `devices/xiaomi-ugglite/patches/` (each listed in `ATTRIBUTION.md`) | GPL-3.0-or-later | The upstream files they modify carry `GPL-2.0-or-later` in their SPDX headers. The patches are distributed under GPL-3.0-or-later by exercising the upstream "or any later version" option; the upstream grant itself is **not** GPL-3.0. Copyright in the upstream code stays with the ztOS authors. |
| Userspace patch series | `patches/userspace/ztmetro/0001`–`0006`, `patches/userspace/ztcamera/0001` and `experimental/` (same upstream terms) | GPL-3.0-or-later | Same basis as the device-layer copies; series position and source base are documented in SERIES.md. |
| Kernel patch | `patches/kernel/0001-wcn36xx-dynamic-ra-start-rate.patch`, `patches/kernel/experimental/` | GPL-2.0-only | Derivative of the Linux kernel file it modifies. The "or later" option does **not** exist for the kernel tree, so no GPL-3.0 label is applied. Upstream copyright is retained and nothing further is granted. |
| Licence texts | `LICENSES/GPL-3.0-or-later.txt`, `LICENSES/GPL-2.0-only.txt` | verbatim texts | GPL-3.0 copied unmodified from the ztOS repository (`upstream/ztOS/LICENSE`, 232 lines, sha256 `fb981668c18a279e285fc4d83fba1e836cc84dd4daa73c9697d3cfd2d8aca6e0`). GPL-2.0 copied unmodified from the FSF's canonical publication <https://www.gnu.org/licenses/old-licenses/gpl-2.0.txt> (17 984 bytes, sha256 `edaef632cbb643e4e7a221717a6c441a4c1a7c918e6e4d56debc3d8739b233f6`). |

The root `LICENSE` applies to original material only. It does **not** relicense
third-party code, and no attempt is made to summarise or replace upstream terms.

## Upstream projects referenced

- ztOS — <https://github.com/Zerone-Laboratories/ztOS>. The source files these
  patches modify (`ztmetro/ztmetro.c`, `ztmetro/settings/ztsettings.c`,
  `ztmetro/core/zrnmetrocore.c` and `ztmetro/camera/ztcamera.c`) declare
  `SPDX-License-Identifier: GPL-2.0-or-later`. The upstream repository also
  ships a GPL-3.0 licence text at its root; that text is not the SPDX grant of
  the modified files. The patches here are distributed under GPL-3.0-or-later
  via the "or later" option.
- postmarketOS pmaports — <https://gitlab.postmarketos.org/postmarketOS/pmaports>,
  GPL-3.0 for packaging metadata. Source of the kernel/device package pins named
  in `device.toml` (device package `device-qcom-msm89x7`, kernel
  `linux-postmarketos-qcom-msm89x7` 7.1.3-r1).
- lk2nd — <https://github.com/msm8916-mainline/lk2nd>, GPL-2.0-only. Bootloader;
  only its DTB name is referenced, no code is copied.
- Linux kernel (msm89x7 mainline tree) — GPL-2.0-only. One one-line patch is
  included under `patches/kernel/`; no kernel source tree is redistributed.

No upstream project endorses this repository. "ztOS" and "postmarketOS" are used
only to describe what the files plug into.

## Included allowlist

Only files that met all of the following were copied: plain text, small, authored
in this project or a reviewable derivative of GPL-2.0-or-later ztOS sources,
containing no
personal data, no hardware identifiers and no unverified experimental state.

Included device files:

- `device.toml`, `layer.sh`, `fixups.sh`, `packages.txt`
- `overlay/etc/ztos/device`, `overlay/etc/ztos/ugglite-capabilities`
- `overlay/etc/modules-load.d/ztos-ugglite.conf`
- `overlay/usr/local/sbin/zboot-usb-gadget` (replaces the GSI's S9-branded
  gadget at the same path; derivative of the ztOS GSI script under the
  upstream tree's GPL-3.0 licence text)
- `overlay/usr/local/sbin/ztos-ugglite-usbnet`, `overlay/usr/local/sbin/ztos-update`
- five accepted patches under `patches/` (each verified with `git apply --check`
  against the pinned ztOS revision; each carries an SPDX and upstream-provenance
  header above its diff, with hunk bytes unchanged)
- `audio/VoiceCall.conf` (the installed UCM voice-call verb; mixer control names
  and values only) and the `Voice Call` use case it adds to
  `audio/xiaomi-ugg.conf`

## Deliberate exclusions

| Excluded | Why |
|---|---|
| Build outputs, images, `*.img`, kernel packages, ramdisks, firmware, `*.ko` | Binaries; not source, not licensed for redistribution here, and easy to mistake for a supported artefact. |
| Everything under the private project's `build/` except this staging tree | Contains logs, captures and intermediate state, some with device identifiers. |
| `patches/rtc-allow-set-time.patch` | RTC write is unsafe and its failure cause is unresolved; publishing it would invite the exact operation that crashed the phone. |
| Local working copies that are now superseded by `patches/` | The haptic, settings-identity, wifi-bars and wcn36xx patches are published in the series with their bases and hashes; the rumble patch only as `experimental/`. Apply one set, never both (`SERIES.md`, "One authority"). |
| Audio C2 material (`ucm2` override, `libspa-alsa` build) | Rejected on hardware; the ALSA UCM file's provenance is an unresolved mix of upstream and local edits. |
| `overlay/etc/udev/rules.d/*`, `overlay/opt/zapret/*`, `overlay/etc/default/*`, `overlay/etc/systemd/**` | Device-specific permissions, third-party routing lists and service changes not reviewed for publication. |
| `maintenance/` (SSH, modules-load, Wi-Fi autostart, keyring) | Contains host/service configuration and a private SSH daemon config; network-facing and not needed to reproduce the layer. |
| `ram-probe/`, `userdata-prep/`, `file-rootfs/`, `direct-root/` init scripts | Installer/probe logic, including unconditional reboot paths; explicitly out of scope for publication. |
| `scripts/`, research notes, `START-HERE.md` and session logs | Session history with device identifiers, boot ids, hostnames and internal process; not a stable document. |
| Any `.env`, credentials, keys, network profiles, MAC/SSID/IP lists | Private data. |

Nothing excluded is referenced as if it were available; the README states plainly
that no installer, no rollback image and no image build is published.

## If you redistribute

Keep `LICENSE`, `LICENSES/`, this file and the per-patch headers intact. The
per-patch headers state the upstream file and revision and its
`GPL-2.0-or-later` grant; do not replace that statement with a GPL-3.0 claim. If you
add kernel patches or firmware-related files, license them under their own
upstream terms and extend this table — do not fold them under the root licence.
