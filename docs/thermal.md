# Thermal and charging — configuration, policy, and what is left alone

This file records how thermal management and charging are configured on the
device and which changes are deliberately not made. It is source and readback
analysis: there is no live thermal or power measurement beyond saved
power-supply readbacks, and **nothing described here was applied**. The RTC
write prohibition and the other device-side rules stay in
[safety](safety.md).

## Thermal: what the kernel already does

- **Zones and trip points:** ten tsens zones (`aoss`, `camera`, `cpuss1`,
  `cpu0`–`cpu3`, `gpu`, `mdm-core`, `q6`) plus the PMIC ADC thermal zone. The CPU
  trips are the vendor's: passive 75 °C, hot 85 °C, critical 100 °C (hysteresis
  2 °C, 250 ms polling); GPU 70/90 °C; the other zones have hot 85 °C only.
  These match the stock vendor device tree, so there is nothing to "fix" in the
  trip points.
- **Cooling:** one cpufreq policy for all four CPUs (OPPs 960/1094/1248/1401
  MHz) and the GPU devfreq. The governor is `step_wise`; there is no user-space
  thermal daemon. Note the vendor inheritance: CPU0's cooling map is attached to
  its hot trip, so the CPU0 zone does not throttle; the working thresholds are
  75 °C through `cpuss1` and 85 °C through CPU1–3, which step the single shared
  policy down to 960 MHz. 100 °C critical means a kernel power-off; it has not
  been exercised.
- **No `thermald` / `thermal-engine`:** thermald is Intel-only, the Qualcomm
  equivalent is a proprietary blob, and the kernel has neither a user-space
  thermal governor nor thermal netlink. A thermal daemon would have no interface
  to act through; this is by design, not a missing package.
- **GPU throttling is not exercised today:** the GPU is not loaded by the
  current workloads (camera processing is CPU/userspace bound), so the GPU
  cooling path is present but untested under a real GPU load.

## Charging: what the device tree and drivers do

- **Charger:** bq25601 with the bq27426 gauge. The device tree sets 3080 mAh,
  1.0 A charge current and 4.4 V for the battery; the charger node sets input
  voltage/current limits (VINDPM 4.5 V, IINDPM 2.0 A); precharge and termination
  are 120 mA; the thermistor/JEITA path is enabled and the charger watchdog is
  off.
- **Effective profile:** the driver's 2.04 A default is clamped by the device
  tree to 1.0 A constant current; the constant voltage is the chip default
  **4.208 V**, not the 4.4 V written in the device tree; termination is 120 mA;
  JEITA protects the cell from the NTC. The safety timer keeps its default.
- **No charge threshold:** the kernel exposes charger writes
  (`constant_charge_current`, `constant_charge_voltage`, `charge_type`, input
  limits), but there is no standard `charge_control_end_threshold` or
  `charge_behaviour`. A charge limit would therefore be a user-space write into
  the charger plus logic that guarantees the phone is charged when needed; that
  is not installed and is not planned in this pass.
- **Interpretation of "100 %":** the phone charges to the chip's 4.208 V and
  shows `Full` while on the cable. Holding that overnight is calendar aging
  (state of charge × temperature); one night is not significant, months are a
  user decision, not a defect. Saved readbacks reported 100 % `Full` on the
  cable at about 4.35 V with `charge_now` above `charge_full` — gauge
  calibration and top-off residue, not proven as a defect.

## Safe boundary

- **Safe:** a read-only snapshot of zones, trip points, cooling state, cpufreq
  and both power supplies, plus a load window (recording + charging) to see
  whether the 75 °C threshold engages and the frequency drops. That measurement
  has not been taken.
- **Do not** change trip points, cooling maps or thermal zones in the DT; do not
  "lower max frequency in idle" (the governor already sits at the lowest OPP and
  the domain power-collapses; there is no OPP below 960 MHz); do not raise the
  charge voltage or current; do not edit the battery node; do not port
  thermald/tlp/powertop-style "optimizers" (they tune subsystems this device
  does not have, or add load); do not touch the PMIC or RTC (the RTC write is
  unsafe — [safety](safety.md)); do not rework suspend here.
- The one manual, reversible experiment if long USB-data sessions on a PC port
  get hot: lower the charger input current to the USB 2.0 500 mA value for that
  session; the driver restores the device-tree default on reboot. It is a
  thermal mitigation for the port, not a charging fix, and it is not applied.

## What is not measured

- The live zone composition after a clean reboot. An older saved log listed ten
  zones but lacked some zones the source declares, so the composition is not
  settled; it has to be re-read before any policy is built on it.
- The charger's live limits, the load/thermal envelope and battery temperature
  under recording.
- Charge behaviour overnight on battery: that is a separate power measurement,
  not a thermal one.

## Evidence boundary

Trip points, cooling maps, charger limits and the battery/charger nodes come
from the pinned kernel device tree at tag `v7.1.3-r1` and the pinned kernel
configuration; charger and gauge values come from saved power-supply readbacks.
No run logs, device identifiers or host paths are published. Nothing in this
file was changed on the device.
