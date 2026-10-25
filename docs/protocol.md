# Furina earbud protocol notes

These notes describe the part of the RoseLink protocol that Furibar uses. They come from a static analysis of the RoseLink Android app (`cn.ikaile.ruoshui.client`). **None of it has been checked against live Bluetooth traffic yet.** Items marked *assumed* are guesses that the Diagnostics section in the app can confirm or correct.

## Finding the earbuds

| What | Value |
| --- | --- |
| BLE manufacturer data prefix | `0B 11 0A 0C` (company ID bytes included). The longest prefix wins: RoseLink compares 6, then 4, then 3 bytes. |
| Byte 6 of the advert | Device kind: `01` earbuds, `04` microphone, anything else headphones |
| Byte 7 of the advert | `01` = Classic Bluetooth available |
| Bytes 11–16 of the advert | MAC address (only when the advert is at least 17 bytes) |

## Transports

Furibar tries both at once and uses whichever opens first. You can force one in Settings.

| Transport | Details |
| --- | --- |
| Classic Bluetooth (RFCOMM) | Service UUID `0cf12d31-fac3-4553-bd80-d6832e7b3931`, found through an SDP lookup on the paired, connected earbuds |
| Bluetooth LE (GATT) | Service `00FE`, write characteristic `00F1`, notify characteristic `00F2` |

## Framing (RS Common V2)

| Direction | Layout |
| --- | --- |
| Mac → earbuds | `FF · SEQ · LEN · PAYLOAD · SUM · AA` |
| Earbuds → Mac | `DD · SEQ · LEN · records · SUM · AA` |

- SEQ is a one-byte counter: it starts at `01` and goes from `FF` back to `00`.
- SUM is the low byte of the sum of every byte before it. Inbound frames are also accepted when the sum starts at byte 2, as RoseLink does.
- Inbound payloads are `TYPE · LEN · VALUE` records.
- *Assumed:* inbound LEN counts the payload only. The decoder also accepts LEN counting payload + SUM + AA, or the whole frame, and keeps whichever reading has a valid tail and checksum.
- Example: setting noise mode to ANC with SEQ `01` gives `FF 01 02 09 01 0C AA`.

**Reads:** payload `FA · type · type …`. On connect, Furibar sends RoseLink's read-all list: `FA 01 07 08 09 0C 0D 0E 12 2A 2B 2C 2D 2E 2F 31 32 33 36 37 38 39 3A 3B 3C 3D 3F 45 46 49`.

**Writes:** payload `type · value`. The earbuds answer with an ACK record `FE · 02 · SEQ · STATUS`.

| ACK status | Meaning |
| --- | --- |
| `00` | success |
| `01` | checksum error |
| `02` | unknown command type |
| `03` | invalid value |
| `04` | not supported |
| `05` | busy |

Furibar shows a change right away. If the earbuds refuse it, the old value comes back and a message appears. If no ACK arrives within 2 seconds, Furibar reads the setting back instead of guessing.

## Settings Furibar uses

The panel shows a control only after the earbuds report a value for it.

| Type | Setting | Values |
| --- | --- | --- |
| `07` | Touch controls | `00` on, `01` off |
| `08` | In-ear detection | `00` on, `01` off |
| `09` | Noise mode | `01` ANC, `02` off, `03` transparency, `04` wind, `05` auto, `06` deep, `07` auto-dynamic |
| `0C` | Battery | read only. *Assumed:* bytes are left, right, case; low 7 bits = percent, high bit = charging, `FF` = unavailable |
| `0D` | Firmware version | read only. *Assumed:* printable ASCII, otherwise bytes joined with dots |
| `0E` | Game (low-latency) mode | *assumed* `01` on, `00` off |
| `2A` | EQ preset | `00` Hi-Fi, `01` Pop, `02` Rock, `03` Light, `04` Custom, `05` Bass+, `06` EAP, `A0`–`A4` Game 1–5 |
| `2B` | Codec mode | read only in Furibar: `00` AAC/SBC, `01` LDAC, `02` LHDC, `03` LC3, `04` aptX, `05` aptX HD, `06` aptX Adaptive |
| `2C` / `2D` / `2E` | ANC level / transparency level / prompt volume | one level byte; *range unknown*, so the earbuds' ACK decides |
| `2F` | Find device | *assumed* `01` left, `02` right; `04` stops |
| `31` | Prompt language | `00` Chinese, `01` English |
| `32` | Multipoint | *assumed* `01` on |
| `33` | Spatial audio | *assumed* `01` on |
| `38` | Spatial mode | `00` off, `01` head tracked, `02` fixed |
| `3A` | Ear-adaptive | *assumed* `01` on |
| `3B` | Tap control | *assumed* `01` on |
| `46` | Hearing protection | one level byte |

## Not implemented

- Gesture remapping (`01`, `3C`) and custom EQ bands (`3E`). Their value layouts aren't known yet. Diagnostics shows the raw bytes, and the raw sender can be used to experiment.
- Codec switching. LDAC needs a cloud activation in RoseLink, and macOS doesn't play LDAC anyway.
- Firmware updates, the AI voice assistant, recording download, and every cloud feature. Furibar never uses the network.

## Checking the assumptions

Open **Diagnostics** with the earbuds connected:

1. Compare **Reported values** with what RoseLink shows on a phone, for example battery percentages and firmware version.
2. Change a setting on the earbuds (for example noise mode by touch) and check that the matching value updates.
3. Use **Copy Log** to share a trace. It includes the earbuds' MAC address if they report it.
