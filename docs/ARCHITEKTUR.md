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
