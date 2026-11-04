# Modem and offline time on ugglite

Status of every claim below is stated at the level it was actually verified on
hardware: driver bound → firmware running → userspace → UI → function. A bound
driver, an `active` unit or `rc=0` is not a working modem.

## Verified on hardware

After a RAM boot of the installed direct-root system (`/ztos-root` on userdata
ext4), the modem comes up without Android and without flashing anything:

- `qcom_q6v5_mss` runs the MSS firmware; `qcom_bam_dmux` binds and provides the
  DMUX channels.
- QRTR is up, `rmtfs` serves the modem's storage requests from a RAM shadow.
- WWAN DPM is configured and a USIM is selected, so ModemManager creates a modem
  object at all.
- ModemManager reports `state=registered`, `access technology=LTE`,
  `registration=home`; signal bars are populated.
- The Android-derived UI indicator (`ztmetro`) shows operator + 4 bars, and the
  device owner confirmed the operator name and bars on screen. This is the UI
  level only.

Not verified: data session/APN, SMS, calls, call audio, GNSS, mobile data
handover with Wi-Fi. Do not read "registered" as "usable cellular data".

## EFS / NV scope

Only `modemst1`, `modemst2`, `fsc` and `fsg` are read, and only through
`rmtfs -r`, where writes land in a RAM shadow buffer and are not persisted.
`persist` is never opened. No EFS dumps, hashes or copies leave the device.

`ztos-modem-storage` launches rmtfs as `-r -P -o /run/ugglite-modem-efs`, a
directory that contains only the four allowed symlinks. The unit uses
`DevicePolicy=closed`; the EFS devices are read-only and only
`/dev/qcom_rmtfs_mem1` is read-write, because that is the protocol's shared
memory, not an NV partition.

Consumers of this recipe may not extend that access. Any use without `-r`, any
disk write to NV, and any export of EFS content are outside this scope.

## What a complete OS image needs

- Packages: `modemmanager`, `libqmi`, `libqrtr-glib`, `ppp` (listed in
  `devices/xiaomi-ugglite/packages.txt`).
- A kernel with `qcom_q6v5_mss`, `qcom_bam_dmux`, QRTR and WWAN. The kernel used
  here comes from postmarketOS; no new MSS driver was written.
- `rmtfs` built from source: `/usr/local/libexec/ugglite-rmtfs`
  (`build-environment/build-ugglite-modem.sh`).
- The enabling files and symlinks in `devices/xiaomi-ugglite/overlay/`:
  `ztos-modem-storage`, `ztos-modem`, `msm-modem-wwan-port`,
  `msm-modem-uim-selection`, ModemManager, and the `swclock-offset` units.

Bring-up order: rmtfs RAM shadow → MSS firmware → WWAN DPM + USIM selection →
`operating mode=online` → ModemManager → consumers (NetworkManager, indicators).

Two device-specific findings, both reproducible without the other:

1. Without a USIM selection this unit returns
   `GW primary session index unknown` and ModemManager reports sim-missing even
   though the card is physically present.
2. Without WWAN DPM there is no net port and ModemManager refuses to create a
   modem object at all.

The postmarketOS helpers are kept byte-compatible in the overlay with one
addition: after USIM selection the operating mode is switched to `online`. MSS is
started once, not in a retry loop — an endless retry hides a firmware or storage
failure instead of reporting it.

## Stopping the stack before hardware experiments

```sh
systemctl stop ModemManager msm-modem-wwan-port msm-modem-uim-selection ztos-modem
systemctl stop ztos-modem-storage
```

Then check that MSS is offline, that `/run/modem-ro` is no longer mounted and that
the firmware path is restored. Do not stop rmtfs before MSS is offline. While MSS
is running, the `/run/modem-ro` mount and the `/run/modem-ro/image` firmware path
belong to `ztos-modem.service`: they are correct ownership, not leftover cleanup,
and an outside cleanup script must not remove them.

## Building without shipping binaries

In a native aarch64 Linux environment with gcc, git and libudev headers:

```sh
mkdir -p build/modem-root
sh build-environment/build-ugglite-modem.sh build/modem-root
```

The script installs only `rmtfs` into the given root; the device overlay and the
package list supply everything else. It fetches pinned revisions and verifies the
resolved commit before compiling. A build of it reproduced the delivered binary
byte for byte
(`9051e20afebc88edb85ce94b49e380706ca63ce65bca3bbbcb56756c525ea637`). A full
installable rootfs was not rebuilt in this pass.

Sources and terms:

| Component | Revision / version | Licence |
|---|---|---|
| [linux-msm/rmtfs](https://github.com/linux-msm/rmtfs) | `b30a3eb38f9af283f18dbd3c7755653efc52c094` (v1.3) | BSD-3-Clause |
| [linux-msm/qrtr](https://github.com/linux-msm/qrtr) | `29e36ae164389580a0f8ea7a7fdb728140ae978d` | BSD-3-Clause |
| [postmarketOS/msm-modem](https://gitlab.postmarketos.org/postmarketOS/msm-modem) | `5f504e0677f40dec93018d53a9b71aa1931db238` | GPL-3.0-or-later |
| [postmarketOS/swclock-offset](https://gitlab.postmarketos.org/postmarketOS/swclock-offset) | 0.3.0 | GPL-3.0-or-later |

`msm-modem-uim-selection` and `msm-modem-wwan-port` keep their GPL-3.0-or-later
headers and the upstream commit they were taken from. The full licence texts are
in `LICENSES/`.

## Time without a working RTC write

`swclock-offset` stores `UTC − raw RTC` in `/var/lib/swclock-offset/offset-storage`.
The RTC is only read: system time is corrected at boot, and the offset is saved at
shutdown.

Verified in a functional run after a RAM reboot: with NTP masked, `NTP=no`,
`NTPSynchronized=no` and `swclock boot rc=0`, system time still matched the host
within about a second. NTP was then unmasked and resynchronised.

This is working *system* time on a continuously running RTC counter; it is not a
repair of hardware timekeeping. A PMIC power loss or RTC reset can invalidate the
stored offset, and upstream 0.3.0 does not detect that case. Do not add
`allow-set-time` to the working device tree for this service — see the RTC section
of `docs/hardware-status.md`.

## UI indicators

`ugglite-modem-status.timer` runs every 10 s, reads only ModemManager state, and
publishes `sim/operator/bars/registered/tech/data` into the existing
`/run/ztoscorenetworking/status`, notifying the session FIFO only on change. IMEI,
IMSI, ICCID and phone number are never written to a file or to the journal. The
Samsung-derived daemon stays masked; two publishers of the same file must not run
at once. There are no new dependencies: `mmcli`, `sh`, `awk` and stock systemd.

Contract checked on the device: ready/home/4G, four bars, operator populated. With
Wi-Fi active the UI hides the technology label and shows the operator name in the
expanded panel. This is an observer; data/airplane buttons, Phone and Messages
still need a separate control backend.
