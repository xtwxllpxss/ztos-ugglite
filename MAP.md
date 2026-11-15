# Map — every working component → public path, or why it is excluded

The point of this file is that nothing disappears silently. Left column is the
local component (`build/…`, `devices/…`), right column is where it goes in the
public repository or why it does not go there at all.

## One authority

`patches/userspace/ztmetro/` (0001–0006) and `patches/kernel/0001`–`0002` are the only
series to apply. `patches/userspace/ztcamera/0001` is a single composed delta with
its own section in `SERIES.md`, not part of that series. `patches/kernel/0003`
is a candidate kernel delta: it is published for review, not part of the
accepted kernel state. The device-layer copies
named below stay published for the release that shipped them, but they are
mirrors, not a second series: applying both double-applies 0001–0003 and the
haptic hunk. `SERIES.md` states this first.

## Published (staged here, with provenance)

| Local component | Public path | Notes |
|---|---|---|
| `devices/xiaomi-ugglite/patches/ztmetro-native-goodix-nav.patch` | `devices/xiaomi-ugglite/patches/0001-…` | already public; kept, byte-identical apart from the SPDX header |
| `build/touchkey-home-haptic/0002-…` / `devices/…/ztmetro-goodix-home-haptic.patch` | `…/patches/0004-ztmetro-goodix-home-haptic.patch` | **new**; series position, base and hash chain in `SERIES.md` |
| `devices/…/ugglite-wifi-bars.patch` | `…/patches/0002-ztmetro-ugglite-wifi-bars.patch` | **new** (series copy; the device copy stays) — required to reproduce the accepted source |
| `devices/…/ztmetro-brightness-no-frame-per-tick.patch` | `…/patches/0003-…` | **new series position**; required to reproduce the accepted source, explicitly *not* a brightness fix |
| accepted camera application (`build/camera-inprocess-2026-11-09/ztcamera.c`) | `patches/userspace/ztcamera/0001-ztcamera-ugglite-accepted.patch` | **new**; composed delta, target and hash chain in `SERIES.md`; rebuild from it gives the installed ELF |
| `devices/…/patches/kernel/venus-hfi3xx-skip-h264-8x8-transform.patch` | `patches/kernel/0003-venus-hfi3xx-skip-h264-8x8-transform.patch` | **new candidate**; one-line upstream-proposed fix, applies/reverts and the Venus directory cross-builds, full kernel not built, never booted |
| GNSS client kit (`devices/xiaomi-ugglite/gnss/`, the GeoClue overlay files it installs, and its host-side report) | `docs/gnss.md` | **new**; the design, install/verify/rollback shape and the prepared-not-installed boundary, in English. The scripts and overlay are not published — see the exclusion table |
| Waydroid freeze-policy kit (`devices/xiaomi-ugglite/waydroid/` and its host-side report) | `docs/waydroid.md` | **new**; what the helper fixes and, explicitly, what it does not (no launch/recover/session units). Scripts and overlay not published |
| `devices/…/ztsettings-ugglite-identity.patch` | `…/patches/0005-…` | **new** |
| `devices/…/wcn36xx-start-rate-0.patch` | `…/patches/kernel/0001-…` | **new**; measured bounds kept verbatim |
| `build/display-minimal-lpm-fix/panel-lpm-errorpath.diff` | `…/patches/kernel/experimental/` | **new**, experimental, not in the default series |
| `build-environment/Dockerfile` | `build-environment/Dockerfile` | **new**; makes the build image reproducible from this repo |
| `build-environment/prepare-kernel.sh`, `finalize-kernel.sh` | `build-environment/` | **new**; pinned pmaports HEAD, refuses drift, verifies signature |
| `build-environment/repack-boot-init.py` | `build-environment/` | **new**; boot image repack used for RAM candidates |
| `build/public-source-expansion/docs/BUILD-AND-BOOT.md` | `docs/BUILD-AND-BOOT.md` | **new**; staged under `build/` at first, moved because the repository's own `/build/` ignore rule would hide it |
| `build/public-source-expansion/docs-public/{README.md,README.ru.md,hardware-status.md}` | `README.md`, `README.ru.md`, `docs/hardware-status.md` | replacements, copied individually — not a directory export |
| `manifest.json`, `README.md` and the audit report of the staging tree | — | staging metadata; never published |
| `devices/xiaomi-ugglite/{device.toml,layer.sh,fixups.sh,overlay,packages.txt}` | already public | unchanged |
| `patches/ztconflo/000{1,2,3}-*.patch` | `build/` … | build-driver patches already pinned in `ATTRIBUTION.md`; unchanged |

| `devices/xiaomi-ugglite/modem/README.md` | `docs/modem.md` | **new**; rewritten in English for the public docs set, technical content unchanged. The local README keeps session notes and is not copied verbatim |
| `devices/xiaomi-ugglite/overlay/etc/systemd/system/{ztos-modem,ztos-modem-storage,msm-modem-*,ugglite-modem-status,swclock-offset-*}.{service,timer}` + enabling symlinks | same paths | **new**; the units that produce the verified `registered/home` state, including the `.requires/` and `.wants/` links — without them the overlay does not enable anything |
| `devices/xiaomi-ugglite/overlay/usr/local/{sbin/ugglite-modem,sbin/ugglite-modem-status,sbin/swclock-offset-boot,sbin/swclock-offset-shutdown,libexec/msm-modem-uim-selection,libexec/msm-modem-wwan-port}` | same paths | **new**; verbatim. `libexec/*` are the postmarketOS GPL-3.0-or-later helpers at the pinned commit, with their SPDX headers intact |
| `build-environment/build-ugglite-modem.sh` | `build-environment/build-ugglite-modem.sh` | **new**; fetches the pinned rmtfs/qrtr revisions, verifies the checkout, installs only the binary. No host path inside |
| `research/ugglite-next-plan.md` | `docs/next-plan.md` | **new**; the prioritised work order, rewritten for publication. Not a verbatim copy: internal paths, candidate sha prefixes and the working-diary framing were dropped |
| `research/ugglite-next-plan.md` (raw), `START-HERE.md`, `research/*` | — | still excluded: device identifiers, boot ids, SSIDs, MACs, host paths and session diary. Only the plan's technical content is published, in `docs/next-plan.md` |
| `research/ugglite-camera-fps-budget.md`, `build/camera-live-test-2026-11-15/RESULT.md`, `build/dark-record-2026-11-15/RESULT.md`, `build/record-tuning-2026-11-15/RESULT.md` | `docs/camera-video.md` | **new**; measurements only, rewritten without run logs, boot ids, host paths, per-run hash tables or the recording control commands |
| `research/ugglite-venus-firmware.md`, `build/venus-load-test-2026-11-15/`, `build/venus-encode-2026-11-15/` | `docs/venus.md` | **new**; firmware discovery, probe chain and the synthetic encode in prose. Firmware blobs, installer/runner scripts, host paths and raw dmesg dumps are excluded |

## Excluded, with the reason (not a judgement on the work)

| Local component | Reason |
|---|---|
| `build/*/ztmetro` (1.45–1.5 MB aarch64 ELF) | binary; regenerated from the published source. Shipping it would make the repo a binary dump |
| `build/*/out/*.img`, `boot.img`, `lk2nd-msm8952-23.1.img`, `*.apk`, `*.ko`, `*.ko.zst` | images/binaries; bootloader and kernel are pinned upstream tags |
| `build/kernel/artifacts`, `build/cache*`, `build/downloads` | build output, firmware APKs, mirrors of upstream releases |
| `upstream/` clones (ztOS, pmaports, lk2nd, ztconflo, ztos-devices) | `.git` trees; pinned by URL + commit instead. No `.git` is copied anywhere |
| `devices/…/patches/rtc-allow-set-time.patch` | RTC write is unsafe on this device (two lost SSH sessions, cause unestablished). Publishing it invites data loss; excluded from the default series **and** from the repository |
| `devices/…/patches/zrnvibe-ff-rumble.patch` | no accepted-build evidence in this pass; staged as `experimental/` until someone confirms the build it went into |
| later UI build `ab8` / its haptic-and-brightness follow-ups | the UI build whose slider regressed on hardware; a binary, and not a source delta anyone accepted. Rolled back; not published as ready |
| `build/audio-*` (C2, c1, alternative-gain, afe-fix) | C2 was rejected on hardware (ACP registry not shared with the PCM → `-ENODEV`); the rest are probes, not accepted deltas |
| `build/audio-*/…` UCM patches that stayed in `build/` | same reason; "static registry" experiments are not support |
| `build/ugglite-rescue`, `install-file-rootfs.sh`, `package-userdata-prep.sh`, `ugglite-remote.py`, `ssh_config` | installer / userdata-write / remote-control material: separate scope, contains host and transport specifics. Architecture is described in docs, not shipped |
| `build/ugglite-modem-correction*/diff.patch`, `audio-afe-fix/dt-inr-fix.patch` | modem path unverified on hardware; DT change not accepted |
| `build/display-rollout`, `display-bl-fix`, `display-ui-*` patches | superseded display experiments, some produced a black screen; keeping them invites "try this" |
| `build/*/REPORT.md`, `DELIVERY.md`, `VALIDATOR.md`, `build.log`, `*.txt` hashes of local runs | session diary; the technical content is folded into `docs/hardware-status.md` and `SERIES.md` |
| `evidence/`, `research/`, `START-HERE.md` | internal log with device identifiers, boot ids, SSIDs, MACs and personal paths |
| `devices/…/overlay/etc/ssh/*`, `ztos-ssh-start`, `wpa_supplicant`/network profiles | credentials and transport configuration |
| `devices/…/overlay/usr/local/sbin/zboot-usb-gadget` | already public at HEAD; unchanged here (no new audit was done). `ztos-update` is updated separately below |
| firmware (`firmware-qcom-msm89x7` contents), `*.mbn`, `*.elf` | binary firmware, redistributed by pmaports under its own terms |
| `build/venus-fw-hunt-2026-11-15/overlay/usr/lib/firmware/venus.{mdt,b00..b04}` | proprietary Qualcomm firmware; redistribution is not permitted. Only file names, sizes and the stock-partition location are described in `docs/venus.md`. No blob, hash list or copy recipe is published |
| `build/venus-fw-hunt-2026-11-15/{install,rollback}-venus-fw.sh`, `build/venus-encode-2026-11-15/*.sh` | host/stand paths and phone-state automation (`modprobe`, `scp`, rollback, dmesg marks); not a publishable recipe, and it would ship paths to unpublished local payloads |
| `build/venus-encode-2026-11-15/*.{h264,png,ko,zst}`, `build/dark-record-2026-11-15/*.{mkv,png,ppm}`, `build/record-tuning-2026-11-15/*.{mkv,log}`, `build/record-tuning-2026-11-15/ztcamera-*` | encoded clips, captures, modules and run logs; the stable technical content is in `docs/camera-video.md` and `docs/venus.md`, the artifacts are not publication material |
| `build/venus-encode-2026-11-15/venus-enc-patched*`, `build/camera-venus-record-2026-11-15/venus-enc-patched-unsigned.ko` | the NOP-neutralised `venus_enc` module: a diagnostic binary that disables one error check, not a fix. The source fix is published as `patches/kernel/0003`; a pre-built module would be a "load this" invitation with no source relation |
| `devices/xiaomi-ugglite/patches/camera/venus-m2m-record-candidate.patch`, `build/camera-venus-record-2026-11-15/src/camera/{venus_m2m.c,venus_m2m.h}`, its build/install/rollback/morning scripts and the `ztcamera-*venus` binary | camera→Venus recording backend. Unit-tested against a mock V4L2 loop but never run on the device; the app delta is against an unpublished 720p30 candidate source line and needs ~920 lines of new encoder-client code that exists only as a host-tested candidate. Publishing a patch that cannot apply to any published source, next to unreviewed 920 lines, would not be a reproducible delta. The status is recorded in `docs/venus.md` |
| `build/camera-pacer-fix-2026-11-15/pacer-fix.patch`, `{ztcamera.c,ztcamera.c.orig,offline/,*.mkv,*.sh,ztcamera-720p30-pacerfix}` | recording-timeline retime candidate. It was built and offline-verified on the `camera-v3`/`0742a21d` source line, which is **not** the live application line (`166d8d04`); it needs a rebase and a rebuild on the live line before any install, and its duration numbers come from that other lineage. Publishing it as a ready candidate would invite installing it over the live app. Deferred; status in `docs/camera-video.md` |
| `build/camera-exposure-controls-2026-11-15/0001-fixed-exposure.patch`, `src/`, `ztcamera-720x1280-30fps-fixed` | host-only calibration candidate against the same unpublished 720p30 source line; never built against the accepted source and never measured on the sensor. The candidate boundary is in the docs, the delta is not published |
| `devices/xiaomi-ugglite/{gnss,waydroid}/**` (scripts, overlay, run logs) | prepared kit scripts. They carry device-transport specifics and unpublished local payload paths. The design and status are published as `docs/gnss.md` and `docs/waydroid.md` |
| `build/auto-rotate-2026-11-15/**` (the patched ztmetro binary, its patch, install/rollback scripts and run logs) | opt-in 180° rotation kit. The binary's base is a locally built, fade-tuned ztmetro that is not reproducible from the published series, and the orientation polarity was never observed on the device; it is an installable-candidate kit with an unproven base, so it is deferred rather than published. The unrotated shell state stays as stated in `docs/hardware-status.md` |

## Display, battery and camera build inputs

| Component | Public path |
|---|---|
| Exact ztMetro source preparation | `build-environment/prepare-userspace.sh` |
| Accepted battery discovery | `patches/userspace/ztmetro/0006-ztmetro-battery-discovery.patch` |
| DSI video clock preservation | `patches/kernel/0002-dsi-preserve-video-clocks.patch` |
| CSI controller, sensor and endpoint sources | `devices/xiaomi-ugglite/camera/` |
| Front S5K5E8 V4L2 subdev + booted DT delta | `devices/xiaomi-ugglite/front-camera/` |
| Front-camera status boundary | `devices/…/front-camera/README.md`, `docs/hardware-status.md` |

## Userspace integration now published

| Component | Public path | Notes |
|---|---|---|
| Front-camera install kit | `devices/xiaomi-ugglite/front-camera/{install,rollback}-front-camera.sh`, `ugglite-front-preview`, `ugglite-front-camera.desktop` | **new**; installs the module with an sha256/vermagic gate, writes `modules-load.d`, helper resolves the video node from the media topology. The module binary is not shipped |
| Audio UCM | `devices/xiaomi-ugglite/audio/HiFi.conf`, `xiaomi-ugg.conf`, `VoiceCall.conf` | **new**; the stock-path verb/devices, the voice-call use case, gain contract and mixer-vs-sink scale in `audio/README.md`. `VoiceCall.conf` is the installed file (`df71fa27…`) |
| Installed-proven updater and offline-time write | `devices/…/overlay/usr/local/sbin/ztos-update`, `…/swclock-offset-shutdown` | **updated**; both files are byte-identical to the installed ones (`771698dd…`, `1e23420a…`). The updater upgrades in one `pacman -Syu` transaction and classifies offline failures; the shutdown helper writes the offset atomically |
| ModemManager enablement symlink | `devices/…/overlay/etc/systemd/system/multi-user.target.wants/ModemManager.service` | **fixed**; points at the absolute `/usr/lib/systemd/system/ModemManager.service`, matching the installed root. The previous `../ModemManager.service` resolved to a non-existent path |
| Touch-key nav mapper | `devices/xiaomi-ugglite/units/ugglite-touchkey-navd.py`, `ugglite-touchkey-nav.service` | **new**; physical Goodix keys → nav codes, non-grabbing, short/long decided by ztmetro. Not the same layer as `patches/userspace/ztmetro/0001` |
| Torch: DT fragment, helper, udev rule, install kit | `devices/xiaomi-ugglite/torch/` — `torch.dtsi`, `zt-flashlight`, `72-ugglite-torch.rules`, `install-torch.sh`, `rollback-torch.sh` | **new** in this pass; the rule and helper moved out of `units/` and now ship with the board DT fragment that creates `white:torch` on gpio34. The node was booted on the phone; the fragment restates that delta and is not a complete DTS |
| Machine-readable pins | `upstream-lock.json` | **new**; the local lock without the host block and unpublished script references |

## Still missing for an end-to-end build

These are the same gaps `docs/BUILD-AND-BOOT.md` lists; nothing here substitutes
for them:

1. **rootfs assembler** — the Arch Linux ARM tarball revision, package list and
   checksum are not pinned; `layer.sh` still needs a pre-existing root.
2. **boot image assembly** — no mkbootimg/initramfs composition; `repack-boot-init.py`
   only replaces `init` inside an image that someone else built.
3. **DT composition** — the board DTS lives in the kernel tree; the fragments here
   are deltas, not a complete DTS, and `front-stream.dtsi` and `torch.dtsi` were
   never compiled from the pinned tree.
4. **package manifest** — no pinned package set/versions for the root, no
   reproducible `pacman -Q` baseline.
5. **kernel patch application** — `prepare-kernel.sh` builds the pmaports kernel
   without `patches/kernel/0001`–`0002`; applying them is a manual step today.
   `patches/kernel/0003` is a candidate on top of that and is not part of any
   kernel recipe.
