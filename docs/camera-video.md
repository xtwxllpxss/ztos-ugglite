# Camera and video — measured sensor and recording budget

This file records what was measured about the rear camera's 1280×720 video path
and what is still missing for a real 30 fps recording. The acceptance boundary
stays in [hardware status](hardware-status.md); this file only adds the numbers
behind "recording tempo is not accepted". Everything below was measured on the
test unit (MSM8917, S5K3L8 rear sensor, kernel `7.1.3-msm89x7`, ztOS camera
application). No number is copied from a datasheet.

## Two source lineages

Read this before installing anything.

Two camera-application source lines exist and they are **not interchangeable**:

| Line | Source | Built artifacts |
|---|---|---|
| live / in-process | accepted source `166d8d04…` = upstream pin + the published composed camera patch | installed application `94fd6c3a…` |
| camera-v3 / 720p30 | `camera-v3` `3b3d1082…` + the 720p30 vertical-blanking cap → `0742a21d…` | 720p30 build `acddafc9…` (not installed); the pacer candidate was built from this line |

The v3 line does not carry the live line's in-process front/rear switch, the
facing debounce or the AF dark/scene work. A build from one line cannot be
installed over the other: the vertical-blanking patch applies cleanly to the live
source, while the AF-settle delta does not apply to `0742a21d`. The correct
720p30 candidate is therefore `4c7c86df…` (804 496 B) = `166d8d04` + the
vertical-blanking cap + AF-settle, built with the same flags as `acddafc9`
(`REC_FPS=30`, 1:1, crf25/5000k), built twice byte-identically, `ARTIFACT PASS`
host-side. It was not run on the phone and is not installed.

The v3 source itself is a local development line and is **not reproducible from
this repository**: the published camera patch series starts from the accepted
source and carries candidates on top of it. Patches `0002`–`0004` under
[`patches/userspace/ztcamera/`](../patches/userspace/ztcamera/) are that
candidate chain — the vertical-blanking cap, the AF settle/boost change and the
pacer retime — each with its base and result source hash; the chain and its
status are in [SERIES](../SERIES.md). They are host-verified candidates: all three candidate builds
are byte-reproducible and pass the artifact check, and none of them has been run
on the phone.

The consequence for the pacer: the retime candidate was written and measured on
the v3/`0742a21d` line. It was later **rebased onto the live line**
(`166d8d04`, the source of the installed application), rebuilt and checked
offline on the same clips; that rebased delta is published as
[`patches/userspace/ztcamera/0004-pacer-retime.patch`](../patches/userspace/ztcamera/)
with its base and result hashes. It is a host-verified candidate, not a ready
install: it has not been run on the phone.

## The sensor is not the limit

The 1280×720 mode in the S5K3L8 driver is a 2×2-binned 3840×2160 window plus a
1.5× scaler, not a crop. Its frame period follows
`fps = 562.5 MHz / (5808 × VTS)`, and the driver's 720p table uses VTS 812:

| mode | LLP | VTS | link | lanes | table fps |
|---|---|---|---|---|---|
| 4208×3120 | 5808 | 3250 | 562 MHz | 4 | 30 |
| 1280×720 | 5808 | 812 | 562 MHz | 4 | 120 |

Measured on the live graph: **119.44 fps** (8.372 ms between V4L2 timestamps),
matching the table. The receiver side is not the limit either: MIPI carries
about 1.1 Gbps of a 4.5 Gbps link, and CSID/VFE were measured at about 119.3 fps.

The 720p mode also clamps `V4L2_CID_EXPOSURE` to 804 lines, i.e. 1/120 s, which
is why night frames are dark: auto-exposure cannot lengthen the exposure.

## A userspace cap gives 30 fps and 1/30 s — in a candidate build

`V4L2_CID_VBLANK` is writable, so exposure time can be traded for frame rate
from userspace. After `VIDIOC_STREAMON`, the candidate application build sets:

| target | vertical blanking | VTS | measured | exposure max |
|---|---|---|---|---|
| 30 fps | 2530 | 3250 | **29.84 fps** (33.509 ms) | 3242 → 1/30 s |
| 24 fps | 3315 | 4035 | not measured | 4027 |

The cap was measured mid-stream: 119.44 fps before, 29.84 fps after, with
`vertical_blanking=2530` read back. In the candidate application the same cap is
applied automatically at stream start when the bound sensor is `s5k3l8` (the
delta is published as
[`patches/userspace/ztcamera/0002-sensor-720p30-cap.patch`](../patches/userspace/ztcamera/)).
DMA pressure falls from about 138 MB/s to 34.6 MB/s.

**This build is not installed.** The installed application remains the accepted
`94fd6c3a…`, which has neither the vertical-blanking cap nor the recording
scaling experiments. The 30 fps sensor rate is therefore measured, not shipped.

## Recording is limited by three separate ceilings

The recording runs were done on the device with the screen dark (backlight off),
no light and no audio; every recorded clip decodes to the end with rc=0.

1. **Encoder.** Same ffmpeg settings as the application, synthetic input, no
   camera:

   | input | frames/s |
   |---|---|
   | 1280×720 BGRA (3.6 MB/frame) | **19.1 / 18.9** |
   | 960×540 BGRA (2.07 MB/frame) | **28.5 / 28.9** |
   | 1280×720 yuv420p (1.35 MB/frame) | 25.7 |
   | 960×540 yuv420p (0.78 MB/frame) | 37.0 |
   | pipe and memory only, no encoder | 80–89 |

   The presets are already `ultrafast + zerolatency + threads 4`; CRF 25→32 and
   threads 4→2 change the result by ±3 %. The pipe and memory are not the limit.

2. **The application is single-threaded.** With the camera open it uses about
   91 % of one core (~30 ms/frame for RAW10 unpack, demosaic and the
   cairo/EGL preview), and during recording 89–95 %. It cannot deliver 30
   frames/s to the encoder however fast the encoder is.

3. **The pacer writes duplicates through the same pipe and loses skipped
   slots.** When it falls behind, the recording tick writes up to four copies of
   one frame, each costing as much as a unique frame, and it advances its
   logical schedule without writing the skipped slots. A clip recorded for
   10.6 s is 6.53 s long (1.63×), so it plays faster than real life. This is a
   user-visible defect separate from the frame-rate ceiling.

Resulting recordings (unique frames per second = (frames − repeated) / clip
duration). The 720p rows used the candidate 720p30 build, whose log confirms the
vertical-blanking cap ran (`vblank 92 -> 2530`), so the sensor was already at
about 30 fps and the encoder was the binding limit:

| variant | frames | repeated | skipped | worst write | clip | unique fps |
|---|---|---|---|---|---|---|
| 720p30 candidate, run 1 | 196 | 125 | 123 | 56 ms | 6.53 s | 10.9 |
| 720p30 candidate, run 2 | 199 | 119 | 123 | 62 ms | 6.63 s | 12.1 |
| 720p30 candidate + 4 MB socket buffer | 238 | 158 | 93 | 37 ms | 7.93 s | 10.1 |
| 540p candidate | 172 | 90 | 125 | 54 ms | 5.73 s | 14.3 |
| 540p candidate + 4 MB socket buffer | 188 | 97 | 101 | 381 ms | 6.27 s | 14.5 |

Two longer dark recordings reached the same conclusion: the 720p30 candidate
gave 459 frames (15.3 s, 286 repeated, 198 skipped, worst write 124 ms, ~11.3
unique fps), and a build of the same 720p30 code with a faster 2×2 demosaic loop
gave 428 frames (14.3 s, 244 repeated, 219 skipped, ~12.9 unique fps). The
demosaic loop is 2.1–2.8× faster on an x86 host and bit-identical in output, but
it did not move the unique rate, because the bottleneck is the recording pipe,
not the demosaic. It has not been timed on the A53.

A 4 MB `SO_SNDBUF`/`SO_RCVBUF` removes the expensive worst-case writes but not
the ceiling: the limit is throughput, not per-frame latency. A 540p candidate
(960×540 capture, 540×960 output) is the best software compromise at 14.5
unique fps, but choosing a reduced resolution is a product decision, and that
candidate is not installed.

## What is not claimed

- 30 unique frames/s recording at any resolution; no resolution is accepted for
  recording.
- Any colour, AE/ISO or AF acceptance. Scene exposure improves only in the
  candidate build above.
- The 2×2 demosaic timing on the phone; only the host measurement exists.
- Any fixed ISO/shutter build: a host-only calibration candidate with manual
  exposure/gain environment overrides exists, but it was built on the same
  camera-v3/720p30 line, is not installed and was not measured on the sensor.
  Its base line is not part of this repository, so the delta is not published
  ([MAP](../MAP.md)).

The next levers, in the order the measurements support: a hardware encoder
([Venus](venus.md) works on this unit but is not integrated), a separate
recording thread so the application does not serialise demosaic and encode, and
fixing the pacer so a clip's duration matches the recording.

The pacer candidate described in "two source lineages" removes the 1.4–1.7×
speed-up by retiming the finished file to the wall clock with an `-itsscale`
stream copy (no frame added, dropped or re-encoded; offline check on the clips
above: 6.53 s of file → 10.63 s against 10.63 s of wall clock, all frames
decode). It does not raise the unique-frame ceiling, and it is a host-verified
candidate that has never been run on the phone. It is published as
[`patches/userspace/ztcamera/0004-pacer-retime.patch`](../patches/userspace/ztcamera/),
rebased onto the live line; [SERIES](../SERIES.md) carries the hash chain and the
status of the whole candidate series.
