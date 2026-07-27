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
- **Muss als root laufen** (`sudo`) — sonst bricht es mit Hinweis ab, weil das
  Gerät unter `/dev` angelegt wird.
- Erzeugt standardmäßig das Gerät **`/dev/serial/smartmeter/SIM`** — also genau
  dort, wo die udev-Regel echte Köpfe anlegt. Dadurch wird es vom Plugin
  **automatisch erkannt**. Les-/gruppenbar für `loxberry` (vzLogger läuft als
  `loxberry`). Anpassbar über `SMARTMETER_SIM_DEVICE`, Intervall über
  `SMARTMETER_SIM_INTERVAL`.
- Dump-Datei optional als Argument; sonst wird `data/sample.dmp` verwendet.

## Im Plugin testen

1. **I/R Leseköpfe** → der Sim-Kopf `SIM` erscheint unter „Automatisch erkannte
   IR-Leseköpfe" (kein manuelles Hinzufügen nötig).
2. **Smartmeter** → SML-Meter auf diesem Device anlegen (Baudrate 9600,
   Parität 8n1) und speichern.
3. Beim Speichern läuft die **Auto-Discovery** und liest den simulierten Strom;
   die gefundenen OBIS-Kanäle erscheinen im **Kanäle**-Tab.

Das Dump stammt aus <https://github.com/hn/smldump> (`sample.dmp`).
