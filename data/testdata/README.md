# SML-Testdaten

Aufgezeichnete SML-Telegramme verschiedener realer Stromzähler zum Testen des
Plugins **ohne echten Lesekopf**. Sie werden vom Simulator-Skript
`bin/simulate_meter.sh` eingespeist (siehe `docs/meter-simulator.md`).

```
sudo ./simulate_meter.sh ISKRA_MT631-D2A51-V22-K0z_without_PIN.bin
```

Wird nur ein Dateiname (ohne Pfad) übergeben, sucht das Skript hier in
`data/testdata/`. Ohne Argument wird das Standard-Sample `data/sample.dmp`
verwendet.

## Herkunft der Daten

Die Dumps stammen aus zwei öffentlichen Git-Repositories:

- **`data/testdata/*.bin`** — <https://github.com/devZer0/libsml-testing>
  Sammlung von SML-Rohaufzeichnungen vieler Zählertypen (DZG, EMH, ISKRA,
  Holley, Itron, EasyMeter, eBZ, Dr. Neuhaus u. a.). Jede `.bin` ist ein
  roher SML-Transportstrom (teils mehrere Telegramme hintereinander).

- **`data/sample.dmp`** (Standard-Sample, eine Ebene höher) —
  <https://github.com/hn/smldump>
  Dessen Per-Message-CRCs waren fehlerhaft und wurden für die auf dem LoxBerry
  installierte `libsml` mit `sml_crc16` neu berechnet (Details in
  `docs/meter-simulator.md`).

Dateien mit `_error` oder `with_error` im Namen enthalten bewusst fehlerhafte
Telegramme (Original-Aufzeichnungen aus dem libsml-testing-Repo) und dienen dem
Test des Fehlerverhaltens.
