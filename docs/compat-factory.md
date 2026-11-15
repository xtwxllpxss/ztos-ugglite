# The compatibility factory — how the Android API gap is closed in batches

Status: **2026-11-15.** Host-side method and methodology. The phone was not
touched by the factory itself; delivery is a separate, gated step. This document
describes the machinery and the numbers it produced, and is deliberately explicit
about what it does **not** automate.

The factory exists because the ATL runtime on this device lacks a large part of
the Android API surface: heavy applications ask for thousands of methods and
hundreds of classes that the installed `api-impl.jar` does not declare. Writing
them by hand does not scale. The factory turns "write missing methods" into a
repeatable loop:

```
crash logs + static demand lists
        |
        v
  collect-crashes   -> one deduplicated queue (what is actually demanded)
        |
        v
    gen-batch       -> source stubs / small classes for one batch
        |
        v
    build-batch     -> javac -> jar -> dx -> api-impl.jar -> pacman package
        |
        v
    verify          -> symbol inventory of the new dex vs the old one
        |
        v
     deploy         -> backup, install, run the test corpus, harvest new crashes
        |
        +--------------------> back into the queue
```

Each step is a script with a machine-readable report; a batch is accepted only
when its verification gate passes.

## Inputs: what counts as demand

The queue is built from two kinds of input:

- **Static missing-API lists** measured against three heavy applications
  (Telegram, VLC, NewPipe): 3058 methods, 288 classes, 621 fields, plus an
  "early blockers" list and a per-application ranking of the most requested
  methods.
- **Real crash logs from the device**: `NoSuchMethodError`,
  `NoClassDefFoundError`, `NoSuchFieldError`, `UnsatisfiedLinkError`, parsed and
  normalised into the same identifiers.

Current queue state: **3356 unique requirements** (3065 missing methods,
289 missing classes, 1 missing field, 1 missing native symbol), idempotent on
re-run (a second collection adds nothing). Device-log entries are ranked above
static ones.

## Generation: signatures from a real SDK, demand-driven

The generator reads public `android.jar` files (they contain every public
framework signature; the bodies throw `Stub!`) and emits only what the demand
list asks for:

- **method and field fragments** inserted into classes that already exist in
  `api-impl`;
- **small stub classes** for classes that do not exist, with the constructors and
  members the queue knows about, plus a dependency closure (a stub whose
  signature needs another missing class pulls that class into the same batch).

Two generation modes exist and both are used:

1. **Single API level.** API 35 alone covers 99.3 % of the measured gap, so it is
   the default.
2. **Multi-API union.** Five public levels (21/30/33/34/35) are merged into one
   virtual SDK: 6422 classes instead of 5977. The union exists because new SDKs
   *remove* declarations — 445 classes are only present in older levels — and old
   APKs still call them. Class *shape* is taken from the oldest level that
   declares the class (old applications were compiled against that shape), while
   members are the union. Overloads are all kept; a member present with different
   return types is resolved by the demand call-site descriptor first, then by the
   widest type, then by the oldest API, and every choice is recorded as metadata.

Every generated element carries `origin_apis` (which levels declare it) and
`chosen_api` (which signature shape was used), so a batch can be audited without
re-reading the jars.

## Build: native javac, no emulation

The build runs on an x86_64 host with an ARM64 JDK for `javac` and an
`art_standalone` distribution for the Android boot classpath:

```
javac -source 8 -target 8 -bootclasspath core-all:core-junit:junit-runner
  -> hax.jar (classes)
  -> dx.jar -> classes.dex -> api-impl.jar
  -> pacman package (only api-impl.jar is replaced in the base package;
     .PKGINFO/.BUILDINFO/.MTREE are regenerated)
```

Measured cost on the host: the base tree is 841 files and compiles in about 3 s;
a batch compiles in 3 s and `dx` in 2 s; the full `-52` tree was 1254 sources with
`javac` and `dx` returning 0. Packaging is a swap of one file inside a copy of the
previous package, so a batch cannot silently change the runtime layout.

API 35 vs union on the same demand: 109 vs 223 generated declarations, i.e. the
union adds 114 declarations that an API-35-only generator cannot produce at all.

## Verification gate

A batch is not shipped until a **symbol inventory** of the new dex is compared to
the installed one, using class/method/field descriptors (not jar bytes; `dx` is
not byte-deterministic):

- the new set must be a **strict superset** — no class, method or field may
  disappear or be renamed (checked: `-51` over `-50`: 0 removed, +130 added;
  `-52` over `-51`: 0 removed, +16 classes / +181 methods / +47 fields);
- every generated declaration is checked against its source `android.jar`
  descriptor, including inherited members;
- each batch has a short checklist of concrete symbols that must be present
  (e.g. `ListFragment`, `getListView`, `setListAdapter`, `onListItemClick`,
  `initLoader`, `getNotification`, `setLatestEventInfo`);
- the packaged file and the installed jar are hash-checked again at install time,
  and a mismatch triggers an automatic rollback.

Host-side success is not device success. The gate only proves that the symbols
are there; the behavioural test is the next step.

## Deployment and harvesting

Deployment is gated and one-owner by design: it backs up the replaced files,
installs the package, verifies the installed jar, runs a small test corpus of
APKs with a timeout, reads each application's log, and normalises new crashes back
into the queue. It is **dry-run by default** and writes to the phone only with an
explicit apply flag plus an environment acknowledgement; the default path cannot
touch the device. Rollback is scripted from the recorded backup.

The harvest is the point of the loop: each batch moves applications past their
current first crash. The observed progression on this device (details in
[Android applications on ztOS](atl-native.md)) was:

| Application | Before | After a batch |
|---|---|---|
| RPN calculator | `NoSuchMethodError: fullScroll` | window lives; then behavioural NPEs; then works |
| timerdroid | `NoSuchMethodError: setNavigationMode` | `getActionBar()` returned null (fixed in the next batch); then `ListFragment` missing (fixed by the union batch) |
| Frozen Bubble | `NoSuchMethodError: Canvas.save(I)` | process survives and the window opens; render blocked by SurfaceView (not an API issue) |
| Angry Birds Classic | died in `PackageManager.getActivityInfo` | reaches its own GL thread; blocked later by EGL (not an API issue) |

A batch that turns one crash into another crash is a success for the queue: the
application moved further and the next demand entry is a real one.

## What the factory does not do

These are the honest limits, and they are the reason a stub batch is not a
feature claim:

1. **A stub is not a behaviour.** Generated bodies return `false`/`0`/`null` and
   log `ATL-sdk-stub`. They remove resolution failures; they do not make a method
   work. Applications may then fail later, or silently misbehave (black page,
   empty list) — that is a gap in the platform, not a factory bug.
2. **Native symbols are never generated.** `UnsatisfiedLinkError` and JNI
   requirements are collected as `native-missing` and reported as a boundary.
   They need native code or a Java-side workaround (for example a different
   codec), not a stub.
3. **Methods that need semantics are not solved.** MediaCodec, MediaExtractor,
   camera2, telecom, `Notification.Builder.getNotification()`, loaders, cursors
   and similar need real implementation work.
4. **Constructors of existing classes are not generated.** A correct constructor
   requires a valid `super(...)` chain that a descriptor does not describe;
   constructors of new stub classes are safe because their superclass is
   `Object`.
5. **Hierarchy of new classes is approximate.** Without a real framework class,
   a new class extends `Object`; `instanceof`/`catch` by parent type and
   inherited members that were not in the demand list are absent. Hints can set a
   parent, but a `View`-like class cannot be produced this way.
6. **Remaining API 36 / hidden API is out of reach.** 13 methods and 2 classes of
   the measured gap are not in any public SDK available to the generator; two
   more demands are unexpressible in a Java stub because the return type
   conflicts with the ATL implementation (`EdgeEffect.draw(Canvas)`,
   `Resources.getMovie(int)`).
7. **Nothing here is device-verified by construction.** Host verification proves
   symbols, not behaviour; the device corpus does, per batch and per application.

## State and where the generic part lives

Three batches (`-50`, `-51`, `-52`) were built this way; `-51` and `-52` were
installed and tested on the phone, `-50` was the base for both. A merged batch
that combines the latest API set with the notification API and a stub-shadowing
fix is in progress and is not claimed here.

The factory was born inside this device port. Its generic form — the queue, the
generator, the build and verification scripts, without any device-specific
inputs — is being published as a separate project:
<https://github.com/xtwxllpxss/native-apk-linux> (work in progress; this
repository does not depend on it).

Evidence (queue files, batch manifests, build logs, package archives, host
trees) is kept in the private project tree and is not published; the numbers
above are the stable part.
