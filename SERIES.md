# Patch series, bases and pins

Every patch here is a real delta that was applied to a real tree. Nothing is a
reconstruction, and nothing was dropped for "not applying to clean upstream".

## One authority

`patches/userspace/ztmetro/0001`–`0006` is the **only** ztmetro series to apply.
`patches/userspace/ztcamera/0001` is the single composed camera-application delta
that reconstructs the accepted source; `0002`–`0004` are **candidates** that apply
on top of its result and are published for review, not as accepted state. None of
the camera patches is part of the ztmetro series or applied by
`build-environment/prepare-userspace.sh`. The camera candidates on the separate
`camera-v3` source line (fixed exposure, Venus M2M recording backend) are not
published: that source line is not reproducible from this repository — see
[docs/camera-video.md](docs/camera-video.md) and [MAP.md](MAP.md). The copies under
`devices/xiaomi-ugglite/patches/` are historical mirrors kept for the
device-layer release that already shipped them; do not apply both, or 0001,
0002, 0003 and the haptic hunk land twice. For the Wi-Fi kernel delta,
`patches/kernel/0001` is the only source — `devices/…/wcn36xx-start-rate-0.patch`
is its working copy, not a second patch to stack on top.

Numbering is repository-wide, not per directory: `ztsettings` lives in the
`ztmetro` source repository (`ztmetro/settings/ztsettings.c`,
`ztmetro/core/ztos-hw.h`), so 0005 legitimately sits in the `ztmetro` directory.

## Userspace — ztOS `ztmetro` / `ztsettings` (upstream GPL-2.0-or-later)

Upstream pin: `https://github.com/Zerone-Laboratories/ztOS` @
`94b35c2a1f4ceb568bc0ab60f5a1acebe7cfefaf`. Apply in this order from the
repository root with `patch -p1 < <file>`.

| # | File | Target | Effect |
|---|------|--------|--------|
| 0001 | `0001-ztmetro-native-goodix-nav.patch` | `ztmetro/ztmetro.c` | native Goodix nav keys |
| 0002 | `0002-ztmetro-ugglite-wifi-bars.patch` | `ztmetro/ztmetro.c` | signal bars for the wcn36xx path |
| 0003 | `0003-ztmetro-brightness-no-frame-per-tick.patch` | `ztmetro/ztmetro.c` | no full frame per brightness tick |
| 0004 | `0004-ztmetro-goodix-home-haptic.patch` | `ztmetro/ztmetro.c` | short haptic pulse on the Goodix Home key |
| 0005 | `0005-ztsettings-ugglite-identity.patch` | `ztmetro/core/ztos-hw.h`, `ztmetro/settings/ztsettings.c` | ugglite hardware identity strings |
| 0006 | `0006-ztmetro-battery-discovery.patch` | `ztmetro/ztmetro.c` | discover the battery through its power-supply type |

### The hash chain is the point

`ztmetro/ztmetro.c` through the series, measured in this staging pass by
applying the patches in order to the pinned upstream file:

| Step | sha256 of `ztmetro/ztmetro.c` |
|---|---|
| upstream `94b35c2a` | `e1acc7969c6d1d51634558721048d403d2bb0b24e33253ddc124a47b1eafec7d` |
| + 0001 | `bd8d036c4331c49c0a541c8f135e3c76bc5c62129943201ec928105dd6336d92` |
| + 0002 | `0cdd916c2c2f1139440645f3da9195ee18246dd8f8a2e821b1c1abc885450581` |
| + 0003 | `e5fde72c97963106f5e8d71c8283368d1b758c2e5014271a70f924bf69c07655` ← **accepted source** |
| + 0004 | `954fce92b2bb7e47a184fb92e897c6ab5b60eaee1c308cfc7e146db84207ccbd` ← **home-haptic source** |
| 0005 | header change only, `ztmetro.c` unchanged |
| + 0006 | `a41147d923a2309d28ee4eead5fe692dbf81f871a62f0f3d605eded0ee581852` ← **accepted battery source** |

Accepted source `e5fde72c` produced the accepted, user-approved binary
`14598ebed2f28cca393e50a0ff6ecff40f10c17aa7e9132166b191482bff40c0`
(1 485 640 B, installed). That source rebuilds **byte-identical** to it in the
same container with the same recipe (`build/touchkey-home-haptic/HASHES.txt`,
`accepted-rebuild.log`), so the binary is a function of this source, not of
toolchain drift.

The home-haptic binary `41f42ab841eac713705c42d2c3ef4c9030270feef62b0b7821c1c717aaf7d998`
(1 485 728 B) is that same tree plus the one hunk of 0004. No binary is
published; the source chain is.

### What 0004 actually changes

It only widens the guard that suppresses a nav-key pulse, so Samsung-style keys
still do not pulse on Home and Goodix keys do:

```c
- if (nav != NAV_START) {
+ if (nav != NAV_START || keyboard->nav_keys) {
```

Wi-Fi bars, brightness throttling and the native-nav composition are untouched
by that hunk. This is why the earlier publication was wrong to drop the haptic
change: it does not apply to pristine `ztmetro.c`, it applies to the composed
accepted tree — which is exactly what the table above reconstructs.

### Limits

- 0003 throttles redraws. The accepted smooth brightness behaviour also
  requires the kernel-side DSI clock change documented below.
- 0005 was accepted during bring-up per the historical status notes. On the
  pinned base `94b35c2a` it passes `patch -p1 --dry-run` with rc=0 and touches
  exactly `ztmetro/core/ztos-hw.h` and `ztmetro/settings/ztsettings.c`.
- `experimental/zrnvibe-ff-rumble.patch` has no accepted-build evidence in this
  pass and stays out of the series.

## Userspace — camera application `ztcamera` (composed delta, not a series)

Target: `ztmetro/camera/ztcamera.c` at the same upstream pin (`94b35c2a`). This
is one composed delta that reconstructs the accepted camera-application source;
it is not a linear series, and `build-environment/prepare-userspace.sh` does not
apply it (that script reads only `patches/userspace/ztmetro/000[1-6]-*.patch`).
From the root of the pinned ztOS checkout:

```sh
git apply patches/userspace/ztcamera/0001-ztcamera-ugglite-accepted.patch
```

| Step | sha256 of `ztmetro/camera/ztcamera.c` |
|---|---|
| upstream `94b35c2a` | `e1dd0e7b528daf1cbc33c74a20d650e25ee60d9836298b5b0346f112177dd1b5` |
| after the patch | `166d8d0490d328cf14ef7d173531eb9f24d94b7bb8450b64e2bb4ed566cacab0` ← **accepted source** |

The accepted source built the installed `/usr/local/libexec/ztcamera-ugglite`
(`94fd6c3aca38201f691ae4b2bdaba6dda33ac0c536651b18f2f204a160085578`,
804 016 B); the build was repeated and came out byte-identical
(`build/camera-inprocess-2026-11-09/RESULT.md`). The delta extends the
application for multiplanar RAW10 (`SGRBG10P`) capture from the CSI RDI node,
in-process front/rear switching and 180° rotation. It does **not** include the
wrapper `/usr/local/bin/ztcamera`, the `ugglite-camera-paths` setup/release
helper or the service that switch the media graph, so on a clean system this
patch alone is not "a working camera in daily use".

### Camera source lineages

The accepted application source `166d8d04` is the live line: it is what built the
installed ELF `94fd6c3a…`. The 720p30 build `acddafc9…` and the first
recording-pacer candidate were built from a **different** camera line
(`camera-v3` `3b3d1082…` + the 720p30 vblank cap → `0742a21d…`), which does not
carry the in-process/debounce/AF-dark work of the live line. The two are not
interchangeable and a candidate from one cannot be installed over the other.
`camera-v3` is a local development line and is not reproducible from this
repository, so the candidates that need it (fixed exposure, Venus M2M recording
backend) are not published; the lineage facts are in
[docs/camera-video.md](docs/camera-video.md). The candidates that *are* published
(`0002`–`0004`) run on the live line and apply on top of the accepted source —
see the next section.

## Userspace — camera application candidates (0002–0004, not accepted state)

These three patches are candidates. They apply in order on top of the accepted
composed delta `0001` and are **not** part of the accepted state: no candidate
build was ever installed or run on the phone. They are published because the
delta is real, the base is reproducible from this repository, and each one fixes
a measured defect.

Target: `ztmetro/camera/ztcamera.c` at the same upstream pin (`94b35c2a`).
`0001` is applied from the checkout root with `git apply`; `0002`–`0004` use
the camera kit's relative paths and are applied from the `ztmetro/` directory
with GNU `patch` (each file's header carries its own base, result and status):

```sh
git apply patches/userspace/ztcamera/0001-ztcamera-ugglite-accepted.patch
cd ztmetro
patch -p1 -F0 < ../patches/userspace/ztcamera/0002-sensor-720p30-cap.patch
patch -p1 -F0 < ../patches/userspace/ztcamera/0003-af-settle-boost.patch
patch -p1 -F0 < ../patches/userspace/ztcamera/0004-pacer-retime.patch
```

### The hash chain is the point

`ztmetro/camera/ztcamera.c` through the chain, measured by applying the
published files in order to the pinned upstream file:

| Step | sha256 of `ztmetro/camera/ztcamera.c` |
|---|---|
| upstream `94b35c2a` | `e1dd0e7b528daf1cbc33c74a20d650e25ee60d9836298b5b0346f112177dd1b5` |
| + `0001` (accepted) | `166d8d0490d328cf14ef7d173531eb9f24d94b7bb8450b64e2bb4ed566cacab0` ← **installed source** |
| + `0002` vblank cap | `5647a698e1db38b0af0c911a3ad2a0df1576c69bd9dbab3a6d7645dbcb17ebee` |
| + `0003` AF settle/boost | `4636d552fcd90000602513b8a520c9f746226f82e84635a4c94fd0ef269ed71d` |
| + `0004` pacer retime | `5846f8d64d3c5d44df09051df510162c5ed1fe439746ee2b41e533f28f35d1e7` ← **candidate source** |

Each patch applies with `-F0` (no fuzz, no offset) and its diff body is
byte-identical to the local camera kit copy it comes from.

### Candidate builds, and what is not published

Three candidate builds were made from this chain with the camera recipe; each
was built twice byte-identically and passed the host artifact check. The
binaries are not published ([MAP.md](MAP.md)):

| Candidate | Composition | Source sha256 | ELF sha256 | Size | On device |
|---|---|---|---|---|---|
| AF only | `0001` + `0003` | `c89b4c4873c6f0c0bf419fb2a9016cc4753bcc8a08e56dfb89e2a8d9d401e928` | `6cab0db057f8aa73eb56adabe16f7777bba0e1964760696b20cad6d909da5cca` | 803 224 B | never run |
| vblank + AF | `0001` + `0002` + `0003` | `4636d552fcd90000602513b8a520c9f746226f82e84635a4c94fd0ef269ed71d` | `4c7c86dfbd1b6ebf80b5d74dda15a36664f0584f8498b3401a1fc1972723af70` | 804 496 B | never run |
| vblank + AF + pacer | `0001` + `0002` + `0003` + `0004` | `5846f8d64d3c5d44df09051df510162c5ed1fe439746ee2b41e533f28f35d1e7` | `4011bccb870705f494a9d35738820df77cc6fc2e722d77010856fea9b14726cb` | 807 560 B | never run |

Evidence per patch, and its limit:

* `0002` — the cap was measured on the phone on the camera-v3 line: 119.44 fps
  before, 29.84 fps after, exposure maximum 804 → 3242 lines (1/30 s). On the
  live line the delta is host-verified only; the measurement is not repeated
  from this source line.
* `0003` — logic and disassembly reviewed host-side; the optical criteria
  (settle 170/280 ms, best-value spread, sweep duration) are a calculation and
  have never been observed on the sensor. AF feel is not accepted.
* `0004` — rebased onto the live line and checked offline on real clips:
  6.533 s of file retimed to 10.632 s against 10.633 s of wall clock, 196/196
  frames, decode rc=0. The live recording has not been made.

None of the three fixes the recording ceiling: unique frames per second stays
limited by the single-threaded application and the software encoder
([docs/camera-video.md](docs/camera-video.md)).

## Device layer — `ztsmsd` receive-dedupe candidate (not accepted state)

`devices/xiaomi-ugglite/phone-ui/ztsmsd` is the installed SMS receive daemon,
published verbatim (sha256
`b2786ed651973542c51f4cb7d828d6647d5e10ee060a2a26e047ffc550d46da8`, the
installed file). `devices/xiaomi-ugglite/phone-ui/ztsmsd-dedupe-v2.patch`
applies from the repository root with `patch -p1` and produces source sha256
`c8a704b45afcfeaa8a0eaea86ea6ac0e6222f17fb50091bbfaf2d5314db3caea`.

Status of that delta: **candidate**, host-verified against a fake ModemManager
(28 of 28 behavioural scenarios, including the two-different-messages-in-one-
second case and a poisoned empty-text dedupe key from the live state), never
installed on the phone. An earlier draft that dropped the message text from the
dedupe key could silently lose a message; it is not published, and this patch
replaces it. Why the receive path is QMI WMS rather than AT, and what a stuck
`(receiving)` object means: [docs/sms.md](docs/sms.md).

## Kernel — `linux-postmarketos-qcom-msm89x7` 7.1.3-r1 (GPL-2.0-only)

Upstream pin: `https://github.com/msm89x7-mainline/linux`, tag `v7.1.3-r1`,
packaged from pmaports `39fe8995ea485a798ac8f1eff091b3962352e791`.

| File | Target | Status |
|------|--------|--------|
| `0001-wcn36xx-dynamic-ra-start-rate.patch` | `drivers/net/wireless/ath/wcn36xx/smd.c` | measured on hardware, one line |
| `0002-dsi-preserve-video-clocks.patch` | `drivers/gpu/drm/msm/dsi/dsi_host.c` | accepted on hardware with the matching display modules and camera boot composition |
| `experimental/panel-otm1901a-lpm-errorpath.diff` | `drivers/gpu/drm/panel/msm89x7-generated/panel-xiaomi-ugglite-otm1901a-tm.c` | module loads; visible brightness NOT accepted |
| `0003-venus-hfi3xx-skip-h264-8x8-transform.patch` | `drivers/media/platform/qcom/venus/hfi_cmds.c` | **candidate**: host-only, cross-built, not booted (details below) |

`0003` is **not** part of the accepted kernel state. It carries the upstream
one-line fix that the subsystem maintainer proposed in the 2023 thread (list
`HFI_PROPERTY_PARAM_VENC_H264_TRANSFORM_8X8` as unsupported in the HFI 1xx
packetizer, so `venus_session_set_property()` skips it instead of failing
`VIDIOC_REQBUFS` on HFI 3xx). Host evidence: the patch applies and reverts
against the pinned tree and the isolated `drivers/media/platform/qcom/venus/`
directory cross-compiles for aarch64 (`LLVM=1`) with rc=0 and no warnings. It was
never built into a full kernel, never booted, and is not in mainline. It changes
nothing on a running device by itself. A full `Image` rebuild is also not the
only route: `venus` is built as a module, `hfi_cmds.o` is linked into
`venus-core.ko`, and a host-side module build produced a core module with the
running kernel's `vermagic` and an identical symbol set — see
[docs/venus.md](docs/venus.md#the-fix-is-one-module-replacement--no-image-rebuild).
Those modules are not published and were never installed or loaded. Background
and the block it removes: [docs/venus.md](docs/venus.md).

`0001` bounds, exactly as measured: WCN3620 on MSM8917/ugglite, one AP and one
station, 690 frames — stock firmware start rate (`133`, MCS5) lost 67–80 %, value
`0` ("no forced start rate") lost 0 %. TLV is
`WCN36XX_HAL_CFG_ENABLE_DYNAMIC_RA_START_RATE` (id 210); only the
`!RF_IRIS_WCN3680` table used by WCN3620 is touched. No claim is made for
WCN3680, other APs or sustained throughput. The stale `/* MCS 5 */` comment is
kept so the hunk stays byte-identical to the measured one.

`experimental/` is not part of the default series and is not brightness support:
the module was inserted into a running system, the panel showed no visible
change, and the error path (DCS write returning < 0) was never exercised.
Its header names the real kernel target (`a/drivers/…`, `b/drivers/…`), so
`patch -p1` from the kernel root addresses the intended file; the hunk itself is
unchanged from the experiment that was run.
