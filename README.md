# Android Bridge

Native macOS-App für die Dateiübertragung zwischen Android-Telefonen und dem Mac per USB (MTP) –
mit Dateimanager in zwei Spalten, Foto- und Videogalerie, Übertragungszentrale und Liquid-Glass-Gestaltung.

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
