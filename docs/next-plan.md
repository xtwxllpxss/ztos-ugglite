# Next work plan, in priority order

This is a work-ordering document, not a status claim. Nothing here is accepted
until the acceptance evidence named for it exists. Each item states why it is
where it is, what one next step is, and what would count as done.

## Where the device actually is

| Area | Verified state |
|---|---|
| Installed root | direct-root `/ztos-root` on userdata ext4; no reinstall, no Android flash |
| Working RAM boot | kernel + camera DT + low-power panel module; USB SSH, DRM and backlight present |
| Latest experimental candidate | did not pass boot acceptance: no USB SSH, no DRM, no backlight, `usb0` down |
| Display | brightness visibly changes; a few-pixel downward frame shift remains |
| Modem | LTE registered/home, 67–70 % signal, UI indicator confirmed; data/APN, SMS, calls, GNSS and call audio unverified (see `docs/modem.md`) |
| Camera | CAMSS/CCI, media0, video0..5, 14 subdevs, two CCI buses bound; no sensor driver, no frames |
| Time | correct system time without NTP via `swclock-offset`; hardware RTC stays at 1970; RTC writes stopped |
| Control channel | ACM exposes a fixed command set only: no shell, no reboot-to-bootloader |

## Ordering and gates

**P0 boot return → P1 display → P2 camera → P3 modem data → P4 RTC → P5 sensors
→ P6 documentation.** P2–P6 preparation is host work and can run in parallel, but
the hardware part of any item waits for P0, because only one actor may own
USB/ACM/fastboot at a time. No new blind RAM images: first explain why the last
MSM candidate failed.

### P0 — Return to a booting system — WAITING

Waiting on one physical fastboot entry: the ACM console cannot reboot to
bootloader, and `RESTART2` from this OS is unverified.

Do: enter stock bootloader → `fastboot boot` lk2nd → check product → `fastboot
boot` the last accepted image, after verifying its SHA256. Never substitute a
"similar" image. Done when: boot id obtained over USB SSH, DRM and backlight
present, LTE home, media0 present, `systemctl --failed` empty, installed
direct-root unchanged.

### P1 — Display jitter and DSI PLL — BLOCKED on P0

Blocked because the hypothesis (PLL reprogrammed on every brightness write) was
never tested: the carrier image did not boot. Editing sources further without an
explanation of that failure is prohibited.

1. Host-only, ready now: read the persistent journal of the failed candidate —
   which module/srcversion actually loaded, symbol/version/probe errors, `usb0`
   and SSH state.
2. Verify the provenance of the full MSM build against the boot kernel, generated
   headers, the original `.ko` and the compile flags. One `dsi_host.c` or config
   diff is not enough for the whole DRM module.
3. Only then one new candidate, boot acceptance, then the same 64/200/64 root
   write with a clock trace, and a separate visual check.

Done when all four hold: (a) candidate boots with SSH and DRM from the accepted
base; (b) the expected MSM srcversion is confirmed; (c) no `dsi0vco_clk` set_rate
appears during the brightness write; (d) the owner sees no shift. (c) and (d) are
different checks and both are required.

### P2 — Camera sensor bring-up without EEPROM — READY (host) / BLOCKED (hardware)

Known: rear module is either S5K3L8 or OV13855 (module variants), front is S5K5E8
— these are families, not this unit's inventory. `slave-addr 0xa0/0x5A` are
EEPROM addresses; the sensor address itself is unknown. Rails: `cam_vdig` l23
1.2 V, `cam_vana` l22 2.85 V, `cam_vio` l6, `cam_vaf` l17 (rear). GPIO: mclk0 26 /
reset0 36 / standby0 35, mclk1 27 / reset1 40 / standby1 39. The source
contradicts itself on MCLK (24 MHz in the power sequence, 19.2 MHz in the EEPROM
nodes) — take the frequency from the sensor datasheet.

Prohibited: reading the EEPROM (personal calibration), writing NV, guessing
reset/standby polarity from `0` flags.

Do: a DT-only RAM candidate that enables `&camss`/`&cci`, applies the rails and
MCLK in the documented order, and performs a read-only chip-ID read of the sensor
at candidate addresses. Done when the chip ID matches S5K3L8 or OV13855 (not the
EEPROM), then a frame from `/dev/video*`. A registered media graph is not camera
acceptance.

### P3 — Modem data/APN — READY; SMS/calls — WAITING (explicit request only)

Known: QMI online, CS/PS attached, ModemManager registered/home. Data session,
SMS, calls, call audio and GNSS untested.

Do: one bounded `mmcli --simple-connect` with the operator APN from the owner's
profile; check address, DNS and route through `wwan`. Never commit APN
credentials. Done when: session up, outbound traffic and DNS go through the
modem, LTE not lost, `ztos-modem.service` not restarted by hand, EEPROM access
still read-only (`rmtfs -r`, shadow in RAM).

### P4 — RTC diagnostics with ramoops — BLOCKED, no failure location preserved

Blocked because two crashes at WRITE_BEGIN and one interrupted `hwclock` left an
unknown outcome. `CONFIG_PSTORE_RAM=y`, but there is no ramoops reserved-memory
region and pstore is empty; an empty pstore does not prove the region is absent.

Prohibited: further RTC writes or new RTC candidates in this item.

Do: a separate diagnostic RAM image with ramoops on the real memory map (do not
guess the address) and markers around individual SPMI operations; then one
controlled run and read pstore. Done when a reproducible failure marker or a
documented reset reason exists — only then is restoring writes worth discussing.
A hard PMIC power loss may lose RAM even with ramoops.

### P5 — Sensors / SMGR — BLOCKED, no part number

Known: the SSC/ADSP interface and the `qcom_smgr` client exist; the actual chips
are unidentified and there are no IIO nodes. `BMA255` inside `sensors.ssc.so` is a
catalogue label, not identification. I2C probing is a hardware step with side
effects, not a read-only operation.

Do: read-only evaluation of `qcom_smgr` on the live rootfs (which SSC clients and
registry entries are actually visible), without streaming or NV; in parallel look
for a board marking or a device-specific source. Done when a part number with bus,
address, supplies and IRQ is confirmed, or the registry yields an unambiguous
device list — only then a DT patch.

### P6 — Documentation and publication — READY

Rules: commit only explicitly chosen files, no `build/`, images, firmware, keys,
network profiles, EFS or raw logs; meaningful messages without backdated
timestamps; verify the published SHA by reading the remote branch. Anything
untracked without a commit and a provenance line is a draft, not an artifact.

## Known, not prioritised

- **Audio C2 and gain.** The C2 design fails across processes; the hardware path
  is blocked and fully rolled back; idle hiss remains. The last attempt modified
  source after the build, so that set must not be delivered. Do not change gain
  before P1.
- **Touchkey long-press.** Logic (short/long, 450 ms) exists in the touchkey
  daemon, but there is no device acceptance recorded for the current build.
  Treat as open; do not rework without an explicit request.
