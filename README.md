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
| Display, replacement/UI builds | **not accepted**; brightness slider does not change the panel, one earlier candidate went black and was rolled back |
| Wi-Fi | associates and passes traffic; rate/throughput under load not fixed |
| Audio | stock path plays, with audible hiss while idle; the replacement path was rejected on hardware |
| RTC write | **unsafe — do not attempt**; root cause not established |
| Modem | LTE registration, signal and the UI indicator work; **data/APN, SMS, calls, call audio and GNSS unverified** — details in [docs/modem.md](docs/modem.md) |
| Offline time | system clock correct without NTP via `swclock-offset`; hardware RTC write still unsafe |
| Camera, suspend | unverified, no claims |

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

Patch series: five `ztmetro`/`ztsettings` deltas plus one kernel delta, in
`SERIES.md` order. `SERIES.md` "One authority" says which copies are the series
and which are historical mirrors. `patches/**/experimental/` is not part of the
default series and is not a feature claim.

## Reproducing a build

You need: git, Docker, an aarch64-capable container host (the build runs native
aarch64, no qemu), `fastboot` on the host, and a phone already prepared with
lk2nd. Then:

1. Build the environment image from `build-environment/Dockerfile`.
2. `sh build-environment/prepare-kernel.sh` — pinned pmaports, pinned kernel tag,
   signature verified.
3. Assemble an Arch Linux ARM aarch64 root, apply this layer
   (`layer.sh apply <root>`, then `fixups.sh <root>`).
4. Wrap the root as a RAM candidate with `repack-boot-init.py`.
5. `fastboot boot <candidate>` — boot, never flash.

This is the whole reproducible path, and it is **not** complete on its own:
the root assembly step has no pinned package list or ArchLinuxARM tarball
checksum, and nothing here installs to `userdata`. The exact remaining gaps are
listed in [docs/BUILD-AND-BOOT.md](docs/BUILD-AND-BOOT.md#gaps--what-a-stranger-still-cannot-do-end-to-end).
There is no installer, no recovery image and no rollback image in this
repository, on purpose.

Upstream revisions are pinned by URL and commit in `ATTRIBUTION.md`; those are
the revisions the patches were made against, not a promise they still build.

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
