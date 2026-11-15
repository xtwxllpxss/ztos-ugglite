# Sensors and auto-rotate — the hub fix, verified after one reboot

The sensor hub on this device was loaded out of order: the sensor registry
firmware could be picked up only after the ADSP had already started, so the
fallback ran late and the sample consumers saw a starved or silent buffer. A
small device-layer overlay puts the registry and the module ordering in place
**before** the ADSP start. Status: **installed on the phone and verified after
one reboot**. The physical tilt was **not** verified by the owner yet.

No kernel, boot image, DT or partition change is involved. The registry file
itself is device-local vendor firmware and is not published; the kit scripts and
overlay are not published (device transport and unpublished payload paths), as
recorded in [MAP](../MAP.md).

## The defect

The sensor hub exposes a registry blob (`sns.reg`) that the driver
`qcom_sns_reg` loads into the DSP's registry layer, and the ADSP then comes up
through `qcom_q6v5_pas`; the `.reg` data must be present before the ADSP boots.
Without a load-order constraint the driver's probe raced the ADSP start and the
registry succeeded only through the late fallback (about 7.6 s), leaving the QMI
sensor service (`qcom_smgr`, endpoint `100:3201`) and the IIO devices without a
working source. The visible symptom was "no samples" from `zt-sensors`: the
accel/gyro/magnetometer/proximity devices existed, but their buffers delivered
nothing to a consumer.

## The fix (device-layer overlay, reversible)

Five files, installed from a host-side kit with a manifest, a backup and a
rollback script; `persist` was never mounted and the boot slot was untouched:

1. the registry blob in `/usr/lib/firmware/qcom/sensors/sns.reg`;
2. a `modprobe.d` soft dependency that makes `qcom_sns_reg` load **before**
   `qcom_q6v5_pas`;
3. a `modules-load.d` entry for the registry driver;
4. a udev-triggered oneshot unit that could supply the registry if it were
   missing at probe time — it is inert when the file is already in place,
   because its `ConditionPathExists=!` is false, which is the intended steady
   state;
5. the helper/manifest needed to install and verify the above.

One coordinated reboot was enough; SSH returned in about half a minute.

## What was verified (2026-11-15, after the reboot)

Order and registry layer:

| Observation | Value |
|---|---|
| registry firmware loaded | **3.215 s** (before the fix the success path was ~7.6 s) |
| ADSP up | **3.886 s** — order registry → ADSP holds |
| vendor-suffixed lookup failure | `sns.reg-xiaomi,ugglite` returns `-2`; the driver documents this `-ENOENT` as ignorable, and the generic file loads |
| driver binding | `qcom_sns_reg.qcom-sns-reg`, `initstate=live` |
| QMI endpoint | QRTR device `5-8`, `MODALIAS=qrtr:100:3201`, bound to the `qcom_smgr` driver |
| udev oneshot | `Result=success`, exit 0, enabled but inactive — no bind-mount fallback was needed |

Function and data:

- `zt-sensors` runs with live accel/gyro/magnetometer/proximity lines that
  change, `orient=up`; no "no samples" warnings in the journal.
- `/dev/iio:device1..4` are the accel/gyro/mag/prox nodes, buffer enabled, scan
  element counts 4/4/4/2. With the consumer stopped for ≤5 s a non-blocking
  read returns **24 / 24 / 24 / 16 bytes** respectively, i.e. a full scan from
  every device (while the daemon runs it drains the QMI-pushed buffer itself,
  which is why a third-party read then sees 0 — expected, not a defect).
- `zt-sensors rotate --set on` + restart applies `auto_rotate = on` without
  errors and sensor data continues. The original value (`off`) was restored and
  `/etc/zt-sensors.conf` matches its automatic backup byte-for-byte.
- Post-reboot checks: **PASS=36 FAIL=0** (one pre-existing `venus` firmware
  version warning), `failed_units=0`, screen off. Kit integrity: all five files
  match the manifest; the rollback script remains available.

## Auto-rotate: unblocked at the sensor layer, not accepted visually

The sensor layer no longer blocks rotation: the daemon accepts
`rotate --set on`, the configuration path works, and the sample stream is
present — the prerequisites that were missing are now met.

Rotation in the compositor itself is **not implemented**: the ROTATION LOCK tile
in the quick settings is a stub, so there is no screen-orientation path in the
UI to accept. What is **not** done:

- the **physical tilt was never performed** by the owner: orientation polarity,
  axis mapping and the actual 180° result are unobserved;
- the separate opt-in 180° compositor kit (a patched compositor build plus
  install/verify/rollback) stays a **candidate**: its base is a locally built,
  fade-tuned compositor not reproducible from the published series, and its
  orientation polarity was never observed on the device. It is documented in
  [auto-rotate.md](auto-rotate.md) and its binary/patch are not published
  ([MAP](../MAP.md)).

So "auto-rotate unblocked" means the sensor prerequisites are verified; it does
not mean rotation was accepted by the user.

## Limits

- Only one reboot and one boot-time measurement; no multi-boot soak.
- The overlay installs a vendor firmware copy from the device's own modem
  partition; it is not downloaded, not redistributed and not published.
- No boot image, kernel, DT or partition change; rollback restores the previous
  firmware path state and removes the ordering files.
- The measurements are from one device; the load-order contract is from the
  driver source, and the observed ordering is consistent with it.

## Evidence boundary

The timings, bindings, byte counts and byte-identical config restore are live
readbacks from the phone journal and sysfs in the verified boot. No boot id,
session log or host path is published. The physical tilt and visual rotation are
explicitly **not** part of the verified result.
