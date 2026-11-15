# Boot time — the splash, its cause, and the installed fix

The installed compositor used to keep its boot splash on screen for about 51 s
after it started. Since 2026-11-15 the installed build removes it at **6.306 s**
on the same clock, and the device owner accepted the change. This file explains
what those numbers are and are not, why the wait happened, what was installed,
and what is still unmeasured. No compositor binary and no compositor patch are
published here: the base source line is a locally built, fade-tuned compositor
that this repository's series does not reconstruct (see [MAP](../MAP.md) and
[SERIES](../SERIES.md)). Status: **installed and accepted on the phone**.

## What the numbers are (and are not)

Both figures come from the compositor's own log on the installed system. The
compositor logs seconds since its own start, so this is **not** "power button to
usable UI":

| Segment | Before | After | Where it goes |
|---|---|---|---|
| compositor start to the readiness gate | ~2.1 s | ~2.1 s | unchanged |
| the readiness gate | 45 s (deadline, always hit) | ~0.1 s (one poll, not waiting) | the fix |
| transition and splash removal | 3.94 s | 3.94 s | unchanged |
| **`splash removed` (compositor clock)** | **51.047 s** | **6.306 s** | measured |

The 51.0 s was ~2.1 s + 45 s + ~3.9 s. The pre-compositor boot (lk2nd → kernel
→ initramfs → systemd → greetd) is **not** in either number: there is still no
`systemd-analyze` sample of that path. It is the next thing to measure, and this
change does not touch it.

## The cause: a Waydroid boot gate that could not complete on this install

Before removing the splash, the compositor waits for the Android/Waydroid side
to be ready, bounded by a 45-second deadline. Its readiness test is "sensor hub
ready and Android ready", where Android counts as ready when the compositor runs
nested, or the runtime marker `/run/ztos-waydroid-boot-ready` exists, or the
Waydroid configuration `/var/lib/waydroid/waydroid.cfg` does **not** exist.

On this device:

- the Waydroid configuration **exists** (the images are installed), so the
  "not installed" branch is false;
- the marker is written only by ztOS's Waydroid boot integration
  (`/usr/local/libexec/ztos-waydroid-boot` plus its user-session unit), which was
  **not installed** here — the marker therefore never appeared;
- the compositor does not run nested.

No branch could become true, so every boot paid the full 45-second deadline. The
sensor-hub half was not the blocker: this device has no `/sys/class/sec`, so the
hub is considered ready on the first poll.

The upstream fix for the marker itself is PR #13, reviewed in
[docs/upstream.md](upstream.md): it lets the Waydroid recovery helper write the
marker. That PR is adopted except its camera hunks, but it is **not merged
here** yet, so the local gate below remains the active mechanism.

## The installed change

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

Evidence, all host-side and on-device:

| | previous binary | installed binary |
|---|---|---|
| ELF sha256 | `b63a4be1…` | `1df48bd4…` |
| size | 1 331 920 B | 1 333 392 B (+1 472) |
| source | previous line | previous line + one delta (+46/−5, 3 hunks) |

- The same container and the reconstructed source rebuild the previous binary
  byte-for-byte; the new binary was then built twice with an identical result.
- The aarch64 artifact check passes (architecture and expected strings); the
  dynamic dependencies are unchanged; exactly three functions change size and
  all other function sizes are identical.
- It is installed on the phone, the previous binary is kept as a backup, and one
  boot on the same install measured `splash removed` at **6.306 s** against
  51.047 s before; the owner accepted the result.
- The delta applies to the local compositor source line, which the published
  series does not reproduce, so the patch is not published. It stays in the
  project's private work tree; [MAP](../MAP.md) records the exclusion.

## Rollback and regression checks that were used

- **Soft rollback, no binary swap:** set the gate to force mode in
  `/etc/ztos/session.env` (the old 45 s wait returns).
- **Hard rollback:** restore the backed-up binary and restart the session.
- Regression checks on the accepted boot: lock screen, touch and icons; Firefox
  and a Qt/Wayland application start; Wi-Fi and battery indicators; home haptic;
  the idle/power fade timings; `waydroid status` stays `STOPPED` (Android is not
  started either way).

The change does not make Android/Waydroid work: the launch path is absent either
way. If the full integration is installed later, the default mode waits up to
5 s, and force mode restores the old behaviour.

## What is still not claimed

- Total boot time is **not measured**. The ~45 s saving applies to the splash
  display; "button to UI" still includes the unmeasured pre-compositor path.
- The pre-compositor candidates that remain unmeasured are unchanged: the
  Waydroid container/images units that are enabled even though Android is
  unused; a camera-path unit that waits for the camera before the graphical
  target; and the modem chain, whose helpers poll for QRTR/SIM. Each needs
  `systemd-analyze blame`/`critical-chain` from a real reboot before anything is
  touched; none of them is applied.
- No boot image, DT, kernel or initramfs change is published or proposed here.

## Evidence boundary

The 51 s figure and its breakdown are quoted from a saved compositor log of the
running install; the 6.306 s figure is the installed binary's own log line on a
real boot; the artifact sizes and hashes are from the host build. No boot ids,
session logs or host paths are published. The candidate change was accepted as
one A/B boot; the pre-compositor path and total boot time are explicitly not
measured.
