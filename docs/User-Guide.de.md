# Smartmeter-NG – Benutzerdokumentation

> Dieses Plugin nutzt im Hintergrund **vzLogger**, die Open-Source-Software des
> [Volkszähler-Projekts](https://www.volkszaehler.org/). Herzlichen Dank an das
> Volkszähler-Projekt!

## Überblick

Smartmeter-NG liest digitale Stromzähler über einen optischen IR-Lesekopf
(seriell oder als **Tibber Pulse** mit WLAN-Bridge) aus und veröffentlicht die
Werte per MQTT. Das eigentliche Auslesen übernimmt vzLogger; die Weitergabe an
den Miniserver das LoxBerry MQTT Gateway.

Eine ausführliche Anleitung gibt es im [LoxBerry Wiki](https://wiki.loxberry.de/plugins/smartmeter_plugin/start).

## Voraussetzungen

- LoxBerry 4.0 oder neuer.
- Ein optischer IR-Lesekopf (USB) **oder** ein Tibber Pulse mit WLAN-Bridge.
- Ein Zähler, der SML, D0 oder OMS über die optische Schnittstelle ausgibt
  (viele Zähler müssen zuvor per **PIN** freigeschaltet werden).
- Der LoxBerry MQTT Broker (in LoxBerry integriert).

vzLogger wird während der Plugin-Installation automatisch aus dem offiziellen
Volkszähler-Repository installiert.

## Die Reiter der Plugin-Seite

- **I/R Leseköpfe** – Leseköpfe verwalten (USB-Kopf oder Tibber Pulse).
- **Smartmeter** – Zähler anlegen; nach dem Speichern werden die Messwerte
  automatisch gesucht.
- **Kanäle** – die einzelnen Messwerte verwalten und den aktuellen Wert live
  ansehen.
- **Einstellungen** – MQTT-Basis-Topic, lokaler Port, Wiederholung.
- **Upgrade** – vzLogger aktualisieren.
- **Logfiles** – Protokolle einsehen.

Oben zeigt ein **Status-Balken** den Zustand des Dienstes (🟢 läuft, 🟠 gestoppt,
⚪ unbekannt/arbeitet) und bietet **(Neu-)Starten** und **Stoppen**.

## 1. Lesekopf hinzufügen

Im Reiter **I/R Leseköpfe** stehen alle Köpfe in einer Tabelle; die Spalte
**Typ** zeigt `usb-auto`, `seriell-man` oder `tibberpulse`. Ein neu eingesteckter
USB-Kopf erscheint nach Klick auf **Aktualisieren** (🔄) neben der Überschrift.

Unter **IR-Lesekopf manuell hinzufügen** wählst du im Feld **Typ**:

- **Serieller Lesekopf**: Gerätepfad (z. B. `/dev/ttyUSB0`) und Namen eintragen,
  **Hinzufügen**. Das Gerät muss vorhanden sein.
- **Tibber Pulse**: **Bridge-IP**, **Node** (bei einem Zähler `1`) und
  **Passwort** (QR-Code auf der Rückseite der Bridge; Benutzer `admin`) eintragen.
  Voraussetzung ist der aktivierte lokale Webserver der Bridge. Beim Hinzufügen
  prüft das Plugin Erreichbarkeit, Zugangsdaten und ob SML-Daten ankommen, und
  stellt den Pulse dann als virtuellen Lesekopf bereit.

## 2. Zähler anlegen

Im Reiter **Smartmeter**:

1. **Protokoll** wählen – meist **SML** (auch für den Tibber Pulse), sonst **D0**
   oder **OMS**. (Exec/Random dienen nur Tests.)
2. Das **Gerät** (den Lesekopf) auswählen.
3. Ggf. Baudrate anpassen (SML üblicherweise 9600).
4. **Namen** vergeben und **Speichern**.

Nach dem Speichern startet automatisch die **Messwert-Suche**. Gefundene Kanäle
erscheinen im Reiter **Kanäle**. Bearbeiten über ⚙, Löschen über das rote ×.

## 3. Kanäle und Live-Werte

Im Reiter **Kanäle** siehst du alle Messwerte; in der Spalte **Aktueller Wert**
wird alle paar Sekunden der aktuelle Wert angezeigt. Über **Auto-Discovery**
lässt sich die Suche erneut starten; fehlende Werte können per OBIS-Kennung
(z. B. `1-0:1.8.0`) manuell ergänzt werden.

## Einstellungen

| Einstellung | Bedeutung |
| --- | --- |
| MQTT Basis-Topic | Vorderer Teil aller MQTT-Themen (Standard `smartmeter-ng`) |
| Lokaler Port | Port des internen vzLogger-Webservers (für die Live-Werte) |
| Wiederholung | Wartezeit vor einem erneuten Leseversuch |

Nach dem Speichern den Dienst über den Status-Balken neu starten.

## MQTT-Ausgabe

vzLogger veröffentlicht jeden Kanal als retained Nachricht unter
`smartmeter-ng/<Zähler>/<Kanal>/raw`. Die Payload enthält Wert und Zeitstempel,
z. B. `{"timestamp": 1749123456789, "value": 16125133}` (Energiezähler in Wh).
Für die Einbindung in Loxone abonniert das LoxBerry MQTT Gateway die Topics.

## Fehlersuche

- **Keine Werte / leere Kanäle:** PIN-Freischaltung, Sitz des Lesekopfs und das
  gewählte Protokoll prüfen.
- **Dienst startet nicht:** Wurde ein USB-Kopf abgezogen, startet der Dienst
  bewusst nicht. Kopf wieder anstecken und neu starten.
- **Tibber Pulse nicht erreichbar:** IP/Netzwerk und den lokalen Webserver der
  Bridge prüfen. Bei Fehlern erhöht das Plugin das Abfrageintervall automatisch
  (im Logfile der Bridge nachvollziehbar).
- **Protokolle:** Reiter **Logfiles** (vzLogger, Watchdog, Updates, Tibber-Pulse).

## Fragen & Fehler melden

- GitHub: <https://github.com/mschlenstedt/LoxBerry-Plugin-Smartmeter-NG/issues>
- LoxBerry Forum: <https://www.loxforum.com>
