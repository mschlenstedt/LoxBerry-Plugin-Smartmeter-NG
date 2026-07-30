# Smartmeter-NG – User Guide

> This plugin uses **vzLogger**, the open-source software of the
> [Volkszähler project](https://www.volkszaehler.org/), under the hood. Many
> thanks to the Volkszähler project!

## Overview

Smartmeter-NG reads digital electricity meters through an optical I/R reading
head (serial, or a **Tibber Pulse** with a WLAN bridge) and publishes the values
by MQTT. vzLogger does the actual reading; the LoxBerry MQTT Gateway forwards the
values to the Miniserver.

A more detailed guide is available in the [LoxBerry Wiki](https://wiki.loxberry.de/plugins/smartmeter_plugin/start).

## Requirements

- LoxBerry 4.0 or newer.
- An optical I/R reading head (USB) **or** a Tibber Pulse with a WLAN bridge.
- A meter that outputs SML, D0 or OMS over the optical interface (many meters
  must be unlocked with a **PIN** first).
- The LoxBerry MQTT broker (built into LoxBerry).

vzLogger is installed automatically from the official Volkszähler repository
during plugin installation.

## Tabs

- **I/R Leseköpfe** (reading heads) – manage heads (USB or Tibber Pulse).
- **Smartmeter** – create meters; saving runs the value discovery automatically.
- **Kanäle** (channels) – manage the values and watch each channel live.
- **Einstellungen** (settings) – MQTT base topic, local port, retry.
- **Upgrade** – update vzLogger.
- **Logfiles** – view the logs.

A **status bar** at the top shows the service state (🟢 running, 🟠 stopped,
⚪ unknown/working) with **(Re)start** and **Stop** buttons.

## 1. Add a reading head

In **I/R Leseköpfe** all heads are listed in one table; the **Type** column shows
`usb-auto`, `seriell-man` or `tibberpulse`. A newly plugged USB head appears
after clicking **Refresh** (🔄) next to the heading.

Under **Add a reading head manually**, pick the **Type**:

- **Serial head**: enter the device path (e.g. `/dev/ttyUSB0`) and a name, then
  **Add**. The device must exist.
- **Tibber Pulse**: enter the **bridge IP**, **node** (`1` for a single meter)
  and **password** (QR code on the back of the bridge; user `admin`). The
  bridge's local webserver must be enabled. On adding, the plugin checks
  reachability, credentials and that SML data arrives, then serves the Pulse as a
  virtual reading head.

## 2. Create a meter

In **Smartmeter**:

1. Choose the **protocol** – usually **SML** (also for the Tibber Pulse), else
   **D0** or **OMS**. (Exec/Random are for testing only.)
2. Select the **device** (the reading head).
3. Adjust the baud rate if needed (SML is typically 9600).
4. Enter a **name** and **Save**.

Saving runs the **value discovery** automatically; found channels appear in the
**Kanäle** tab. Edit with the gear (⚙), delete with the red ×.

## 3. Channels and live values

The **Kanäle** tab lists all values; the **Current value** column updates every
few seconds. Use **Auto-Discovery** to re-run the search, or add a missing value
manually by its OBIS identifier (e.g. `1-0:1.8.0`).

## Settings

| Setting | Meaning |
| --- | --- |
| MQTT base topic | Prefix of all MQTT topics (default `smartmeter-ng`) |
| Local port | Port of vzLogger's internal webserver (used for the live values) |
| Retry | Wait time before retrying after a read error |

After saving, restart the service via the status bar.

## MQTT output

vzLogger publishes each channel as a retained message at
`smartmeter-ng/<meter>/<channel>/raw`. The payload carries the value and a
timestamp, e.g. `{"timestamp": 1749123456789, "value": 16125133}` (energy
counters in Wh). The LoxBerry MQTT Gateway forwards the topics to Loxone.

## Troubleshooting

- **No values / empty channels:** check the PIN unlock, the head's seating and
  the selected protocol.
- **Service does not start:** if a USB head was unplugged, the service refuses to
  start on purpose. Reconnect the head and restart.
- **Tibber Pulse unreachable:** check IP/network and that the bridge's local
  webserver is enabled. On errors the plugin raises the poll interval
  automatically (visible in the bridge's log file).
- **Logs:** the **Logfiles** tab (vzLogger, watchdog, updates, Tibber Pulse).

## Questions & bug reports

- GitHub: <https://github.com/mschlenstedt/LoxBerry-Plugin-Smartmeter-NG/issues>
- LoxBerry forum: <https://www.loxforum.com>
