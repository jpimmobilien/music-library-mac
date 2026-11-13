# ORBIT 0.4.0 – „Spatial Liquid Glass“ (Android)

Mit 0.4.0 heißt die App **ORBIT** (vorher Aether) und bekommt das Designsystem *Spatial Liquid Glass* – gemeinsam mit
der macOS-App (ORBIT 2.0, dort `docs/ORBIT.md`). Paketname (`de.privateapp.aether`), Modul- und Klassennamen bleiben,
damit Einstellungen, Favoriten und Papierkorb erhalten bleiben (keine unnötigen Architekturänderungen).

## Name und Symbol
- Anzeigename zentral in `gradle.properties` (`aether.appName=ORBIT`); alle Texte nennen ORBIT.
- Startsymbol aus der Vorlage des Auftraggebers (`tools/icons/orbit-icon-source.png`), erzeugt mit
  `tools/icons/make_orbit_icons.py` als **adaptives Symbol** in fünf Dichten: Hintergrund = Verlauf der Vorlage
  (Ausgleichsfläche 2. Ordnung, mittlere Abweichung 3,6/255), Vordergrund = Chip mit „i“ exakt freigestellt (liegt in
  der 66-dp-Schutzzone), **Designsymbol** (Android 13) als Silhouette. Vorschau: `docs/design/orbit-symbol-vorschau.png`.
- Startbildschirm (Android 12+) zeigt das neue Symbol auf der Verlaufsfarbe.

## Designsystem
- Grundfarben `OrbitPalette` (identisch mit macOS): Arctic Blue, Electric Cyan, Deep Ocean, Sapphire, Soft Violet,
  Pearl White, Graphite. Bedeutung: Blau = System, Cyan = Datenströme, Violett = Auswertungen, Grün positiv,
  Orange erhöht, Rot nur kritisch.
- Themes: Adaptiv, Liquid Glass Hell („Pearl White“), Liquid Glass Dunkel („Deep Ocean“), Minimal Hell, **Minimal
  Dunkel (neu)**, Deep Dark. Akzente: **Arctic Blue** (Standard), **Electric Cyan**, **Soft Violet**, Emerald, Amber,
  Rose, Graphite, Systemfarbe. Jede Kombination ist auf WCAG AA geprüft (ContrastTest, 6 Tests).
- Effektstärke **Minimal / Ausgewogen / Immersiv** (bestand schon) steuert jetzt zusätzlich die ORBIT-Effekte
  (`OrbitEffects.resolve`, JVM-getestet). Vorrang: „Animationen entfernen“ bzw. „Bewegung reduzieren“ > Energiesparmodus
  > Effektstärke.

| Effekt | Minimal | Ausgewogen | Immersiv |
|---|---|---|---|
| Auftakt beim Kaltstart (≈ 0,8 s, über fertigem Inhalt, fängt keine Berührungen ab) | – | ✓ | ✓ |
| Lichtfelder gleiten beim Bereichswechsel (1,4 s, räumliche Orientierung) | – | ✓ | ✓ |
| Lebendiger Hintergrund: Drift ≈ 1 min Umlauf, ~15 Bilder/s, nur im Vordergrund, nicht im Energiesparmodus | – | – | ✓ |
| Lichtreflex an der Berührstelle (Glaskarten) | – | ✓ | ✓ |
| Räumliche Übergänge (Tiefe beim Bereichswechsel, Unterseiten schieben die vorige zurück) | – | ✓ | ✓ |
| Verwandelbare Karten (ORBIT-Core-Zeile → Detailkarte) | ✓ | ✓ | ✓ |
| Rollende Zahlen (Akku, ORBIT Core) | – | – | ✓ |
| Datenfluss, Akku-Welle beim Laden, Fortschrittsschimmer – nur bei echter Aktivität | ✓ | ✓ | ✓ |

## Visualisierungen aus echten Daten
- **ORBIT Core** (Übersicht, ganz oben): Kern mit fünf Bahnen – Arbeitsspeicher (ActivityManager), Speicher,
  Thermik (genutzte thermische Reserve, PowerManager), Netzwerk (TrafficStats, bezogen auf die Spitze der letzten
  5 Minuten), Akku. **CPU- und GPU-Auslastung gibt Android normalen Apps nicht frei** – das Panel sagt es, statt Werte
  zu schätzen. Fehlt ein Wert, bleibt die Bahn gestrichelt. Gemessen wird nur, solange die Übersicht sichtbar ist (1 s).
  Antippen einer Zeile öffnet die Detailkarte: **Speicherschichten** (belegt/verfügbar, Linie = Schwelle, ab der
  Android Apps beendet), **Akku-Flüssigkeit**, **Thermometer** der Reserve, Grundlage des Bogens.
- **Akku-Flüssigkeit** (Gerät › Akku): Füllstand = gemessener Ladestand, die Oberfläche bewegt sich nur, während
  Android „lädt“ meldet.
- **Sensor-Globus** (Gerät › Bewegung): Himmelskugel mit den Satelliten, die der GNSS-Empfänger meldet (Azimut,
  Elevation, Signalstärke, genutzt/ungenutzt), und der Blickrichtung des Telefons (Kompass). Ziehen dreht und neigt,
  Doppeltippen stellt zurück. Keine simulierten Sensoren.

## Dateien, Rückmeldung, Haptik
- Dateivorgänge: **flüssiger Fortschrittsbalken** (Füllung = echter Fortschritt, Schimmer nur während der Vorgang
  arbeitet). Die Erfolgsmeldung erscheint erst nach Abschluss – dann Bestätigungssymbol und Haptik („Bestätigen“),
  bei Problemen „Ablehnen“.
- **Haptik** (Einstellungen › Darstellung, standardmäßig an): Bereichswechsel, Zeilen des ORBIT Core, Abschluss von
  Vorgängen. Die Vibrationseinstellung von Android hat Vorrang.
- Leere Zustände: eigene Illustration (ORBIT-Zeichen mit Symbol).

## Prüfung
Unit-Tests (JVM, Gradle in der CI), Typprüfung, Kontrasttest, Prüfskript „Farben aus dem Theme“, Release-Build mit
`apksigner`/`aapt2`-Prüfung, Installation und Start auf einem Android-15-Emulator mit Bildschirmfotos aller Themes,
Effektstärken und Hauptbereiche (Telefon und Tablet-Größe). Ergebnisse: `docs/STATUS.md`.
