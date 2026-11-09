# Units and helpers — touch keys and torch

Two independent userspace pieces that the ztmetro patch series does not cover.
Neither duplicates `patches/userspace/ztmetro/`: 0001 is ztmetro's own nav
handling, while the mapper here turns the *physical* Goodix keys into the nav
codes ztmetro already understands.

## Touch keys

| File | Installed path |
|---|---|
| `ugglite-touchkey-navd.py` | `/usr/local/lib/ugglite-touchkey-navd.py` |
| `ugglite-touchkey-nav.service` | `/etc/systemd/system/ugglite-touchkey-nav.service` |

The mapper reads the key input node and emits nav codes through `uinput`; it
never grabs the device, so if it dies the keys are harmless and the on-screen
nav bar still works. Physical codes were taken from a user capture
(`KEY_LEFTMETA` left, `KEY_F1` centre, `KEY_F2` right) and map to
`KEY_APPSELECT` / `KEY_HOMEPAGE` / `KEY_BACK`.

Short/long press is **not** timed in the mapper: it forwards both edges with the
real duration and ztmetro's own 450 ms hardware-key timer decides tap vs hold.
Synthesising a release tap here would produce two actions per press.

The physical `Super` modifier leak is handled by remapping keycode 125 to
`KEY_UNKNOWN` in the evdev keycode table for the lifetime of the process
(`EVIOCSKEYCODE_V2`, index-based, restored on exit, nothing persisted). The
remap is best-effort: if the kernel refuses it the mapper keeps working and only
the Super leak remains.

`ConditionPathExists=/dev/input/event3` in the unit is the node the mapper was
delivered against on the accepted boot. Input numbering is not guaranteed across
kernels; if the touch keys stop working, check the node first.

The unit's `Documentation=` points at the local delivery report, which is not
published; this README is the public description.

## Torch

| File | Installed path |
|---|---|
| `72-ugglite-torch.rules` | `/etc/udev/rules.d/72-ugglite-torch.rules` |
| `zt-flashlight` | `/usr/local/bin/zt-flashlight` |

The rear flash is two TLMM lines (`gpio33` flash-enable, `gpio34` flash-now),
driven in the stock firmware by a vendor LED driver that mainline does not have.
The minimal mainline fix is a `gpio-leds` node labelled `white:torch` on
`gpio34`, which is **not** published here: it is a board DT change that also
needs a leds-gpio default-state decision, and it has not been through the DT
review the other fragments got. The rule and helper below are useless until that
node exists — `zt-flashlight status` says so instead of pretending.

Given the node, `zt-flashlight on|off|status|test [seconds]` is a one-shot
control (no daemon), and the udev rule gives the `alarm` user write access to
`brightness` so ztmetro's tile can toggle it. `test` restores the previous
value on exit.
