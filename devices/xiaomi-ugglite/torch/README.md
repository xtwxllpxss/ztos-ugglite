# Rear torch — `white:torch` on gpio34

The rear flash of the Redmi Note 5A is two TLMM lines: `gpio33` is the
flash-enable line and `gpio34` is flash-now. The stock firmware drives them
with a vendor LED driver (`qcom,leds-back-gpio-flash`) that mainline does not
have; the mainline board DT has no flash node at all. ztmetro's flashlight
tile was therefore writing a path that nothing created.

This directory is the complete delta that gives the tile its node: a
`gpio-leds` fragment using the stock `leds-gpio` driver (already built in,
`CONFIG_LEDS_GPIO=y`), the udev rule that lets the UI user write it, and a
one-shot helper.

## Verified on the phone

The DT-only RAM candidate
`6995175f872e8bdf5f9cc1b8126a9af50e5431425ce148a18366c12c9ad516c7`
(front-camera DT plus this torch block; accepted kernel and ramdisk inherited)
booted and exposed:

```
/sys/class/leds/white:torch/brightness        max_brightness = 1
/sys/class/leds/white:torch/trigger           [none]
```

With `72-ugglite-torch.rules` applied, `brightness` becomes `root:alarm 0664`,
so the `alarm` user that ztmetro runs as can write it. ztmetro's tile writes
exactly this path — `TORCH_PATH = /sys/class/leds/white:torch/brightness`,
level 9 — and the node it was missing now exists.

That is the proof: the node, its gpio, its `max_brightness` and the write
permission are all observed on the device. It is not a mainline flash driver
and makes no claim about strobe, current control or a torch mode beyond
on/off. The candidate image itself is not published here (see the build gaps
in [`MAP.md`](../../../MAP.md)); this directory carries sources only.

## GPIO mapping is vendor-derived

`gpio33 = flash_en`, `gpio34 = flash_now` and the 1..200/201..255 split come
from the vendor DT and the vendor `leds-msm-back-gpio-flash.c` driver, not
from a pin-level measurement on this board. The mainline DT uses neither line
for anything else. Do **not** search for the torch by probing other GPIOs: if
this mapping ever stops matching the hardware, the honest result is "no
torch", not a new pin to try.

With `leds-gpio` the vendor split disappears: `max_brightness` is 1, so any
non-zero value means on and 0 means off. ztmetro writes 9, which is clamped
to 1.

## Files

| File | Installed path / role |
|---|---|
| `torch.dtsi` | board DT fragment: `gpio-leds` `white:torch` on gpio34, pinctrl for gpio33/gpio34 |
| `72-ugglite-torch.rules` | `/etc/udev/rules.d/72-ugglite-torch.rules` — `chgrp alarm`, `chmod 0664` on `brightness` |
| `zt-flashlight` | `/usr/local/bin/zt-flashlight` — `on`, `off`, `status`, `test [seconds]` |
| `install-torch.sh` | installs the rule and helper on the phone, reloads udev, checks `alarm` access |
| `rollback-torch.sh` | forces the LED off and removes the rule and helper |

## DT

`torch.dtsi` is a fragment, not a complete board DTS. It matches the labels
of the pinned `msm8917-xiaomi-ugglite.dts`:

```dts
&tlmm { cam_flash_pins: cam-flash-pins { pins = "gpio33", "gpio34"; ... }; };
/ { torch-leds { compatible = "gpio-leds"; ... label = "white:torch"; ... }; };
```

Including it in the board DTS and rebuilding the DTB is a boot-image step, so
it is outside this directory's install scripts. The fragment restates the
decompiled delta that was actually booted and was not recompiled from the
pinned tree here. `gpio33` is driven low by the pinctrl state so the strobe
path cannot be opened by a floating enable line.

## Install and rollback (phone, root)

The node must already exist in the running boot; the scripts only handle the
userspace half and never touch `/boot`, the kernel, the ramdisk or the DT.

```sh
sh install-torch.sh     # rule + helper, udev reload/trigger, alarm write check
sh rollback-torch.sh    # LED off, rule and helper removed
```

`zt-flashlight` is one-shot, no daemon:

```sh
zt-flashlight status      # node, brightness, trigger
zt-flashlight on
zt-flashlight off
zt-flashlight test 5      # on for 5 s, then restores the previous value (trap)
```

`test` always restores what it found, including on Ctrl-C or a failed write.

## Boundary

- The flash emitter is not rated for continuous operation. Keep runs short;
  a long unattended torch is a heat and cell-drain experiment, not a feature.
- The tile is faint while the rule is not applied, because ztmetro gates on
  `access(path, W_OK)`. That is expected before `install-torch.sh`, not a
  second defect.
- The node is deliberately on the stock `leds-gpio` driver. There is no
  `flash` class device, no strobe, no current or duration control, and no
  interaction with the camera's flash-enabled metadata.
- ztmetro needs no rebuild: it opens the path on every tap.
