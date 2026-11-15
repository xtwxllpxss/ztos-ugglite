# Store and OSIAL — working, and why the first verdict was wrong

Both applications were recorded as FAIL in the first application pass: the Store
showed skeleton tiles instead of a list, and OSIAL showed an empty body after
about 11 s. A later, longer look on the same install shows that **neither
application is broken**. Status: **working, verified by frames and a dump**.

This is a correction of a first-pass verdict, not a new feature: no Store or
OSIAL binary, package or configuration was changed between the two looks.

## The Store

With enough time to populate, the Store draws its package lists — the AUR and
repository sources render as lists of entries, not as skeleton tiles.

The only visible failure left is a network one: **`pkgstats.archlinux.org` does
not resolve** (DNS), and the application shows that failure on screen. It does
not empty the lists; it is an error line in an otherwise rendered window. The
first-pass frame caught the window before the lists had arrived, which is why it
looked like an empty store.

## OSIAL

The OSIAL management window produces its dump in **1.9 s** and covers **13
interfaces**. The earlier "`asking ztOSIAL`, empty body after ~11 s" was a
capture taken while the dump was still pending, not a failure of the
application.

## What is not claimed

- Browsing the lists is verified visually; **installing a package from the
  Store was not exercised** in this pass.
- OSIAL's management actions were not exercised — the dump and the list of
  interfaces are the verified part.
- The DNS failure is an upstream-network condition of this environment. This
  file does not claim it is fixed, worked around or harmless in general; it is
  the one visible defect on screen.
- One boot, one session; no soak test.

## Evidence boundary

The rendered lists, the on-screen DNS failure, the dump duration and the
interface count are live readbacks from the phone (frames and a protocol dump).
The dump and the session log are kept locally and are not published; no log,
screenshot, host path or network profile is published.
