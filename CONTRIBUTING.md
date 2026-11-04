# Contributing

This is a small, experimental device adaptation, not a supported distribution.
Before sending a change, read `docs/hardware-status.md` and `docs/safety.md`.

## Rules that will not be relaxed

- **No binaries.** No images, kernels, firmware, kernel modules, ramdisks or
  build outputs in a pull request.
- **No personal or device-identifying data.** No MAC addresses, SSIDs, IP
  addresses, hostnames, boot ids, serial numbers, SSH keys or logs copied from a
  live device.
- **No unverified hardware claims.** "It builds" is not "it boots". State what
  was observed and on which baseline; anything untested belongs under "not
  verified".
- **No RTC write patches, no installer, no flashing scripts.** These paths were
  unsafe or explicitly out of scope.
- **Licence must be clear.** New files need an explicit SPDX licence header and a
  row in `NOTICE.md`. Patches that modify upstream code keep the upstream grant
  (`GPL-2.0-or-later` for ztOS today); if you distribute them under
  GPL-3.0-or-later, say that this is the "or later" option, not the upstream
  grant. Kernel derivatives stay GPL-2.0-only with SPDX identifiers; do not put
  them under the root licence.

## Practical notes

- Patches should apply to a named ztOS revision (or describe its base) and be
  plain `diff`/`git format-patch` text under `devices/xiaomi-ugglite/patches/`.
- Keep shell scripts POSIX `sh`, idempotent where they touch a root, and confined
  to the path given on the command line.
- If a change adds a file, add it to the allowlist and licence table in
  `NOTICE.md` in the same commit.

Review is best-effort. A pull request may be declined because a claim cannot be
verified, not because the code is wrong.
