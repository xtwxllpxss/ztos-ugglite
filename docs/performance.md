# Performance and memory — host-only recommendations, not applied

The device has 1831 MB of RAM and one 900 MB zram swap device. This file
collects the memory and browser tuning recommendations prepared while the phone
was not available for measurement, and states plainly that **none of them is
applied**: no sysctl, no browser policy, no package. Below, "estimate" means a
figure derived from configuration and upstream defaults; the acceptance protocol
is the measurement.

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

## Browser: what the stack actually is

- **GL stack:** the same freedreno stack as the compositor — Adreno 308
  (`FD306A`), EGL `msm`, Mesa 26.2.x, Wayland over DRM `msm`/`msm_dpu`.
  Panfrost does not apply (Mali); kmsro is not needed (one DRM node); zink is
  not available: there is no Vulkan for a3xx (Turnip starts at a6xx).
- **Firefox 159 is installed** with no distribution policy (`/etc/firefox` is
  absent), so it runs upstream defaults. WebRender is the default and takes the
  GL path when the driver is not blocklisted.
- **Hardware video decode is not reachable:** the Venus decoder is not
  integrated, there is no VA-API driver for it in the repositories, and Firefox
  on Linux only uses VA-API. Video stays software-decoded.
- So on 1.8 GB the gains are in process count, cache and background networking,
  not in GPU flags.

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

## Evidence boundary

The configuration statements come from the pinned kernel configuration, the
device layer and saved readbacks; the Firefox defaults are from the installed
version. The per-area kit scripts (apply/rollback/verify) are **not published**:
they are bound to the phone session and to unpublished local payload paths;
[MAP](../MAP.md) records why. No setting in this file has been applied, and no
speedup is claimed as measured.
