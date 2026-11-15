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
| Boot observability | **installed** — a small early/mid/ok marker kit writes boot stages to `/boot` (on the root filesystem, not covered by a mount) and to `/var/log/boot-health`, with a fallback to a volatile directory when `/var` itself did not mount; the mount timeouts were raised and the session ordered after `/home` and `/var`. It exists because this device has no pstore/ramoops, so a boot that dies before the disk leaves no trace. One supervised reboot produced all three stages, `ok` about **56 s** after boot start; raw logs are not published — [docs/hardware-status.md](docs/hardware-status.md#boot-observability--2026-11-15) |
| Boot time / splash | **installed and accepted** — the splash-fast compositor removes the splash at **6.306 s** instead of 51.047 s on the compositor's own clock. The 51 s was a boot gate waiting for a Waydroid marker this install never wrote; the installed build waits only when that integration is installed (measured on one boot, same install; total "button to UI" is still not measured) — [docs/boot-time.md](docs/boot-time.md) |
| Display, baseline | works — confirmed by the device owner |
| Display brightness | Works on the accepted persistent install with preserved DSI video clocks. The owner confirmed smooth adjustment without frame shift |
| Compositor renderer (pixman) | **installed candidate** — the compositor can run with the software pixman renderer (`WLR_RENDERER=pixman`) instead of GLES2. On the phone it removed the GPU resets that had taken the compositor down when an Android application opened a GL surface: 0 resets, compositor CPU about 8 %, resident about 104 MB. A follow-up build fixed the bottom black band (bottom fully-black rows 120 → 0) and made the lock screen unlock on a real finger swipe; synthetic control swipes do not unlock on the software path, which is a test limitation rather than a regression. Not owner-accepted as the default renderer — [docs/hardware-status.md](docs/hardware-status.md#software-renderer--2026-11-15) |
| Wi-Fi | associates and passes traffic; rate/throughput under load not fixed. Remote access over Wi-Fi is persistent: the SSH unit listens on a wildcard address `0.0.0.0:2222` and survives a reboot (after the test reboot the session was back in about 12 s); the USB path stays usable. No network address, SSID or key is published |
| Audio | speaker playback and incoming-call audio accepted (RX1/RX2 at 104 in the accepted gain test; the installed verb writes 120, +36 dB, louder without distortion); idle hiss remains. Microphone is quiet, gain candidates not accepted |
| RTC write | **unsafe — do not attempt**; root cause not established |
| Modem | LTE registration and the UI indicator work; **incoming calls and call audio are accepted**, SMS reception imports messages, data on/off and autoconnect are accepted; outgoing calls untested, SMS sending fails (RP cause 38), WWAN data unverified (tariff allow-list). How received messages travel (QMI WMS) and a host-verified dedupe candidate: [docs/sms.md](docs/sms.md) — [docs/modem.md](docs/modem.md) |
| GNSS | modem GPS engine verified (NMEA output, satellite received with SNR 31); no user-space client installed yet. A prepared GeoClue client kit is documented, not installed — [docs/gnss.md](docs/gnss.md) |
| Offline time | system clock correct without NTP via `swclock-offset`; hardware RTC write still unsafe |
| Rear camera | S5K3L8 identified and RAW10 1280×720 capture verified; owner reports the camera working. After the storage move a stale `ztcamera` and a broken media graph (`STREAMON` `EPIPE`) stopped the rear camera; restarting the camera path and killing the stale process restored a 1280×720 preview at about 21 fps, and an automatic-reset resilience launcher kit is built (candidate, not installed). For 720p30, hardware (Venus) encoding was **not accepted**: the trial stalled (107/300 frames, `-110`) and was rolled back; a software candidate `9f3491c4…` (RAW→NV12, no BGRA conversion) is built and not installed. Colour: the v3.1 colour pipeline is **installed** and was measured in a device window — 0.0 % clipped pixels, no pink cast, about 21 fps in good light (the earlier AE/AWB v2 metrics: rear R/G cast 1.138→1.011, front 1.152→1.050, meanY stable, sdY 12.4→3.9). Autofocus: an AF-retry build is installed as well; it scores a frame only after the lens has actually moved, and in the 20 cm measurement it selected the real focus peak (about position 300), where the previous sweep picked 458 and was about 32 % softer. In a dark room autofocus is cancelled (mean frame level 0.002, gain up to 512, about 1 fps), so a low-light AE branch is in progress. 720p30 recording, colour calibration acceptance, AE/ISO acceptance and AF feel are not accepted — [docs/camera-video.md](docs/camera-video.md), [docs/venus.md](docs/venus.md), [SERIES.md](SERIES.md) |
| Front camera | S5K5E8 chip ID `0x5e80`, both CSI links and a 640×480 capture verified; the owner reports the camera working. The `Loading…` failure in the camera application was diagnosed, fixed and accepted: live preview from `/dev/video1` at 640×480 and about **62 fps** (binary after the fix `c2a28339…`, previous `ea79a1c8…` kept as a backup). Preview orientation/mirroring, higher modes and AE are not accepted — [docs/front-camera.md](docs/front-camera.md) |
| Rear torch | works — DT-only `gpio-leds` node `white:torch` on gpio34, writable by the UI through a udev rule; `max_brightness=1`, on/off only. GPIO mapping is vendor-derived |
| Sensors / auto-rotate | **sensor hub fixed, installed and verified after one reboot** — the sensor registry firmware loads at 3.215 s and the ADSP comes up at 3.886 s, in that order (before the fix the registry only succeeded at ~7.6 s through a late fallback); `/dev/iio:device1..4` deliver 24/24/24/16 bytes per scan with the consumer stopped and `zt-sensors` is live (accel, gyro, magnetometer, proximity, values change). Auto-rotate is unblocked at the sensor layer (`rotate --set on` accepted without errors, config restored byte-for-byte), but rotation in the compositor is **not implemented** (the ROTATION LOCK tile is a stub) and the physical tilt was never performed, so no visual rotation is accepted — [docs/sensors.md](docs/sensors.md), [docs/auto-rotate.md](docs/auto-rotate.md) |
| Apps / UI | 35 applications surveyed and closed: **PASS 12 · PARTIAL 11 · FAIL 10 · HIDDEN 1** (plus one invalid capture, Firefox, measured separately). Delivered after the sweep: vim runtime, calculator glyphs/centring, btop config, Power Management telemetry (upstream PR #16), front-camera preview, a single calculator header (`af5c345f…`, accepted by frame), the combined app bar build (`356ac939…`, top bar for foreign applications only) and its bottom-position A/B build (`6ad8529e…`). The owner then chose **`appbar=off`**: there is no app bar now. The Windows Phone reference (app bar is bottom-only; the two-line header belongs to pages, not to single-screen applications) is published as short facts with source links in [docs/apps.md](docs/apps.md); third-party screenshots are not published. `ztgallery` **v2 is installed** (folders/albums, video with posters and durations, day grouping); scroll (`379631fa…`) and gesture (`1940a499…`) builds are candidates. Store and OSIAL work — the Store renders its package lists and OSIAL dumps 13 interfaces in 1.9 s; the only visible failure is that `pkgstats.archlinux.org` does not resolve (DNS) — [docs/apps.md](docs/apps.md), [docs/store-and-osial.md](docs/store-and-osial.md) |
| System theme (ztmetro-dark) | **installed and verified** for GTK3/GTK4 (user `settings.ini`), Qt (`/etc/environment` `GTK_THEME` / `QT_QPA_PLATFORMTHEME=qt6ct`, `qt6ct.conf`) and Firefox (`userChrome.css`, `userContent.css`, `user.js` in the real profile). Before/after frames of galculator and featherpad confirm the dark flat chrome; NetSurf, foot and vim follow the palette, btop does not (separate geometry problem) — [docs/apps.md](docs/apps.md) |
| Files / open-with | **fixed and verified**: the Files logic (`ztfiles` + GIO) was working; the missing part was MIME associations and desktop entries. `mimeapps.list` plus `.desktop` files now open text in featherpad and images in swayimg, confirmed with `gio mime`. Owner acceptance of actually opening a file is not claimed — [docs/apps.md](docs/apps.md) |
| Waydroid | **removed by owner decision** — images, userdata and the freeze-policy helper are gone (about 2.3 GB freed); Android compatibility is not part of the daily system. The earlier freeze-policy evidence is kept in [docs/waydroid.md](docs/waydroid.md); the replacement is the native ATL runtime below, not Waydroid — [docs/atl-native.md](docs/atl-native.md) |
| Android apps (ATL) | **native path works** — ATL ships with the ztOS image for this device and runs an APK as an ordinary compositor client (no container, no Android image, no root). The image had been trimmed in a way that removed the Java runtime tree and the JNI bridge; both were restored from the image's own package store, and `ztos-android doctor` is OK. Observed on the phone: the upstream demo APK, an expression evaluator, the Politics Canvas game and the RPN calculator render and work; timerdroid runs but its tab content is stub-only; Frozen Bubble opens with a black page (DMA-BUF SurfaceView); 2048 is blocked on a native JNI symbol; Angry Birds opens and starts its GL thread but gets no EGL context. The API gap is closed in batches — 3037/3058 missing methods (99.3 %) have public SDK signatures and three batches were delivered. Waydroid was removed; this replaces it — [docs/atl-native.md](docs/atl-native.md), [docs/compat-factory.md](docs/compat-factory.md) |
| Android notifications | layer 1 implemented and partly installed: app → NotificationManager → GNotification → D-Bus → ztnotifyd → compositor banner and centre, with tap-to-open. The notification daemon and the notification-aware API jar are installed, but the compositor build carrying the banner was replaced by the software-renderer build of the same day, and the probe APK hit a stub-shadowing defect, so **end-to-end is not yet proven on the phone**. Action buttons, cold-start intent extras, icons and channel enforcement remain limits — [docs/atl-native.md](docs/atl-native.md#notifications--layer-1) |
| Android API factory | a host-side loop turns device crash logs and static missing-API lists into one deduplicated queue (**3356 requirements**), generates stubs from public SDK signatures (one API level or a five-level union; 99.3 % of the measured heavy-application gap), builds a native `api-impl.jar` with javac/dx, verifies strict symbol supersets, and deploys behind backup/rollback gates. It does not create behaviour, native symbols or constructors of existing classes — those are stated limits. The generic part is being published separately — [docs/compat-factory.md](docs/compat-factory.md) |
| Upstream adoption | PR #16 merged onto the accepted base and installed on the phone: `ztpower`, `ztdevices`, `ztsettings` replaced with the upstream-source builds, verified live — nonzero battery telemetry (`100 %`, `Charging (+30 mA)`, `4.38 V`, `31.4 °C`; sysfs 4.382 V agrees), settings and devices windows render, no segfault, previous binaries backed up. PR #13 accepted except its camera hunks, not merged yet; #14 dropped as a duplicate, #11 not needed — [docs/upstream.md](docs/upstream.md) |
| Updates | `ztos-update check` completes; `apply` upgrades in a single `pacman -Syu` transaction |
| Memory / browser | zram (900 MB, `lz4`) is active; the memory and Firefox-pref changes are host-only recommendations, **none applied**. One live browser measurement exists: WebRender over EGL/freedreno is active (DPR 2), 10 processes, PSS ~630 MB, no OOM; the 32.9 ms median in the frame trace is the **compositor's** vblank loop (mean 28.08 ms ≈ 35.6 fps), **not** Firefox's frame rate; the dmabuf-present hypothesis was A/B-tested and not confirmed (forcing `widget.dmabuf.enabled=false` kept the 2× frames and `EBUSY` was zero inside every trace window), so the next question is the compositor's own pacing during scroll; no sysctl or preference is applied — [docs/performance.md](docs/performance.md) |
| Venus hardware video encode | probe passes in a running boot and a synthetic 720p H.264 encode works, but the firmware is device-local and not published, boot-time persistence is untested and the camera does not use it yet. The **720p30 hardware path is not accepted**: the encode trial stalled (107/300 frames, `-110`) and was rolled back. A software candidate `9f3491c4…` (RAW→NV12, no BGRA) is prepared for measurement, and a Venus ftrace plan exists for the next hardware attempt. The source fix for the stock-encoder HFI bug is a candidate kernel patch, cross-built but not booted — [docs/venus.md](docs/venus.md), [SERIES.md](SERIES.md) |
| Thermal / charging | the vendor trip points (75/85/100 °C) and the 1 A / 4.208 V charge clamp are already correct; there is no user-space thermal daemon by design; analysis only, nothing changed — [docs/thermal.md](docs/thermal.md) |
| Suspend | `deep` unsupported by firmware; only `s2idle` available, screen-off power not measured |
| Storage / disk layout (Plan A) | **done and accepted**: Waydroid images deleted and former Android partitions reused for `/var`, `/home` and a 256 MB swap; the 9.7 GB root partition now has **4.0 GB free (58 %)** where it had 851 MB. `/var` has 2.4 GB free; `/home` was tight (19 MB free) and was then relieved by moving the media trees (`Pictures`, `Videos`, the gallery cache) onto `/var` and bind-mounting them back, so applications keep their paths: `/home` now has **211 MB free (56 %)**, and the bind mounts are active after a reboot. The layout uses `nofail`; the first reboot after the storage move needed a power cycle and that risk is open. No partition paths or identifiers are published — [docs/hardware-status.md](docs/hardware-status.md) |

Details and the exact evidence boundary: [docs/hardware-status.md](docs/hardware-status.md).
What is still open, ranked by daily-driver impact: [docs/gap-audit.md](docs/gap-audit.md).
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
docs/                         hardware status, camera and video (two source lineages), front camera, Venus, Store and OSIAL, SMS reception, auto-rotate, sensors, app acceptance, upstream adoption, recovery, GNSS client, Waydroid, boot time, performance, thermal, safety, native Android applications (ATL), the compatibility factory, and the ranked gap audit
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

- No binaries, images, kernel packages, firmware, APKs or built logs.
- No credentials, network profiles, host names, machine identifiers or personal
  paths.
- No RTC write patch: it is unsafe on this hardware.
- No third-party Windows Phone screenshots: the WP study is published as short facts with source links only.
- Rejected or unaccepted experiments are not published as features; where a
  source delta has real value but no acceptance, it lives under `experimental/`
  with its limitation stated.

## Licence

Original adaptation material: GPL-3.0-or-later. Patch files are derivative works
of the projects they modify and keep those projects' terms — userspace patches
GPL-3.0-or-later (upstream is GPL-2.0-or-later), kernel patches GPL-2.0-only.
`NOTICE.md` and `PROVENANCE.md` state which file is under which terms; the root
`LICENSE` does not relicense third-party code.
