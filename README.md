# ztos-ugglite — device adaptation for Xiaomi Redmi Note 5A (ugglite)

*Русская версия: [README.ru.md](README.ru.md)*

Device layer, build recipe and a small, explicitly tracked patch series for
running [ztOS](https://github.com/Zerone-Laboratories/ztOS) on the Xiaomi Redmi
Note 5A (`ugglite`, Qualcomm MSM8917, Adreno 308) with the mainline
`linux-postmarketos-qcom-msm89x7` kernel and lk2nd as the first stage.

Unofficial and experimental. Not a product, not an installer, not an endorsed
ztOS or postmarketOS device. Verified state is a persistent install: the boot
slot carries lk2nd followed by a ztOS payload (the stock boot image is backed up
for rollback) and ztOS runs from an internal ext4 root. Several core functions
are still unverified or broken.

## Hardware status

| Area | State |
|---|---|
| Boot, persistent (lk2nd + ztOS boot slot) | works — host-free reboots; stock boot image backed up for rollback |
| Boot, RAM candidates (`fastboot boot`) | works — tests a kernel/DT without touching the slot |
| Boot time / splash | the splash stays up for ~51 s because a boot gate waits 45 s for a Waydroid marker this install never writes; a host-built compositor candidate removes the wait (51 → ~6 s expected), it is not installed — [docs/boot-time.md](docs/boot-time.md) |
| Display, baseline | works — confirmed by the device owner |
| Display brightness | Works on the accepted persistent install with preserved DSI video clocks. The owner confirmed smooth adjustment without frame shift |
| Wi-Fi | associates and passes traffic; rate/throughput under load not fixed |
| Audio | speaker playback and incoming-call audio accepted (RX1/RX2 at 104 in the accepted gain test; the installed verb writes 120, +36 dB, louder without distortion); idle hiss remains. Microphone is quiet, gain candidates not accepted |
| RTC write | **unsafe — do not attempt**; root cause not established |
| Modem | LTE registration and the UI indicator work; **incoming calls and call audio are accepted**, SMS reception imports messages, data on/off and autoconnect are accepted; outgoing calls untested, SMS sending fails (RP cause 38), WWAN data unverified (tariff allow-list). How received messages travel (QMI WMS) and a host-verified dedupe candidate: [docs/sms.md](docs/sms.md) — [docs/modem.md](docs/modem.md) |
| GNSS | modem GPS engine verified (NMEA output, satellite received with SNR 31); no user-space client installed yet. A prepared GeoClue client kit is documented, not installed — [docs/gnss.md](docs/gnss.md) |
| Offline time | system clock correct without NTP via `swclock-offset`; hardware RTC write still unsafe |
| Rear camera | S5K3L8 identified and RAW10 1280×720 capture verified; owner reports the camera working. The sensor path measured 119.44 fps and a candidate build caps it to 29.84 fps with exposure up to 1/30 s, but that build is not installed. The cap, the AF settle/boost change and the pacer retime are published as **candidate source patches** (host-verified, never run on the phone). 720p30 recording, colour calibration, AE/ISO and AF feel are not accepted — see [docs/camera-video.md](docs/camera-video.md) and [SERIES.md](SERIES.md) |
| Front camera | S5K5E8 chip ID `0x5e80` and both CSI links verified, first frame captured; owner reports the camera working. Preview orientation/mirroring and higher modes not accepted |
| Rear torch | works — DT-only `gpio-leds` node `white:torch` on gpio34, writable by the UI through a udev rule; `max_brightness=1`, on/off only. GPIO mapping is vendor-derived |
| Updates | `ztos-update check` completes; `apply` upgrades in a single `pacman -Syu` transaction |
| Memory / browser | zram (900 MB, `lz4`) is active; the prepared memory and Firefox changes are host-only recommendations, none applied — [docs/performance.md](docs/performance.md) |
| Venus hardware video encode | probe passes in a running boot and a synthetic 720p H.264 encode works, but the firmware is device-local and not published, boot-time persistence is untested and the camera does not use it yet. The source fix for the stock-encoder HFI bug is a candidate kernel patch, cross-built but not booted; `venus` is a module, so the same fix can be delivered as one module replacement without rebuilding the kernel image (modules built host-side, not delivered) — [docs/venus.md](docs/venus.md), [SERIES.md](SERIES.md) |
| Waydroid | unverified; only a prepared freeze-policy helper exists and it is not installed — [docs/waydroid.md](docs/waydroid.md) |
| Thermal / charging | the vendor trip points (75/85/100 °C) and the 1 A / 4.208 V charge clamp are already correct; there is no user-space thermal daemon by design; analysis only, nothing changed — [docs/thermal.md](docs/thermal.md) |
| Suspend | `deep` unsupported by firmware; only `s2idle` available, screen-off power not measured |

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
  audio/                      UCM (HiFi.conf, VoiceCall.conf) for the qdsp6 speaker and voice-call paths
  units/                      touch-key nav mapper and its systemd unit
  torch/                      rear-flash DT fragment, udev rule, helper, install kit
build-environment/
  Dockerfile                  native aarch64 Arch Linux ARM build image
  prepare-kernel.sh           kernel build in a separate container, pinned pmaports
  finalize-kernel.sh          in-container build/verify/export, refuses drift
  repack-boot-init.py         replace only init inside an existing boot image
docs/                         hardware status, camera and video (two source lineages), Venus, SMS reception, auto-rotate, recovery, GNSS client, Waydroid, boot time, performance, thermal, safety
SERIES.md                     patch order, base commits, hash chain, apply commands
PROVENANCE.md                 per-file licence terms and derivation
MAP.md                        every working component → path, or why excluded
LICENSES/, NOTICE.md          full licence texts and per-area scope
```

Patch series: six `ztmetro` userspace deltas, the composed camera-application
delta plus three camera-application candidates (host-verified, never run on the
phone), a device-layer SMS receive candidate, and three kernel source deltas
(0003 is a candidate, not accepted state), documented in `SERIES.md` order. `SERIES.md`
"One authority" says which copies are the series and which are historical
mirrors. `patches/**/experimental/` is not part of the default series and is not
a feature claim.

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
