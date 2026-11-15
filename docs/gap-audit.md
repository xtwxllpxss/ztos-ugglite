# Open gaps — the ten things that stand between this port and a daily phone

Status: **2026-11-15, evening.** Host-side audit of the running install. This is
the honest "what does not work yet" list, ranked by whether a person can live
with the device as a phone — calls, messages, notifications, data, camera,
battery, stability — not by technical interest. Android application support is
strategically large but does not make the device a phone, so it sits outside this
list ([Android applications](atl-native.md)).

Sizing: **S** up to a day, **M** two to five days, **L** weeks. "Who" names the
kind of work needed: `host` (no phone), `device` (a supervised phone window),
`user` (a physical action such as a SIM, a call, headphones, a card or a tilt).

| # | Gap | Evidence that it is open | Severity | Size | Next concrete action | Who |
|---|---|---|---|---|---|---|
| 1 | **SMS: sending fails (modem error + network cause), a received message can stay stuck in the receive object** — not usable as a messaging phone | the receive path is documented in [SMS reception](sms.md); sending failure is recorded on the live install | blocker | M | install the host-verified receive-daemon candidate, then one outgoing and one incoming test; if sending still fails, capture the modem transaction | device + user |
| 2 | **Outgoing calls have never been tried**; the SIM reports an FDN lock with an empty list, which is a plausible local cause of rejection | call path documented in [modem](modem.md); incoming calls, ringtone and two-way audio were accepted earlier | blocker (unknown) | S (test) / M (fix) | one outgoing call to a known number, record the modem state and whether audio is two-way | device + user |
| 3 | **Mobile data: a bearer comes up, but application traffic does not flow** (HTTPS probes time out; the tariff is allow-list based, so it is not claimed either way) | [modem](modem.md) | blocker away from home | S (A/B) / M (fix) | A/B: the same SIM in another phone and another SIM in this device, then an HTTP(S) probe with the address/route/DNS recorded | user + device |
| 4 | **Android notifications and background work are incomplete** — an Android application without a window is effectively dead | [Android applications](atl-native.md#notifications--layer-1) | strong (for the Android scenario) | M (layer 1) / M–L (layer 2) | finish the merged batch, then run the notification probe end to end on the phone | host + device |
| 5 | **Stability: spontaneous hard hangs and one boot that did not come up without a power cycle**; no journal survives a boot that never reached the disk | boot observability kit is described in [hardware status](hardware-status.md#boot-observability--2026-11-15) | blocker for trust | M | with the markers installed, one regular reboot and one heavy camera+browser scenario, then read the health log | device + host |
| 6 | **Camera stills: autofocus scoring and exposure** — the installed build is being moved to a retry-based sweep and a colour-corrected pipeline; measurement is one window away | [camera and video](camera-video.md) | strong | S (one window for both) | run the AF and colour measurement protocols on three scenes and compare frames against the accepted build | device + user |
| 7 | **Camera video: about 11–14 unique frames/s in a 30 fps container, clips shorter than real time; 720p30 not obtained** | [camera and video](camera-video.md) | strong | M | measure the software NV12 candidate on one 10–15 s clip, then treat preview tempo as a separate measurement | device + host |
| 8 | **GNSS: the modem's engine works, but no user-space client is installed** — maps and "where am I" do not work | [GNSS client](gnss.md) | strong | S | deliver the prepared GeoClue client kit, verify the position indoors/outdoors | device + user (open sky) |
| 9 | **Audio on the move: the microphone is quiet (gain candidates not accepted), the headphone jack and Bluetooth audio were never tested** | [hardware status](hardware-status.md) | strong | S–M | deliver the UCM gain candidate, then one headphone and one A2DP test | host + device + user |
| 10 | **Battery: real drain and screen-off uptime are not measured** (the logger has only run with the cable attached); `deep` suspend is not supported by the firmware | [hardware status](hardware-status.md) | strong | S (measure) / M (idle) | one self-contained run of at least an hour without USB, screen off, Wi-Fi on | user + device |

Outside the ten, and not forgotten: real third-party APKs and a user-level
application installer for the Android path; the gallery's delivery; MTP/SD-card
exchange; a rotation mode in the compositor; update rollback and kernel-module
pinning; the Firefox SIGSEGV A/B; push (FCM/UnifiedPush-style).

## What was already closed or moved in the last day — do not re-raise as new

| Item | State |
|---|---|
| Android: native ATL recovered from the image and running applications as plain windows | recovered and observed; batches `-50`…`-52` installed ([Android applications](atl-native.md)) |
| Android: first application window (proof of concept) | closed as a proof of concept, not as user acceptance |
| Notifications: framework path | layer 1 implemented and partly installed; end-to-end pending |
| Camera colour | host-side candidate measured, installed candidate awaiting the device protocol |
| Camera autofocus | cause proven, retry-based candidate installed, measurement window pending |
| Gallery: delivery candidate | built, awaiting delivery |
| Home space (media moved off `/home`) | accepted on the device — `/home` free space 19 → 211 MB, verified after a reboot |
| Wi-Fi SSH persistence | accepted on the device — one wildcard listener, survives a reboot |
| Boot observability | kit installed, one reboot measured, markers present |
| Storage plan A (separate `/var`, `/home`, swap) | accepted on the device; first reboot after the move needed a power cycle (open risk) |
| Venus hardware encode | status fixed: trial stalled, rolled back, not accepted; retry only on a clean boot with diagnostics |
| Software renderer (pixman) | installed candidate: no GPU resets, the bottom-band defect is fixed |
| Publication #8 | done; this is publication #9 |

## Why this order

1–3 are the phone itself: without calls, messages and data, nothing else makes it
a phone, and none of the three needs a new kernel or device tree — an already
tested candidate and one user test each.
4 matters because without notifications and background, an Android application
is not "like on Android" even with a complete API.
5 comes early because spontaneous hangs devalue everything else, and two happened
in one morning.
6–7 are the camera: it works, but quality and video tempo are direct owner
requests and the candidates are already built, so the price is one device window.
8–10 are daily functions with a cheap start and a clear check.
