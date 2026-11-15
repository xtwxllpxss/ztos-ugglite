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

"Accepted" means the device owner confirmed the function on the phone. Where a
number comes from a host build or from a saved log, the row says so.

| Area | State |
|---|---|
| Boot, persistent (lk2nd + ztOS boot slot) | works — host-free reboots; stock boot image backed up for rollback |
| Boot, RAM candidates (`fastboot boot`) | works — tests a kernel/DT without touching the slot |
| Boot time / splash | **installed and accepted** — the splash-fast compositor removes the splash at **6.306 s** instead of 51.047 s on the compositor's own clock. The 51 s was a boot gate waiting for a Waydroid marker this install never wrote; the installed build waits only when that integration is installed (measured on one boot, same install; total "button to UI" is still not measured) — [docs/boot-time.md](docs/boot-time.md) |
| Display, baseline | works — confirmed by the device owner |
| Display brightness | Works on the accepted persistent install with preserved DSI video clocks. The owner confirmed smooth adjustment without frame shift |
| Wi-Fi | associates and passes traffic; rate/throughput under load not fixed |
| Audio | speaker playback and incoming-call audio accepted (RX1/RX2 at 104 in the accepted gain test; the installed verb writes 120, +36 dB, louder without distortion); idle hiss remains. Microphone is quiet, gain candidates not accepted |
| RTC write | **unsafe — do not attempt**; root cause not established |
| Modem | LTE registration and the UI indicator work; **incoming calls and call audio are accepted**, SMS reception imports messages, data on/off and autoconnect are accepted; outgoing calls untested, SMS sending fails (RP cause 38), WWAN data unverified (tariff allow-list). How received messages travel (QMI WMS) and a host-verified dedupe candidate: [docs/sms.md](docs/sms.md) — [docs/modem.md](docs/modem.md) |
| GNSS | modem GPS engine verified (NMEA output, satellite received with SNR 31); no user-space client installed yet. A prepared GeoClue client kit is documented, not installed — [docs/gnss.md](docs/gnss.md) |
| Offline time | system clock correct without NTP via `swclock-offset`; hardware RTC write still unsafe |
| Rear camera | S5K3L8 identified and RAW10 1280×720 capture verified; owner reports the camera working. The sensor path measured 119.44 fps and a candidate build caps it to 29.84 fps with exposure up to 1/30 s, but that build is not installed. The cap, the AF settle/boost change and the pacer retime are published as **candidate source patches** (host-verified, never run on the phone). 720p30 recording, colour calibration, AE/ISO and AF feel are not accepted — see [docs/camera-video.md](docs/camera-video.md) and [SERIES.md](SERIES.md) |
| Front camera | S5K5E8 chip ID `0x5e80`, both CSI links and a 640×480 capture verified; the owner reports the camera working. The `Loading…` failure in the camera application was diagnosed, fixed and accepted: live preview from `/dev/video1` at 640×480 and about **62 fps** (binary after the fix `c2a28339…`, previous `ea79a1c8…` kept as a backup). Preview orientation/mirroring, higher modes and AE are not accepted — [docs/front-camera.md](docs/front-camera.md) |
| Rear torch | works — DT-only `gpio-leds` node `white:torch` on gpio34, writable by the UI through a udev rule; `max_brightness=1`, on/off only. GPIO mapping is vendor-derived |
| Sensors / auto-rotate | **sensor hub fixed, installed and verified after one reboot** — the sensor registry firmware loads at 3.215 s and the ADSP comes up at 3.886 s, in that order (before the fix the registry only succeeded at ~7.6 s through a late fallback); `/dev/iio:device1..4` deliver 24/24/24/16 bytes per scan with the consumer stopped and `zt-sensors` is live (accel, gyro, magnetometer, proximity, values change). Auto-rotate is unblocked at the sensor layer (`rotate --set on` accepted without errors, config restored byte-for-byte), but rotation in the compositor is **not implemented** (the ROTATION LOCK tile is a stub) and the physical tilt was never performed, so no visual rotation is accepted — [docs/sensors.md](docs/sensors.md), [docs/auto-rotate.md](docs/auto-rotate.md) |
| Apps / UI | 35 applications surveyed and all 35 settled: **PASS 12 · PARTIAL 11 · FAIL 10 · HIDDEN 1** (plus one invalid capture, Firefox, measured separately). Fixes delivered after the sweep: vim runtime, calculator glyphs/centring, btop user config, Power Management telemetry (upstream PR #16) and the front-camera preview. Store and OSIAL **work** — the Store renders its AUR/repository package lists and OSIAL dumps 13 interfaces in 1.9 s; the only visible failure is that `pkgstats.archlinux.org` does not resolve (DNS), shown on screen. Rotation is not implemented in the compositor (the ROTATION LOCK tile is a stub); `ztgallery` v2 (folders/albums, video, scroll) is in development. Still open: UI clipping at 360×640@2, switch toggles, the `0 fps` camera status — [docs/apps.md](docs/apps.md), [docs/store-and-osial.md](docs/store-and-osial.md) |
| Waydroid | **freeze policy installed and verified** — the helper survives screen-off/on (`verify.sh` 12/0), a session starts in about 5 s, Android 13 reaches `boot_completed=1`, a manually launched app draws a real window, and ztmetro's screen-off policy completes. Not a full integration: no `recover`/`launch` units, `systemui` ANR on 2 GB, a manual start while the screen is off is still frozen until a thaw; launching Android from a ztmetro tile is not implemented and was not confirmed visually — the owner deferred that work to the very end — images and userdata untouched — [docs/waydroid.md](docs/waydroid.md) |
| Upstream adoption | PR #16 merged onto the accepted base and installed on the phone: `ztpower`, `ztdevices`, `ztsettings` replaced with the upstream-source builds, verified live — nonzero battery telemetry (`100 %`, `Charging (+30 mA)`, `4.38 V`, `31.4 °C`; sysfs 4.382 V agrees), settings and devices windows render, no segfault, previous binaries backed up. PR #13 accepted except its camera hunks, not merged yet; #14 dropped as a duplicate, #11 not needed — [docs/upstream.md](docs/upstream.md) |
| Updates | `ztos-update check` completes; `apply` upgrades in a single `pacman -Syu` transaction |
| Memory / browser | zram (900 MB, `lz4`) is active; the memory and Firefox-pref changes are host-only recommendations, **none applied**. One live browser measurement exists: WebRender over EGL/freedreno is active (DPR 2), 10 processes, PSS ~630 MB, no OOM; the 32.9 ms median in the frame trace is the **compositor's** vblank loop (mean 28.08 ms ≈ 35.6 fps), **not** Firefox's frame rate; a present/dmabuf hypothesis is open and an A/B plan exists, unapplied — [docs/performance.md](docs/performance.md) |
| Venus hardware video encode | probe passes in a running boot and a synthetic 720p H.264 encode works, but the firmware is device-local and not published, boot-time persistence is untested and the camera does not use it yet. The source fix for the stock-encoder HFI bug is a candidate kernel patch, cross-built but not booted; `venus` is a module, so the same fix can be delivered as one module replacement without rebuilding the kernel image (modules built host-side, not delivered) — [docs/venus.md](docs/venus.md), [SERIES.md](SERIES.md) |
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
docs/                         hardware status, camera and video (two source lineages), front camera, Venus, Store and OSIAL, SMS reception, auto-rotate, sensors, app acceptance, upstream adoption, recovery, GNSS client, Waydroid, boot time, performance, thermal, safety
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
