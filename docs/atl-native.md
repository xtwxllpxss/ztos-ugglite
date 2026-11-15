# Android applications on ztOS — native ATL, not Waydroid

Status: **2026-11-15, evening.** Android applications run through
[ATL (Android Translation Layer)](https://gitlab.com/android_translation_layer/android_translation_layer)
as ordinary Wayland clients of the ztOS compositor. There is no Android image,
no container and no second kernel: an APK is started by `ztos-android run` as the
regular desktop user, and its window is composited like any other window.

This file covers four things: what is installed and how it was recovered, what
was actually observed on the phone, the notifications layer underneath the
window, and the limits that no amount of API stubbing removes. The method used
to fill the API gap is a separate document: [the compatibility factory](compat-factory.md).

Status vocabulary: **works on device** (observed in a run on the phone),
**partial** (it starts and something visible happens, but the function is not
there), **blocked** (a known, named blocker stops it), **candidate** (built and
checked on the host, not installed).

## What is installed

ATL is not an experiment bolted onto the system: it ships with the ztOS image
built for this device, from the recipes under the project's `android/atl/` tree
(`art_standalone`, `android_translation_layer`, `bionic_translation`, `vixl`,
`wolfssl-jni`, `libopensles`). The built packages are installed and their
archives are kept in a local package store inside the image; the integration is
the `ztos-android` helper with `install`, `open`, `run`, `inspect`, `launch`,
`uninstall`, `list`, `doctor` and `sync` subcommands.

That mattered because the image had been slimmed before flashing: the trimmer
removed files that the packages still claimed, so ATL was installed but could
not start anything. Two removals were fatal:

- the whole `/usr/lib/java` tree (about 30 MB: the ART boot-classpath jars,
  `api-impl.jar`, `ghax.jar`, `framework-res.apk`, `natives/*.so`);
- `libtranslation_layer_main.so`, the JNI bridge.

`pacman -Qkk` named 25 missing files for `art_standalone` alone. The repair was
to reinstall the two packaged archives from the image's own store, with no
rebuild: the tree came back, `pacman -Qkk` reported 0 altered for both packages,
and `ztos-android doctor` returned "ARM64 runtime and linked libraries: OK".
The usable lesson is general: **a trimmed image can strip an installed runtime
silently**, and the package manager's file check is the tool that shows it.

An earlier approach, an Alpine aarch64 chroot with its own ART (about 700 MB),
proved that ATL itself works on this SoC but is the wrong shape: it needs root
and a chroot, duplicates the whole runtime, and complicates every system update.
The native path replaced it.

## How an application starts, and what it costs

```
ztos-android run <app>.apk   (as user alarm, no root, no chroot)
  -> ART standalone starts the app's dex
  -> ATL api-impl.jar answers android.* calls from the app
  -> the app's window is a normal Wayland surface in ztmetro
```

- First launch of an app: about **80 s**, almost all of it ART compiling a boot
  image (74 MB, cached under the user's cache directory). Later launches of the
  same app take seconds.
- Warm start to a visible window: about **4.5 s** (measured as the window
  appearing in the compositor, on this install).
- Resident memory: about **240 MB** for a small app; `MemAvailable` stayed at
  about 1.18 GB with one application open on the 1.8 GB device.
- The native window is edge-to-edge: the compositor does not draw a title bar
  for it. (The chroot experiment drew a client-side decoration; that is not part
  of the native path.)

The app's `stdout/stderr` go to a per-package log under the user's state
directory, which is how the device results below were read.

## Device results

Executed on the phone, one application at a time, logs and frames kept locally.
The frames and logs are **not published**; the table states what they showed.

| Application | What was observed | Status |
|---|---|---|
| `com.example.demo_application` (upstream ATL test APK) | window and rendered content on both paths; the earlier container path also logged `onResume`/`onWindowFocusChanged` | works on device |
| `dudeofx.eval` (Expression Evaluator) | window, `onResume`, rendered UI — measured on the earlier container path | works on device |
| `eu.veldsoft.politrics` (Politics, a small Canvas game) | full Canvas UI: board, pieces, coloured cells; observed on both the container and the native path | works on device |
| `com.ath0.rpn` (RPN calculator) | crashed before the API batches; after them the window lives and the calculator is usable | works on device |
| `com.tomatodev.timerdroid` | stopped crashing on `NoClassDefFoundError: ListFragment` after the API batch that added `ListFragment`; process stays alive | partial — the tab content is stub-only, so the UI can be empty |
| Frozen Bubble | no longer crashes; the window opens | partial — the game render is black: its page is a DMA-BUF SurfaceView page that the software compositing path does not read back |
| 2048 | blocked on `UnsatisfiedLinkError` for a native JNI symbol (`XmlBlock.nativeGetText`) | blocked — a Java stub cannot fix a missing native method; a separate native-path branch is in progress |
| Angry Birds Classic | the window opens, the app's GL thread starts, and the GPU stays healthy (0 resets under the software renderer) | blocked — no EGL context is created (`fd -1` from the Mesa `dri2` screen); this is an ATL/EGL platform branch, not an API stub |

What this demonstrates: small and medium 2D/Canvas applications are usable
today; games with their own GL/SurfaceView page need the EGL render path; native
libraries and JNI need per-symbol work that stubbing cannot provide.

## The API gap, in numbers

Measured against what three heavy applications ask for (Telegram 10.14.3,
VLC 3.7.2, NewPipe 0.29.3):

| Missing from the installed ATL runtime | Count |
|---|---|
| methods | 3058 |
| classes | 288 |
| fields | 621 |

Public `android.jar` signatures cover **3037/3058 methods (99.3 %)**,
**286/288 classes** and **618/621 fields** — the symbols are not the problem.
Three delivered batches closed most of the symbol-level gap (numbers from the
batch reports):

| Batch | What it did | Effect |
|---|---|---|
| `-50` | SDK-generated stubs plus two AOSP pilots (`ContentProviderOperation`, `AccessibilityNodeInfo`) | +644 classes / +8461 methods; applications stopped dying on `NoSuchMethodError` and moved to behavioural failures |
| `-51` | three behavioural NPEs (`PackageManager.getActivityInfo`, `Activity.getActionBar` returning null, `PackageParser` signature bookkeeping) | +130 members; applications moved past those crashes |
| `-52` | multi-API union: five public API levels merged into one virtual SDK, demand filtered against the real dex inventory | +16 classes / +181 methods / +47 fields, including `ListFragment`; strict superset check (0 removed symbols) |

Separately, an *AOSP-port study* measured how much of the same gap can be closed
by copying Android framework Java instead of writing stubs: **62.5 % of the
methods (1912/3058) are clean Java** that can be taken from AOSP; 28.9 % need a
thin native shim; 8.6 % (262 methods, 51 classes) have no backend in ATL at all
(camera, telecom/radio, Bluetooth/Wi-Fi, DRM, RenderScript, media extractors,
audio effects, TV, biometrics). Two AOSP pilots were fully ported and are in the
delivered jar: `ContentProviderOperation` (6/6 missing methods) and
`AccessibilityNodeInfo` (126/142). The conclusion is deliberately sober:
copying AOSP is the largest and cheapest lever for **API surface and Java
behaviour**, but a daily-driver application still depends on the B/C backends.

## Notifications — layer 1

Android notifications are the first non-window integration. The implemented
path was (host-verified; installed in pieces):

```
Android app -> ATL api-impl.jar (Notification.Builder / NotificationManager)
  -> GNotification -> GIO freedesktop backend -> D-Bus org.freedesktop.Notifications
  -> ztnotifyd (records id/package/actions; pushes a ctl line to the shell)
  -> ztmetro (banner + notification centre; updates by id, no duplicates)
  <- tap: raise the app window or launch the package, then send the tap back
  -> ztnotifyd emits ActionInvoked/NotificationClosed -> the app's intent
```

Pieces and their state:

- **ztnotifyd**: records id, package and actions, adds the ctl pipe, implements
  `notifyi`/`noteremove`, `click`/`close`/`closeall`, `GetCapabilities` with
  body+actions. Host smoke on a real session bus: 11/11 checks pass.
- **ztmetro**: banners and centre notes carry id/package/flags, update by id, and
  a tap brings the app forward. Banner pixel test passed (accent share of the top
  quarter 0.000 → 0.353 → 0.000) and the render regression against the previous
  binary was 16/16 byte-identical PNGs.
- **ATL side**: `getNotification()` returns the built notification (seven of 25
  scanned APKs crashed on the previous `null`), `setSound`, builder chaining,
  `(tag,id)` folding, `cancel(tag,id)`, `cancelAll()`, `notifyAsUser`.

Current install state, stated precisely: `ztnotifyd` and the notification-aware
`api-impl.jar` are installed; the compositor build that carries the banner and
tap handling was installed and then **replaced by the software-renderer build of
the same day**. The end-to-end sequence (banner appears → tap opens the app) has
therefore **not been proven on the phone yet**. The first probe APK also hit two
defects that are not notification bugs: an SDK stub shadowed a real `ViewGroup`
method (`FrameLayout.removeViews`), and the APK's `resources.arsc` could not be
unpacked. A merged batch is in progress.

Limits inside layer 1: notification action buttons are parsed but not drawn by
the shell (only the whole-note tap is reachable); a cold-start tap opens the app
but does not deliver intent extras; byte icons are dropped by the freedesktop
backend, so the icon comes from the desktop entry; channels, priority, sound and
vibration are kept in Java and not enforced by the shell.

## Adapters that already exist, and the limits that remain

Already inside ATL/ztOS and used by the path above:

- `android.graphics` Canvas rendered through GSK/Pango (the working path for 2D
  applications);
- EGL/GLES, `ANativeWindow` and `AHardwareBuffer` for `SurfaceView`-style pages
  (`libandroid/egl.c`, `native_window.c`), with the EGL platform branch as the
  open issue on this device;
- MediaCodec **decoders** through FFmpeg (aac, h264, mp3, opus, vp8, vp9) and the
  NDK `AMediaCodec`/`AMediaExtractor` surface; there are **no encoders**
  (`createEncoderByType` throws);
- sensors through IIO, audio through the ztOS PipeWire stack, input through the
  compositor;
- push: ztOS has its own MCS push service (`zrn-pushd`), independent of Android
  push.

Limits that are structural, not pending work:

- **No binder↔D-Bus bridge.** Android framework services that applications
  expect to reach over binder do not exist; ATL implements the class library,
  not the system services behind it.
- **No Skia/hwui.** The 2D path is GSK-based; there is no pixel-compatible
  `android.graphics` implementation.
- **No vendor Android backends.** camera/camera2, telecom/radio, Bluetooth/Wi-Fi,
  DRM, RenderScript, secure media buffers, biometrics and TV are stub-only on
  this platform.
- **Google services cannot work.** Play services, Play Integrity and Widevine
  DRM fundamentally require the Android platform and Google's signed components;
  microG is the same class of problem. Applications that hard-depend on them are
  out of scope for this port, not "work in progress".
- Native application libraries (`lib/*.so` inside APKs) load through
  `bionic_translation`, but every missing JNI symbol is a native defect
  (`2048` above), never a stub candidate.

## Boundary of these claims

- No Android application is accepted as a daily driver on this device. The
  table above says what was observed once, not that an application is supported.
- The notifications path is implemented and partly installed; end-to-end phone
  verification is pending, and this document does not claim it.
- The chroot experiment is history; the native path is the one that ships.
- Evidence (per-run logs, frames, APKs, package archives, host build trees) is
  kept in the private project tree and is not published. Statuses here are the
  stable part; the run detail is not.
