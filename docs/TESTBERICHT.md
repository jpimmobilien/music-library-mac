# Testbericht – Android Bridge 1.0.0

Alle Prüfungen laufen automatisch in der Build-Pipeline (`.github/workflows/android-bridge.yml`) auf echten
macOS-Rechnern von GitHub. Ergebnisse, Protokolle und Bildschirmfotos liegen im Zweig `ci-ergebnisse-android-bridge`.

## Tatsächlich geprüft

| Bereich | Prüfung | Umgebung | Ergebnis |
|---|---|---|---|
| Kompilieren | Release-Build ohne Fehler | macOS 26, Xcode 26 (Swift 6.3, SDK 26.5) | ✓ |
| Kompilieren (Rückfall ohne Liquid Glass) | Release-Build | macOS 15 Intel, Xcode 16 (Swift 6.1) | ✓ |
| Unit-Tests (ABCore) | 55 Tests: PTP-Kodierung, Container, Datensätze, MTP-Sitzung gegen simuliertes USB-Gerät, Geräteerkennung, Sortierung, Suche, Konfliktnamen, Metadatenfilter, Übertragungsmathematik | macOS 26 arm64 **und** macOS 15 x86_64 | ✓ |
| Universal Binary | `lipo -verify_arch arm64 x86_64`, `minos 13.0` je Architektur | macOS 26 | ✓ |
| Abhängigkeiten | nur Apple-Systembibliotheken verknüpft (nichts zu bündeln) | macOS 26 | ✓ |
| Signatur | ad-hoc, `codesign --verify --deep --strict` | macOS 26 / 15 | ✓ |
| DMG | erstellt, `hdiutil verify`, eingehängt, App + Verknüpfung „Programme“ vorhanden, Architekturen und Signatur in der DMG geprüft, SHA-256 | macOS 26 | ✓ |
| Installation + Start | DMG einhängen, App kopieren, starten, Selbsttest (Fenster sichtbar, USB-Überwachung aktiv, Protokollkern) | macOS 26 Apple Silicon (nativ) | ✓ |
| Installation + Start | wie oben, Intel-Teil des Universal Binary über Rosetta | macOS 26 Apple Silicon | ✓ |
| Installation + Start | wie oben, nativ x86_64 | **echter Intel-Mac**, macOS 15 | ✓ |
| Bildschirmfotos | 7 Ansichten × hell/dunkel; Liquid Glass (macOS 26) und Rückfall (macOS 15) | macOS 26 / 15 | ✓ |

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
6. Bei Problemen: Seitenleiste → Diagnose → „In Zwischenablage kopieren“ (enthält keine Dateinamen).
