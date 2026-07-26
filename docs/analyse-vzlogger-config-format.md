# Analyse: vzLogger-Config-Format & Editor-Struktur

Grundlage für den Aufbau des vzLogger-Konfigurations-Tabs. Beschreibt das
Format der `vzlogger.conf`, alle relevanten Parameter mit Typen/Defaults/Enums
und — besonders wichtig — das **schema-getriebene Abhängigkeitsmuster** des
offiziellen Config-Editors, an dem sich unsere WebUI strukturell orientieren
soll.

Erstellt am 2026-07-26.

## Quellen

1. **Wiki (Parameterbeschreibung):**
   <https://wiki.volkszaehler.org/software/controller/vzlogger/vzlogger_conf_parameter>
2. **Beispiel-Configs:**
   <https://github.com/volkszaehler/vzlogger/tree/master/etc>
   (`vzlogger.conf`, `vzlogger.conf.meterOMS`, `.InfluxDB`, `.meterOCR`,
   `.mySmartGrid`)
3. **Config-Editor (strukturelles Vorbild) + Quellcode:**
   <http://volkszaehler.github.io/vzlogger/> ·
   <https://github.com/volkszaehler/vzlogger/tree/gh-pages>
   Der Editor ist ein generischer **JSON-Schema-Editor** (`js/jsoneditor.min.js`),
   der aus dem Schema **`etc/vzlogger_generic.schema.json`** (JSON-Schema
   draft-04, ~45 KB) das komplette Formular samt Abhängigkeiten erzeugt.

> **Wichtig:** Das offizielle Schema stammt aus einer Zeit **vor** der
> MQTT-Unterstützung. Es enthält **keine** `mqtt`-Sektion. MQTT ist nur im Wiki
> dokumentiert (und in unserem eigenen Generator bereits umgesetzt). Für unsere
> WebUI liefern wir MQTT also selbst; das Schema deckt Struktur, Protokoll-
> Abhängigkeiten und Kanäle ab.

---

## 1. Gesamtstruktur der `vzlogger.conf`

Die Datei ist JSON (mit erlaubten Kommentaren — der Editor nutzt
`strip-json-comments`). Top-Level-Objekt:

| Feld | Typ | Default | Bedeutung |
|------|-----|---------|-----------|
| `retry` | integer | 0 | Wartezeit (s) nach fehlgeschlagener Anfrage |
| `verbosity` | enum `0,1,3,5,10,15` | 1 | Loglevel: 0=alert,1=error,3=warning,5=info,10=debug,15=finest |
| `log` | string | `/var/log/vzlogger.log` | Pfad zur Logdatei |
| `push` | array | [] | Push-Server-Ziele (`url`) — für uns irrelevant |
| `local` | object | — | Lokaler HTTPd (Live-Abfrage) |
| `mqtt` | object | — | *(nicht im Schema; siehe §3)* MQTT-Ausgabe |
| `meters` | array (`minItems:1`) | — | Liste der Zähler |

## 2. `local` (lokaler HTTPd)

| Feld | Typ | Default | Bedeutung |
|------|-----|---------|-----------|
| `enabled` | bool | false | Lokalen HTTPd für Live-Readings starten |
| `port` | integer | 8080 | TCP-Port |
| `index` | bool | false | Index-Listing aller Kanäle, wenn keine UUID angefragt |
| `timeout` | integer | 0 | Verbindungs-Timeout (s) |
| `buffer` | integer | 0 | Ringpuffergröße |

## 3. `mqtt` (nur Wiki + unser Generator, nicht im Schema)

| Feld | Typ | Default | Bedeutung |
|------|-----|---------|-----------|
| `enabled` | bool | false | MQTT-Verbindung aktivieren |
| `host` | string | test.mosquitto.org | Broker-Adresse |
| `port` | integer | 1883 | Broker-Port (1883 unverschlüsselt, 8883/8884 TLS) |
| `id` | string | `vzlogger_<pid>` | Statische Client-ID |
| `user` / `pass` | string | — | Broker-Zugangsdaten |
| `cafile` / `capath` / `certfile` / `keyfile` / `keypass` | string | — | TLS-Zertifikate |
| `keepalive` | integer | 30 | Keepalive-Intervall (s) |
| `topic` | string | vzlogger/data | Basis-Topic |
| `retain` | bool | false | Retain-Flag |
| `rawAndAgg` | bool | false | Rohdaten auch bei aktivem aggmode publizieren |
| `qos` | integer | 0 | QoS 0 oder 1 |
| `timestamp` | bool | false | Timestamp in Payload aufnehmen |

## 4. `meters[]` — Zähler

Jeder Zähler hat **gemeinsame Basis-Optionen** plus **protokollspezifische**
Felder. Im Schema realisiert als `oneOf` über Zähler-Typen (siehe §6); jeder Typ
ist `allOf: [ meter (Basis) , { protocol: <fest> , … } ]`.

### Basis-Optionen (alle Zählertypen)

| Feld | Typ | Default | Bedeutung |
|------|-----|---------|-----------|
| `enabled` | bool | false | Zähler aktivieren |
| `allowskip` | bool | false | Bei Öffnungsfehler Zähler ignorieren statt Abbruch |
| `interval` | integer | -1 | Abfrageintervall (s), -1=aus (für Pull-Zähler) |
| `aggtime` | integer | -1 | Aggregationsfenster (s), -1=aus |
| `aggfixedinterval` | bool | false | Timestamps auf aggtime runden |
| `protocol` | enum | — | Kommunikationsprotokoll (fixiert je Typ) |
| `device` | string | `/dev/lesekopf0` | Serielles Gerät (bei *dev*-Varianten) |
| `channels` | array | — | Kanäle (siehe §5) |

### Protokoll: SML (`meterSMLdev` — seriell) ← für uns primär

| Feld | Typ | Default | Bedeutung |
|------|-----|---------|-----------|
| `device` | string | /dev/lesekopf0 | Serielles Gerät |
| `pullseq` | string | — | Hex-Sequenz vor jedem Read (Pull-Zähler) |
| `baudrate` | enum `50…230400` | 9600 | Baudrate (Dropdown) |
| `parity` | enum `8n1,7n1,7e1,7o1` | 8n1 | Parität (Dropdown) |
| `use_local_time` | bool | false | Rechner-Uhrzeit als Timestamp nutzen |

Variante `meterSMLhost`: SML über TCP (`host` statt `device`).

### Protokoll: D0 (`meterD0dev` — seriell, EN 62056-21)

| Feld | Typ | Default | Bedeutung |
|------|-----|---------|-----------|
| `device` | string | /dev/lesekopf0 | Serielles Gerät |
| `dump_file` | string | — | Serieller Dump zur Diagnose |
| `pullseq` | string | — | Init-Sequenz (hex), z. B. `2F3F210D0A` |
| `ackseq` | string | auto | Ack-Sequenz / gewünschte Baudrate; `auto` = vzLogger bestimmt |
| `baudrate` | enum `50…230400` | 300 | Baudrate initial (Dropdown) |
| `baudrate_read` | enum `50…230400` | 300 | Baudrate nach Handshake |
| `parity` | enum `8n1,7n1,7e1,7o1` | 7e1 | Parität |
| `wait_sync` | enum `end,off` | off | Auf Sync-Muster `!` warten |
| `read_timeout` | integer | 10 | Lese-Timeout (s) |
| `baudrate_change_delay` | integer | 0 | Delay (ms) vor Baudratenwechsel |

Variante `meterD0host`: D0 über TCP.

### Protokoll: OMS (`meterOMS` — M-Bus)

| Feld | Typ | Default | Bedeutung |
|------|-----|---------|-----------|
| `device` | string | /dev/ttyUSB0 | Serielles Gerät |
| `baudrate` | number | 9600 | Baudrate |
| `key` | string | — | AES-Schlüssel, exakt 32 Hex-Zeichen |
| `mbus_debug` | bool | false | libmbus-Debugausgaben |
| `use_local_time` | bool | false | Rechner-Uhrzeit als Timestamp |

### Protokoll: S0 (`meterS0` — Impulse; für IR-Köpfe irrelevant, der Vollständigkeit halber)

`gpio`(-1), `mmap`(enum `,rpi1,rpi2`), `gpio_dir`(-1), `configureGPIO`(true),
`resolution`(1000 Imp/kWh), `send_zero`(false), `debounce_delay`(30 ms),
`nonblocking_delay`(100000 ns).

### Weitere Typen (im Schema, für uns nicht relevant)

`meterRandom`, `meterFile`, `meterExec`, `meterFluksoV2`, `meterW1therm`
(1-Wire-Temperatur), `meterOCR` (Bilderkennung, mit eigenen Sub-Strukturen für
Bounding-Box/Recognizer).

## 5. `channels[]` — Kanäle

Im Schema `oneOf` über Ausgabe-APIs: `channelNULL` (nur lokaler HTTPd),
`channelVZ` (volkszaehler), `channelmySmartGrid`, `channelInFluxDB`. Für uns
relevant ist die **Kanal-Identifikation** unabhängig von der API:

| Feld | Typ | Default | Bedeutung |
|------|-----|---------|-----------|
| `api` | enum | volkszaehler | Ausgabe-API (bei uns über MQTT/lokal ersetzt) |
| `uuid` | string | — | Kanal-UUID |
| `identifier` | string | — | Wert-Kennung, protokollabhängig: OBIS `1-0:1.8.0` (sml/d0), `Impulse` (s0) |
| `middleware` | string | http://localhost/middleware.php | API-Endpunkt (channelVZ) |
| `aggmode` | enum `avg,max,sum,none` | none | Aggregation: AVG=Leistung(W), MAX=Zählerstand(Wh), SUM=Zähler(S0) |
| `duplicates` | integer | 0 | Duplikate nur alle N s senden (nur für abs. Zählerstände!) |

Unser Plugin ergänzt pro Kanal `mqtt_topic = <serial>/<output-key>` und pflegt
UUID/Anzeige über das eigene Kanal-Dokument (siehe
`analyse-vzlogger-konzept.md`).

## 6. Das schema-getriebene Editor-Muster (strukturelles Vorbild)

Der Editor (json-editor + JSON-Schema) erzeugt das Formular **generisch** aus dem
Schema. Die Muster, die wir für unsere WebUI übernehmen sollten:

- **Typ-Auswahl per `oneOf` → Dropdown.** `meters[]`-Items sind ein `oneOf`
  über alle Zählertypen (Default `meterInvalid` = „Choose any of the supported
  ones"). Die Auswahl des Typs **blendet die passenden Felder ein** — d. h.
  Protokoll bestimmt die sichtbaren Optionen. Genauso `channels[]` über die
  API-Typen.
- **`allOf`-Komposition:** jeder Zählertyp = Basis-`meter` + protokollspezifische
  Properties mit **fest gesetztem `protocol`-Enum**. So sind gemeinsame Felder
  nur einmal definiert.
- **`enum` → Dropdown.** `baudrate`, `parity`, `wait_sync`, `verbosity`,
  `aggmode`, `mmap` erscheinen als Auswahllisten (nicht Freitext).
- **`default` → Vorbelegung** der Felder.
- **`description` → Hilfetext** neben/unter dem Feld.
- **`required`** markiert Pflichtfelder (z. B. `local.enabled`).

### Übertragung auf unseren vzLogger-Tab

- Pro Zähler ein **Protokoll-Dropdown** (sml/d0/oms — die serielle *dev*-Variante,
  da wir IR-Leseköpfe nutzen), das die protokollspezifischen Felder ein-/ausblendet.
- **`device` kommt aus dem IR-Köpfe-Dropdown** (statt Freitext `/dev/lesekopf0`).
- **Baudrate/Parität als Dropdowns** mit den Schema-Enums und den obigen Defaults
  (SML 9600/8n1, D0 300/7e1).
- Globale Sektionen (Local, MQTT, Advanced) als eigene Formularblöcke.
- Kanäle pro Zähler: `identifier` (OBIS) + `aggmode`-Dropdown; UUID/Output-Key
  verwaltet unser Kanal-Dokument.
- Beschreibungen als Hilfetexte übernehmen (unsere `language_*.ini`-Keys).

### Nützliche Referenzen im Editor-Repo

- `etc/vzlogger_generic.schema.json` — vollständige Feld-/Typ-/Enum-/Default-
  Definition (maschinenlesbar; ideal, um Dropdown-Werte & Defaults 1:1 zu
  übernehmen).
- `index.html` + `js/jsoneditor.min.js` — Referenz für Layout/Verhalten.
- Beispiel-Configs in `etc/` — reale `vzlogger.conf`-Strukturen zum Abgleich.
