# Hardware status — Xiaomi Redmi Note 5A (ugglite)

Conservative statement of what has been observed on the device. "Works" means
observed in a hardware session, not guaranteed to survive a rebuild. Everything
not listed as verified is unverified, including things that look like they should
work.

## Verified

- **Boot.** lk2nd hands over to a host-assisted RAM candidate; kernel
  `7.1.3-msm89x7`, DTB `qcom/msm8917-xiaomi-ugglite.dtb`. Userspace reaches
  greetd and an SSH session over USB. Nothing is flashed to reach this state.
- **Display and battery.** The owner confirmed smooth brightness adjustment
  without frame shift on the accepted DSI video-clock build. The userspace
  battery indicator is visible after discovery by power-supply type.
- **Rear camera capture.** The driver verified S5K3L8 chip ID `0x30c8`. The
  complete CSI graph delivered 1280×720 RAW10 buffers. Those buffers were
  almost black under the trial conditions. Scene exposure, continuous
  preview and camera application integration remain unverified.
- **Front camera identification.** The out-of-tree S5K5E8 driver
  ([devices/…/front-camera/](../devices/xiaomi-ugglite/front-camera/)) loaded
  against the accepted kernel, read chip ID `0x5e80` over CCI1, and CAMSS bound
  both sensors (`s5k3l8 → csiphy0`, `s5k5e8 → csiphy1`, links enabled). A
  640×480 SGRBG10 capture produced exactly 384000 bytes and cleaned up. This is
  identification plus one unbuffered capture, not front-camera support: preview,
  orientation, AE and the larger modes are untested, and the front node
  necessarily delays the rear graph because CAMSS has a single async notifier.
- **Rear torch.** A DT-only `gpio-leds` node `white:torch` on `gpio34`
  (`gpio33` held low, `max_brightness=1`) booted in the same RAM candidate as
  the front DT (`6995175f…`) and appeared as `/sys/class/leds/white:torch`.
  `72-ugglite-torch.rules` makes its `brightness` `root:alarm 0664`, which is
  the access ztmetro's flashlight tile needs. The GPIO mapping
  (`gpio33` = flash-enable, `gpio34` = flash-now) is vendor-derived, not
  measured; the node is a plain on/off LED, not a mainline flash driver, so
  there is no strobe, current or duration control.
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
  6 is the stock ceiling).
- **Touch keys and haptics.** Goodix navigation, the Home-key pulse and the
  settings identity strings were built, installed and accepted during bring-up.
  The non-grabbing key mapper that feeds the physical keys into that navigation
  is published under `devices/xiaomi-ugglite/units/`.
  The haptic pulse itself was **not** measured by feel; it was accepted on the
  owner's report that the delivered build behaves.

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

## Works — modem registration (no data claim)

- **Cellular registration.** After a RAM boot the MSS firmware runs, `qcom_bam_dmux`
  binds, QRTR/`rmtfs` serve the modem's storage from a RAM shadow, WWAN DPM and a
  USIM are selected, and ModemManager reports `state=registered`, LTE,
  `registration=home`. The device owner confirmed the operator name and four bars
  in the UI. Two device-specific requirements were found: without USIM selection
  this unit reports sim-missing although the card is present, and without WWAN DPM
  ModemManager creates no modem object. Recipe, service split, scope limits and
  licence pins: [docs/modem.md](docs/modem.md).
- **Offline time.** `swclock-offset` keeps system time correct with NTP masked by
  storing `UTC − raw RTC` and only *reading* the RTC. Verified with
  `NTPSynchronized=no` and `swclock boot rc=0`; the system clock stayed within a
  second of the host. A PMIC power loss or RTC reset can invalidate the stored
  offset and upstream 0.3.0 does not detect it.

## Unsafe

- **RTC write.** Writing the hardware clock is unsafe on this device: two capture
  attempts lost the SSH session around the write, and whether the cause is a PMIC
  reset, wrong offsets or driver behaviour is **not established**. Absence of a
  panic in the stream proves nothing. No RTC patch is published.

## Unverified

- Modem **data session/APN, SMS, calls, call audio and GNSS** (registration itself is listed above), camera preview and scene exposure, front-camera preview/orientation/AE, suspend, and anything not listed above. No claims.

## Evidence

Patch-level provenance (base commits, hash chains, what was measured and under
which conditions) is in `SERIES.md` and `PROVENANCE.md`. Build-time `not_verified`
lists live with each recipe in `build/`. This file deliberately does not carry
session logs, boot identifiers or per-run sysfs values: the status is the stable
part, the run detail is not.

## Update 2026-11-15 — state after the persistent install

This addendum supersedes the sections above where they conflict. It records what
changed after the boot slot was written and the install was used daily.

Verified since the previous revision:

- **Persistent boot.** The boot slot carries lk2nd followed by a ztOS payload;
  the stock boot image is backed up for rollback. Host-free reboots reach ztOS.
  RAM candidates (`fastboot boot`) remain the way to test a kernel/DT change
  without touching the slot.
- **Cameras in daily use.** The device owner reports both cameras working on the
  current firmware. Rear RAW10 1280×720 capture and the full CSI graph were
  verified earlier; the front sensor reads chip ID `0x5e80` with both links
  enabled. The torch works.
- **Calls and SMS reception.** An incoming call produced the ringtone, the call
  screen, an answer and voice in both directions; the owner accepted it. An SMS
  receive layer imports messages into ztOS. Data off/on and autoconnect are
  accepted.
- **GNSS engine.** Enabling `gps-raw`/`gps-nmea` produces NMEA; a satellite was
  received (SNR 31). No fix indoors is expected. No user-space client is
  installed yet.
- **Updates.** `ztos-update check` completes and reports pending packages;
  `apply` now upgrades with a single `pacman -Syu` (an earlier version ran
  `puacman -Su` in a separate run, which is a partial upgrade).

Still not accepted, and why:

- **Recording tempo.** Captured frames are fast enough (the sensor path was
  measured at about 119 fps in 1280×720), but the userspace CPU demosaic plus a
  15-fps pacer yields a 15-fps clip. A 720p30/24 build exists but is not accepted.
- **Low-light exposure.** In the 1280×720 mode the driver clamps exposure to
  1/120 s until vertical blanking is raised, so night frames are dark and noisy.
- **Camera quality.** Colour calibration, AE/ISO, AF feel and front-preview
  orientation/mirroring.
- **Microphone.** The capture route is proven; gain candidates
  (`ADC1 Volume` 6→8, `TX1 Digital Volume` 84→88) are not accepted.
- **SMS sending.** Fails with RP cause 38. The SIM reports an FDN lock, which is
  the leading configuration candidate; the modem/network cause is not proven.
- **WWAN data.** A bearer comes up and addresses/routes are handed out, but
  HTTPS probes time out. The tariff uses allow-lists, so this is not claimed
  either way.
- **Venus hardware video encode.** Driver and DT node are enabled, but the root
  filesystem carries no Venus firmware, so probe fails after `-ENOENT`. Software
  encode only.
- **Suspend.** `deep` is not supported by the firmware (PSCI reports
  `NOT_SUPPORTED`); only `s2idle` is available and screen-off draw is not
  measured. An ambient-light channel does not exist, so automatic brightness is
  not possible; auto-rotate is not wired into the shell.
