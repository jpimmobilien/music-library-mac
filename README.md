# Android Bridge

Native macOS-App für die Dateiübertragung zwischen Android-Telefonen und dem Mac per USB (MTP) –
mit Dateimanager in zwei Spalten, Foto- und Videogalerie, Übertragungszentrale und Liquid-Glass-Gestaltung.

**Neu in 4.1:** „Dieser Mac“ mit Modellbild in der Seitenleiste, Auswahl in der Seitenleiste als schwebende
Liquid-Glass-Fläche, die federnd zum neuen Eintrag gleitet, federnde Seitenwechsel, Dateimanager standardmäßig mit großen
Vorschauen, „Zuletzt verwendet“ als Kacheln, Großansicht lädt die Nachbarfotos vor (Blättern ohne Wartezeit),
MacBooks 2016–2020 standardmäßig in Silber.

**Neu in 4.0:** kinoreife Gestaltung – die Übersicht ist eine dunkle Bühne mit Lichtband, auf der Ihr Telefon und
**Ihr Mac in seiner echten Bauform** stehen (Modell wird erkannt: z. B. MacBook Pro 2017 mit Kinn, Apple-Silicon-MacBook
mit Notch, MacBook Air, iMac, Mac mini/Studio; selbst gezeichnet, ohne Produktfotos und Logo; Gehäusefarbe wählbar).
Akzente in Blau und Violett, tiefes Schwarz im dunklen Modus, Kopfleisten, die beim Scrollen zur Glasleiste werden,
Glas, das auf den Zeiger reagiert und beim Drücken nachgibt, Fotos, die aus ihrer Kachel aufzoomen (Oberfläche dahinter
weichgezeichnet), illustrierte leere Zustände, echte Vorschauen auch für Dokumente auf der Mac-Seite und eine
Zusammenfassung mit großem „Duplikate löschen“-Knopf.

**Neu in 3.0:** vollständig neue Gestaltung „Midnight Glass“ – Übersicht mit eigener Telefon-/Mac-Darstellung,
Speicherringen und Schnellzugriffen, Galerie mit großen Bildern nach Monaten, Vollbild-Ansicht, Dateimanager mit
Speicherflächen und Rasteransicht, Duplikate als große Vorschauen, „Speicher verwalten“ (Belegung nach Art,
größte Dateien), Akkustand. Samsung-SSDs werden nicht mehr fälschlich als Telefon erkannt.

**Neu in 2.0:** Dateien und Ordner direkt auf dem Telefon löschen (immer mit Bestätigung – das Telefon hat über USB
keinen Papierkorb), **Duplikate finden** (byte-genauer Inhaltsvergleich per SHA-256, ähnliche Bilder getrennt) und eine
vollständig neue Gestaltung.

- **Universal-App:** Apple Silicon (M1 und neuer) und Intel, ohne Rosetta
- **macOS 13 Ventura oder neuer** – auf macOS 26 mit nativem Liquid Glass, darunter mit Systemmaterialien
- **Keine Treiber, keine Kernel-Erweiterung, keine Fremdbibliotheken** – eigene MTP-Implementierung auf Apples
  Benutzerraum-USB-Framework IOUSBHost
- **Alles lokal:** kein Konto, keine Cloud, keine Telemetrie, keine Netzwerkverbindungen

## Installation

1. `AndroidBridge.dmg` doppelklicken.
2. **Android Bridge** auf den Ordner **Programme** ziehen.
3. Die App ist **ad-hoc signiert, aber nicht von Apple beglaubigt** (dafür wäre ein kostenpflichtiges
   Apple-Developer-Konto nötig). Beim **ersten** Start fragt macOS deshalb nach:
   - **macOS 15/26:** App doppelklicken → „Fertig“ wählen → Systemeinstellungen → Datenschutz & Sicherheit →
     ganz unten bei „Android Bridge wurde blockiert“ auf **Dennoch öffnen** → bestätigen.
   - **macOS 13/14:** Rechtsklick auf die App → **Öffnen** → nochmals **Öffnen**.
   - Alternativ im Terminal: `xattr -dr com.apple.quarantine "/Applications/Android Bridge.app"`

## Telefon verbinden

1. Telefon per USB-Kabel anschließen (das Kabel muss Daten übertragen können).
2. Telefon entsperren.
3. In der Mitteilung „USB“ **Dateiübertragung / Android Auto** wählen.

Android Bridge erkennt das Gerät automatisch – protokollbasiert über die USB-Schnittstellen, ohne Modelllisten
(Pixel, Samsung, Xiaomi/Redmi/POCO, OnePlus, OPPO, Motorola, Sony, Nothing, Honor u. a.).

Meldet die App „Von anderem Programm belegt“, hält meist der macOS-Fotodienst das Telefon. Die Schaltfläche
**macOS-Fotodienst freigeben** beendet den Dienst `ptpcamerad` kurz; macOS startet ihn bei Bedarf selbst neu.

## Bauen

Die DMG entsteht automatisch auf GitHub-Actions-Rechnern mit macOS (siehe `.github/workflows/android-bridge.yml`).
Lokal auf einem Mac mit Xcode 16 oder neuer: `Build.command` doppelklicken, oder

```
swift test
scripts/build_app.sh
scripts/make_dmg.sh        # → dist/AndroidBridge.dmg
```

Siehe `docs/ARCHITEKTUR.md` für die technischen Entscheidungen und `docs/TESTBERICHT.md` für den Prüfstand.
