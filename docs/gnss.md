# GNSS client — prepared install kit, not installed

The modem's GNSS engine already works on this unit, but nothing on the device
asks it for a position yet: there is no user-space client. This file documents
the prepared client kit, what it does, how it is verified, and what is still
missing. It is a **prepared kit, not an installed feature**: none of it has been
written to the device, no unit was enabled, and no fix was observed through
GeoClue.

Current verified engine state: enabling `gps-raw`/`gps-nmea` produces NMEA and a
satellite was received at SNR 31; no fix indoors is expected
([hardware status](hardware-status.md)). The kit adds the client, not the
engine.

## What the kit is

`geoclue` 2.8.2 with its ModemManager provider. An application creates a
GeoClue client; GeoClue asks ModemManager to enable location and disables the
source when the client goes away. There is no permanent daemon and no
permanently running GPS session. `iio-sensor-proxy`, network location and
Wi-Fi/3G/IP sources are not used.

Seven files are installed; the package itself (`pacman -S geoclue`) is a
separate prerequisite and is not in the current image package list.

| File | Purpose |
|---|---|
| polkit rule `60-ztos-geoclue-modemmanager.rules` | **required**: GeoClue runs as a system user without a logind session, while ModemManager's `Device.Control` (used for `Location.Setup`) defaults to `auth_admin`; without the rule setup fails with "Not authorized". The subject is only the `geoclue` user |
| geoclue drop-in `90-ztos-ugglite.conf` | `[modem-gps] enable=true` only; every network source is `false`; a headless-client whitelist entry for the probe. The path is `/etc/geoclue/conf.d/` — in GeoClue 2.8.2 that is `CONFIG_D_DIRECTORY`, and `/etc/geoclue/geoclue.conf` is not modified |
| `ztos-modem-gnss.service` | Arch/systemd port of the pmaports `modem-gnss` preparation: `qmicli --loc-set-engine-lock=mt` and `--loc-set-nmea-types=all`. **Not enabled by default**: ModemManager 1.24.2 already produces NMEA traces, so this is a fallback only |
| `ztos-gnss-session.service` | on-demand oneshot, 180 s cap for an NMEA proof and for clients that bypass GeoClue. No `[Install]`, so it cannot be enabled; `ExecStopPost` force-disables the sources |
| `ztos-modem-gnss` | wrapper for the preparation unit: checks, logs, `mmcli -L`, before/after readback |
| `ztos-gnss-session` | enables `gps-raw`+`gps-nmea`, polls NMEA/fix, disables on trap; `--cleanup` only disables |
| `ztos-geoclue-probe` | headless end-to-end probe: client → GeoClue → ModemManager; proves `gps-nmea` is on while the client lives and off afterwards, and prints the coordinates only locally |

What is deliberately **not** installed: the `geoclue` package, Bluetooth
support, applications, and edits to `/etc/geoclue/geoclue.conf`.

## Power behaviour

GNSS is on request and always switched off:

- `geoclue.service` is D-Bus activated (`Type=dbus`, no `[Install]`): no process
  exists until a client asks for a position;
- the `modem-gps` source opens the engine for the life of the client and closes
  it on `clear_caps`/`mm_modem_location_setup` teardown;
- the session unit starts only on an explicit `systemctl start`, runs at most
  180 s (`TimeoutStartSec=240`), and `ExecStopPost` disables the sources even
  after a `SIGKILL`;
- the preparation unit only configures LOC and is disabled by default;
- the overlay has no wants-symlinks for any of these units, so GNSS is off after
  boot.

## Install and verification (first run is still to do)

The install script is dry-run by default: it checks preconditions and prints the
plan, and `--apply` writes the seven files, backing up pre-existing ones. It
never enables or starts a unit. The full order is: install the `geoclue`
package, run the installer, then the verifier. `verify.sh` is a read-only,
ten-section PASS/FAIL check: package and system user, installed files +
`systemd-analyze verify` + units not enabled, drop-in contents, `geoclue.service`
running as the `geoclue` user, `pkcheck` for that process, the GeoClue provider
turning ModemManager `gps-nmea` on and off, NMEA in a bounded session, GPS not
left enabled, and no authorization/config errors in the GeoClue journal.

Manual equivalents:

```sh
mmcli -m 0 --location-status        # before: enabled: 3gpp-lac-ci
ztos-gnss-session 30                # bounded session; rc=10 indoors with NMEA, rc=0 with a fix
mmcli -m 0 --location-status        # after: enabled: 3gpp-lac-ci again
ztos-geoclue-probe --timeout 60     # rc=0 provider works (gps-nmea on->off), 10 also has a position,
                                    # 20 GeoClue did not enable GPS, 30 it did not disable it
```

Acceptance on the street: a `New location`/fix within 1–3 minutes with accuracy
of tens of metres, and the engine off again after the client exits. Coordinates
are personal data and are not written to reports, commits or chat.

## Limits and risks

- **The kit has not been installed or run.** The first run is an on-device step.
  The device was offline when the kit was prepared and needs a reboot first.
- **A-GPS/SUPL needs mobile data.** The modem is configured for
  `supl.google.com:7275` and the `xtrapath*.izatcloud.net` hosts, but WWAN data
  on this device is not proven (tariff allow-list). A cold start without A-GPS is
  slower; open sky works without it.
- **The polkit rule is broad in action, narrow in subject:** all of
  ModemManager's `Device.Control` for the `geoclue` user, because ModemManager
  does not pass per-method detail to polkit. That is the minimum needed and is
  an accepted risk.
- **Version sensitivity.** The drop-in targets GeoClue 2.8.x
  (`/etc/geoclue/conf.d`, `modem-gps`) and expects ModemManager ≥ 1.24. A
  `pacman -Syu` can update either; re-run the verifier after an upgrade.
- **The package is not in the image.** `packages.txt`/`device.toml` do not list
  `geoclue`; the overlay does not install it. That is a packaging decision for
  after acceptance.
- The kit scripts themselves are not part of this repository: they carry
  device-transport specifics and unpublished local payload paths. This document
  records the design, the verification and the boundary; the exclusion is stated
  in [MAP](../MAP.md).
