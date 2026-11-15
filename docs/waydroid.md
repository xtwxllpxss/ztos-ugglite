# Waydroid freeze policy — prepared helper kit, not installed

Waydroid is **unverified** on this device ([hardware status](hardware-status.md)):
it has not been exercised end to end, and the full ztOS Android stack
(`launch`, `recover`, session/boot units, images) is not present. This file
documents one prepared, host-tested helper that closes exactly one defect —
Android freezes on screen-off and never thaws — and states everything it does
not fix.

Status of the kit: **prepared, host-only**. Nothing was installed or started on
the phone; the device needs its planned reboot first. This is a design and
verification record, not a claim that Waydroid works.

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
(`lxc-info` `STOPPED`/unreadable, like Waydroid's own `helpers.lxc.status()`).
A boot guard (`sys.boot_completed`) and a launch marker/push-hold deferral keep
a freeze out of container start and launch. Exit codes: `0` applied/deferred/no
container, `1` requested state not confirmed (ztmetro then logs "did not
confirm"), `2` usage error.

Three overlay files are installed: the helper in `/usr/local/bin`, a sudoers
template (`@DESKTOP_USER@`) allowing only `--apply 0` and `--apply 1`, and a
user oneshot unit that is inert without the saved state file. The installer
also writes `persist.waydroid.suspend=false` into `waydroid.cfg` and
`waydroid_base.prop` — that property takes effect at the next container start
(for a running session, only `waydroid prop set persist.waydroid.suspend false`
does). Rollback thaws first, then restores the files and configs.

## Acceptance (still to do)

On a rebooted device with an initialised Waydroid:

1. `waydroid status` shows `Session: STOPPED`, `lxc-info … -n waydroid -sH`
   agrees.
2. The verifier reports `0 failed`, and `sudo -n -l` for the desktop user shows
   both allowed helper invocations.
3. Android boots with `sys.boot_completed=1` (the launcher is not part of this
   kit; the session is started manually for the test).
4. Policy without a screen: `active` then `idle` gives `cgroup.freeze=1` and
   `lxc-info` `FROZEN`, then `active` gives `0`/`RUNNING`; the journal shows
   `frozen: cgroup.freeze 0 -> 1` and `thawed: cgroup.freeze 1 -> 0`, and a
   repeated `idle` writes nothing.
5. `waydroid app list` / `waydroid app launch <pkg>` opens and responds. (The
   launch command itself thaws the container; that is expected and does not
   replace the helper.)
6. Main criterion: an Android app in the foreground, screen off → the ztmetro
   log says `Waydroid screen-off policy completed` (not "did not confirm") and
   `cgroup.freeze=1`; screen on with app focus → `cgroup.freeze=0` and the app
   responds. Repeat 2–3 times.

## Limits and risks

- **Only the freeze policy.** It does not add `ztos-waydroid-recover`,
  `ztos-waydroid-launch`, session/boot user units or stripped images. Without
  them, launching an Android app from a ztmetro icon does not work; the helper
  only keeps a manually started container from getting stuck frozen.
- **Version contracts.** Freeze/thaw commands were checked against Waydroid
  1.6.3-1 and LXC 1:7.0.0-2 (Arch, aarch64): `waydroid container
  freeze|unfreeze` and `lxc-freeze|lxc-unfreeze -P /var/lib/waydroid/lxc -n
  waydroid`. A `pacman -Syu` can update either; re-run the verifier and the
  freeze/thaw test after an upgrade. Both CLI commands busy-wait without their
  own timeout, so they are always called under `timeout`, with the `lxc-*`
  fallback behind them.
- **`perfd` writes `cgroup.freeze` directly** with the same lock. It is not
  expected to thaw a background app today, but a journal review is the first
  step if an unexpected thaw appears.
- **No launch marker on the device.** Because `ztos-waydroid-launch` is absent,
  nothing writes the launch marker; the first `idle` is therefore done manually
  only after `sys.boot_completed=1`.
- **Disk.** The full upstream installer cannot run on this unit: it copies a
  1.99 GB `system.img` with 1.6 GB free. This kit does not touch images or
  userdata; its backup is about 10 KB.
- The kit scripts and overlay are not part of this repository: they carry
  device-transport specifics and unpublished local paths. This document records
  the design and the boundary; the exclusion is stated in [MAP](../MAP.md).
