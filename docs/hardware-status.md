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
- **Wi-Fi.** The `wcn36xx` path associates and passes traffic in the tested
  conditions. Rate and throughput under load are not fixed; that limitation is
  part of the current state, not a pending claim.
- **Audio.** The stock path reaches the speaker and produces sound, with audible
  hiss while idle. That is the state today.
- **Touch keys and haptics.** Goodix navigation, the Home-key pulse and the
  settings identity strings were built, installed and accepted during bring-up.
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

- Modem **data session/APN, SMS, calls, call audio and GNSS** (registration itself is listed above), camera preview and scene exposure, suspend, and anything not listed above. No claims.

## Evidence

Patch-level provenance (base commits, hash chains, what was measured and under
which conditions) is in `SERIES.md` and `PROVENANCE.md`. Build-time `not_verified`
lists live with each recipe in `build/`. This file deliberately does not carry
session logs, boot identifiers or per-run sysfs values: the status is the stable
part, the run detail is not.
