# Performance and memory — recommendations, and one live browser measurement

The device has 1831 MB of RAM and one 900 MB zram swap device. This file
collects the memory and browser tuning recommendations prepared on the host, and
states plainly that **none of them is applied**: no sysctl, no browser policy, no
package. The browser stack itself was measured once on the phone on 2026-11-15;
that measurement and one important correction to how its frame trace reads are
in the browser section. Below, "estimate" means a figure derived from
configuration and upstream defaults; the acceptance protocol is the measurement.

## The device as it is

- **RAM:** 1831 MB total.
- **Swap:** zram `900 MB` (49 % of RAM), `lz4`, priority 100, created at boot by
  the device layer's zram unit; there is no disk swap and no zswap. The kernel
  is built with zram and several compressors, but the unit selects `lz4`.
- **Reclaim policy:** the device layer's zram sysctl file sets only
  `vm.swappiness=100` (right for zram; the default 60 is disk-swap oriented).
  `vm.page-cluster` is left at the kernel default 3 (8-page readahead) and the
  watermark factors at their defaults.
- **No OOM policy service:** `systemd-oomd` is disabled and the distribution's
  memory-policy unit is masked at runtime; the kernel OOM killer is the only
  mechanism.
- **What fits:** the compositor and system sat around 1.0–1.1 GB used with
  0.75–0.8 GB available at idle in a saved readback; one browser tab is
  estimated at 300–500 MB and a Waydroid session at 0.9–1.4 GB. Waydroid + a
  browser + the compositor does not fit in 1.8 GB even with zram; the compositor
  plus one browser does. Waydroid's images (2.3 GB) are on eMMC, not in RAM.
- **Why tuning matters:** zram has no writeback, so a full cap is an OOM, not a
  slow path. The OOM killer takes the largest process and the UI is not
  protected. Tuning therefore targets swap-in latency and early reclaim, not
  "freeing memory".

## Memory candidate P1 — three sysctl values

One file under `/etc/sysctl.d/`, three lines, testable without a reboot and
fully reversible:

| Setting | Now | Proposed | Why |
|---|---|---|---|
| `vm.page-cluster` | `3` (kernel default) | `0` | swap-in on zram does not need an 8-page readahead; that readahead is extra decompression and latency on a 4×A53 |
| `vm.watermark_boost_factor` | default (15000) | `0` | no large watermark boost after fragmentation |
| `vm.watermark_scale_factor` | default (10) | `125` | kswapd wakes earlier, fewer synchronous direct-reclaim stalls |
| `vm.swappiness` | `100` | keep | right for zram; the UI slider range is 10–100 |

Status: **not applied.** Test with `sysctl -w` one line at a time under the same
load; persist only if the measured run is same-or-better; revert with the old
values or a reboot. Expect no effect at idle — these knobs only matter when
swap or reclaim is active. Do not `swapoff` and do not recreate the zram device
while the UI or a browser is running: swapped pages live in zram, and removing
the device with dirty swap risks an immediate OOM.

## Memory candidate P2 — only by measurement, one factor per step

- If swap used sits at the cap during ordinary use: A/B a larger cap (1200 MB,
  about 65 %) or `zstd`; measure swap used, compression CPU and responsiveness.
  A larger cap holds more compressed pages and turns a quick OOM into longer
  thrashing, so it is not free.
- If PSI `memory full` grows while swap is below the cap: `vm.min_free_kbytes`
  around 100 MB (postmarketOS uses this for 1 GB devices). It buys earlier
  reclaim for about 100 MB of lost available memory; A/B only.
- Do not add disk swap (latency and eMMC wear), do not unmask the distribution's
  1.5 GB `lzo-rle` memory policy (constants for a different device, and it
  conflicts with the device layer), do not enable `systemd-oomd` (no swap-aware
  configuration; it may kill the session), do not push `swappiness` above 100
  (the UI slider only covers 10–100).

Acceptance for either step: no new OOM kill, swap used and PSI not worse at the
same load, no subjective slowdown in scrolling or app switching. Measure on a
clean boot, not on a boot with a known kernel fault: a tainted kernel with stuck
I/O tasks inflates load and distorts reclaim latency.

## Browser: the stack, and one live measurement (with a correction)

The stack, from the live run and the packaged versions:

- **GL stack:** the same freedreno stack as the compositor — Adreno 308
  (`FD306A`), EGL `msm`, Mesa 26.2.x, Wayland over DRM `msm`/`msm_dpu`.
  Panfrost does not apply (Mali); kmsro is not needed (one DRM node); zink is
  not available: there is no Vulkan for a3xx (Turnip starts at a6xx).
- **Firefox is installed** with no distribution policy (`/etc/firefox` is
  absent), so it runs upstream defaults (the long measurement run below used
  159; the later A/B used 160.0-1 — no distribution policy in either case).
  WebRender is the default and does take
  the GL path here: the run reported `Compositing = WebRender`, device pixel
  ratio 2, WebGL on EGL/freedreno `msm`.
- **Hardware video decode is not reachable:** the Venus decoder is not
  integrated, there is no VA-API driver for it in the repositories, and Firefox
  on Linux only uses VA-API. Video stays software-decoded.
- On 1.8 GB the gains are in process count, cache and background networking,
  not in GPU flags.

One real run was made on 2026-11-15 (about 8 minutes, `about:` pages only, no
network, no prefs/system change): 10 Firefox processes, RSS 1.22 GB / PSS
~630 MB, `MemAvailable` 1.31 → 0.63 GB, swap 0, no OOM, CPU busy ~53 %. A scroll
frame trace of 263 intervals gave **median 32.9 ms, mean 28.08 ms, p95 48.6 ms**,
95.4 % of intervals on the 60 Hz grid, with a 1×/2×/≥3× split of 40 % / 55 % / 5 %.

**How to read that trace — the correction.** These are **compositor** intervals,
not Firefox's frame rate. While an application is live, the compositor draws on
every vblank, so a 2× interval means a missed vblank, and a mean of 28.08 ms is
about **35.6 fps of the compositor loop** — the earlier reading "median 32.9 ms =
Firefox at 30 fps" is wrong. The compositor itself is not CPU-bound (draw 1.1 ms,
commit 0.2 ms, no jitter, four quads on the display plane; the 2× frames show the
same CPU numbers). The pattern alternates 1,2,1,2 (`63 %` of neighbouring pairs
sum to 50.0 ms, phase stable), while a control trace on this panel earlier
measured a full 60 fps — so the doubling is session-level. The present/dmabuf
display-plane hypothesis was then tested directly: forcing
`widget.dmabuf.enabled=false` did **not** change the split (control runs kept the
2× frames at 33.3–35.6 %, dmabuf-off runs at 32.4–34.5 %, means 26.4–27.1 vs
24.4–26.1 ms), and `EBUSY` was **zero** inside every trace window while the 2×
frames stayed — so the missed-vblank-on-present explanation is not supported. The
compositor does report repeated `Atomic commit failed` lines, which also appear
without Firefox. The next question is the compositor's own pacing during scroll;
answering it needs an exclusive phone window and a frame counter in the
compositor, which does not exist yet. The purple fills in `about:support` are a
known Firefox accent-token bug ([bug 2079098](https://bugzilla.mozilla.org/show_bug.cgi?id=2079098)),
not GPU artefacts.

## Browser candidate P1 — one policy file

One reversible file, `/etc/firefox/policies/policies.json`; no packages and no
compositor change:

| Preference | Default → proposed | Effect | Cost |
|---|---|---|---|
| `dom.ipc.processCount`, `dom.ipc.processCount.webIsolated`, `dom.ipc.processPrelaunch.enabled` | 8 / 1–4 / true → 2 / 1 / false | 2–5 fewer processes, ~100–250 MB | weaker tab isolation |
| `browser.cache.memory.capacity` | −1 (auto) → 32 768 KB | bounds the per-process memory cache | slower back/forward |
| `browser.sessionstore.interval` | 15 000 → 60 000 ms | less eMMC write and CPU in the background | up to 1 min of session lost on a crash |
| `network.dns.disablePrefetch`, `network.predictor.enabled` | false / true → true / false | fewer background DNS/socket operations | first navigation slightly slower |
| `media.ffmpeg.vaapi.enabled`, `media.hardware-video-decoding.enabled` | auto → false | skips failed hardware-decode initialisation | none while there is no VA-API |

Status: **not applied.** Acceptance: `about:support` reports WebRender (not
"WebRender (Software)"), WebGL renderer `FD306A` and the Wayland window
protocol; `MemAvailable` stays ≥ 250 MB, swap does not sit at the cap, no OOM
kills and no browser crash; no checkerboard or black-rectangle artifacts;
scrolling and tab switching are not subjectively worse. Measure three runs on
three sites (first readable frame), the checkerboard telemetry, the additive PSS
of the browser processes and CPU. One factor per step; back up the file and
remove it to revert — the policy only changes Firefox, and removing it restores
the defaults.

## Browser candidate P2 — only if P1 is not enough

- A/B hardware versus software WebRender: Adreno 308 has a history of tiling and
  black-rectangle artifacts on some drivers; software WebRender is correct but
  slower. Never force it permanently without numbers.
- `gfx.webrender.software=true` as the GPU-versus-CPU step. The
  `widget.dmabuf.enabled=false` A/B has already been run and did not remove the
  2× frames (see the browser section), so it is not a pending candidate.
- `fission.autostart=false` with process count 2: a hard memory cap at the cost
  of weaker site isolation.
- Reduced cosmetic animation in Firefox.
- Angelfish as a fallback only after Firefox; QtWebEngine is heavier by process
  count. Its flags are known, but nothing was applied.

## What NOT to do

Do not force WebRender (`gfx.webrender.all`, the old `MOZ_WEBRENDER`, the dead
`layers.acceleration.force-enabled`); do not set `MESA_LOADER_DRIVER_OVERRIDE`,
`LIBGL_ALWAYS_SOFTWARE` or `MESA_GLES_VERSION_OVERRIDE=2.0` (breaks GLES 3 and
WebRender); do not use `FD_MESA_DEBUG` unless artifacts are reproduced (it is a
slowdown); do not add fonts; do not change zram, the compositor or the Venus
stack as part of browser tuning. No package was added and no setting is applied
by this document.

## One-owner rule around heavy GPU clients

Two spontaneous hard hangs on 2026-11-15 were analysed read-only (watchdog reset,
kernel silent because hung-task/lockup detectors are off): both coincided with
more than one GPU/media client alive (camera + browser; then the first WebKit
browser launch). Memory was excluded (swap 0, no OOM). The cause is **not
proven**; the operating rule is one owner of the phone at a time and no two
heavy GPU applications in one test window. This is a boundary of the
measurements above, not a solved defect.

## Evidence boundary

The configuration statements come from the pinned kernel configuration, the
device layer and saved readbacks; the null results are from the installed
version. The one browser run is a real measurement on the phone with its
artifacts kept locally; the frame-trace interpretation above is the corrected
one and is labelled as a hypothesis where it is not measured. The per-area kit
scripts (apply/rollback/verify) are **not published**: they are bound to the
phone session and to unpublished local payload paths; [MAP](../MAP.md) records
why. No sysctl, policy or pref in this file has been applied.
