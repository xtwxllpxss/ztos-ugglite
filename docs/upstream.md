# Upstream adoption — PR #16 installed and verified on the phone

This file records which upstream ztOS changes were merged onto the accepted base
and installed on the running system, how the result was verified, and what is
still open. Status: **PR #16 builds installed and verified by captured frames**;
the binaries in the running system were replaced, with the previous ones kept as
a backup. The change is in the running system, not merely staged.

The merge log and the built binaries live in the project's private work tree.
This repository publishes the state and the evidence boundary, not the binaries.

## What was delivered

The PR #16 merge was applied to the accepted base and the three affected
binaries were rebuilt from upstream source and installed:

| Binary | Version in the running system | What it replaces |
|---|---|---|
| `ztpower` | `36c8791d…` | the build with hard-coded Galaxy S9 power-supply paths |
| `ztdevices` | `6dac4635…` | the previous device/services window |
| `ztsettings` | `7725ed9f…` | the previous settings window |

Before the install the current binaries were backed up on the device, so
rollback is a file restore rather than a rebuild. No kernel, DT, boot image,
systemd unit or configuration file changed.

## How the result was verified

Verification was by frames and live readbacks, not by the build's exit code:

- **Power Management (`ztpower`)** — the previously zeroed battery telemetry is
  now real: `100 %`, `Charging (+30 mA)`, `4.38 V`, `31.4 °C`. The charge
  voltage in sysfs reads `4.382 V`, which agrees with the window. The cycle
  counter stays `n/a` because this gauge has no cycle counter; that is a
  property of the hardware, not a defect introduced by the merge.
- **Devices and Services (`ztdevices`) and Settings (`ztsettings`)** — both
  windows render their content in captured frames, and no segfault appeared in
  the session.
- The accepted boot was otherwise unchanged: display, touch and the session
  survived the install.

The frame-level detail of the application sweep is in [apps.md](apps.md); the
battery row is also stated in [hardware-status.md](hardware-status.md).

## What is still open

- **PR #13 is accepted except its camera hunks and is not merged.** It carries
  the Waydroid lifecycle (`recover`/`launch` units) and the boot-ready marker
  the splash gate in [boot-time.md](boot-time.md) refers to. Until it is merged,
  those paths stay absent.
- **PR #14 was dropped as a duplicate** of work already delivered; **PR #11 was
  not needed** for this device.
- The merge does not add interaction handling: the sweep verified that the
  windows render and that the telemetry is live, not that every control changes
  a setting.
- One boot and one session — not a soak test.

## Evidence boundary

The telemetry values, window renders and the absence of a crash are from the
installed system on the phone. The hash prefixes are the installed binaries'
identities. No binary, merge log, session transcript, boot id or host path is
published; [MAP.md](../MAP.md) records why. Where a value is quoted from sysfs,
it is labelled as such.
