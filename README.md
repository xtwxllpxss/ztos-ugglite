# ztos-ugglite — device adaptation for Xiaomi Redmi Note 5A (ugglite)

*Русская версия: [README.ru.md](README.ru.md)*

Device layer, build recipe and a small, explicitly tracked patch series for
running [ztOS](https://github.com/Zerone-Laboratories/ztOS) on the Xiaomi Redmi
Note 5A (`ugglite`, Qualcomm MSM8917, Adreno 308) with the mainline
`linux-postmarketos-qcom-msm89x7` kernel and lk2nd as the first stage.

Unofficial and experimental. Not a product, not an installer, not an endorsed
ztOS or postmarketOS device. Verified state is a hand-assembled root filesystem
booted from a host over USB; several core functions are unverified or broken.

## Hardware status

| Area | State |
|---|---|
| Kernel + userspace boot over USB (lk2nd → RAM candidate) | works |
| Display, baseline | works — confirmed by the device owner |
| Display brightness | Working on the accepted RAM build with preserved DSI video clocks. The owner confirmed smooth adjustment without frame shift |
| Wi-Fi | associates and passes traffic; rate/throughput under load not fixed |
| Audio | stock path plays, with audible hiss while idle; the replacement path was rejected on hardware |
| RTC write | **unsafe — do not attempt**; root cause not established |
| Modem | LTE registration, signal and the UI indicator work; **data/APN, SMS, calls, call audio and GNSS unverified** — details in [docs/modem.md](docs/modem.md) |
| Offline time | system clock correct without NTP via `swclock-offset`; hardware RTC write still unsafe |
| Rear camera | S5K3L8 identified and RAW10 1280×720 capture verified. Scene exposure and application preview remain unverified |
| Suspend | unverified |

Details and the exact evidence boundary: [docs/hardware-status.md](docs/hardware-status.md).
Safety notes before touching the device: [docs/safety.md](docs/safety.md).

## What is in here

```
devices/xiaomi-ugglite/
  device.toml                 registry entry: pmaports pin, kernel, DTB, lk2nd subpackage
  layer.sh                    apply <root>: copy overlay/ into an existing root
  fixups.sh                   idempotent post-copy fixes (setuid, pacman sandbox)
  packages.txt                extra packages for the assembled root
  overlay/                    files copied over the assembled root
  patches/                    patch series, see SERIES.md
  camera/                     rear CSI/DT fragments
  front-camera/               S5K5E8 out-of-tree driver, install kit, DT delta
  audio/                      UCM (HiFi.conf) for the qdsp6 speaker/headphone path
  units/                      touch-key nav mapper, torch helper + udev rule
build-environment/
  Dockerfile                  native aarch64 Arch Linux ARM build image
  prepare-kernel.sh           kernel build in a separate container, pinned pmaports
  finalize-kernel.sh          in-container build/verify/export, refuses drift
  repack-boot-init.py         replace only init inside an existing boot image
docs/                         hardware status, safety
SERIES.md                     patch order, base commits, hash chain, apply commands
PROVENANCE.md                 per-file licence terms and derivation
MAP.md                        every working component → path, or why excluded
LICENSES/, NOTICE.md          full licence texts and per-area scope
```

Patch series: six userspace deltas and two kernel source deltas, documented in
`SERIES.md` order. `SERIES.md` "One authority" says which copies are the series
and which are historical mirrors. `patches/**/experimental/` is not part of the
default series and is not a feature claim.

## Reproducing a build

From a fresh checkout you can prepare the pinned userspace sources, build a
kernel package in an ARM64 container, and apply the device overlay to an
existing root. Start with [Build and boot](docs/BUILD-AND-BOOT.md), which lists
the commands and the inputs still needed to assemble a bootable system.

Upstream revisions are pinned by URL and commit in `ATTRIBUTION.md` and
`upstream-lock.json` (the machine-readable form); those are the revisions the
patches were made against, not a promise they still build.

## Scope of this publication

- No binaries, images, kernel packages, firmware or built logs.
- No credentials, network profiles, host names, machine identifiers or personal
  paths.
- No RTC write patch: it is unsafe on this hardware.
- Rejected or unaccepted experiments are not published as features; where a
  source delta has real value but no acceptance, it lives under `experimental/`
  with its limitation stated.

## Licence

Original adaptation material: GPL-3.0-or-later. Patch files are derivative works
of the projects they modify and keep those projects' terms — userspace patches
GPL-3.0-or-later (upstream is GPL-2.0-or-later), kernel patches GPL-2.0-only.
`NOTICE.md` and `PROVENANCE.md` state which file is under which terms; the root
`LICENSE` does not relicense third-party code.
