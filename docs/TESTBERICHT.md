# Testbericht – Android Bridge 5.2.0

_Rückfallversionen: 5.1 (Commit 11312ce), 5.0 (Commit 7d7a8a5), 4.2 (Commit 3414b1f), 4.0 (Commit 962b36b), 3.0 (Commit 27de89b), 2.0 (Commit 30402af) und 1.0 (Zweig `android-bridge-v1.0`)._

## Neu in 5.2 geprüft (Lauf 40, Commit af2ffc4)

| Prüfung | Ergebnis |
|---|---|
| Titelbild | MacBook Pro mit Touch Bar (2016–2020): vom Nutzer gelieferte Produktfotos – ohne Telefon Seitenansicht, verbunden Ansicht von oben mit der laufenden App perspektivisch im Bildschirm; andere Modelle weiter gezeichnet. Bildschirmfoto 17 hell/dunkel geprüft |
| App-Symbol | vom Nutzer geliefertes Symbol im macOS-Raster (824 px, transparente Ecken, Schatten) |
| Startseite | Highlights-Kacheln entfernt |
| Bewegung | Lichtimpuls beim Verbinden, Geräteauftritt/-abgang, Fortschrittsbalken mit Lichtpunkten in Übertragungsrichtung (Tempo = gemessene Geschwindigkeit, steht ohne Datenfluss), Geschwindigkeitsverlauf aus echten Messwerten, Erfolgsring/Schütteln bei Fehler, Scan-Lichtbogen (Duplikate, laufende Übertragungen), Löschanimation der Duplikatgruppen, Ladeschimmer für Vorschaubilder, magnetisches Hover; alles aus bei „Bewegung reduzieren“ oder ausgeschalteten Animationen |
| Unit-Tests | 96 ohne Fehler (macOS 26 Intel, macOS 15 Intel, x86_64) |
| Universal-Build, Installation + Start | x86_64 + arm64; installiert und gestartet auf macOS 26 Intel und macOS 15 Intel |
| Nicht geprüft | Apple-Silicon-Läufe erneut ohne freie GitHub-Maschine abgebrochen; Animationen nur als Code und Standbild geprüft (keine Videoaufnahme in der Build-Umgebung); echte Telefone/Übertragungen |

## Aus Version 5.1 (Lauf 39, Commit 11312ce)

| Prüfung | Ergebnis |
|---|---|
| Gestaltung nach apple.com | Geräte mit Kontakt- und Umgebungsschatten, Aluminiumkante, Scharnier, Glanzlichtern und sichtbarer Telefonkante; „Erste Schritte“ als eigene Ansicht über einen großen Knopf; Highlights-Kacheln; Dunkelmodus #1D1D1F mit helleren Flächen; Glas mit Glanzlicht; Speicherbalken als Glasröhre |
| Unit-Tests | 96 Tests ohne Fehler (macOS 26 Intel, macOS 15 Intel, x86_64) |
| Universal Binary | x86_64 + arm64, gebaut mit Xcode 26 auf macOS 26 (Intel) |
| Installation aus der DMG + Start | macOS 26 Intel (Liquid Glass aktiv), macOS 15 Intel |
| Bildschirmfotos | Intel-Build-Maschinen: Übersicht ohne/mit Gerät, Erste Schritte, Einstellungen, Duplikate, Übertragungen, Mac-Bauformen, hell und dunkel |
| Nicht geprüft | Apple-Silicon-Läufe fielen aus (GitHub hatte keine freien arm64-Maschinen: „not acquired by Runner … capacity constraints“); Dateimanager und Galerie in 5.1 daher nicht neu fotografiert (Code dort nur Speicherbalken geändert); echte Telefone |

## Aus Version 5.0

| Prüfung | Ergebnis |
|---|---|
| Titelbild | Produktseiten-Aufbau: Status, große Überschrift, Aktionen, darunter der erkannte Mac in echter 3D-Perspektive (Deckel, Tastatur, Touch Bar/Funktionstasten, Trackpad) mit der laufenden App auf dem Bildschirm, davor das Telefon passend zum Hersteller (Pixel, Galaxy Ultra, Galaxy, allgemein). Alle Geräte sind selbst gezeichnet – keine Apple-Fotos, keine Logos |
| Mac-Bauformen | 9 Modelle (u. a. 15" MacBook Pro 2017 mit Touch Bar, MacBook Air 2017 mit Silberrahmen, MacBook Pro 14" mit Notch, iMac 24", Mac Studio + Studio Display) hell und dunkel geprüft; Bildschirminhalt füllt jetzt auch 16:9-Displays |
| Dateimanager | beide Spalten mit runden Ecken; Tabelle, Raster und Rollbalken werden an den Ecken beschnitten; leere Tabellen ohne Zebrastreifen (macOS 14+) |
| Farben | Systemakzentfarbe statt Verläufen, flache Schaltflächen ohne Leuchten, ruhigere Hintergründe; leere Zustände mit SF Symbols statt Illustrationen |
| Unit-Tests, Universal-Build, DMG, Installation + Start | wie 4.2: macOS 26 Apple Silicon, macOS 15 Apple Silicon, macOS 15/26 Intel |
| Nicht geprüft | echte Telefone und echte Mac-Hardware außer den Build-Maschinen |

## Aus Version 4.2 (Lauf 34, Commit 3414b1f)

| Prüfung | Ergebnis |
|---|---|
| Unit-Tests | 96 Tests ohne Fehler auf macOS 26 (arm64) und macOS 15 (x86_64) |
| Universal Binary | x86_64 + arm64, gebaut mit Xcode 26 auf macOS 26 (Apple Silicon) |
| Installation aus der DMG + Start | macOS 26 Apple Silicon nativ und über Rosetta (Liquid Glass aktiv), macOS 15 Intel (Rückfall-Glas) |
| Bildschirmfotos | alle 22 Ansichten × hell/dunkel auf macOS 26 Apple Silicon (natives Liquid Glass + Rückfall) und macOS 15 Apple Silicon; Intel-VMs nur Seiten ohne Fotos (deren virtuelle Grafik bricht bei Fotoseiten in Metal ab: `MTLLoader … Target device architecture is nil`) |
| Layout-Durchgang | Navigationsleiste oben, Gerätekapsel unten, Galerie, Großansicht, Dateimanager, Duplikate mit Löschleiste, Speicher, Favoriten, Übertragungen, Einstellungen; korrigiert: leere Zustände ragten im kleinsten Fenster unter die Gerätekapsel – sie wählen jetzt je nach Höhe große, kleine oder keine Illustration |
| Bekannte Aufnahme-Artefakte der Build-Maschinen | einzelne Aufnahmen direkt nach dem Fensterwechsel unvollständig (z. B. ein verkleinertes Dateimanager-Foto); nicht reproduzierbar, die jeweils andere Aufnahme derselben Seite ist vollständig |
| Nicht geprüft | echte Telefone und echte Mac-Hardware außer den Build-Maschinen |

## Aus Version 4.0

| Prüfung | Ergebnis |
|---|---|
| Unit-Tests | 96 Tests ohne Fehler auf macOS 26 (arm64) und macOS 15 (x86_64); neu: `MacModelTests` (Bauform aus Modellkennung – MacBook Pro 2017 mit Kinn, Notch-Modelle, M2-13"-Ausnahme, Air, iMac, Desktop, unbekannte Kennung) |
| Mac-Erkennung auf echter Hardware der Build-Maschinen | Intel-Maschine als „Mac mini · Ende 2012“ erkannt (Namensliste von macOS), virtuelle macOS-26-Maschine fällt korrekt auf „Mac“ mit aktueller Bauform zurück |
| Bildschirmfotos | 22 Ansichten × hell/dunkel auf macOS 26 (Liquid Glass + Rückfall), dazu eine Tafel aller Mac-Bauformen; macOS 15 Intel in 1512×930, 1728×930, 1280×800 und 960×640 |
| Layout-Durchgang | Bühne, leere Zustände, Dateimanager im kleinsten Fenster, Duplikate-Leiste geprüft; korrigiert: Fotos im Mac-Bildschirm der Bühne liefen über ihre Kachel, Großansicht auf Intel/macOS 15 nicht eingepasst (Rollbalken) – jetzt passt sich das Bild bei jeder Größenänderung neu ein |
| Installation aus der DMG | macOS 26 (Apple Silicon) und macOS 15 (Intel) |
| Nicht geprüft | echte Geräte (Telefon, deine Samsung-SSD), echte Gehäusefarbe (nicht auslesbar – wählbar), Bauformen anderer Macs nur als gezeichnete Tafel (die Zuordnung ist per Unit-Test geprüft) |

## Aus Version 3.0

| Prüfung | Ergebnis |
|---|---|
| Unit-Tests | 90 Tests ohne Fehler (neu: Samsung-SSD/Monitor nicht als Telefon, Akkustand lesen bzw. nicht unterstützt, kurze Speichernamen) |
| Bildschirmfotos | 21 Ansichten × hell/dunkel, auf macOS 26 (natives Liquid Glass + Rückfall) und macOS 15 Intel; Fenstergrößen 960×640 (kleinstes Fenster), 1280×800, 1512×945 und 1728×1080 (die Build-Maschinen begrenzen die Höhe auf ihren Bildschirm) |
| Layout-Durchgänge | 3 Durchgänge mit Korrekturen: Telefonuhr skaliert, Werkzeuge rücken bei Platzmangel unter den Titel, Tabellenspalten passen in die Spalten, Speichernamen gekürzt, Bestätigungstext bricht um, Bildfüllungen vergrößern keine Ebenen mehr |
| Installation aus der DMG | macOS 26 (Apple Silicon, nativ und Intel-Teil über Rosetta) und macOS 15 (Intel) |
| Nicht geprüft | echte Geräte (Telefon, Samsung-SSD) – die Erkennung ist mit nachgebildeten Schnittstellen getestet; UI-Automatisierung (XCUITest) ist mit dem SwiftPM-Projekt nicht eingerichtet, die Prüfung erfolgt über Bildschirmfotos |

## Aus Version 2.0

Alle Prüfungen laufen automatisch in der Build-Pipeline (`.github/workflows/android-bridge.yml`) auf echten
macOS-Rechnern von GitHub. Ergebnisse, Protokolle und Bildschirmfotos liegen im Zweig `ci-ergebnisse-android-bridge`.

## Tatsächlich geprüft

| Bereich | Prüfung | Umgebung | Ergebnis |
|---|---|---|---|
| Kompilieren | Release-Build ohne Fehler | macOS 26, Xcode 26 (Swift 6.3, SDK 26.5) | ✓ |
| Kompilieren (Rückfall ohne Liquid Glass) | Release-Build | macOS 15 Intel, Xcode 16 (Swift 6.1) | ✓ |
| Unit-Tests (ABCore) | 86 Tests: PTP-Kodierung, Container, Datensätze, MTP-Sitzung gegen simuliertes USB-Gerät, Geräteerkennung, Sortierung, Suche, Konfliktnamen, Metadatenfilter, Übertragungsmathematik; **neu in 2.0:** Löschen (31 Tests zusammen mit Duplikaten und Balkenerkennung) | macOS 26 arm64 **und** macOS 15 x86_64 | ✓ |
| Universal Binary | `lipo -verify_arch arm64 x86_64`, `minos 13.0` je Architektur | macOS 26 | ✓ |
| Abhängigkeiten | nur Apple-Systembibliotheken verknüpft (nichts zu bündeln) | macOS 26 | ✓ |
| Signatur | ad-hoc, `codesign --verify --deep --strict` | macOS 26 / 15 | ✓ |
| DMG | erstellt, `hdiutil verify`, eingehängt, App + Verknüpfung „Programme“ vorhanden, Architekturen und Signatur in der DMG geprüft, SHA-256 | macOS 26 | ✓ |
| Installation + Start | DMG einhängen, App kopieren, starten, Selbsttest (Fenster sichtbar, USB-Überwachung aktiv, Protokollkern) | macOS 26 Apple Silicon (nativ) | ✓ |
| Installation + Start | wie oben, Intel-Teil des Universal Binary über Rosetta | macOS 26 Apple Silicon | ✓ |
| Installation + Start | wie oben, nativ x86_64 | **echter Intel-Mac**, macOS 15 | ✓ |
| Bildschirmfotos | 12 Ansichten × hell/dunkel (neu: Duplikate – Bereich und Ergebnisse, Löschbestätigung, Einstellungen, eine Spalte); Liquid Glass (macOS 26) und Rückfall (macOS 15) | macOS 26 / 15 | ✓ |

### Neu in 2.0: Löschen und Duplikate (simuliertes Gerät bzw. Speicherleser)

| Fall | Test |
|---|---|
| Einzelne Datei, Datei auf SD-Karte | `testDeleteSingleFile`, `testDeleteFileOnSDCard` |
| Ordner samt Inhalt (Android löscht rekursiv) | `testDeleteFolderRecursivelyAndroidStyle` |
| Gerät löscht nur leere Ordner → Inhalt einzeln | `testDeleteFolderOnDeviceThatOnlyDeletesEmptyFolders` |
| Geschützte Datei (Zugriff verweigert) – Rest wird gelöscht, Fehler gemeldet | `testProtectedFileIsReportedOthersDeleted` |
| Objekt existiert nicht mehr | `testDeleteMissingObjectIsNotAnError` |
| Abbruch, Trennung während des Löschens | `testCancelledBeforeDeleteThrows`, `testDisconnectDuringDeleteThrows` |
| Gleicher Inhalt: gleicher Name / andere Namen / andere Ordner / anderer Speicher | `testSameNameSameContentIsDuplicate`, `testIdenticalContentDifferentNamesFoldersAndStorages` |
| Gleiche Größe, anderer Inhalt → **kein** Duplikat | `testSameSizeDifferentContentIsNotDuplicate`, `testSameEdgesDifferentMiddleNeedsFullHash` |
| Dateien mit einmaliger Größe werden nie gelesen | `testUniqueSizesAreNeverRead`, `testDifferentHeadsSkipFullHash` |
| Große Videos ohne Teillesen | `testLargeIdenticalVideosWithoutRangeSupport` |
| 5.000 Dateien | `testThousandsOfFilesGrouping` |
| Nicht lesbare Datei → übersprungen, nie Duplikat; Trennung → Abbruch | `testUnreadableFileIsSkippedNotGrouped`, `testDisconnectDuringScanAborts` |
| Abbruch der Suche | `testCancellation` |
| Ähnliche Bilder (andere Auflösung) getrennt, verschiedene Bilder nicht ähnlich | `testSameImageDifferentResolutionIsSimilar`, `testDifferentImagesAreNotSimilar`, `testClusteringSeparatesGroups` |
| Vorschlag: höhere Auflösung, Kameraordner, Originalname; Auswahl behält immer eine Datei | `testKeepSuggestionPrefersHigherResolutionForSimilar`, `testSelectionAlwaysKeepsOne` |
| Schwarze Balken in Vorschaubildern (Hoch-/Querformat), dunkler Himmel bleibt | `LetterboxTests` (5 Tests) |

### Protokolltests im Detail (simuliertes Gerät)

Die MTP-Sitzung wird gegen ein simuliertes USB-Gerät geprüft, das die Bulk-Semantik nachbildet (Lesen endet bei vollem
Puffer oder kurzem Paket, Nullpakete, Geräte ohne Nullpaket). Geprüft werden u. a.:

- Download in 15 Größen rund um Paket- und Puffergrenzen, mit/ohne Nullpaket, mit bekannter und unbekannter Länge
  (Pfad für Dateien über 4 GB), Kopf als eigener Transfer
- Upload in 8 Größen mit ungleichmäßiger Lieferung der Quelldaten
- Abschnittsweises Herunterladen (GetPartialObject64) mit anderen Anfragen dazwischen
- Auflisten über GetObjectPropList und über GetObjectInfo
- Abbruch während Download/Upload, Fehler beim Schreiben am Ziel, Fehler beim Lesen der Quelle – Sitzung bleibt benutzbar
- veraltete Antworten früherer Transaktionen, Restdaten einer unterbrochenen Verbindung
- Ordner anlegen, umbenennen, löschen; Sitzung erneut öffnen

Die Protokollschicht wurde zusätzlich unabhängig gegen das Verhalten des Android-MTP-Servers (AOSP) überprüft; alle
sieben Befunde dieser Prüfung sind behoben und durch Tests abgedeckt.

## Nicht geprüft (ehrlich ausgewiesen)

| Bereich | Grund |
|---|---|
| **Löschen und Duplikatsuche an einem echten Telefon** | Gegen das simulierte Gerät getestet (inkl. Android-Verhalten bei Ordnern und geschützten Dateien), **nicht an echter Hardware verifiziert**. Bitte zuerst mit unwichtigen Testdateien ausprobieren. |
| Ähnliche Bilder mit echten Fotos | Der Wahrnehmungs-Hash ist mit erzeugten Bildern getestet; die Trefferqualität mit echten Fotos ist nicht gemessen. |
| **Echte Übertragung mit einem Android-Telefon** (Pixel 6 Pro und andere) | An den Build-Rechnern hängt kein Telefon. Erkennung, Verbindung, Auflisten, Hoch-/Herunterladen, SD-Karte, Dateien > 4 GB sind gegen das simulierte Gerät getestet, aber **nicht an echter Hardware verifiziert**. |
| Start unter macOS 13 und 14 | GitHub stellt keine macOS-13/14-Rechner mehr bereit. Die App ist für macOS 13 gebaut (`minos 13.0`) und verwendet nur APIs, die ab macOS 13 verfügbar sind. |
| Ziehen einer Telefondatei direkt in den Finder | Funktion vorhanden (Datei wird beim Ablegen geladen), ohne angeschlossenes Telefon nicht automatisiert prüfbar. |
| Beglaubigung durch Apple (Notarisierung) | Kein Apple-Developer-Konto hinterlegt – die App ist ad-hoc signiert (siehe README: erster Start). |

## Empfohlene Hardware-Prüfung (Pixel 6 Pro)

1. App installieren und starten, Telefon anschließen, „Dateiübertragung“ wählen → Übersicht zeigt „Verbunden“ und den Speicher.
2. Dateimanager: `DCIM/Camera` öffnen, Fotos auswählen, auf den Mac übertragen.
3. Einen Ordner vom Mac auf das Telefon ziehen (z. B. nach `Download`).
4. Galerie öffnen, Vorschau eines Fotos und eines Videos.
5. Eine große Videodatei (> 4 GB, falls vorhanden) übertragen.
6. **2.0 – Löschen:** einen Testordner mit 2–3 Dateien anlegen, eine Datei per Kontextmenü löschen, dann den Ordner
   (Häkchen in der Bestätigung) – im Dateimanager und in „Fotos & Videos“ prüfen, dass beide verschwunden sind.
7. **2.0 – Duplikate:** ein Foto in `Download` kopieren (z. B. vom Mac hochladen), „Duplikate finden“ → nur `DCIM` und
   `Download` wählen → Gruppe prüfen → „Nur diese behalten“ → löschen → Ergebnis prüfen.
8. Bei Problemen: Seitenleiste → Diagnose → „In Zwischenablage kopieren“ (enthält keine Dateinamen).
