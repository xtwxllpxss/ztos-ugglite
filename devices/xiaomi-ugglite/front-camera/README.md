# Front camera — S5K5E8 out-of-tree V4L2 subdev

Source for the front module of the Redmi Note 5A (ugglite): Samsung S5K5E8,
CCI bus 1 address `0x2d`, 24 MHz MCLK1, reset GPIO40 / standby GPIO39 (both
active-low), two CSI-2 data lanes.

This is **not** an upstream driver and it is **not** accepted front-camera
support. What is proven and what is not is stated below; the boundary is the
same one as in [docs/hardware-status.md](../../../docs/hardware-status.md).

## Verified on the phone

On the RAM candidate `11a4198590fac9f5804cef20201f513ca467ca1f3adceaf863381414ff4a6519`
(DT-only delta over the accepted baseline, accepted kernel/ramdisk inherited):

- the module `s5k5e8.ko` (sha256 `64b6572e8bb6675e996b80da28e2e3a51539ec8c935eaf80a00a96b79fd6de4e`)
  autoloaded against the running `7.1.3-msm89x7` kernel (vermagic matched);
- a chip-ID read at register `0x0000` returned `0x5e80` (16-bit big-endian),
  i.e. the rail/clock/reset sequence reached the part;
- the media graph bound both sensors: `s5k3l8 -> csiphy0` and
  `s5k5e8 -> csiphy1` links `ENABLED`, all `/dev/video*` present;
- a 640x480 SGRBG10 capture through `csiphy1 -> csid1 -> ispif1 -> vfe0_rdi1`
  produced exactly 384000 bytes and cleaned up (no residue, rear still works).

## Not verified / not claimed

- No accepted preview and no accepted still. Orientation is expected to be
  wrong: the installed ztCamera live path transposes the Bayer frame 90° and
  does not mirror; the stock front orientation is 270° + mirror, so the preview
  is probably upside down and unmirrored. Not tested.
- 1296x972 and 2592x1944 modes, AE, and the register init preamble are
  unproven. The five mode tables are per-mode register lists from the stock
  HAL; there is no shared group-hold/stream-on preamble in them, and
  stream-on (`0x0100 = 1`) is the Samsung standard, not an observed write.
- The link frequency `418 MHz` is derived from the HAL `op_pixel_clk`, not
  measured on the board.
- VFE1 is unusable on this board; the working path is VFE0 RDI1.

## Board-level consequence, not a defect in this driver

CAMSS registers **one** v4l2-async notifier for the whole controller. It
completes only after *every* sensor node has bound, and it creates all links
and video nodes at that point. With the front node present, the rear graph is
therefore created only after `s5k5e8` binds — the same mechanism already
accepted for `dw9714`. A DT-only "node exists but does not block" variant does
not exist. Mitigation is early module autoload in userspace
(`/etc/modules-load.d/ugglite-front-camera.conf` in the local delivery), not a
different DT.

## Build

```sh
make -C <pinned linux 7.1.3-msm89x7 tree> M=$PWD ARCH=arm64 LLVM=1 modules
```

The mode tables were extracted from the stock
`libmmcamera_s5k5e8_{oef0501,f5e8ybf}_d6.so` (identical `.text`/`.rodata` in
both variants). A register record is `(u16 addr, u8 value)`; 16-bit quantities
are split over two consecutive byte registers, which is why the driver uses a
16/8 regmap rather than the rear `s5k2xx` 16/16 one. The values are functional
settings taken for interoperability; no code from that binary is included, and
the original driver code here is GPL-2.0-only like the kernel tree it builds
against.

## Files

| File | Role |
|---|---|
| `s5k5e8.c` | V4L2 subdev: power sequence, regmap, modes, stream, exposure/gain |
| `s5k5e8_modes.h` | five per-mode register tables, generated from the HAL |
| `front-stream.dtsi` | reference DT delta that was booted (labels restated, not compiled) |
| `Makefile` | out-of-tree module build |
