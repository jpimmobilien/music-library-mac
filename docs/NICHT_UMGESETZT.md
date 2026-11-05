# Einschränkungen und offene Punkte (Version 2)

## Nicht geprüft (kein Gerät bzw. nicht automatisierbar)

| Thema | Stand |
|---|---|
| **macOS 13 Ventura** | Die App ist für macOS 13 gebaut (Mindestversion 13.0 in beiden Architekturen, keine neueren Schnittstellen ohne Abfrage). GitHub bietet keinen macOS-13-Rechner mehr an – **auf Ventura nicht gestartet**. |
| **Echter Intel-Mac** | Alle Tests laufen nativ auf einem Intel-Rechner (macOS 15). Die Oberfläche wurde mit dem Intel-Teil der App über Rosetta gezeichnet, weil die Intel-Rechner von GitHub keine Metal-Grafik haben. **Auf echter Intel-Hardware ist die Oberfläche nicht gesehen.** |
| **Bedienung von Hand** | Klicken, Ziehen & Ablegen, Kontextmenüs, Tastenkürzel, Trackpad-Gesten (Zoom, Wischen mit drei Fingern), Medientasten, Menüleiste, Vollbild. Diese Teile sind gebaut, aber nicht automatisch prüfbar. |
| **Wiedergabe über Lautsprecher** | Die Klangkette (EQ, Bass, Tonhöhe, Tempo, Lautstärke über 100 % mit Limiter) ist offline gemessen; über ein echtes Audiogerät nicht angehört. |
| **Echte Musiksammlung** | Gemessen mit einer erfundenen Bibliothek mit 10.000 Titeln, nicht mit echten Dateien (Einlesen, Dateiüberwachung, externe Laufwerke). |
| **Gatekeeper beim ersten Start** | Nach Apples Dokumentation beschrieben (INSTALLATION.md), nicht ausprobiert. |
| **Signieren/Beglaubigen mit Developer ID** | Vorbereitet (`scripts/notarize.sh`, Build-Schritte), aber ohne Entwicklerkonto nicht ausführbar und deshalb ungetestet. |

## Bekannte Schwächen

| Thema | Stand |
|---|---|
| **Kompaktes Raster bei sehr vielen Titeln** | Im Bereich *Titel* mit 10.000 Einträgen ist das kompakte Raster (viele kleine Kacheln je Zeile) die langsamste Ansicht beim Scrollen (siehe PERFORMANCE.md). Liste, Detailliste und normales Raster sind deutlich flüssiger. |
| **Ansicht wechseln** | Das erste Umschalten auf eine andere Ansicht dauert bei 10.000 Titeln einige Zehntelsekunden (die Ansicht wird neu aufgebaut). |
| **Liquid Glass** | Nur auf macOS 26 (natives `glassEffect`). Auf macOS 13–15 gleichwertige Glas-Darstellung aus Unschärfe, Tönung und Glanzkante. |
| **Bewegung reduzieren** | Ist die Systemeinstellung „Bewegung reduzieren“ an, stehen Platte, CD, Spulen und Lichtring still (gewollt). |

## Nicht umgesetzt

| Thema | Stand |
|---|---|
| **Opus und Ogg FLAC** abspielen | Tags werden gelesen/geschrieben, die Titel erscheinen in der Bibliothek, Abspielen meldet „nicht unterstützt“. Ogg **Vorbis** wird abgespielt. |
| **WMA, WavPack, TTA, DSD, APE, Musepack, Speex** | werden beim Einlesen nicht aufgenommen (macOS kann sie nicht abspielen) |
| **Lückenlose Wiedergabe** (gapless) | zwischen zwei Titeln ist eine kurze Pause möglich |
| **Widgets** | brauchen eine App-Erweiterung mit Xcode-Projekt und Signierung; Ersatz: Mini-Player-Fenster und Player in der Menüleiste |
| **Übernahme aus Apple Music / iTunes** | Playlists, Wertungen und Wiedergabezahlen der Musik-App werden nicht übernommen |
| **AirPlay-Auswahl in der App** | Ausgabe über das Kontrollzentrum von macOS wählen |
| **Sprachen** | nur Deutsch |
| **VoiceOver** | Bedienelemente sind beschriftet, aber nicht mit VoiceOver getestet |
