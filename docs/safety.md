# Safety notes

This device adaptation touches a phone whose only boot path is a host-assisted
RAM boot. Read this before running anything from this repository.

## What NOT to do

- **Do not flash partitions.** `fastboot boot` is the only boot method that was
  used. Flashing boot/system/recovery/modem/persist or changing the partition
  table is out of scope and can leave the phone unusable.
- **Do not expect an installer.** No installer, no flashing script and no
  rollback image are published here. The installed root lives in `userdata`;
  restoring Android is not covered.
- **Do not write the RTC.** The write path crashed or dropped the session in
  every attempt, and the cause is unknown. Do not "test" it.
- **Do not run unverified RAM probe images.** Some diagnostic images used during
  bring-up rebooted unconditionally and could return the phone to Android in an
  unexpected state. The images themselves are not here.
- **Do not leave the rear torch on unattended.** It is the camera flash LED,
  not a lamp: continuous operation heats the emitter and drains the cell. Use
  short bursts and keep an eye on the lens area.
- **Do not put personal data into build inputs.** No network profiles, hostnames,
  SSH keys, MAC addresses, IP addresses or boot logs belong in a public fork.

## Host-side hygiene

- Build on a host you control; the layer copies files into a root you assembled.
  `layer.sh` only writes inside the root you name, and refuses a path that does
  not exist.
- `fixups.sh` sets a setuid bit on `fusermount3` and edits `pacman.conf` inside
  the target root only. Review it before running it on anything you care about.
- Keep USB as the only console during a RAM boot; there is no display fallback
  when the session dies.

## Reporting

Security-sensitive findings about *this* repository (for example a script that
writes outside its target) can be reported as a normal issue. There is no
dedicated security contact, no bounty and no response-time promise; do not send
credentials or personal device data in a report.
