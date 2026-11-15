# Front camera — the `Loading…` failure, the fix, and what is accepted

Status: **fix delivered to the phone and accepted by the device owner**. The
front camera now shows a live preview. This file states the defect, what was
changed, what was observed after the fix, and what is still not claimed.

Kit material lives in [devices/xiaomi-ugglite/front-camera/](../devices/xiaomi-ugglite/front-camera/);
the camera binary and its logs are not published.

## The defect

The S5K5E8 sensor itself was already working: chip ID `0x5e80` was read over
CCI1, CAMSS bound both sensors (`s5k3l8 → csiphy0`, `s5k5e8 → csiphy1`), and a
640×480 SGRBG10 capture produced a full 384000-byte buffer. The camera
application, however, sat on a `Loading…` screen with four dots: the preview
process was gone, and no frame ever reached the UI. In the application sweep
this was recorded as a FAIL of the front-camera case.

## The fix

The cause of the stuck `Loading…` state was identified in the application's
startup path, and a corrected binary was built, installed and accepted. The
previous binary was kept as a backup:

| | binary |
|---|---|
| before the fix (backup) | `ea79a1c8…` |
| after the fix (installed) | `c2a28339…` |

No kernel, DT, boot image or partition change was involved; the fix is a
userspace replacement.

## What was verified after the fix

- The preview node `/dev/video1` delivers live frames at **640×480**, about
  **62 fps** — a moving preview, not a single still frame.
- The camera application leaves `Loading…` and shows the preview.
- The owner accepted the result on the phone.

The first capture path (384000-byte SGRBG10 buffer) and the sensor binding are
stated in [hardware-status.md](hardware-status.md).

## What is not claimed

- **Orientation and mirroring of the preview are not accepted** — the physical
  result was not judged by the owner.
- **Higher modes are not accepted.** The larger front modes (1296×972,
  2592×1944) were not verified in this pass, and AE behaviour is not calibrated.
- A front-camera node still delays the rear graph, because CAMSS has a single
  async notifier; that limitation is unchanged.
- One fix, one boot: no soak test and no regression sweep of the rear camera
  after the replacement.

## Evidence boundary

The frame size, the fps rate and the accepted preview are live readbacks from
the phone after the install; the binary identities are hash prefixes of the
installed file and its backup. No screenshot, run log, boot id or host path is
published.
