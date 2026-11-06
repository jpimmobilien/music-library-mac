# Einschränkungen und offene Punkte (Version 2.1)

## Nicht geprüft (kein Gerät bzw. nicht automatisierbar)

| Thema | Stand |
|---|---|
| **macOS 13 Ventura** | Die App ist für macOS 13 gebaut (Mindestversion 13.0 in beiden Architekturen, keine neueren Schnittstellen ohne Abfrage). GitHub bietet keinen macOS-13-Rechner mehr an – **auf Ventura nicht gestartet**. |
| **Echter Intel-Mac** | Alle Tests laufen nativ auf einem Intel-Rechner (macOS 15). Die Oberfläche wurde mit dem Intel-Teil der App über Rosetta gezeichnet, weil die Intel-Rechner von GitHub keine Metal-Grafik haben. **Auf echter Intel-Hardware ist die Oberfläche nicht gesehen.** |
| **Bedienung von Hand** | Klicken, Ziehen & Ablegen, Kontextmenüs, Tastenkürzel, Trackpad-Gesten (Zoom, Wischen mit drei Fingern), Medientasten, Menüleiste, Vollbild. Neu in 2.1 ebenso: Aufziehen der Auswahl mit der Maus, Klicks im Löschdialog, „Als Album zusammenfassen“, macOS-Farbwähler, Größenwechsel des Mini-Players mit Animation. Diese Teile sind gebaut und als Vorschaubild geprüft, aber nicht automatisch bedienbar. |
| **Apple-Musik-Übernahme** | Die Zuordnung (Pfad bzw. Titel/Interpret/Album/Dauer) und das Lesen einer Mediathek-XML sind getestet. Der Zugriff über das iTunesLibrary-Framework braucht die Freigabe „Medien & Apple Music“ und eine echte Musik-Mediathek – **auf den Build-Rechnern nicht möglich, nicht ausprobiert**. |
| **Wiedergabe über Lautsprecher** | Die Klangkette (EQ mit jedem Preset, Bass, Tonhöhe, Tempo, Lautstärke über 100 % mit Limiter, Pegelanalyse) ist offline gemessen; über ein echtes Audiogerät **nicht angehört**. Die Klangqualität der Tonhöhe ist mit Messsignalen (Akkord, Anschläge, Sinustöne) belegt, nicht mit echter Musik im Hörvergleich. |
| **Echte Musiksammlung** | Gemessen mit einer erfundenen Bibliothek mit 10.000 Titeln, nicht mit echten Dateien (Einlesen, Dateiüberwachung, externe Laufwerke). |
| **Gatekeeper beim ersten Start** | Nach Apples Dokumentation beschrieben (INSTALLATION.md), nicht ausprobiert. |
| **Signieren/Beglaubigen mit Developer ID** | Vorbereitet (`scripts/notarize.sh`, Build-Schritte), aber ohne Entwicklerkonto nicht ausführbar und deshalb ungetestet. |

## Bekannte Schwächen

| Thema | Stand |
|---|---|
| **Kompaktes Raster bei sehr vielen Titeln** | Im Bereich *Titel* mit 10.000 Einträgen ist das kompakte Raster (viele kleine Kacheln je Zeile) die langsamste Ansicht beim Scrollen (siehe PERFORMANCE.md). Liste, Detailliste und normales Raster sind deutlich flüssiger. |
| **Ansicht wechseln** | Das erste Umschalten auf eine andere Ansicht dauert bei 10.000 Titeln einige Zehntelsekunden (die Ansicht wird neu aufgebaut). |
| **Liquid Glass** | Nur auf macOS 26 (natives `glassEffect`). Auf macOS 13–15 gleichwertige Glas-Darstellung aus Unschärfe, Tönung und Glanzkante. |
| **Bewegung reduzieren** | Ist die Systemeinstellung „Bewegung reduzieren“ an, stehen Platte, CD, Spulen und Lichtring still und die Pegelbalken sind ausgeblendet (gewollt). |
| **Tonhöhe (2.1)** | Solange die Tonhöhe verändert ist, verzögert die Verarbeitung den Klang um ≈ 0,14 s (wie bei Android); Zeit- und Liedtext-Anzeige laufen dann um diesen Betrag vor. Beim ersten Verstellen aus „Original“ entsteht eine kurze Pause von ≈ 0,14 s; Wechsel zwischen zwei Tonhöhen und zurück auf „Original“ sind lückenlos. Bei stehenden Akkorden ist Apples bisheriges Verfahren messbar etwas sauberer (−53 statt −49 dB Störanteil), bei Anschlägen (Schlagzeug, Klavier) ist das Android-Verfahren deutlich besser (Vorecho −25 bis −32 dB statt −6 bis −10 dB). Dateien mit mehr als zwei Kanälen nutzen weiter Apples Verfahren. |
| **Hinzufügedatum (2.1)** | Ohne Apple-Musik-Daten gilt das Erstellungsdatum der Datei. Wurden Dateien vor dem Import kopiert (z. B. von einer Festplatte), ist das der Zeitpunkt des Kopierens. Das genaue iTunes-Datum gibt es nur mit „Aus Apple Musik übernehmen …“ bzw. der freigegebenen Mediathek-XML. |
| **Raster (2.1)** | Die Spaltenbreite ist fest aus der Fenstergröße berechnet (Absturzschutz, s. Änderungsübersicht); rechts bleibt dadurch bis zu 16 pt mehr Rand. |

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
