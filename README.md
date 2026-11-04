# ztos-ugglite — device adaptation for Xiaomi Redmi Note 5A (ugglite)

*Русская версия: [README.ru.md](README.ru.md)*

Device overlay, build notes and a small set of accepted patches for running
[ztOS](https://github.com/Zerone-Laboratories/ztOS) on the Xiaomi Redmi Note 5A
(`ugglite`, Qualcomm MSM8917, Adreno 308), using the mainline
`linux-postmarketos-qcom-msm89x7` kernel and lk2nd as the bootloader.

**This is an unofficial, experimental, host-assisted RAM-boot adaptation. It is
not a product, not an installer and not an officially supported ztOS device.**
Nothing here is endorsed by the ztOS or postmarketOS projects. Do not expect a
one-command install: the verified state is a hand-built root filesystem booted
over USB from a host, and several core functions are unverified or broken — the
latest display candidate is one of them (see
[status](docs/hardware-status.md)).

## What actually works, and what does not

Short version, as of the last hardware session:

| Area | State |
|---|---|
| Kernel / RAM boot to userspace | works (ztOS baseline `4fed0f28…` booted via lk2nd) |
| Display | baseline image confirmed working by the device owner after rollback; the replacement panel module produced a black screen and is rejected; UI brightness control remains unresolved (`EACCES`) |
| Audio | stock path plays with idle hiss; a replacement (C2) was rejected on hardware |
| Wi-Fi | works with limitations (throughput/rate behaviour not fixed) |
| RTC write | **unsafe, do not attempt** — cause of the crash is not established |
| Modem, camera, suspend | **not verified** — no claims are made |

Details, evidence boundaries and open failure modes: [docs/hardware-status.md](docs/hardware-status.md).

## Repository layout

```
devices/xiaomi-ugglite/
  device.toml                 registry entry (pmaports pins, kernel, lk2nd, SoC)
  layer.sh                    apply <root>: copy overlay/ into an existing root
  fixups.sh                   idempotent post-copy fixes (setuid, pacman sandbox)
  packages.txt                extra packages for the assembled root
  overlay/                    files copied over the assembled root
  patches/                    device patches accepted during bring-up
docs/                         hardware status and safety notes
LICENSES/                     full licence texts; see NOTICE.md for per-area scope
```

`device.toml` intentionally leaves `[boot].rootfs_target` unset: the carrier
choice belongs to whoever builds the image, and the build driver requires it
explicitly. The entry is therefore **not** self-sufficient; it is an input, not
a finished device package.

## Build and boot — what is reproducible

Only the *inputs* are reproducible here, not an image. The build needs a host
with pacstrap/arch-chroot (or pmbootstrap), `mkbootimg`, `mke2fs`, and an
aarch64 cross setup; this repository contains no binaries, no kernel, no
firmware and no image. The verified path was:

1. Assemble an Arch Linux ARM root with the pinned kernel package
   (`linux-postmarketos-qcom-msm89x7` 7.1.3-r1) and the ugglite DTB
   `qcom/msm8917-xiaomi-ugglite.dtb`.
2. Apply this layer with `layer.sh apply <root>`, then `fixups.sh <root>`.
3. Boot that root as a RAM candidate through lk2nd, with USB as the only
   console — never by flashing a partition.

Because the assembled root lived on the host and in `userdata`, **no automatic
installer, no rollback image and no recovery procedure is published here.** If
you do not already have a working host-assisted boot, this repository will not
give you one.

Pinned upstream revisions and their provenance are recorded in
[ATTRIBUTION.md](ATTRIBUTION.md); they are the revisions the notes were written
against, not a guarantee that they still build.

## Status and scope of this publication

- Not an official ztOS or postmarketOS artefact; no upstream endorsement.
- No support promise. Issues are read, but a broken device is your own risk.
- Excluded on purpose: binaries, images, firmware, private configuration,
  network profiles, credentials, raw hardware logs and unverified experimental
  patches. See [NOTICE.md](NOTICE.md) for the exact allowlist rationale.

## Licence

Original adaptation material in this repository is licensed under
GPL-3.0-or-later. Patch files are derivative works of the projects they modify
and keep those projects' terms. `NOTICE.md` states which file is under which
licence; the root `LICENSE` does not relicense third-party code.
