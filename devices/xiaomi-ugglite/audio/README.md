# Audio — UCM for the ugglite codec path

The stock qdsp6 path on this phone: `MultiMedia1 -> PRI_MI2S_RX -> RX1/RX2 ->
HPHL/HPHR`, where HPHL/HPHR feed the board's external speaker amp, and the
headphone jack is the same pair without the amp switch. Capture is
`AMIC -> CIC1 -> DEC1 (ADC1) -> MultiMedia2 -> TERT_MI2S_TX`.

| File | Installed path |
|---|---|
| `HiFi.conf` | `/usr/share/alsa/ucm2/xiaomi-ugg/HiFi.conf` |
| `xiaomi-ugg.conf` | `/usr/share/alsa/ucm2/conf.d/xiaomi-ugg/xiaomi-ugg.conf` |

`xiaomi-ugg.conf` makes the verb discoverable as the `HiFi` use case; without
it the card falls back to whatever UCM the distribution ships for qdsp6.

## Gain contract

`RX1/RX2 Digital Volume` is written **once per verb**, not in the per-device
`EnableSequence`. The PCM lifetime design enables and disables the
`SectionDevice` on every stream open/close, so a `cset` there would rewrite the
analog gain on every idle cycle and silently undo what the user set. Everything
in the device sequences below the verb is routing and power only.

The control's scale is 1 dB per step with `84` as the 0 dB reference:

| Value | Gain | Note |
|---|---|---|
| 84 | 0 dB | stock/quiet baseline |
| 104 | +20 dB | the level the device owner accepted without distortion |
| 120 | +36 dB | the value published in `HiFi.conf` here |
| 124 | +40 dB | codec maximum; not accepted (distortion never confirmed) |

Change the two lines in `SectionVerb` to move the whole path; the per-device
sequences do not need editing.

## Capture gain

The capture route (`AMIC -> CIC1 -> DEC1 (ADC1)`) is switched in the same
`SectionVerb`, and so is its PGA: `ADC1 Volume 6`.

The stock boot default is **4**; the stock Android mixer path activates **6**,
which is also the stock ceiling. The UCM publishes the stock active value, not
a boost beyond the vendor calibration. The TLV step is nominally 6 dB, but a
0 -> 4 comparison made during the microphone work measured about +12 dB, so the
effective step is closer to 3 dB and 6 is not +36 dB in practice.

`TX1 Digital Volume` stays at its 84 (0 dB) default. It is post-ADC gain and
would raise the noise floor together with the signal. `TX1 HPF` is already
enabled at 150 Hz. Neither is written by this UCM.

`SectionDevice."Mic"` carries routing and capabilities only; its per-stream
sequence stays empty for the same reason as the playback devices.

## Mixer vs sink volume

These numbers are **hardware mixer** steps. The PipeWire sink is a separate
scale and the two are not comparable:

- a sink at 100 % is 0 dB; above 100 % is boost;
- `wpctl` prints that scale linearly (`1.00` = 100 %), `pactl` prints percent
  (`100%`), and `pactl` accepts values above 100 % for boost;
- the UCM value sets the codec path gain underneath the sink, so "sink 100 %"
  is not "0 dB" at the speaker unless the mixer is at its reference too.

## Boundary

This is the stock-path configuration only. The alternative UCM/PCM lifetime
design (C2, "static registry") was rejected on hardware — the ACP registry is
not shared with the PCM in the PipeWire process, so required-open returns
`-ENODEV` — and must not be reintroduced as a fix. Idle hiss remains.
