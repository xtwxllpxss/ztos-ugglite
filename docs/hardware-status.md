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
  in-process facing switch. Preview orientation/mirroring, the larger modes
  (1296×972/2592×1944) and AE remain unaccepted, and a front node delays the
  rear graph because CAMSS has a single async notifier.
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
  candidate is published as a source patch, unmeasured on the sensor.
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

Three documents record host-only work that has **not** been applied to the
device. None of them is an installed feature, a measured improvement or an
accepted change.

- **Splash holds for ~51 s.** The measured figure is compositor-internal: the
  splash is removed at 51.0 s because a boot gate waits up to 45 s for a
  Waydroid/Android readiness marker that this install never writes (the upstream
  boot integration is not installed; the Waydroid configuration exists, so the
  "not installed" branch is false). Sensor readiness is not the blocker. A
  host-built compositor candidate removes the Android wait (51 s → ~6 s
  expected, arithmetic on the saved log); it is not installed and was never run
  on the phone. Pre-compositor boot time is not measured. Details, A/B and
  rollback: [boot time](boot-time.md).
- **Memory and browser.** zram (900 MB, `lz4`, `swappiness=100`) is active; the
  prepared changes are three sysctl values and one Firefox policy file, all
  reversible and none applied — [performance and memory](performance.md).
- **Thermal and charging.** The vendor trip points (75/85/100 °C) already match
  the stock device tree, there is no user-space thermal daemon by design, and
  charging is clamped to 1 A / 4.208 V. Analysis only, no change made —
  [thermal and charging](thermal.md).

## Unverified

- Waydroid: not exercised end to end. Only the prepared freeze-policy helper
  exists, and it is not installed ([Waydroid](waydroid.md)).
- Anything not listed above. No claims.

## Evidence

Patch-level provenance (base commits, hash chains, what was measured and under
which conditions) is in `SERIES.md` and `PROVENANCE.md`. Build-time `not_verified`
lists live with each recipe in `build/`. This file deliberately does not carry
session logs, boot identifiers or per-run sysfs values: the status is the stable
part, the run detail is not.
