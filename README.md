# Smartmeter-NG for LoxBerry

Smartmeter-NG is a LoxBerry plugin for reading smart meters through optical I/R reading heads and publishing their values by MQTT.

The plugin drives the external `vzlogger` program: it provides a web frontend to configure meters and OBIS channels, generates and validates `vzlogger.conf`, and supervises the `vzlogger` process. vzLogger reads the meters and publishes each channel over MQTT itself; the LoxBerry MQTT Gateway forwards the values to the Miniserver.

The former legacy Perl reader has been removed; it is only maintained in the `Version1` branch.

## Documentation

- [English user guide](docs/User-Guide.en.md)
- [Deutsche Benutzerdokumentation](docs/User-Guide.de.md)
- [Documentation index](docs/Readme.md)

## Main Features

- Detects optical I/R reading heads below `/dev/serial/smartmeter/`.
- Generates and validates the vzLogger configuration from a web frontend, with SML, D0, OMS, and a custom JSONC mode.
- Discovers OBIS channels and lets you name their MQTT output per reader.
- Installs and updates the `vzlogger` package from the Volkszaehler repository (only the `vzlogger` binary, no other Volkszaehler components).
- Runs `vzlogger` in the foreground from a plugin watchdog and restarts it after an unexpected exit.
- Logs through LoxBerry's central log manager with a configurable log level.
- Offers an optional live-reading view served by vzLogger's local HTTP endpoint.

## MQTT Output

- vzLogger publishes each channel at `<base topic>/<reader>/<output key>/raw`.
- It also publishes `<...>/uuid` and `<...>/id` (the OBIS identifier) as retained messages, and `<...>/agg` when aggregation is enabled.
- The default base topic is `smartmeter`.
- The payload is the plain meter value, or a `{"timestamp":<ms>,"value":<number>}` object when timestamps are enabled.
- Values are the raw meter readings; SML energy counters report Wh.

## Release Notes

See [CHANGELOG.md](CHANGELOG.md) for notable changes and release notes.

## Known Issues

See [Known Issues](KNOWN-ISSUES.md) for confirmed limitations and planned follow-up work.
