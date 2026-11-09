# Provenance and licence boundaries

Rule applied to every file here: **the repository's own `LICENSE` never
relicenses someone else's code.** Per-area terms:

| Area | Upstream terms | What this repository may claim |
|---|---|---|
| `ztmetro`, `ztsettings` patches | `SPDX-License-Identifier: GPL-2.0-or-later` in the upstream files (ztOS also ships a GPL-3.0 text at its root) | derivative under `GPL-3.0-or-later` by taking the "or later" option; upstream copyright stays with the ztOS authors; hunk bytes unchanged |
| kernel patches (`patches/kernel/**`) | Linux kernel, `GPL-2.0-only` | same terms, nothing additional granted; the "or later" option does **not** exist for the kernel tree, so no GPL-3.0 labelling is applied to it |
| `build-environment/*` (Dockerfile, prepare/finalize, repack) | original work of this project | `GPL-3.0-or-later` |
| `devices/xiaomi-ugglite/*` | original work, except patches | `GPL-3.0-or-later` |
| lk2nd, pmaports, firmware, kernel binaries | upstream projects | not redistributed here; referenced by URL + tag only |
| docs (`README*`, `docs/**`, `SERIES.md`, `MAP.md`, `PROVENANCE.md`, `NOTICE.md`) | original work of this project | `GPL-3.0-or-later`; no upstream text is relabelled |

Unknown or unclear licence → **excluded**, with the reason written down in
`MAP.md`, never guessed into a licence header.

## What each added file is, and how it was derived

* `patches/userspace/ztmetro/0001-…` — copy of the already-published patch, plus
  the SPDX header the earlier publication prepended. Content otherwise
  byte-identical (verified with `cmp` against the working copy).
* `patches/userspace/ztmetro/0002-…` — copy of
  `devices/xiaomi-ugglite/patches/ugglite-wifi-bars.patch` (the version still
  published at the device path) with a header noting its series position and the
  before/after source hashes. Hunk bytes unchanged.
* `patches/userspace/ztmetro/0003-…` — copy of
  `devices/…/ztmetro-brightness-no-frame-per-tick.patch`, hunk bytes unchanged.
  It was staged as experimental at first, then moved into the series: applying
  0001–0003 reproduces the accepted source `e5fde72c` exactly, so it is required
  to reproduce the accepted binary, not an optional experiment. It is not a
  brightness fix claim.
* `patches/userspace/ztmetro/0004-…` — the working copy
  `devices/…/ztmetro-goodix-home-haptic.patch` (sha256
  `12c69ab5fc89f22e68ce379cac43f7edd0d0b8ee17810fab8c477bd10858af6f`) with a
  header stating the series position, base and result source hashes. Hunk bytes
  unchanged; the full series was applied end to end in this pass and lands on
  `954fce92`.
* `patches/userspace/ztmetro/0005-…` — working copy of
  `ztsettings-ugglite-identity.patch`, unmodified.
* `patches/userspace/ztmetro/experimental/zrnvibe-ff-rumble.patch` — working
  copy, unmodified, out of the default series: no accepted-build evidence in
  this pass.
* `patches/kernel/0001-…` — working copy of `wcn36xx-start-rate-0.patch` plus a
  `GPL-2.0-only` header. The stale `/* MCS 5 */` trailing comment is
  **preserved**, not fixed, so the hunk stays byte-identical to the one that was
  measured. The header also names the upstream tree, tag and file and states
  that the original copyright is retained and none is claimed by this project.
* `docs/BUILD-AND-BOOT.md` — the build/boot recipe, written here. Staged as
  `build/BUILD-AND-BOOT.md` first; moved because `build/` is ignored by the
  public repository's `.gitignore`, so a plain `git add` would have dropped it
  without a sound.
* `docs-public/*` — proposed replacements for the public `README.md`,
  `README.ru.md` and `docs/hardware-status.md`; original work, no upstream text
  copied into them.
* `patches/kernel/experimental/panel-otm1901a-lpm-errorpath.diff` — copy of the
  one-hunk diff from `build/display-minimal-lpm-fix/`, with base and patched
  source hashes. The full patched `.c` is not shipped: it is a generated kernel
  file, regenerable from the pinned tree plus this diff.
* `build-environment/*` — verbatim copies. No host path, container name,
  credential or SSH alias was introduced; the scripts were checked for
  `/Users/…` and other personal paths and contain none.

## Provenance of the measurements quoted in `SERIES.md`

Quotes are copied from the working notes, not re-measured:

* haptic rebuild determinism — `build/touchkey-home-haptic/HASHES.txt`
  (`accepted-rebuild.log` byte-identical to the accepted build log);
* wcn36xx 67–80 % / 0 % loss — the patch's own commit message
  (`devices/…/wcn36xx-start-rate-0.patch`), 690 frames, one AP and one station;
* LPM module load without a visible brightness change —
  `build/display-minimal-lpm-fix/manifest.json`, `not_verified` block.

If any of these need to be restated publicly as a current fact, they should be
re-measured; here they are attributed, not asserted.

## Provenance of the modem / offline-time material

* `docs/modem.md` — original English text written for this repository from the
  device work notes. It is not a translation of upstream documentation and copies
  no upstream prose.
* `devices/…/overlay/usr/local/libexec/msm-modem-uim-selection` and
  `msm-modem-wwan-port` — taken from postmarketOS/msm-modem at
  `5f504e0677f40dec93018d53a9b71aa1931db238` (GPL-3.0-or-later). They keep the
  upstream SPDX line and the commit they came from in their headers; the only
  local change is the `operating mode=online` step after USIM selection, which is
  visible in the file. `LICENSES/GPL-3.0-or-later.txt` ships the licence text.
* `devices/…/overlay/usr/local/sbin/swclock-offset-{boot,shutdown}` — from
  postmarketOS/swclock-offset 0.3.0, GPL-3.0-or-later; upstream copyright header
  retained verbatim.
* `devices/…/overlay/usr/local/sbin/ugglite-modem*`, the systemd units and
  `build-environment/build-ugglite-modem.sh` — original work for this device,
  GPL-3.0-or-later like the rest of the device layer.
* The build script fetches rmtfs `b30a3eb3…` and qrtr `29e36ae1…` (both
  BSD-3-Clause) and fails if the resolved commit differs. Their source is not
  vendored here; the licence of any binary produced from them stays BSD-3-Clause,
  and no such binary is shipped.
* The rebuilt `rmtfs` hash quoted in `docs/modem.md` is copied from the delivery
  log of the accepted build, not recomputed for this repository.

## Display, camera and battery milestone

- Userspace 0006 copies the accepted battery discovery delta against the pinned
  ztOS source under the same userspace patch terms as 0001–0005.
- Kernel 0002 copies the DSI video-clock delta under GPL-2.0-only.
- The camera directory carries device-tree fragments from the accepted camera
  graph work. It contains source and binding notes only.
- `devices/xiaomi-ugglite/front-camera/` — original GPL-2.0-only driver code
  written for this device. `s5k5e8_modes.h` holds functional register values
  extracted from the stock `libmmcamera_s5k5e8_*_d6.so` for interoperability;
  no code or data structure from that binary is redistributed beyond those
  register settings, and `front-stream.dtsi` is a restatement of a booted
  decompiled delta, not a decompiled dump.
- The source preparation script archives the pinned upstream and applies the
  public series. It does not redistribute upstream binaries.
- `devices/xiaomi-ugglite/audio/` — UCM written for this device from the working
  mixer state; GPL-3.0-or-later like the rest of the device layer. It contains
  control names and values, no upstream text. The capture gain
  (`ADC1 Volume 6`) is the stock Android active value (stock boot default 4),
  not a new measurement.
- `devices/xiaomi-ugglite/units/ugglite-touchkey-navd.py` and
  `ugglite-touchkey-nav.service` — original work, GPL-3.0-or-later.
- `devices/xiaomi-ugglite/torch/{72-ugglite-torch.rules,zt-flashlight,install-torch.sh,rollback-torch.sh}`
  — original work, GPL-3.0-or-later. `torch.dtsi` is GPL-2.0-only like the
  kernel tree it is included in: a readable restatement of the booted
  decompiled DT delta. The GPIO numbers and the vendor driver's en/now
  semantics come from the vendor DT and driver, not from upstream code copied
  here.
- `devices/xiaomi-ugglite/front-camera/{install,rollback}-front-camera.sh`,
  `ugglite-front-preview`, `ugglite-front-camera.desktop` — original work,
  GPL-3.0-or-later. They carry no host path and no device identifier; the
  module hash they check is the build published in this directory's source.
- `upstream-lock.json` — a publication copy of the project's own lock: the
  host-environment block and the references to unpublished local scripts were
  removed. Commit hashes and URLs are facts, not upstream files.
