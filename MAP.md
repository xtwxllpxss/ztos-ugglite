# Map — every working component → public path, or why it is excluded

The point of this file is that nothing disappears silently. Left column is the
local component (`build/…`, `devices/…`), right column is where it goes in the
public repository or why it does not go there at all.

## One authority

`patches/userspace/ztmetro/` (0001–0005) and `patches/kernel/0001` are the only
series to apply. The device-layer copies named below stay published for the
release that shipped them, but they are mirrors, not a second series: applying
both double-applies 0001–0003 and the haptic hunk. `SERIES.md` states this first.

## Published (staged here, with provenance)

| Local component | Public path | Notes |
|---|---|---|
| `devices/xiaomi-ugglite/patches/ztmetro-native-goodix-nav.patch` | `devices/xiaomi-ugglite/patches/0001-…` | already public; kept, byte-identical apart from the SPDX header |
| `build/touchkey-home-haptic/0002-…` / `devices/…/ztmetro-goodix-home-haptic.patch` | `…/patches/0004-ztmetro-goodix-home-haptic.patch` | **new**; series position, base and hash chain in `SERIES.md` |
| `devices/…/ugglite-wifi-bars.patch` | `…/patches/0002-ztmetro-ugglite-wifi-bars.patch` | **new** (series copy; the device copy stays) — required to reproduce the accepted source |
| `devices/…/ztmetro-brightness-no-frame-per-tick.patch` | `…/patches/0003-…` | **new series position**; required to reproduce the accepted source, explicitly *not* a brightness fix |
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
| `devices/…/overlay/usr/local/sbin/ztos-update`, `zboot-usb-gadget` | already public at HEAD; unchanged here (no new audit was done) |
| firmware (`firmware-qcom-msm89x7` contents), `*.mbn`, `*.elf` | binary firmware, redistributed by pmaports under its own terms |
