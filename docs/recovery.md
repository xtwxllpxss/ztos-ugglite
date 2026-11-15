# Recovery — what to do when the phone stops answering

This is a decision tree, not an installer. It starts from the state the phone is
in and deliberately does not contain a single command that writes a partition.
The repository ships no boot image, no rootfs image, no recovery image, no
installer and no restore script; the images this page names are the ones the
owner keeps outside the repository.

Read [Safety notes](safety.md) first. The rules there are absolute and this page
does not relax any of them.

## Level 0 — the phone answers (SSH over USB)

The normal state. Applications, modules and settings can be changed live; only a
kernel, DT or ramdisk change needs a reboot. A restart of ztOS is a plain
`systemctl reboot` inside ztOS: the boot slot is not written by a reboot, there
is no A/B slot to switch, and the installed payload comes back. This is **not**
an Android reboot and it does not enter the bootloader.

Before rebooting, check the one thing that a reboot cannot fix — power:

* the charger is connected and the battery reports that it is charging;
* the battery capacity is high enough that the boot will not be interrupted.

After the phone is back on the same USB transport, compare rather than assume:

* a new boot identifier (the previous one is remembered by the operator, not by
  this repository);
* the same kernel release;
* `systemctl is-system-running` reports `running` or `degraded`, and the
  previously installed files and services are still there.

If the reason for the reboot never happened (for example the phone was degraded
by a failed driver probe), stop at this level and do not stack a second
experiment on top of the first one.

## Level 1 — no SSH, but fastboot and lk2nd work

This is the host-assisted RAM path. **`fastboot boot` loads an image into RAM
and writes nothing**; the boot slot keeps the installed payload and a plain
restart returns to it. It is the only boot method this repository describes.

1. Enter fastboot physically: hold **Volume Down** while powering the phone on.
   There is no SSH fallback for this step. If the phone does not enter fastboot
   and the screen does not show what was expected, stop and ask the owner what
   the screen shows instead of guessing.
2. Confirm the bootloader: `fastboot devices` must list the phone, and
   `fastboot getvar product` must report `ugglite`. If it reports anything else,
   stop.
3. Load the first stage with `fastboot boot <lk2nd image>`, then repeat
   `fastboot getvar product`: lk2nd reports `lk2nd-msm8952`. Do not continue if
   it does not.
4. Load a RAM image with `fastboot boot <RAM image>`. The image must be a build
   whose provenance is known (the owner's verified build), because a RAM image
   that reboots unconditionally can return the phone to an unexpected state.
5. The host-assisted image brings up USB networking and an SSH session; once it
   is reachable, compare the boot identifier and the kernel release and state of
   the system as at level 0. A restart from the RAM system returns to the
   installed slot.

`fastboot` itself is the transport, not a licence to write: `fastboot flash`,
`erase`, `format`, `-w` and every variant that writes a partition stay out of
bounds. See "what NOT to do" below.

The build side of a RAM candidate (host-side repack, kernel package, pinned
lk2nd revision) is documented in [Build and boot](BUILD-AND-BOOT.md); this page
only covers the recovery choice.

## Level 2 — nothing boots, or fastboot is not reachable

**Stop.** This repository has no step for this case, and inventing one on a
phone whose state is unknown is how a recoverable phone becomes an unrecoverable
one.

What is true and should be stated plainly:

* There is exactly one boot partition and it was written once, after the stock
  boot image was backed up outside the repository. Restoring that backup is a
  write. It is a one-off owner decision, not a documented recipe, and this
  repository neither ships the image nor a script that performs the write.
* That backup is stock Android. Restoring it does not restore ztOS: the
  installed root lives on internal storage that was reformatted for ztOS, and
  **booting Android is forbidden on this unit** because Android's storage
  management can re-encrypt or factory-reset that data. The accepted decision
  from bring-up is that Android is never booted here.
* The Android system partition was never re-flashed or tested, and
  anti-rollback/verified boot were not examined. Do not assume a rollback is
  available.
* Writing anything else — boot, system, recovery, modem, persist, the partition
  table — is out of scope and can leave the phone unusable.
* Physical service and EDL are not documented for this board. They are a
  separate owner decision, not something to attempt from a terminal.

When level 2 is reached, the useful actions are to stop touching the phone,
write down its last observed state (what the screen shows, what `fastboot
getvar` still answers, which USB device appears) and hand that to the owner.

## What NOT to do

- **Never flash, erase, format, `-w`, or change the partition table.** Not "just
  this once", not with a backup at hand. The RAM path exists precisely so that
  the slot is not written.
- **Never boot Android.** Restoring the stock boot backup is not a supported
  step and booting Android can destroy the installed ztOS root and its data.
- **Never run `fsck -y`, `mke2fs` or a formatter against the installed root
  partition** to "repair" it. A filesystem repair that rewrites the root is a
  data-loss operation on a phone that may only need a reboot.
- **Never write the RTC, NV, EFS or the modem partitions.** EFS access is
  read-only by design; an RTC write has already lost the session on this unit.
- **Never retry an unknown-outcome operation a second time.** Two identical
  failures mean stop and change the premise, not repeat the command.
- **Never reload `venus_core` more than once in one boot.** A second re-probe
  crashed in `venus_add_dynamic_nodes` and left the video core powered with no
  nodes until the next reboot ([Venus](venus.md)).
- **Do not treat a degraded session as a broken phone.** A failed driver probe
  can leave a slow or partially broken session; a planned restart is the first
  recovery step, not a reinstall.

## What this page does not publish, and why

| Not published | Reason |
|---|---|
| Boot, RAM, rootfs and stock images, their copies and their hashes | binaries and firmware; the owner keeps the verified copies, the repository does not redistribute them |
| Installer, restore, `fastboot flash` and userdata scripts | write paths into partitions and device-specific transport; publishing them would invite the exact destructive operation this page forbids |
| Boot identifiers, device serials, USB addresses, host paths | per-device identifiers and session material |
| A step for the "nothing boots" case | no such step was validated; inventing one is unsafe |

The status boundary and what is prepared but unverified is in
[hardware status](hardware-status.md). The build and RAM-candidate side is in
[build and boot](BUILD-AND-BOOT.md).
