# Applications and UI — acceptance matrix and delivered fixes

35 applications were surveyed on the installed system. A case is one
unlock → launch → dark screenshot → restore session; `PASS` in the raw results
means only "a front window with the expected application id appeared", so the
frames were reviewed by content and the verdicts below are content verdicts. On
the first pass 26 of 35 cases were captured: **PASS 9 · PARTIAL 9 · FAIL 8**,
with no segfaults, no core dumps and no OOM kills in the logged boot. A
follow-up pass closed 8 more cases and confirmed the ninth (`epiphany`) hidden.
All 35 cases are now settled: **PASS 12 · PARTIAL 11 · FAIL 10 · HIDDEN 1**,
with one invalid capture (Firefox, taken in a later boot and measured
separately in [performance.md](performance.md)).

## First pass — 26 frames

| Application | Verdict | What was visible / the defect |
|---|---|---|
| Calculator | **fixed later** | labels sat on the lower edge, `⌫` was a .notdef box, `0` was clipped; later centred and `←` used (installed) |
| Files | PASS | home/Downloads/Pictures; opening a file was not shown |
| People | PARTIAL | one contact; the avatar is split from its row |
| Messaging | PASS | a thread with text; send/receive not exercised |
| Phone | PASS | keypad, call/save; no call was placed |
| Settings | PARTIAL | main page renders; an applications tab and the bottom are clipped; brightness shows 1 % at 0 |
| Power Management | **FAIL** | all battery values were zero (`0 %`, `0 mA`, `0.00 V`, `0.0 °C`, `0 cycles`, `sleep < 1 s`); the binary read hard-coded Galaxy S9 supply paths. Fixed later through upstream PR #16 |
| Devices and Services | PARTIAL | "missing (6)" mixes masked and not-installed, labels truncated |
| Sound | PARTIAL | equaliser and band render; a switch is drawn wrong, `PRESETS` clipped |
| Welcome | PASS | text and next |
| Music | PARTIAL | channel chips, six tracks; the third tab and the last track are clipped, no playback indicator |
| App Store | **FAIL** | skeleton tiles instead of a list, empty search field, two stray blue artefacts |
| OSIAL Management | **FAIL** | `asking ztOSIAL`, empty body after ~11 s |
| Camera | PARTIAL | UI and AF frame render, thumbnail present; status shows `0 fps` with a live noisy viewfinder |
| Front camera | **FAIL** | `Loading…` and four dots, no window; preview process gone |
| Superscan | PARTIAL | chrome `about:blank` renders, the body is black (document not painted) |
| Terminal | PASS | title, menu, prompt |
| Foot | PASS | prompt and cursor; no server-side decorations |
| Htop | PARTIAL | CPU/load/swap; the right columns are clipped |
| Vim | **fixed later** | `E1187` — the runtime directory had been cut from the image while the package was in the database; reinstalling the runtime fixed it (`vim -e -c q` rc=0) |
| btop++ | **FAIL** | `Terminal size too small: 55×23`, needs `80×24` |
| mpv | PARTIAL | placeholder "Drop files or URLs…"; launched without a file |
| NetSurf | PASS | really loaded a page; URL/logo/scrollbar clipped |
| Angelfish | **FAIL** | chrome and tab render, body is an empty grey fill (Vulkan/EGL failure) |
| Firefox | not valid here | the captured frame was from a later boot; the valid live measurement is in [performance.md](performance.md) |
| qv4l2 | PASS | V4L2 loopback node and driver name render |

## Follow-up pass — 8 cases plus the hidden one

| Case | Verdict | Note |
|---|---|---|
| Waydroid | PASS | Android window in front after **9.9 s**; the session itself was started manually — see [waydroid.md](waydroid.md) |
| foot-server | PASS | no window by nature; the `foot --server` process is alive, no stray front window |
| built-in app list | PASS | page renders with the expected list state |
| built-in lock screen | PASS | dark wake produces a lock state instead of a drawn frame |
| built-in start page | PARTIAL | a frame exists, but the automated "front window" criterion does not apply to a compositor page |
| built-in shade (quick settings) | PARTIAL | frame rendered, the `menu` flag in the state line did not become 1 |
| qvidcap | FAIL | no front window within 10 s |
| footclient | FAIL | no front window within 10 s |
| epiphany | hidden | confirmed hidden from the menu by a reversible local override; the file and exec target exist |

## Fixes delivered after the sweep

- **Vim** — `vim-runtime` had been stripped from the assembled image; the
  runtime directory was reinstalled and vim starts and quits cleanly.
- **Calculator** — vertical text centring and a `←` glyph instead of .notdef;
  built, installed, verified by frame; the previous binary is kept as a backup.
- **btop** — a reversible user config selects the `proc` box only, because the
  foot terminal geometry is 55×23 and btop refuses anything below 80×24. The
  theme does not fix this; the root cause is the 360 pt logical width and the
  terminal font.
- **Power Management** — the upstream PR #16 builds (`ztpower`, `ztdevices`,
  `ztsettings`) were installed on the accepted base; ztpower now shows live
  telemetry (`100 %`, `Charging (+30 mA)`, `4.38 V`, `31.4 °C`, `cycles n/a` —
  the gauge has no cycle counter) and the settings/devices windows render
  without a crash. Details: [upstream.md](upstream.md).
- **Combined ztmetro build** — the app-bar and minimum-size changes are built,
  not yet installed.

## UI kits delivered

- **`ztgallery`** — a native camera roll (one C file, three installed files:
  binary, desktop entry, icon), grouped by day with a full-screen viewer and a
  swipe between photos. Grid and viewer were checked against host renders and
  on the phone by frame; the tile appears in the application list. A version 2
with folders/albums, video playback and scrolling is in development, not
installed.
- **Theme (system half)** — 21 files installed with a 21/21 hash check: GTK3/
  GTK4/libadwaita CSS, Qt/KDE settings, foot and vim palettes, Firefox chrome,
  icon and a launcher wrapper. On the phone NetSurf renders a flat black chrome
  through the wrapper, foot and vim follow the palette; btop is unaffected by
  the theme (see above) and gnome-terminal does not inherit the wrapper's
  environment. Rollback was checked as a dry run only. Both kits are host-side
  artefacts, not part of this repository.

## Still broken, and not proven

Still broken on the accepted install: UI clipping at 360×640@2 (Settings,
Music, htop, NetSurf, Devices, Sound); switch toggles drawn as a white square
outside the track; the camera status `0 fps` while the preview is live; the
People avatar split.

Two first-pass failures have since been explained. **Store and OSIAL are not
broken**: a longer wait shows the Store's AUR/repository package lists, and the
only visible failure is that `pkgstats.archlinux.org` does not resolve (DNS);
OSIAL dumps 13 interfaces in 1.9 s — [store-and-osial.md](store-and-osial.md).
The front-camera `Loading…` was traced to a cause and fixed: live preview from
`/dev/video1` at 640×480, about 62 fps — [front-camera.md](front-camera.md).
`ztgallery` v2 (folders/albums, video, scrolling) is in development, not
installed.

Not proven (manual owner acceptance): interactive behaviour — placing and
receiving a call and its audio, sending and receiving SMS, typing into the
calculator, saving a contact, opening a file, capture/video/AF/torch, audible
sound, play/next in Music, playback in mpv, installing from the Store, Settings
transitions, terminal interaction, browser scrolling. One WebKit application
(`epiphany`) coincided with a hard hang earlier that morning and was hidden from
the menu until it is re-tested; the reboot-hang class and the one-heavy-GPU-
client rule are documented in [performance.md](performance.md) only as a
boundary, not as a solved issue.

## Evidence boundary

Every verdict above is from a captured frame or a live process/state readback on
the phone, not from the raw `PASS` flag of the automation. The frames were taken
in one boot; a "blank screen" can also be a slow load, so Store/OSIAL/Angelfish
deserve a second look after a longer wait. No screenshots, logs or device
identifiers are published.
