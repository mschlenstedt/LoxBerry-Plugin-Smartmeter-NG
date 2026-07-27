# Meter-Simulator (Test ohne echten Lesekopf)

Zum Testen ohne Hardware liegt ein kleines Bash-Skript bei, das einen seriellen
SML-Zähler simuliert: `bin/simulate_meter.sh`. Es erzeugt mit `socat` ein
virtuelles serielles Gerät und speist ein mitgeliefertes SML-Dump
(`data/sample.dmp`, ein echtes SML-Telegramm) in einer Schleife ein. vzLogger
liest es wie einen echten Lesekopf. **Nicht** in der WebUI eingebunden.

## Verwendung

```
sudo /opt/loxberry/bin/plugins/smartmeter-ng/simulate_meter.sh
```

- Voraussetzung: `socat` (`sudo apt-get install socat`).
- Erzeugt standardmäßig das Gerät `/dev/ttySmartmeterSim` (les-/gruppenbar für
  `loxberry`, weil vzLogger als `loxberry` läuft). Anpassbar über
  `SMARTMETER_SIM_DEVICE`, Intervall über `SMARTMETER_SIM_INTERVAL`.
- Dump-Datei optional als Argument; sonst wird `data/sample.dmp` verwendet.
- `sudo` ist nötig, weil das Gerät unter `/dev` angelegt wird.

## Im Plugin testen

1. **I/R Leseköpfe** → manuellen Kopf mit dem Gerätepfad (`/dev/ttySmartmeterSim`)
   hinzufügen.
2. **Smartmeter** → SML-Meter auf diesem Device anlegen (Baudrate 9600,
   Parität 8n1) und speichern.
3. Beim Speichern läuft die **Auto-Discovery** und liest den simulierten Strom;
   die gefundenen OBIS-Kanäle erscheinen im **Kanäle**-Tab.

Das Dump stammt aus <https://github.com/hn/smldump> (`sample.dmp`).
