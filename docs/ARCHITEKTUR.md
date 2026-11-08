# Architektur und technische Entscheidungen

## MTP-Umsetzung: eigene Implementierung auf IOUSBHost

| Ansatz | Ergebnis der Bewertung |
|---|---|
| **libmtp** (+ libusb) | Ausgereift, große Gerätedatenbank – aber **LGPL-2.1** (Pflichten beim Weitergeben einer gebündelten App: Neuverlinkbarkeit, Quelltextangebot), C-Abhängigkeitskette muss für arm64 und x86_64 gebaut und gebündelt werden. |
| **libusb** allein | LGPL-2.1, zusätzliche Schicht ohne Mehrwert gegenüber Apples eigenem Benutzerraum-Framework. |
| **Swift-MTP-Bibliotheken** | Keine aktiv gepflegte, produktionsreife Bibliothek für macOS gefunden. |
| **ImageCaptureCore** | Für Kameras/Bilder gedacht; kein vollständiger Dateisystemzugriff, kein Hochladen beliebiger Dateien. |
| **IOUSBHost (Apple, macOS 10.15+)** ✔ | Benutzerraum, kein Treiber, keine Kernel-Erweiterung, Universal 2 ohne Zusatzaufwand, keine Lizenzpflichten. |

Gewählt: **eigene MTP/PTP-Implementierung (Modul `ABCore`) über IOUSBHost**. Das Protokoll folgt der öffentlichen
Spezifikation (USB-IF „Media Transfer Protocol v1.1“, ISO 15740 PTP) sowie dem Verhalten des Android-MTP-Servers
(AOSP `MtpServer`).

Wichtige Punkte der Umsetzung:

- **Container-Rahmung:** Lesen über einen Eingangspuffer, der Paketgrenzen, Nullpakete (ZLP) und zusammengelaufene
  Transfers (Daten + Antwort in einem Lesevorgang bei Geräten ohne ZLP) korrekt behandelt.
- **Dateien über 4 GB:** Datenphase mit Länge `0xFFFFFFFF` und Ende per kurzem Paket (in beide Richtungen),
  `ObjectInfo` mit Größe `0xFFFFFFFF`, echte Größe über die Eigenschaft `ObjectSize` (UInt64). Alle Größen sind
  durchgehend `UInt64`; Übertragungen werden gestreamt, nie vollständig in den Speicher geladen.
- **Teilstücke (GetPartialObject64):** Downloads großer Dateien laufen in 16-MB-Abschnitten. Dazwischen kommen
  Ordneranfragen und Vorschaubilder an die Reihe (Priorisierung), Downloads lassen sich anhalten und fortsetzen.
- **Schnelles Auflisten:** `GetObjectPropList` (Tiefe 1) für große Ordner, mit Plausibilitätsprüfung und Rückfall auf
  `GetObjectInfo` je Objekt.
- **Abbruch:** Klassenanforderung „Cancel Request“ (0x64), Restdaten verwerfen, Stillstand der Endpunkte aufheben –
  die Sitzung bleibt benutzbar.
- **Serialisierung:** je Gerät eine Warteschlange mit genau einer laufenden Transaktion (MTP ist seriell); mehrere
  Geräte arbeiten unabhängig voneinander.

## Geräteerkennung

IOKit-Benachrichtigungen für `IOUSBHostDevice` und `IOUSBHostInterface` (kein Abfragen im Takt). Klassifizierung
protokollbasiert über die Schnittstellen (`ABCore/USBClassification.swift`):

1. herstellerspezifische Schnittstelle mit Namen „MTP“,
2. herstellerspezifische Schnittstelle (FF/FF/00) eines Android-Herstellers bzw. eines Geräts mit ADB-Schnittstelle,
3. Standard-Bildgeräteklasse (06/01/01, PTP).

Die Herstellerliste dient nur der Anzeige und der Erkennung „Telefon ohne Dateiübertragung“ – nie als
Voraussetzung. Neue Modelle (z. B. Pixel 11 Pro) funktionieren ohne Anpassung, solange sie Standard-MTP sprechen.

## Module

| Ordner | Inhalt |
|---|---|
| `Sources/ABCore` | PTP/MTP-Container, Datensätze, Sitzung, Klassifizierung, Sortierung, Konfliktnamen, Übertragungsmathematik – ohne Apple-UI-Frameworks, vollständig unit-getestet |
| `USB/` | IORegistry-Überwachung, IOUSBHost-Transport |
| `MTP/` | Gerätewarteschlange (`MTPWorker`), `DeviceBackend`, Verbindungsablauf (`DeviceConnection`), `DeviceManager` |
| `Transfer/` | Übertragungs-Engine (Planung, Konflikte, temporäre Dateien, Prüfung, Pause/Fortsetzen, Wiederholen) |
| `Services/` | Einstellungen, Favoriten, Verlauf, Vorschaubilder, Diagnose, Fehlermeldungen, Mitteilungen |
| `Design/` | Liquid Glass (macOS 26) und Rückfall (macOS 13–15), Farben, Komponenten |
| `Views/` | Übersicht, Dateimanager, Galerie, Vorschau, Übertragungen, Favoriten, Verlauf, Einstellungen, Diagnose |
| `Snapshot/` | Bildschirmfotos und Selbsttest für die Build-Pipeline |

## Sicherheit beim Übertragen

- Kopieren ist immer der Standard; Originale werden nie nach dem Übertragen gelöscht.
- Downloads schreiben zuerst in eine versteckte temporäre Datei (`.Name.xxxx.abpart`) und werden erst nach
  bestandener Prüfung umbenannt; bei Fehlern wird die temporäre Datei entfernt.
- Uploads: bei Fehlern wird das unvollständige Objekt auf dem Telefon gelöscht. „Ersetzen“ lädt zuerst unter
  vorläufigem Namen hoch und löscht das Original erst nach erfolgreicher Prüfung.
- Prüfung: immer Dateigröße; optional SHA-256 (Ziel wird erneut gelesen und verglichen).
- Löschen auf dem Telefon nur nach Bestätigung; auf dem Mac nur in den Papierkorb.

## Version 2.0: Löschen auf dem Telefon

- `MTPSession.deleteTree` (ABCore): `DeleteObject` auf das Objekt. Android löscht Ordner rekursiv selbst; Geräte,
  die nur leere Ordner löschen, werden erkannt (Antwort ≠ OK) – dann werden die Kinder einzeln gelöscht und der
  Ordner erneut. „Objekt existiert nicht mehr“ gilt als gelöscht. Geschützte Objekte werden mit Antwortcode gemeldet,
  der Rest wird trotzdem gelöscht. Trennung und Abbruch beenden den Vorgang sofort.
- `DeletionService` (App): führt eine bestätigte `DeletionRequest` aus, meldet Fortschritt, ermittelt den
  tatsächlich frei gewordenen Speicher (Speicherinfo vor/nach) und listet nicht gelöschte Objekte mit Grund.
- Bestätigung (`DeleteConfirmationSheet`): Anzahl Dateien/Ordner, Größe, Speicherorte, Warnung „kein Papierkorb“;
  bei Ordnern zusätzlich ein Häkchen „Ich verstehe …“. Die Löschtaste ist nie die Standardtaste (Return löscht nicht).
- Ohne Bestätigung führt kein Weg zu `deleteTree`: Kontextmenüs, Werkzeugleisten, ⌘⌫ und die Duplikatliste rufen
  ausschließlich `AppModel.requestDeletion` auf, das nur die Bestätigung öffnet.

## Version 2.0: Duplikate finden

Eigener Dienst mit getrennten Teilen:

| Teil | Ort | Aufgabe |
|---|---|---|
| Suche | `DuplicateScanner.collect` | Bereiche (Speicher, DCIM, Pictures, Movies, Download, Documents, aktueller Ordner) per Breitensuche erfassen – nur Name, Größe, Typ, Datum. `Android/data`, `Android/obb` und versteckte Ordner werden übersprungen. |
| Vergleich | `ExactDuplicateFinder` (ABCore) | 1. nur gleich große Dateien; 2. Anfang + Ende (je 64 KB, kleine Dateien vollständig); 3. nur bei gleichem Fingerabdruck die ganze Datei per SHA-256 (gestreamt). Nicht lesbare Dateien werden übersprungen und nie als Duplikat gewertet; Trennung bricht ab. |
| Ähnliche Bilder | `PerceptualHash` (ABCore) | optional: dHash 9×8 der MTP-Vorschaubilder, Abstand ≤ 5. Ergebnis immer als „ähnlich – nicht identisch“ getrennt. |
| Vorschläge | `KeepSuggestion` (ABCore) | Kameraordner, Originalname (ohne „(1)“, „Kopie“, „-WA“), älteste Datei; bei ähnlichen Bildern höhere Auflösung. Nur Empfehlung – nichts wird automatisch markiert. |
| Auswahl | `DuplicateScanner` | markieren, „nur diese behalten“, Vorschlag übernehmen, Gruppe überspringen. Jede Gruppe behält immer mindestens eine Datei – auch über Gruppen hinweg. |
| Löschen | `AppModel.deleteMarkedDuplicates` → `DeletionService` | Bestätigung mit Gruppen, verbleibenden Dateien, freizugebendem Speicher und Orten; danach Gruppen aktualisieren, Fehler getrennt zeigen. |

## Version 2.0: Gestaltung

Eigenes Designsystem nach den Prinzipien der Musikbibliothek (nicht kopiert):

- `Design/Theme.swift`: Farbtokens (Hell/Dunkel eigenständig, Akzent „Bridge-Mint“), Abstände (4-pt-Raster,
  Seitenrand 28), Radien, Maße, Bewegung (Federn), Typografie mit Inter/Inter Display (im Paket, SIL OFL 1.1),
  Glas (macOS 26 `glassEffect`, sonst NSVisualEffectView + Tönung + Lichtkante), verdeckte Titelleiste.
- `Design/Chrome.swift`: Seitengerüst (großer Titel, Untertitel, Werkzeugkapsel rechts, Fenster-Ziehfläche),
  Glasknöpfe, Suchfeld, Segmente, schwebende Aktionsleiste, Hinweise, Dialogkopf, Abschnitte.
- Fenster: Inhalt bis an den Rand, schwebende Glas-Seitenleiste (Ampel-Knöpfe liegen darauf), Atmosphäre-Hintergrund.
- MTP-Vorschaubilder: schwarze Balken (Android rechnet Hochformatfotos in 160×120 ein) werden symmetrisch erkannt
  und abgeschnitten (`Letterbox`, ABCore, getestet).

## Version 3.0: „Midnight Glass“

- `Design/Theme.swift`: neue Palette (tiefe Flächen, Signal-Grün, Tiefblau, Violett), Systemschrift SF Pro,
  `CinematicBackground` (Lichtfelder, höchstens 20 Bilder/s, pausiert ohne Animationen bzw. bei „Bewegung reduzieren“),
  Glas in fünf Schichten, `revealOnAppear`.
- `Design/Visuals.swift`: eigene Darstellungen – Telefon, neutrales Notebook (ohne Markenzeichen), Lichtverbindung,
  Speicherring, Akku, Vorschaumosaik.
- `Services/DeviceShowcase.swift`: liest für die Übersicht nur 2–3 Ordnerlisten des Kameraordners (keine Inhalte);
  `StorageBreakdown` berechnet die Belegung nach Art aus einer vollständigen Galerie-Suche.
- Fenster: durchgehende Seitenleiste; unter 1100 pt Breite (oder per ⌃⌘S) Symbolleiste. Seitenköpfe weichen bei
  Platzmangel aus (`ViewThatFits`) – Werkzeuge rücken unter den Titel statt abgeschnitten zu werden.
- Dateimanager: eigene `SplitPanes` statt `HSplitView` (die Systemteilung erzeugte unter macOS 26 einen grauen
  Titelleistenstreifen über dem Seitentitel).
- Galerie: Abschnitte je Monat (`GallerySection`), `SectionMosaic` (neuestes Bild 2×2, Rest als fester Raster, faul geladen).
- Großansicht als Ebene über dem ganzen Fenster statt als Dialog.
- USB-Erkennung: Geräte eines Android-Herstellers gelten nur noch als „Telefon ohne Dateiübertragung“, wenn sie eine
  telefontypische Schnittstelle haben (ADB, MTP/PTP, Tethering, MIDI, herstellerspezifisch) – Massenspeicher wie die
  Samsung PSSD T5 EVO, Monitore oder Tastaturen werden ignoriert.
- Akkustand: PTP-Geräteeigenschaft 0x5001 (`GetDevicePropValue`), nur wenn das Gerät sie anbietet.
