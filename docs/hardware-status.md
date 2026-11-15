# Hardware status — Xiaomi Redmi Note 5A (ugglite)

Conservative statement of what has been observed on the device. "Works" means
observed in a hardware session, not guaranteed to survive a rebuild. Everything
not listed as verified is unverified, including things that look like they should
work.

## Verified

- **Boot, persistent.** The boot slot carries lk2nd followed by a ztOS payload
  written once; the stock boot image is backed up on the host for rollback.
  Host-free reboots reach ztOS: kernel `7.1.3-msm89x7`, DTB
  `qcom/msm8917-xiaomi-ugglite.dtb`, userspace on an internal ext4 root that
  reaches greetd and an SSH session over USB. RAM candidates (`fastboot boot`)
  remain the way to test a different kernel/DT without touching the slot.
- **Display and battery.** The owner confirmed smooth brightness adjustment
  without frame shift on the accepted DSI video-clock build. The userspace
  battery indicator is visible after discovery by power-supply type.
- **Rear camera.** The driver verified S5K3L8 chip ID `0x30c8`; the complete CSI
  graph delivered 1280×720 RAW10 buffers. The camera application was extended
  for multiplanar RAW10 and 180° rotation, and the installed binary
  (`94fd6c3a…`) is reproducible from the published
  [camera-application patch](../patches/userspace/ztcamera/); the device owner
  reports the camera working. The 1280×720 sensor path measured 119.44 fps, and
  a userspace vertical-blanking cap in a candidate application build measured
  29.84 fps with exposure up to 1/30 s; that build is not installed. Colour
  calibration, AE/ISO, AF feel and 720p30 recording are **not** accepted, and
  night frames stay dark on the installed build (the 1280×720 mode clamps
  exposure to 1/120 s). Sensor modes, recording ceilings and the pacer defect:
  [camera and video](camera-video.md).
- **Front camera.** The out-of-tree S5K5E8 driver
  ([devices/…/front-camera/](../devices/xiaomi-ugglite/front-camera/)) loaded
  against the accepted kernel, read chip ID `0x5e80` over CCI1, and CAMSS bound
  both sensors (`s5k3l8 → csiphy0`, `s5k5e8 → csiphy1`, links enabled). A
  640×480 SGRBG10 capture produced exactly 384000 bytes and cleaned up. The
  owner reports the front camera working through the camera application's
  in-process facing switch. The application's `Loading…` failure was diagnosed,
  fixed and accepted: the installed preview delivers live `/dev/video1` frames
  at 640×480 and about 62 fps (binary after the fix `c2a28339…`; the previous
  `ea79a1c8…` is kept as a backup). Preview orientation/mirroring, the larger
  modes (1296×972/2592×1944) and AE remain unaccepted, and a front node delays
  the rear graph because CAMSS has a single async notifier. Details:
  [front camera](front-camera.md).
- **Rear torch.** A DT-only `gpio-leds` node `white:torch` on `gpio34`
  (`gpio33` held low, `max_brightness=1`) booted in the RAM candidate
  `6995175f…` — that payload is now the installed boot slot — and appeared as
  `/sys/class/leds/white:torch`. `72-ugglite-torch.rules` makes its `brightness`
  `root:alarm 0664`, which is the access ztmetro's flashlight tile needs. The
  GPIO mapping (`gpio33` = flash-enable, `gpio34` = flash-now) is
  vendor-derived, not measured; the node is a plain on/off LED, not a mainline
  flash driver, so there is no strobe, current or duration control.
- **Wi-Fi.** The `wcn36xx` path associates and passes traffic in the tested
  conditions. Rate and throughput under load are not fixed; that limitation is
  part of the current state, not a pending claim.
- **Audio.** The stock path reaches the speaker and produces sound, with audible
  hiss while idle. That is the state today. The UCM that produces it is published
  under `devices/xiaomi-ugglite/audio/`; its playback gain (`RX1/RX2 Digital
  Volume`, 1 dB per step, 84 = 0 dB) is written once per verb, and the owner
  accepted 104 (+20 dB) without distortion. 120 (+36 dB) is what the published
  file sets; 124 is the codec maximum and was not accepted. The same verb sets
  `ADC1 Volume 6`, the stock Android active capture gain (stock boot default 4;
  6 is the stock ceiling). Incoming-call audio was accepted separately; the
  `Voice Call` use case that routes it is published alongside.
- **Touch keys and haptics.** Goodix navigation, the Home-key pulse and the
  settings identity strings were built, installed and accepted during bring-up.
  The non-grabbing key mapper that feeds the physical keys into that navigation
  is published under `devices/xiaomi-ugglite/units/`.
  The haptic pulse itself was **not** measured by feel; it was accepted on the
  owner's report that the delivered build behaves.
- **Modem — registration and accepted consumers.** On the persistent install the
  MSS firmware runs, `qcom_bam_dmux` binds, QRTR/`rmtfs` serve the modem's
  storage from a RAM shadow, WWAN DPM and a USIM are selected, and ModemManager
  reports `state=registered`, LTE, `registration=home`. The device owner
  confirmed the operator name and four bars in the UI. Two device-specific
  requirements were found: without USIM selection this unit reports sim-missing
  although the card is present, and without WWAN DPM ModemManager creates no
  modem object. Accepted separately: an incoming call with ringtone, call
  screen, answer and voice both ways; SMS reception importing messages into
  ztOS; data off/on and autoconnect. Outgoing calls are untested, SMS sending
  fails with RP cause 38, WWAN data is unclaimed (tariff allow-list). Recipe,
  service split and scope limits: [modem.md](modem.md). How received messages
  actually travel (QMI WMS, not AT), what a stuck `(receiving)` object means and
  a host-verified dedupe candidate for the receive daemon are in
  [SMS reception](sms.md); that candidate is not installed.
- **GNSS engine.** Enabling `gps-raw`/`gps-nmea` produces NMEA; a satellite was
  received (SNR 31). No fix indoors is expected. No user-space client is
  installed yet; a prepared GeoClue client kit is documented, not installed:
  [GNSS client](gnss.md).
- **Offline time.** `swclock-offset` keeps system time correct with NTP masked by
  storing `UTC − raw RTC` and only *reading* the RTC. Verified with
  `NTPSynchronized=no` and `swclock boot rc=0`; the system clock stayed within a
  second of the host. A PMIC power loss or RTC reset can invalidate the stored
  offset and upstream 0.3.0 does not detect it.
- **Updates.** `ztos-update check` completes and reports pending packages;
  `apply` upgrades with a single `pacman -Syu` transaction. The earlier version
  refreshed with `pacman -Sy` and upgraded with `pacman -Su` in a separate run,
  which is a partial upgrade.

## Not accepted / broken

- **Historical display regression.** Earlier replacement modules produced a
  black screen or failed to change visible brightness. Those builds were
  rolled back. The accepted DSI video-clock build supersedes those results.
- **Experimental panel patch.** A minimal error-path delta (restore
  `MIPI_DSI_MODE_LPM` before the DCS-write error return) loads as a module and
  changes nothing in the success path. It is published under
  `patches/kernel/experimental/` with no brightness claim.
- **Audio, replacement path.** A different UCM/PCM lifetime design was rejected
  on hardware: the ACP static registry is not shared with the PCM in the
  PipeWire process, so required-open returns `-ENODEV`. It was rolled back and
  must not be reintroduced as a fix.
- **Video recording tempo.** A 30 fps sensor rate is achievable from userspace
  (measured 29.84 fps in a candidate build), but recording is still not 30
  unique frames/s: the CPU x264 encoder accepts about 19 fps at 720p and 29 fps
  at 540p, the single-threaded application already runs at 89–95 % of one core,
  and the pacer fills late slots with duplicate frames. Measured recordings
  carry 11–14 unique frames/s in a 30 fps container. None of the measurement
  builds is installed. Numbers: [camera and video](camera-video.md).
- **Recording pacer defect.** When it falls behind, the pacer writes duplicate
  frames through the same pipe and does not write the skipped slots, so a clip
  is 1.4–1.7× shorter than the recording and plays faster than real time. This
  is independent of resolution. The retime candidate was rebased onto the live
  application line and is published as a host-verified candidate
  ([`0004-pacer-retime.patch`](../patches/userspace/ztcamera/)); it has not been
  run on the phone (see [two source lineages](camera-video.md#two-source-lineages)
  and [SERIES](../SERIES.md)).
- **Low-light exposure, installed build.** In the 1280×720 mode the driver
  clamps exposure to 1/120 s until vertical blanking is raised, so night frames
  are dark and noisy. The candidate build raises vertical blanking and reaches
  1/30 s; it is not installed.
- **Camera quality.** Colour calibration, AE/ISO, AF feel and front-preview
  orientation/mirroring. A host-only candidate adds fixed ISO/shutter environment
  overrides for calibration; it is not installed and was not measured on the
  sensor, so no manual-exposure claim is made, and its source line is not part of
  this repository (see [camera and video](camera-video.md)). The AF settle/boost
  candidate is published as a source patch, unmeasured on the sensor; a separate
  retry-based build from the local camera line is installed and measured — see
  the camera update at the end of this file.
- **Microphone.** The capture route is proven; gain candidates
  (`ADC1 Volume` 6→8, `TX1 Digital Volume` 84→88) are not accepted.
- **SMS sending.** Fails with RP cause 38. The SIM reports an FDN lock, which is
  the leading configuration candidate; the modem/network cause is not proven.
- **WWAN data.** A bearer comes up and addresses/routes are handed out, but
  HTTPS probes time out. The tariff uses allow-lists, so this is not claimed
  either way.
- **Venus hardware video encode — not integrated.** Driver and DT node are
  enabled. The stock `modem` partition carries the Venus firmware and
  `firmware_class.path` points there, but the boot-time probe runs before that
  partition is mounted and fails after `-ENOENT`. Reloading the core module in a
  running boot makes the probe pass and registers the decoder/encoder nodes, and
  a synthetic 1280×720 H.264 encode through the encoder node completes and
  decodes back. The camera application does not use it, reboot-time persistence
  was not tested, and the firmware is proprietary and not published:
  [Venus](venus.md). The source fix for the HFI 1xx/3xx property bug that blocks
  the stock encoder is published as a candidate kernel patch
  (`patches/kernel/0003-venus-hfi3xx-skip-h264-8x8-transform.patch`): it applies
  to the pinned tree and the Venus directory cross-builds, but it was never
  built into a full kernel, booted or measured on the device. `venus` is a
  module, so the fix does not need a rebuilt Image at all — the 2026-11-15
  module build produced `venus-core.ko` with the running kernel's vermagic and
  an identical symbol set; those modules were built host-side, are not
  published and were never installed or loaded (details in
  [Venus](venus.md#the-fix-is-one-module-replacement--no-image-rebuild)). A
  camera-side recording backend that feeds the encoder exists as a host-only
  candidate and is not published (see [MAP](../MAP.md)). Recording still uses
  the software encoder.
- **Suspend and automatic brightness.** `deep` is not supported by the firmware
  (PSCI reports `NOT_SUPPORTED`); only `s2idle` is available and screen-off draw
  is not measured. An ambient-light channel does not exist, so automatic
  brightness is not possible. Auto-rotate is not wired into the shell.

## Unsafe

- **RTC write.** Writing the hardware clock is unsafe on this device: two capture
  attempts lost the SSH session around the write, and whether the cause is a PMIC
  reset, wrong offsets or driver behaviour is **not established**. Absence of a
  panic in the stream proves nothing. No RTC patch is published.

## Prepared install kits — not installed

Two kits are prepared and host-tested, and neither has been installed or run on
the device. They are recorded as discrete status, not as features:

- **GNSS client** (GeoClue + ModemManager): seven files, package prerequisite
  `geoclue`, D-Bus-activated and off at rest. Not installed; first run and a
  street fix are pending — [GNSS client](gnss.md).
- **Waydroid freeze policy helper**: closes the screen-off freeze that never
  thaws. It does not add the missing launch/recover/session units, so it is not
  "Waydroid support" — [Waydroid](waydroid.md).

The kit scripts are not part of this repository; [MAP](../MAP.md) states why. A
separate opt-in 180° auto-rotate candidate exists on the host, but it is an
installable binary whose base is not reproducible from the published series and
its orientation polarity is unproven, so it is deferred rather than published;
the shell does not rotate today. Its design, acceptance boundary and risk are in
[auto-rotate](auto-rotate.md).

## Host-only analyses — not applied

Two documents record host-only work that has **not** been applied to the device.
Neither is an installed feature, a measured improvement or an accepted change.
(The splash work that was in this list is now installed and accepted; it moved to
the update section at the end of this file.)

- **Memory and browser.** zram (900 MB, `lz4`, `swappiness=100`) is active; the
  prepared changes are three sysctl values and one Firefox policy file, all
  reversible and none applied — [performance and memory](performance.md).
- **Thermal and charging.** The vendor trip points (75/85/100 °C) already match
  the stock device tree, there is no user-space thermal daemon by design, and
  charging is clamped to 1 A / 4.208 V. Analysis only, no change made —
  [thermal and charging](thermal.md).

## Unverified

- Waydroid: removed by the owner's decision on 2026-11-15; its freeze-policy
  helper is no longer installed ([Waydroid](waydroid.md)).
- Anything not listed above. No claims.

## Evidence

Patch-level provenance (base commits, hash chains, what was measured and under
which conditions) is in `SERIES.md` and `PROVENANCE.md`. Build-time `not_verified`
lists live with each recipe in `build/`. This file deliberately does not carry
session logs, boot identifiers or per-run sysfs values: the status is the stable
part, the run detail is not.

## Update 2026-11-15

- **Front camera:** `Loading…` fixed and accepted; live `/dev/video1` preview at
  640×480, about 62 fps — [front camera](front-camera.md).
- **Store and OSIAL:** not broken. The Store renders package lists and the only
  visible failure is DNS for `pkgstats.archlinux.org`; OSIAL dumps 13 interfaces
  in 1.9 s — [Store and OSIAL](store-and-osial.md).
- **Sensors:** the sensor data path is verified, but rotation in the compositor
  is not implemented and the ROTATION LOCK tile is a stub — [sensors](sensors.md).

## Update 2026-11-15 — second pass

- **App bar:** the combined build (`356ac939…`, top bar for foreign applications
  only) was installed and accepted; a bottom-position A/B build (`6ad8529e…`)
  was tested on the phone, and the owner then chose **`appbar=off`** — no bar is
  shown now. `ztcalculator` keeps a single header (`af5c345f…`, accepted by
  frame). The Windows Phone study is published as facts with source links only —
  [applications and UI](apps.md).
- **Theme:** GTK3/GTK4, Qt and Firefox theme delivery is installed and verified;
  before/after frames of galculator and featherpad confirm it — [applications and
  UI](apps.md).
- **Files:** open-with is fixed through `mimeapps.list` and `.desktop` entries;
  text opens in featherpad, images in swayimg, `gio mime` confirms — [applications
  and UI](apps.md).
- **Gallery:** v2 installed (folders/albums, video with posters and durations,
  day grouping); scroll and gesture builds are candidates — [applications and
  UI](apps.md).
- **Rear camera incident:** a stale `ztcamera` and a broken media graph
  (`STREAMON` `EPIPE`) stopped the rear camera; restarting the camera path
  restored a 1280×720 preview at about 21 fps. An automatic-reset resilience
  launcher kit is built, not installed — [camera and video](camera-video.md).
- **Colour:** AE/AWB v2 metrics pass on frames (rear R/G cast 1.138→1.011, front
  1.152→1.050, meanY stable, sdY 12.4→3.9), but the live candidate `9344a13e…`
  segfaulted in `color_auto_wb`; the camera was rolled back to the accepted
  `94fd6c3a…` and this work is paused — [camera and video](camera-video.md).
- **720p30:** hardware (Venus) encode was **not accepted** — the trial stalled
  (107/300 frames, `-110`) and was rolled back. Software candidate `9f3491c4…`
  (RAW→NV12, no BGRA) is built and not installed; a Venus ftrace plan exists —
  [Venus](venus.md).
- **Storage (Plan A):** Waydroid removed; former Android partitions reused for
  `/var`, `/home` and a 256 MB swap; the 9.7 GB root partition now has **4.0 GB
  free (58 %)** where it had 851 MB. `/var` has 2.4 GB free; `/home` was tight
  (19 MB free) at this point and was relieved later the same day — see the third
  pass at the end of this file. The first reboot needed a power cycle — that risk
  is open. No partition paths or identifiers are published.
- **Android apps:** Waydroid removed by owner decision. The ATL feasibility note
  at this point said binder is not a blocker and packaging (Alpine/musl vs
  Arch/glibc) is; the later native result supersedes the packaging question —
  see "Native Android runtime (ATL)" in the third pass and
  [Android applications](atl-native.md).
## Update 2026-11-15 — third pass

### Boot time and splash — installed and accepted

The compositor on the phone now removes its boot splash at **6.306 s** on its own
clock instead of 51.047 s. The 51 s was a readiness gate waiting for an
Android/Waydroid marker that this install never writes; the installed build only
waits when that integration is present. Both numbers are compositor-internal:
"power button to usable UI" is still not measured, and the pre-compositor boot
(lk2nd → kernel → initramfs → systemd → greetd) has no `systemd-analyze` sample.
The owner confirmed the change. No compositor binary or patch is published — the
base is the local fade-tuned compositor line; details in [boot time](boot-time.md).

### Boot observability — 2026-11-15

Reason: this device has no pstore/ramoops, so a boot that dies before the disk
leaves no trace — and one earlier boot needed a power cycle with no journal
surviving it. What is installed:

- three marker units: `early` (before local-fs), `mid` (after local-fs) and `ok`
  (after multi-user, the session manager and NetworkManager, waiting up to 30 s
  for a Wi-Fi IPv4 address). Each writes a stage line with a boot id, mount
  sources/labels, failed units, `findmnt --verify`, `systemd-analyze`, the SSH
  listener, sessions, the media bind mounts, swap and the boot-list revision;
- the primary record goes to `/boot` on the root filesystem, which no mount
  covers; `/var/log/boot-health/` is the readable copy, with a fallback to a
  volatile directory when `/var` itself did not mount;
- fstab timeouts for the extra filesystems raised to 10 s, and the media bind
  mounts ordered after `/var` with `x-systemd.requires-mounts-for=/var` (the
  previous `x-systemd.device-timeout` on bind entries was meaningless — a bind
  mount has no device unit);
- a session ordering drop-in so the session starts after `/home` and `/var`.

One supervised reboot produced all three stages, with `ok` about **56 s** after
boot start; mounts, the SSH wildcard listener and the session were all recorded.
A boot that dies before the markers no longer overwrites the previous boot's
records, which is what makes the next failure classifiable. Raw health logs are
not published (they encode this install's partition identity).

### Software renderer — 2026-11-15

The compositor can render with pixman (CPU) instead of GLES2, selected by
`WLR_RENDERER=pixman` in the session environment. Installed as a candidate; GLES2
stays the default for a normal session.

- Before the change, opening a GL surface from an Android application could take
  the compositor down with a GPU reset. Under pixman there were **0** GPU resets
  and the compositor stayed up (CPU about 8 %, resident about 104 MB).
- A follow-up build fixed three defects of the software path: a 120-row black
  band at the bottom (the lock screen was left in a slid-up position), the lock
  screen staying drawn over an application, and unlock. The bottom
  fully-black-row count went **120 → 0**. The lock screen now unlocks on a
  **real finger swipe**; synthetic control-protocol swipes do not unlock on the
  software path, which is a limitation of the test method, not of the device.
- Not owner-accepted as the default renderer.
- No compositor binary, source delta or kit is published: the base is the local
  fade-tuned compositor line — see [MAP](../MAP.md).

### Native Android runtime (ATL)

Android applications run natively through ATL as ordinary compositor clients —
no container, no Android image, no root, no second kernel. The image had been
trimmed in a way that removed the Java runtime tree and the JNI bridge; both were
restored from the image's own package store and `ztos-android doctor` reports
OK. Observed on the phone: the demo APK, an expression evaluator, a Canvas game
and the RPN calculator work; timerdroid runs with stub-only content; Frozen
Bubble opens a black DMA-BUF page; 2048 is blocked on a native JNI symbol; Angry
Birds reaches its GL thread but gets no EGL context. Full status, the API-batch
numbers and the structural limits: [Android applications](atl-native.md); the
method behind the batches: [compatibility factory](compat-factory.md).

### Notifications, layer 1

The framework path (application → NotificationManager → GNotification → D-Bus →
notification daemon → compositor banner and centre, tap → launch/focus) is
implemented and host-verified. The daemon and the notification-aware API jar are
installed, but the compositor build carrying the banner was replaced by the
software-renderer build, and the probe APK hit a stub-shadowing defect, so
**end-to-end on the phone is not proven.** Limits: no action buttons in the
shell, cold-start taps drop intent extras, icons come from the desktop entry,
channels/priority/sound are stored but not enforced —
[Android applications](atl-native.md#notifications--layer-1).

### Wi-Fi SSH persistence

The SSH unit used to bind address-specific sockets at start, so after a boot in
which the interface had no IPv4 address yet there was no usable entry — the
documented "device is up and in the network but there is no entry" state. The
installed unit now listens on a wildcard address (`0.0.0.0:2222`) and survives a
reboot: after the test reboot the session was back in about **12 s** and the
wildcard listener was present. The USB path still works. No address, SSID, key or
unit file is published.

### Home space and media bind mounts

`/home` was at 19 MB free (97 % used) after the storage change. `Pictures`,
`Videos` and the gallery cache were copied to the `/var` filesystem and
bind-mounted back, with three fstab entries marked as one block; application
paths are unchanged. Verified after a reboot: the mounts are active and the
gallery starts. `/home` is now at **211 MB free (56 %)**. No partition paths,
UUIDs or fstab contents are published.

### Camera — 2026-11-15, evening

- **Colour v3.1 installed and measured on the phone:** 0.0 % clipped pixels, no
  pink cast, about 21 fps in good light. The earlier AE/AWB v2 frame metrics
  (rear R/G 1.138→1.011, front 1.152→1.050, meanY stable, sdY 12.4→3.9) were the
  host-side measurement this build came from.
- **Autofocus:** the retry build is installed. It stops scoring a frame until the
  lens has moved (the previous sweep scored a frame exposed *before* the move),
  and in the 20 cm measurement it selected the real focus peak — about position
  300, where the old sweep chose 458 and was about 32 % softer. Debug lines are
  available in the application log.
- **Low light:** in a dark room autofocus is cancelled because the frame is dark
  (mean level 0.002, gain ramps to 512, about 1 fps); a low-light AE branch is in
  progress.
- Colour-calibration acceptance, AE/ISO acceptance and AF feel remain
  unaccepted: these builds are installed candidates, not accepted features.

### Open gaps

The ranked top-10 list of what still stands between this port and a daily phone:
[gap audit](gap-audit.md).
