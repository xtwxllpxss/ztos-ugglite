# Patch series, bases and pins

Every patch here is a real delta that was applied to a real tree. Nothing is a
reconstruction, and nothing was dropped for "not applying to clean upstream".

## One authority

`patches/userspace/ztmetro/0001`–`0006` is the **only** ztmetro series to apply.
`patches/userspace/ztcamera/0001` is a single composed camera-application delta
with its own section below; it is not part of the ztmetro series and not applied
by `build-environment/prepare-userspace.sh`. The copies under
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

## Kernel — `linux-postmarketos-qcom-msm89x7` 7.1.3-r1 (GPL-2.0-only)

Upstream pin: `https://github.com/msm89x7-mainline/linux`, tag `v7.1.3-r1`,
packaged from pmaports `39fe8995ea485a798ac8f1eff091b3962352e791`.

| File | Target | Status |
|------|--------|--------|
| `0001-wcn36xx-dynamic-ra-start-rate.patch` | `drivers/net/wireless/ath/wcn36xx/smd.c` | measured on hardware, one line |
| `0002-dsi-preserve-video-clocks.patch` | `drivers/gpu/drm/msm/dsi/dsi_host.c` | accepted on hardware with the matching display modules and camera boot composition |
| `experimental/panel-otm1901a-lpm-errorpath.diff` | `drivers/gpu/drm/panel/msm89x7-generated/panel-xiaomi-ugglite-otm1901a-tm.c` | module loads; visible brightness NOT accepted |

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
