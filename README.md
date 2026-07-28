# Smartmeter-NG for LoxBerry

Smartmeter-NG is a LoxBerry plugin for reading smart meters through optical I/R reading heads and publishing their values by MQTT.

The plugin drives the external `vzlogger` program: it provides a web frontend to configure reading heads, meters and OBIS channels, generates and validates `vzlogger.conf`, and supervises the `vzlogger` process. vzLogger reads the meters and publishes each channel over MQTT itself; the LoxBerry MQTT Gateway forwards the values to the Miniserver.

This plugin builds on **vzLogger**, the open-source software of the [Volkszähler project](https://www.volkszaehler.org/) — many thanks to that community.

## Documentation

- [User wiki page (DokuWiki, German)](docs/dokuwiki.txt)
- [Deutsche Benutzerdokumentation](docs/User-Guide.de.md)
- [English user guide](docs/User-Guide.en.md)

## Main Features

- **Reading heads** (tab *I/R Leseköpfe*): auto-detects USB I/R heads below `/dev/serial/smartmeter/`, and lets you add serial heads or a **Tibber Pulse** (I/R head with a WLAN bridge) manually. A Tibber Pulse is validated (reachable, credentials, SML data) and then served as a virtual reading head by its own bridge process.
- **Meters** (tab *Smartmeter*): create SML, D0 or OMS meters on a head; `exec` and `random` exist for testing. Saving runs OBIS auto-discovery automatically.
- **Channels** (tab *Kanäle*): manage the discovered OBIS channels and see each channel's **current value live** (polled from vzLogger's local HTTP endpoint).
- **Settings** (tab *Einstellungen*): MQTT base topic, local HTTP port and retry.
- **Upgrade** (tab *Upgrade*): shows the installed and available `vzlogger` version and updates the package from the Volkszähler/Cloudsmith repository, into its own log file.
- **Watchdog**: runs `vzlogger` in the foreground, refuses to start against an unplugged head's device, restarts after an unexpected exit, and manages the Tibber Pulse bridges (started before vzlogger). The plugin log level maps to vzLogger's verbosity.

## MQTT Output

- vzLogger publishes each channel at `<base topic>/<meter>/<channel name>/raw` as a retained message.
- The default base topic is `smartmeter-ng`.
- With timestamps enabled (the default), the payload is a `{"timestamp":<ms>,"value":<number>}` object; SML energy counters report Wh.
- The channel UUID and the OBIS identifier are published as additional retained topics.

## Release Notes

See [CHANGELOG.md](CHANGELOG.md) for notable changes and release notes.

## Known Issues

See [Known Issues](KNOWN-ISSUES.md) for confirmed limitations and planned follow-up work.
