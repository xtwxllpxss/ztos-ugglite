# Hardware status — Xiaomi Redmi Note 5A (ugglite)

Last updated from the hardware session that booted the ztOS baseline
`4fed0f289ce6f739b2151326400b22d2aece7e63be2e11bba1d1c2392aad5faf`, plus a
later session that trialled a replacement UI build hot-swapped into the running
system without a reboot (display section below).
Everything below is either observed on the phone or explicitly unverified; there
is no third category. "Works" means observed in that session, not guaranteed to
survive a rebuild.

## Verified

- **Boot.** lk2nd hands over to a host-assisted RAM candidate; the kernel is
  `7.1.3-msm89x7`, the DTB is `qcom/msm8917-xiaomi-ugglite.dtb`. Userspace
  reached greetd and the SSH service over USB.
- **Display — not accepted.** The last display candidate used the accepted
  `panel-xiaomi-ugglite-otm1901a-tm` module and the driver bound; the connector
  briefly reported `connected / enabled / dpms=On`, then went Off on its own and
  the user saw a **black screen**. The visible acceptance therefore failed, and a
  rollback to the baseline image completed; the device owner confirmed the baseline display works. Binding
  is not a working display and is not reported as one. Earlier notes that called
  the panel "usable for a text/graphical session" are superseded by this run.
  The baseline display was later confirmed working by the device owner, and no
  display candidate has passed visible acceptance since.
- **Brightness control from the UI — not working (regression).** In the later
  hot-trial session a replacement UI/compositor build was installed into the
  running system (no reboot) and exercised. The owner reports that dragging the
  screen-brightness slider produces stutter/jitter and **the brightness does not
  change**. The compositor path does reach logind and the kernel backlight and
  writes the expected values (50 % → 128, 65 % → 166, 77 % → 196 raw), so the
  failure is downstream of the write or in the compositor's own slider handling,
  not a permission error. An earlier `EACCES` on the same control was a separate
  issue; a permission fix was never a brightness fix and was not shipped as one.
  A sysfs write that returns success is **not** evidence that the slider works.
  A rollback of that single binary to the previous build was in progress when
  this was written and had not been re-verified; nothing here should be read as
  "fixed" or "rolled back cleanly".
- **Audio (stock path).** Playback reaches the speaker sink and produces sound,
  with audible hiss while idle. This is the state today.
- **Wi-Fi.** The wcn36xx path associates and passes traffic in the tested
  conditions, with limitations: rate/throughput behaviour under load is not
  fixed, and no patch for it is included in this repository.
- **Touch keys, haptics, settings identity.** Accepted patches for the Goodix
  touch keys (navigation, home key behaviour), haptic feedback and the settings
  identity strings were built and installed during bring-up; the patches kept
  here are the ones that were accepted.

## Broken or unsafe

- **RTC write.** Writing the hardware clock is unsafe on this device. Two
  capture attempts lost the SSH session around the write, and the root cause
  (PMIC reset vs. wrong offsets vs. driver behaviour) is **not established**.
  Absence of a panic in the SSH stream proves nothing. Do not write RTC.
  No RTC patch is included in this repository.
- **Audio replacement (C2).** An alternative UCM/PipeWire lifetime approach was
  rejected on hardware: the ACP registry is not shared with the PCM in the
  PipeWire process, so required-open returns `-ENODEV`. It was fully rolled back.
  No C2 material is included, and it should not be reintroduced as a "fix".
- **Display diagnostic image.** A RAM probe image built during display
  diagnostics unconditionally executed `reboot -f` after 120 s and risked
  returning to Android with the wrong expectations. It is not part of this
  repository and must not be rebuilt from these notes.

## Not verified — no claims

- **Modem / telephony.** No call, SMS or data session was verified. Do not
  assume a working modem because firmware files or drivers exist.
- **Camera.** No capture was verified end to end.
- **Suspend / resume.** Not verified. Idle power behaviour is unknown.
- **GPU acceleration.** freedreno/Adreno 308 is present in the kernel
  configuration; a rendered desktop was not benchmarked and no 3D claim is made.

## Boundaries that matter for reproducibility

- The installed root lives in `userdata`. There is **no rollback image** and no
  supported way back to Android from this repository.
- No binaries, images, firmware blobs, kernel packages, private network
  configuration, credentials or raw hardware logs are published here.
- The pinned upstream revisions in `ATTRIBUTION.md` are the ones the notes were
  written against; they are not a guarantee that a rebuild today produces the
  same image.
