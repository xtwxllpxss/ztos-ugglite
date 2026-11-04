# Attribution and pinned revisions

The notes and patches were written against these exact upstream revisions. They
are recorded so a reader can reproduce the starting point, not as a claim that
the trees still build or that these are current upstream heads.

| Upstream | URL | Revision used | Licence |
|---|---|---|---|
| ztOS | https://github.com/Zerone-Laboratories/ztOS | `94b35c2a1f4ceb568bc0ab60f5a1acebe7cfefaf` (shallow) | `GPL-2.0-or-later` in the three modified source files (the repository root also ships a GPL-3.0 text) |
| postmarketOS pmaports | https://gitlab.postmarketos.org/postmarketOS/pmaports | `39fe8995ea485a798ac8f1eff091b3962352e791` | GPL-3.0 (packaging) |
| lk2nd | https://github.com/msm8916-mainline/lk2nd | `fd380ac637d1af38598e3f3c5321d4c962b96315` | GPL-2.0-only |

Relevant postmarketOS packages at that revision:

- device package: `device-qcom-msm89x7` (pkgver 8, pkgrel 0) — ugglite is not a
  standalone pmOS device; the generic MSM89x7 package ships its DTB pattern and
  the three ugglite panel modules.
- kernel: `linux-postmarketos-qcom-msm89x7` 7.1.3-r1, upstream tree
  https://github.com/msm89x7-mainline/linux at tag `v7.1.3-r1`.
- lk2nd subpackage for this SoC: `lk2nd-msm8952`.

## Patch provenance

All patches under `devices/xiaomi-ugglite/patches/` are local work derived from
ztOS source files whose SPDX headers say `GPL-2.0-or-later`, applied on top of
the ztOS revision above. They are distributed under GPL-3.0-or-later by
exercising that "or later" option; the upstream grant is not restated as GPL-3.0.
Each patch carries an SPDX/provenance header above its diff. "Accepted on
device" below means the patch was built and installed during bring-up; it does
not mean a visible effect was accepted, and the display candidate's visible
acceptance failed (see below). They are not upstream submissions and no pull
request exists for them here. Paths inside each patch are relative to the ztOS
source root, so `ztmetro/ztmetro.c` means `<ztOS>/ztmetro/ztmetro.c`.

| Patch | Upstream file(s) touched | Status |
|---|---|---|
| `ztmetro-native-goodix-nav.patch` | `ztmetro/ztmetro.c` | built and installed; visible effect not separately accepted |
| `ztmetro-brightness-no-frame-per-tick.patch` | `ztmetro/ztmetro.c` | built and installed; brightness UI still fails with `EACCES`, so no visible effect is claimed |
| `ztsettings-picker-open-frames.patch` | `ztmetro/core/zrnmetrocore.c` | built and installed; visible effect not separately accepted |
| `ztsettings-config-dir-mkdir.patch` | `ztmetro/settings/ztsettings.c` | built and installed; visible effect not separately accepted |
| `ugglite-wifi-bars.patch` | `ztmetro/ztmetro.c` | built and installed; Wi-Fi remains limited |

One kernel patch is included at `patches/kernel/0001-wcn36xx-dynamic-ra-start-rate.patch`
(GPL-2.0-only, one line; measured bounds in `SERIES.md`). The kernel tree
itself, the panel experiment and the RTC patch are not published — `SERIES.md`
and `MAP.md` state the reason for each.

## Device facts

- SoC: Qualcomm MSM8917, GPU Adreno 308 (freedreno).
- DTB: `qcom/msm8917-xiaomi-ugglite.dtb`, name confirmed from
  `lk2nd/device/dts/msm8952/msm8917-mtp.dts` (`lk2nd,dtb-files`).
- Panels present in the kernel package:
  `xiaomi,ugglite-otm1901a-tm`, `xiaomi,ugglite-ili9881c-sc`,
  `xiaomi,ugglite-otm1901a-hx`. The tm variant is the one whose module bound in
  the last hardware run; that run's visible acceptance failed (the screen stayed
  black). Baseline rollback completed and the device owner confirmed its display
  works; the replacement module remains rejected. "Bound" means the driver probe succeeded, not that the display
  was seen working.
- Boot chain: lk2nd → mainline kernel → host-assisted RAM root.
