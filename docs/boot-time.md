# Boot time — the ~51 s splash, its cause, and the candidate fix

The installed compositor keeps its boot splash on screen for about 51 s after it
starts. This file explains what that number is and is not, why the wait happens
on this device, and what a host-built candidate changes. Status: **analysis and
candidate, not installed**. No compositor binary and no compositor patch are
published here: the base source line is a locally built, fade-tuned compositor
that this repository's series does not reconstruct (see [MAP](../MAP.md) and
[SERIES](../SERIES.md)).

## What the 51 s is

The figure comes from the compositor's own log, from a saved boot of the
installed system. The compositor logs seconds since its own start, so this is
**not** "power button to usable UI":

| Segment | Time | Evidence in the saved log |
|---|---|---|
| compositor start to the readiness gate | ~2.1 s | mode-set 0.94 s, splash logo 1.21 s, application list 1.73 s |
| the readiness gate itself | 45 s (deadline) | `boot: readiness timed out after 45s, continuing` at 47.083 s |
| transition and splash removal | 3.94 s | `boot: transition complete, splash removed` at 51.026 s |

So 51.0 s = ~2.1 s + 45 s + ~3.9 s. The pre-compositor boot (lk2nd → kernel →
initramfs → systemd → greetd) is **not** in that number: the saved logs contain
no `systemd-analyze` sample and no monotonic timestamps for those stages. It is
the next thing to measure, and the candidate below does not touch it.

## The cause: a Waydroid boot gate that cannot complete on this install

Before removing the splash, the compositor waits for the Android/Waydroid side
to be ready, bounded by a 45-second deadline. In prose, its readiness test is
"sensor hub ready and Android ready", where Android counts as ready when the
compositor runs nested, or the runtime marker
`/run/ztos-waydroid-boot-ready` exists, or the Waydroid configuration
`/var/lib/waydroid/waydroid.cfg` does **not** exist.

On this device:

- the Waydroid configuration **exists** (the images are installed), so the
  "not installed" branch is false;
- the marker is written only by ztOS's Waydroid boot integration
  (`/usr/local/libexec/ztos-waydroid-boot` plus its user-session unit), which is
  **not installed** here — the marker therefore never appears;
- the compositor does not run nested.

No branch can become true, so every boot pays the full 45-second deadline. The
sensor-hub half is not the blocker: this device has no `/sys/class/sec`, so the
hub is considered ready on the first poll. This is upstream behaviour written
for a target where Android starts at login (the compositor line comes from the
ztOS Galaxy S9 work); here Android is not launched at all and the launch path is
not present.

## The candidate change (host-built, never run on the phone)

The change touches one userspace binary — the compositor — and nothing else: no
boot image, DT, kernel, initramfs, systemd unit or configuration file.

In words: the boot gate learns whether the Waydroid boot integration is actually
installed, and waits for Android only when it is. The wait for that case is
capped at 5 s instead of 45 s, and is zero here. An environment variable selects
the mode (`unset`/`auto`: wait only if the integration is installed;
`0`/`off`/`no`: never wait for Android; `1`/`force`: the old 45 s, for A/B
without replacing the binary). The sensor-hub wait keeps its own 45 s deadline
on hardware that has one. One extra line in the boot log records which gate was
chosen.

Evidence for the candidate, all host-side:

| | installed binary | candidate |
|---|---|---|
| ELF sha256 | `b63a4be1…` | `1df48bd4…` |
| size | 1 331 920 B | 1 333 392 B (+1 472) |
| source | installed line | installed line + one delta (+46/−5, 3 hunks) |

- The same container and the reconstructed installed source rebuild the
  installed binary byte-for-byte; the candidate was then built twice with an
  identical result.
- The aarch64 artifact check passes (architecture and expected strings); the
  dynamic dependencies are unchanged; exactly three functions change size and
  all other function sizes are identical.
- It has **never been installed or executed on the phone**. The delta applies to
  the local compositor source line, which the published series does not
  reproduce, so the patch is not published. It lives in the project's private
  work tree at `build/splash-fast-2026-11-15/ztmetro-waydroid-gate.patch`;
  [MAP](../MAP.md) records the exclusion.

Expected effect, from the saved-log arithmetic: gate start at ~2.08 s + one poll
(~0.1 s) + the 3.94 s transition ≈ **6.1 s** to `splash removed` on the
compositor's clock (from 51.0 s), and the logo on screen drops from about 49.8 s
to about 4 s. This is arithmetic on one saved log, not a measurement of the
candidate.

## A/B acceptance and rollback (owner step)

A is the installed binary; B is the candidate, with the installed binary backed
up first and the session restarted. One A boot and one B boot are enough.

- **Metric:** `splash removed` seconds in the compositor log; with B the log
  should show the gate choosing "not waiting" and no readiness timeout.
- **Regression checks:** lock screen, touch and icons; Firefox and a Qt/Wayland
  application start; Wi-Fi and battery indicators; home haptic; the idle/power
  fade timings; `waydroid status` stays `STOPPED` (Android is not started in
  either A or B).
- **Soft rollback, no binary swap:** set the gate to force mode in
  `/etc/ztos/session.env`.
- **Hard rollback:** restore the backed-up binary and restart the session.
- **Do not deliver** if the on-device artifact hash/check differs from the
  recorded one, if there is no agreed boot window, or if the full Waydroid
  integration is being installed in the same boot. If B does not reach the UI
  within about 8 s or shows visual artifacts, roll back immediately.

## What is not claimed, and what is next

- Total boot time is **not measured**. The ~45 s saving applies to the splash
  display; "button to UI" still includes the unmeasured pre-compositor path.
- The candidate does not make Android/Waydroid work: the launch path is absent
  either way. If the integration is installed later, the default mode would wait
  up to 5 s, and force mode restores the old behaviour.
- Nothing else in the boot path was changed. On the pre-compositor side the
  candidates that remain unmeasured are: the Waydroid container/images units
  that are enabled even though Android is unused; a camera-path unit that waits
  for the camera before the graphical target; and the modem chain, whose helpers
  poll for QRTR/SIM. Each needs `systemd-analyze blame`/`critical-chain` from a
  real reboot before anything is touched; none of them is applied.
- No boot image, DT, kernel or initramfs change is published or proposed here.

## Evidence boundary

The 51 s figure and its breakdown are quoted from a saved compositor log of the
running install; the candidate numbers are from the host build. No boot ids,
session logs or host paths are published. Where a number here is arithmetic
rather than measurement, it is labelled as such.
