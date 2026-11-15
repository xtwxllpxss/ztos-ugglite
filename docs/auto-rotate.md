# Auto-rotate — prepared kit, not installed

The shell does not rotate today: the installed ztmetro has no rotate command, and
the UI stays upright whatever the accelerometer reports. A prepared, host-tested
kit adds an optional 180° auto-rotate and deliberately supports nothing else.
It has never been installed or run on the phone, and the patched binary is not
published. This page records the design, the acceptance boundary and the one
unproven assumption, so the work is not a surprise later.

Status: **prepared / not installed / not device-tested**. The display state and
the "auto-rotate is not wired into the shell" statement in
[hardware status](hardware-status.md) are unchanged by this page.

## What it would do

Tilt flows through the vendor sensor stack to the kernel's IIO device, is read by
the session's sensor daemon, and the daemon already knows how to send a rotate
command to the shell's control pipe. The installed shell simply has no such
command. The kit is therefore one changed shell binary plus a daemon setting —
no kernel change, no sensor rework, no compositor change.

Mechanism, layer by layer:

| Layer | Behaviour |
|---|---|
| Sensor | vendor `sns.reg` → ADSP/SSC → `qcom_smgr` → IIO accelerometer |
| Sensor daemon | reads IIO directly (no D-Bus, `iio-sensor-proxy` is not involved and must not be enabled), classifies upright/inverted with a threshold and a debounce, and writes `rotate 0\|180` to the shell's control pipe when auto-rotate is enabled |
| Shell | a new `screen_rotate()` inverts clip-space x and y in the quad projection, which every surface goes through (home, splash, lock, shade, application windows), and mirrors touch and pointer in the same handlers |
| Deliberately refused | 90/270 are refused with a log line and the pose is kept: a portrait shell needs a landscape layout, not a rotated one. The DotMatrix style is refused too (its own GL pass would stay upright) |
| Configuration | there is no config key in the installed shell, which is why a patched binary is required; the daemon side is a normal opt-in setting, off by default |

The daemon does not need to be replaced: its installed version already emits the
command and matches the prepared one. The shell patch touches only the rotation
field and projection, the touch/pointer handlers, the new rotation function and
the command parser; fade, splash, haptic, battery, Wi-Fi and navigation code are
untouched.

## Prepared kit shape (host-tested only)

The kit is reversible and has three parts: a host-side install with a dry-run
default that checks the candidate binary, verifies the currently installed shell
and free space, and takes a timestamped backup before swapping the file
atomically; a read-only verification script that checks the installed binary,
the backup, the daemon and the control pipe; and a rollback that restores the
backup and turns the auto-rotate setting off. Installing the binary does not by
itself enable rotation — the setting stays off, and the binary only takes effect
after the session restarts or the phone reboots.

Acceptance, in order, on the device:

1. **Polarity first, with rotation still off.** The daemon must report upright as
   `normal` and upside down as `inverted`. If it reports them the other way
   round, the kit must not be enabled: the fix is the sign of one axis in the
   sensor daemon's orientation matrix, not the shell binary.
2. Enable the setting and restart the daemon; turning the phone over rotates the
   whole UI and the daemon log shows the command and the shell's acknowledgement.
3. Touch must land on the icon that is visible, including drag and scroll —
   the mirroring is code-reviewed but not observed.
4. Turning the phone back restores the upright UI; 90/270 keep the current pose
   with a refusal in the log.
5. Regressions: boot splash, idle/power fade, lock screen, home haptic,
   battery/Wi-Fi tiles, brightness.

Rollback is either turning the setting off (safe default, binary may stay) or
restoring the backed-up binary; the session must be restarted for either to take
effect. SSH is independent of the session, so a rollback remains possible even
if the session does not come back.

## The one real risk

**Orientation polarity is unproven.** Only the lying-flat state was ever
observed on the phone, and the sensor stack's notion of "upright" was not
verified in the hand. If it is inverted, the UI would rotate when the phone is
held upright. That is why polarity is step one of acceptance and why the setting
stays off until it is checked.

Smaller limits: only 0/180 exists by design; touch mirroring is proven by code
reading only; the DotMatrix style ignores rotation; rotation only works while
the shell session is alive and its control pipe exists.

## What is not published, and why

| Not published | Reason |
|---|---|
| The patched ztmetro binary | a binary, and the repository publishes no ELF payloads |
| The rotation patch | its base is a locally built, fade-tuned ztmetro that is not reproducible from the published ztmetro patch series, so the delta could not be applied to any published source |
| Install/verify/rollback scripts, manifest and run logs | they embed local payload paths and session material, and the kit is deferred rather than delivered — [MAP](../MAP.md) states the decision |

The installed shell's own source is reproducible from
[the ztmetro series](../patches/userspace/ztmetro/) as documented in
[SERIES](../SERIES.md); the rotation delta was made against a different local
composition of that source.
