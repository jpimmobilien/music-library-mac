# Testbericht – Android Bridge 3.0.0

_Rückfallversionen: 2.0 (Zweig `android-bridge` bis Commit 30402af, DMG „AndroidBridge-2.0“) und 1.0 (Zweig `android-bridge-v1.0`)._

## Neu in 3.0 geprüft

| Prüfung | Ergebnis |
|---|---|
| Unit-Tests | 93 Tests ohne Fehler (neu: Samsung-SSD/Monitor nicht als Telefon, Akkustand lesen bzw. nicht unterstützt, kurze Speichernamen) |
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
