# Venus hardware video encode — firmware found, probe passes

MSM8917 includes a Venus video core. The kernel has `CONFIG_VIDEO_QCOM_VENUS=m`,
and the device tree node `venus@1d00000` is enabled with
`compatible = "qcom,msm8917-venus"`, a 4 MiB reserved-memory region and the
`core/iface/bus/vcodec0_core` clocks. On the installed root the boot-time probe
fails before any of that matters: `request_firmware("venus.mdt")` returns
`-ENOENT`, `venus_boot()` converts that to `-EINVAL`, and probe fails with `-22`.
The firmware was simply not in the root filesystem.

## The firmware is on the device already

It is in the stock `modem` partition (`/dev/mmcblk0p1`, vfat), which the modem
service mounts read-only at `/run/modem-ro`:

```
/run/modem-ro/image/venus.mdt
/run/modem-ro/image/venus.b00 … venus.b04
```

Six files, 633 040 bytes in total, built in 2019 from stock firmware
`MSM8917.LA.3.0`. This is the canonical Qualcomm firmware location (Android's
`/firmware/image`); nothing had to be downloaded, and no raw block device read
was needed.

The firmware loader's search path (`firmware_class.path`) is also pointed at
`/run/modem-ro/image`, so the firmware is reachable by name once that partition
is mounted. The ordering is the problem: the driver is probed at boot (about
5.5 s), before the modem service mounts the partition, and a failed probe is
never retried, so the device stays unbound for the whole boot.

The driver asks for `venus.mdt` and the loadable segments (`venus.b02`,
`venus.b03`, `venus.b04`). The split-image size (4 MiB) matches the reserved
region, so the size check in `venus_load_fw()` passes. There is no
`firmware-name` property and no `video-firmware` child node, so the driver takes
the trusted-zone path (`qcom_mdt_load()` plus PAS authentication and reset,
PAS id 9).

## Re-probing in a running boot succeeds

After the modem partition is mounted, unloading and reloading the core module
makes the probe pass without a reboot and without copying any file:

```
modprobe -r venus_core
modprobe venus-core
```

The kernel log shows the firmware being loaded from
`/run/modem-ro/image/venus.mdt` … `venus.b04`, the driver binds, and two
platform devices appear: `1d00000.venus:video-decoder` and
`1d00000.venus:video-encoder`. Two additional V4L2 nodes are registered;
`v4l2-ctl --list-devices` names them "Qualcomm Venus video decoder" and
"Qualcomm Venus video encoder". The `/dev/videoN` numbers are not stable across
reloads — use the device names, not the numbers.

Two warnings are expected and non-fatal: `Unsupported property: 0` and
`VenusLow : error reading F/W version`. The firmware still loads and the nodes
still register.

## H.264 encoding works on synthetic frames — after an HFI3xx fix

The stock encoder module cannot encode H.264 on this firmware: `venus_enc`
unconditionally sends `HFI_PROPERTY_PARAM_VENC_H264_TRANSFORM_8X8`, which the
HFI 1xx packet writer for HFI 3xx does not know, so `REQBUFS` fails with
`-EINVAL` (traced to `venc_set_properties+0x1a4 = -22`; the same code is in
mainline master, i.e. an upstream bug rather than a porting mistake). The
measurement below was made with the error check neutralised by **one NOP
instruction in `venus_enc.ko`** loaded from `/var/tmp` (the file in
`/lib/modules` was not modified). That binary patch is a diagnostic, not a
fix. The proper fix is a source change (skip the property on HFI 3xx); it is now
published as the candidate kernel patch
`patches/kernel/0003-venus-hfi3xx-skip-h264-8x8-transform.patch` (status in
[SERIES](../SERIES.md)). A full kernel was never built from it and it was never
booted, and no patched module is shipped here; the NOP-patched diagnostic module
is not published. The 2026-11-15 module build below shows that the fix does not
need a rebuilt kernel at all.


The encoder node is a V4L2 memory-to-memory device: NV12 frames in, H.264 out.
On a 1280×720 synthetic source, `v4l2-ctl` fed 300 frames and produced a
71 677-byte H.264 High stream that decodes completely (300/300 frames). A short
run of 300 frames took 6.7 s including process setup and teardown, i.e. about
45 fps, and the `v4l2-ctl` process used about 1.3 % of one CPU core. A software
x264 run on the same synthetic source finished faster in wall-clock but consumed
about 2.9 CPU cores: the value of the hardware path is the CPU budget, and it
has not been measured against the application's real recording pipe. Without an
explicit crop the encoder output is 1280×736 because of the 16-line height
alignment; with a crop it is exactly 1280×720.

This proves the encoder, not the feature. What it does not prove:

- no camera frame has gone through the Venus path yet; the application still
  records through ffmpeg/x264 on the CPU;
- the short run measures the encoder alone, not a 30 fps camera pipeline;
- Venus **decoding** is not working in this configuration: the decoder returned
  "event not sufficient resources" and a frame-number gap, and decoded only 17
  of 30 frames of a software-encoded reference. The encode direction is the
  useful one; the decode direction stays unproven.

## The fix is one module replacement — no Image rebuild

`venus` is built as a module (`CONFIG_VIDEO_QCOM_VENUS=m`), and the file the
one-line fix changes, `hfi_cmds.o`, is linked into `venus-core.ko` — not into the
kernel image. Delivering the fix therefore does **not** require rebuilding the
kernel `Image`, the ramdisk or the DT: one module in the root filesystem is
replaced, and the accepted boot baseline stays exactly as it is. That is a
different scope from the kernel candidate in [SERIES](../SERIES.md), which exists
for anyone who wants the change in the image instead.

Built host-side from the pinned tree plus the published candidate patch, in the
project's aarch64 container with clang/LLD:

- `venus-core.ko`, `venus-dec.ko` and `venus-enc.ko` were produced from the
  patched tree; the core module's `srcversion` is `8A3493636BC04E7B32F5841`
  against the baseline module's `A89A6883…21D6`, and its `vermagic` is
  `7.1.3-msm89x7 SMP preempt mod_unload aarch64`, byte-for-byte the running
  kernel's value;
- the undefined-symbol sets of the rebuilt and the baseline core module are
  identical (139 = 139, empty diff), and `CONFIG_MODVERSIONS` is off, so there is
  no symbol-CRC gate beyond the vermagic;
- the patch is proven at object level: patched and unpatched `hfi_cmds.o` differ,
  and the disassembly of `pkt_session_set_property_1x` changes (452 → 440
  instructions);
- the modules are unsigned because module signing was disabled in the build copy
  only (`MODULE_SIG_FORCE` is not set on the device), so loading one taints the
  kernel with `E`.

Status: **modules built, not delivered.** They were built host-side (the phone
was left alone), and nothing was installed, loaded or booted: the unit still
needed its planned restart after the earlier Venus oops, so device acceptance is
open. No module binary is published here — it is a binary and it is only valid
for this exact kernel build. Loading it is kernel code, so it needs the owner's
explicit agreement, even though no partition is involved.

The reversible shape, if someone repeats it with their own build:

1. back up the stock `venus-core.ko.zst` inside the module tree in the root
   filesystem (never in the boot image), with its hash;
2. put the rebuilt module at the same path and run `depmod`;
3. take effect with a single module reload or a restart (one re-probe per boot —
   see the warning above);
4. verify: the module reports the expected `srcversion` and `vermagic`, the
   encoder node appears, a 720p H.264 memory-to-memory encode succeeds without
   the NOP module and without an unsigned diagnostic module, and the kernel log
   is clean apart from the expected unsigned-module taint;
5. roll back by restoring the backup, then one reload or restart.

Risk: if the vermagic or the symbol set does not match, the module refuses to
load — the failure is loud and safe. The same firmware, the same HFI version and
the same one-re-probe-per-boot rule from the section above apply.

## Persistence, licensing and risk

The files are proprietary Qualcomm firmware. They are **not** in this
repository, not redistributable, and not downloaded from anywhere: they exist on
the device because the stock modem partition exists, and the repository ships no
blob, no firmware copy script and no installer. A persistent arrangement has to
make the files reachable at probe time — for example a rootfs copy, or a unit
that mounts the stock partition and re-triggers the probe. Neither is published
here, and reboot-time behaviour was not tested in this pass: the re-probe above
was done in the running boot.

Risks, for anyone who repeats it: PAS authentication can refuse on another unit
or another firmware version, and the HFI version expected by this kernel
(`HFI_VERSION_3XX`) must match the stock firmware. A failure would show up in
the kernel log, not as missing files. Enabling the VPU is a short power/clock action. Do **not**
`modprobe -r venus_core`/`modprobe venus-core` more than once in a boot: a
second re-probe on this kernel crashed in `venus_add_dynamic_nodes` (upstream
bug) and left the VPU powered with no V4L2 nodes until the next reboot. One
re-probe after the partition is mounted is safe; repeating it is not. The
device tree node, the modem mount and the modem service were not modified.

## What is not claimed

- Camera recording through Venus, or any recording improvement: not integrated,
  not measured. A camera-side recording backend that feeds the M2M encoder
  exists as a host-only candidate: it was unit-tested against a mock V4L2 loop,
  was never run on the device, and depends on the camera-v3 application source
  line, which is not part of this repository, so its delta is not published
  ([MAP](../MAP.md), [camera and video](camera-video.md)).
- Loading the rebuilt module on the phone: the modules were built host-side and
  never installed, loaded or booted here; device acceptance is open.
- Boot-time persistence, or behaviour on any other unit.
- Hardware decode.
- Redistribution of the firmware.

Next: integrate the encoder into the camera application, and keep the separate
recording-thread and pacer fixes from [camera and video](camera-video.md) — a
hardware encoder alone does not give 30 unique frames/s while the application
still does demosaic, scaling and the encode feed on one thread.
