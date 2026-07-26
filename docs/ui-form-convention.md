# UI-Konvention: Formularaufbau & Service-Status-Block

Grundsatzentscheidungen für alle Tabs (angelehnt an das Gateway-Tab von
LoxBerry-Plugin-Audioserver4Home, umgesetzt im LoxBerry Design System).

## 1. Formularzeile

Aufbau: **Label links, Eingabefeld rechts, kurzer Hilfetext darunter** (in der
Feldspalte). Direkt rechts neben dem Label steht ein kleiner grauer
**„?"-Button** (`.sm-help`), der in die passende Stelle im Volkszähler-Wiki
verweist (neuer Tab).

Markup-Muster (statisch im Template; Werte kommen per Ajax/JS):

```html
<div class="lb-form-row">
	<label class="lb-form-label" for="FIELD_ID">
		<TMPL_VAR VZLOGGER.SOME_LABEL>
		<a class="sm-help" href="https://wiki.volkszaehler.org/…#anker" target="_blank" rel="noopener" title="Hilfe">?</a>
	</label>
	<div class="lb-form-field">
		<input class="lb-input" type="text" id="FIELD_ID">
	</div>
	<div class="lb-form-help"><TMPL_VAR VZLOGGER.SOME_LABEL_HELP></div>
</div>
```

- `lb-form-row` / `lb-form-label` / `lb-form-field` / `lb-form-help` sind
  DS-Klassen. `lb-form-help` sitzt automatisch in der Feldspalte.
- `.sm-help` wird von `templates/javascript.js` per injiziertem `<style>`
  definiert (grauer Kreis mit „?"). Das ist das Pendant zum kleinen Icon-Button
  im I/R-Köpfe-Tab, hier grau und als Wiki-Link.
- Für Dropdowns `lb-select`, für Textareas `lb-textarea` verwenden. Enum-Werte
  und Defaults stammen aus `docs/analyse-vzlogger-config-format.md`.

## 2. vzLogger-Service-Status-Block

Wird oben auf **jedem Tab außer Live-Daten und Logdateien** angezeigt: farbiges
Status-Badge (grün „läuft"/rot „gestoppt"/grau „unbekannt") mit Haken/Kreuz-Icon
und PID, daneben zwei Buttons **Neu starten** und **Stoppen**, darunter `<hr>`.

Einbindung: im Template genügt der Mountpunkt

```html
<div id="vz-service"></div>
```

`templates/javascript.js` rendert den Block hinein, pollt alle 5 s
`ajax.cgi?action=vz-status` und schaltet die Buttons auf `vz-restart` /
`vz-stop`. Diese Ajax-Aktionen rufen `bin/watchdog.pl` auf
(`--action=pid|restart|stop`). Die `pid`-Aktion ist bewusst ungeloggt/lockfrei,
weil sie im Polling-Takt läuft.

Lokalisierte Strings: `COMMON.SERVICE_*`.
