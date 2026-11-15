# Waydroid freeze policy — installed and verified

Waydroid now runs on this device to a verified point: a session starts, Android
13 boots, a manually launched application draws a real window, and ztmetro's
screen-off policy completes instead of failing. This file documents the helper
that closes one defect — Android freezes on screen-off and never thaws — and
states exactly what is still missing. Status: **helper installed on the phone
and verified live**; images and userdata untouched; this is not a full Android
integration.

## The defect

The policy owner is ztmetro. It writes
`/run/user/1000/ztos-waydroid-power-state` (`active|idle|screen-off`) and calls
the helper synchronously before turning the display off; it logs
`Waydroid did not confirm screen-off freeze` when the call fails and
`Waydroid screen-off policy completed` when it succeeds. `zrn-pushd` asks the
same helper for a `sync` after a push (holding a push-hold file), and `perfd`
uses the same lock and writes `cgroup.freeze` itself.

Stock Waydroid freezes the container on its own: `persist.waydroid.suspend` is
unset, which means true, so after the display timeout Android calls
`IHardware.suspend` and the container manager runs `lxc-freeze`. That happens
outside ztOS policy. If no thaw path exists, the container stays `FROZEN`, the
app looks hung, and a freeze that lands during start/launch can leave LXC in
`FREEZING` (the "`container start` hangs" symptom). Upstream ztOS keeps
`persist.waydroid.suspend = false` for the same reason.

`binderfs` is not involved: the accepted 7.1.3 kernel has
`CONFIG_ANDROID_BINDER_IPC=y`, legacy `/dev/binder` nodes and no
`CONFIG_ANDROID_BINDERFS`; Waydroid 1.6.3 MAINLINE works with the legacy nodes.
No kernel or DT change is needed.

## What the helper does

It is a small root helper (`ztos-waydroid-power`) plus a narrow sudoers rule and
one user oneshot unit that applies the saved state at login. Actions:

| Action | What happens |
|---|---|
| `active` | thaw the payload if it is frozen: `waydroid container unfreeze`, else `lxc-unfreeze`, last resort write `0` to `cgroup.freeze` |
| `idle` / `screen-off` | freeze only if allowed: defer while the container is booting, launching or push-held; `waydroid container freeze` with a timeout, else `lxc-freeze`; verify `lxc-info` `FROZEN` / `cgroup.freeze=1` |
| `sync` | apply the saved state (used on focus/display changes and after a push) |

Freeze and thaw go through the LXC freezer (the same actions upstream
`recover.sh` uses), not a raw cgroup write; the cgroup write is only the last
resort for a thaw. The helper is idempotent (writes only on change), serialised
by `flock` on the same lock `perfd` uses, and a no-op when there is no container
(`lxc-info` `STOPPED`/unreadable). A boot guard (`sys.boot_completed`) and a
launch marker/push-hold deferral keep a freeze out of container start and
launch. Exit codes: `0` applied/deferred/no container, `1` requested state not
confirmed (ztmetro then logs "did not confirm"), `2` usage error.

Three overlay files are installed: the helper in `/usr/local/bin`, a sudoers
template (`@DESKTOP_USER@`) allowing only `--apply 0` and `--apply 1`, and a
user oneshot unit that is inert without the saved state file. The installer
also writes `persist.waydroid.suspend=false` into `waydroid.cfg` and
`waydroid_base.prop` — that property takes effect at the next container start.

## Verification on the phone (2026-11-15)

A dry run first (0 failures, installer plan and sudoers accepted, exactly one
line added to each config), then install with a backup, then a live run:

- helper sha256 `147cea27…`, sudoers `0440` with only the two allowed
  invocations, `visudo` clean, user unit enabled; `verify.sh` reported
  **12 passed, 0 failed**, twice; image mtimes unchanged.
- `waydroid session start` → `Session: RUNNING`, `Container: RUNNING`, LXC
  `RUNNING` within about **5 s**, payload cgroup present, `cgroup.freeze=0`.
- Android 13: `sys.boot_completed=1`; `waydroid app list` returns the preloaded
  applications; `waydroid app launch com.android.contacts` rc=0, and the Android
  Files window is actually drawn on the panel (screenshot checked); ztmetro logs
  `showing app 'Waydroid'`.
- `zrn-pushd`: 25 failures before the install, **0 after**; screen-off produces
  `Waydroid screen-off policy completed` instead of the error.
- The saved state applies: `persist.waydroid.suspend=false` is visible in the
  Android property store after the container start; cgroup freeze toggles
  `0 → 1` on idle/screen-off and `1 → 0` on active, and a push-hold defers a
  freeze.
- Cleanup: session stopped again, no stray processes, `systemctl`: failed
  units 0, display off; rollback tested as a dry run only (backups present,
  atomic restore path intact).

## What is still missing

- **No launch/recover units.** Upstream's `ztos-waydroid-recover` and
  `ztos-waydroid-launch` are absent, so `zrn-pushd` logs "command not found"
  every few minutes even with the helper installed, and launching an Android
  application from a ztmetro icon does not work; the tested path is a manual
  `waydroid session start` plus `waydroid app launch`. PR #13 (adopted except
  its camera hunks) is the upstream source of that missing lifecycle; not
  merged here yet. Launching Android from a ztmetro tile stays unimplemented and
  was not confirmed visually; the device owner deferred that work to the very
  end of the queue, so the helper remains installed but is not driven by a tile.
- **`systemui` ANR on 2 GB.** Android's launcher/system UI can hit an
  application-not-responding dialog on this memory size; the session continues
  but the window is behind it.
- **Screen-off start hazard.** A manual `waydroid session start` while the
  display is off (and no launch marker is written) is frozen by the policy
  about 8 s after the container starts; it reaches `boot_completed=1` only after
  an `active` state or a push-hold thaws it. This is the residual risk the
  launch marker in PR #13 removes.
- **One session, one boot.** The verification above is one boot and one session
  cycle, not a soak test.

## Limits and risks

- **Only the freeze policy.** It does not add session/boot user units or
  stripped images, and it is not Android application support in the product
  sense.
- **Version contracts.** Freeze/thaw commands were checked against Waydroid
  1.6.3-1 and LXC 1:7.0.0-2 (Arch, aarch64): `waydroid container freeze|unfreeze`
  and `lxc-freeze|lxc-unfreeze -P /var/lib/waydroid/lxc -n waydroid`. A
  `pacman -Syu` can update either; re-run the verifier and the freeze/thaw test
  after an upgrade. Both CLI commands busy-wait without their own timeout, so
  they are always called under `timeout`, with the `lxc-*` fallback behind them.
- **`perfd` writes `cgroup.freeze` directly** with the same lock. It is not
  expected to thaw a background app today, but a journal review is the first
  step if an unexpected thaw appears.
- **Disk.** The full upstream installer cannot run on this unit: it copies a
  1.99 GB `system.img` with about 1.6 GB free. This kit does not touch images or
  userdata; its backup is about 10 KB.
- The kit scripts and overlay are not part of this repository: they carry
  device-transport specifics and unpublished local paths. This document records
  the design, the verification and the boundary; the exclusion is stated in
  [MAP](../MAP.md). No image, module or installer is published.

## Evidence boundary

The verification facts above are live readbacks from the phone (session state,
Android properties, journal lines, cgroup values, screenshot). No boot ids,
host paths, session transcripts or screenshots are published. "Runs" here means
a manually started session with a launched application on one boot; it does not
mean a supported Android experience.
