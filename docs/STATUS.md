# Umsetzungsstand

Stand 13.11.2026 · **ORBIT 0.4.0** (vorher AETHER 0.3.0, Phase 3)

## ORBIT 0.4.0 – „Spatial Liquid Glass“ (Auftrag „ORBIT Master Prompt“)

Prüfstufe neu: **Build** (Gradle, echte Android-SDK-Bibliotheken) und **Emulator** (Android 15, x86_64, Pixel-7-Profil
und Tablet-Größe 1600 × 2560 / 320 dpi). Hardware-Prüfung auf einem echten Telefon steht weiterhin aus.

| Punkt des Auftrags | Stand | Geprüft |
|---|---|---|
| Name ORBIT, neues Symbol (adaptiv, Designsymbol, Startbildschirm) | ✔ | Build (`aapt2`: Label „ORBIT“), Emulator |
| Designsystem: Palette, Materialebenen, Themes inkl. Minimal Dunkel, Effektprofile, Bewegung reduzieren | ✔ | JVM-Test (Kontrast 6, OrbitTest 6), Emulator (alle Themes, alle Effektstärken) |
| 1 Auftakt · 2 lebendiger Hintergrund · 3 Lichtreflex · 4 räumliche Navigation | ✔ | Build, Emulator (Standbilder) |
| 5 verwandelbare Karten · 6 Datenfluss · 8 ORBIT Core | ✔ (CPU/GPU von Android nicht freigegeben – benannt) | JVM-Test (Rechenlogik), Build, Emulator |
| 7 Live-Diagramme | ◐ bestehende Verlaufsdiagramme (Speicher) unverändert | Build |
| 9 Temperatur · 10 Akku-Flüssigkeit · 11 Speicherschichten | ✔ | Build, Emulator |
| 12 Sensor-Globus | ✔ (echte GNSS-Meldungen + Kompass) | Build; Emulator liefert eigene Satelliten |
| 13 Dateianimationen · 14 Statusrückmeldung · 15 Haptik | ✔ | Build; Haptik nur auf Hardware spürbar |
| Leere Zustände mit eigener Illustration | ✔ | Build |
| Tatsächlicher Build, installierbare APK | ✔ `ORBIT-0.4.0.apk` | Build, `apksigner`, Emulator-Installation |

### Prüfprotokoll 0.4.0 (GitHub Actions, Zweig `orbit-android`, Ergebnisse im Zweig `ci-ergebnisse-orbit-android`)

| Prüfung | Ergebnis |
|---|---|
| Unit-Tests (Gradle) | **232/232** – core/files 155 (echte Dateien), core/model 71 (davon 6 ORBIT), Designsystem 6 (Kontrast aller Themes × Akzente) |
| Release-Build | `ORBIT-0.4.0.apk` (≈ 27,6 MB, versionCode 3), AGP 9.3.1, compileSdk 37, minSdk 31, targetSdk 36 |
| Paketprüfung | `apksigner verify`: Signaturschema v2 gültig (Projektschlüssel); `aapt2`: Paket `de.privateapp.aether`, Name „ORBIT“, Symbol adaptiv |
| Emulator (Android 15, x86_64, 4 GB) | Installation mit allen Laufzeitrechten, 3 Kaltstarts je ≈ 3,3–4,0 s (Software-Grafik), Bildschirmfotos: 6 Hauptbereiche hell/dunkel, alle 6 Themes, 3 Effektstärken, Tablet-Größe, aufgeklappte ORBIT-Core-Karte, Sensor-Globus hell/dunkel; **keine App-Abstürze** (Lauf 6) (Absturzpuffer leer, kein FATAL im vollständigen Logcat) |
| Offline-Prüfungen | Typprüfung aller Module 0 Fehler/0 Warnungen, Prüfskript „Farben aus dem Theme“ ohne Verstoß |

**Im Build gefunden und behoben:** ORBIT-Core-Namen auf schmalen Telefonen abgeschnitten („Arbeitsspei…“) → Kern
oben, Legende in voller Breite; Thermik-Bahn war schon bei 43 % orange → Orange erst ab 60 %, Rot ab 85 %;
Einstellungen nannten „fünf“ Themes → sechs. In Lauf 3 brach der **Emulator** (nicht die App) beim Scrollen der
Bewegungsseite ab und die Absturzprüfung wartete bis zur Zeitgrenze: Seitdem hat jeder Schritt eine Frist, das
vollständige Logcat wird mitgeschrieben, und der Emulator bekommt 4 GB statt der Vorgabe. In Lauf 5 brach der
Emulator erneut ab, wieder beim Wischen am linken Rand der Bewegungsseite: Das Logcat endet mit einer abgebrochenen
Zurück-Geste des Systems (`ShellBackPreview`), die App meldete keinen Fehler (kein FATAL, Absturzpuffer leer). Seit
Lauf 6 öffnet der Prüfmodus die Bewegungsseite direkt beim Sensor-Globus (`orbit.snapshot=globe`), ohne zu wischen –
Lauf 6 lief vollständig durch, ohne Abbruch und ohne App-Fehler.

**Sensor-Globus im Emulator:** Der Emulator meldet 6 Satelliten mit Signal, aber offenbar ohne Richtung – alle Punkte
liegen übereinander am Nordpunkt des Horizonts. Das ist die Meldung des Emulators, keine Darstellung der App; auf
einem Telefon verteilen sich die Satellitenpunkte nach ihrem gemeldeten Azimut und ihrer Elevation.

**Grenzen:** Die Bildwiederholraten des Emulators (`gfxinfo`) sind mit Software-Grafik (SwiftShader) nicht
aussagekräftig – jedes Bild gilt dort als „ruckelnd“, auch ohne ORBIT-Effekte (Lauf 1). Flüssigkeit, Haptik, echte
Satelliten, SD-Karte und USB müssen auf einem Telefon geprüft werden (docs/TESTPLAN.md).

Legende: **✔ umgesetzt** · **◐ teilweise / Grundlage** · **– spätere Phase**. „Geprüft“ nennt die höchste erreichte
Prüfstufe: *JVM-Test* (automatisiert, ausgeführt; bei `core:files` gegen echte Dateien), *Typprüfung* (gegen
Android-/AndroidX-Schnittstellen kompiliert, nicht ausgeführt), *Vorschau* (nachgebaute Design-Vorschau), *Gerät*
(bisher bei keinem Punkt).

## Phase 3 – dein Auftrag

| Wunsch | Stand | Geprüft | Wo |
|---|---|---|---|
| Zugriff auf alle Daten | ✔ „Zugriff auf alle Dateien“ mit Erklärung, Rückkehr-Erkennung, Stand in den Einstellungen | Typprüfung | `platform/storage/AllFilesAccess.kt`, `ui/files/FilesScreen.kt`, `ui/settings/InfoScreens.kt` |
| Löschen | ✔ Papierkorb je Speicher (mit Widerrufen, Wiederherstellen, Leeren) und endgültiges Löschen nach Bestätigung | JVM-Test (`TrashTest`), Typprüfung | `core/files/TrashStore.kt`, `TrashOperations.kt`, `ui/files/TrashScreen.kt` |
| Bearbeiten | ✔ Umbenennen, Ordner erstellen, Kopieren, Verschieben, Duplizieren, Komprimieren, Entpacken, Textdateien bearbeiten | JVM-Test (`CopyTest`, `MoveTest`, `RenameCreateTest`, `ArchiveTest`, `WriteTextTest`, `CancellationTest`) | `core/files/*Operations.kt`, `ui/files/*` |
| SD-Karte | ✔ wie interner Speicher (Liste, Vorgänge, eigener Papierkorb); geprüftes Verschieben zwischen den Speichern; „nur lesbar“ erkannt | JVM-Test (Speichergrenzen simuliert), Typprüfung · **echte Karte ausstehend** | `platform/storage/VolumeRoots.kt`, `core/files/TransferOperations.kt` |
| Geschwindigkeit, Höhe usw. | ✔ Geschwindigkeit, Kurs, Höhe (Meeresspiegel/Ellipsoid/Druck), Satelliten, Kompass, Messung seit dem Öffnen | JVM-Test (`MotionModelsTest`), Typprüfung · **Hardware ausstehend** | `core/model/motion`, `platform/device/motion`, `ui/motion` |
| „Wie bei Apple“ | ✔ Aufbau wie „Dateien“/„Kompass“ auf dem iPhone: Aktionsblatt, Auswahl-Werkzeugleiste, Schnellansicht, Widerrufen, ehrliche Zustände, Bewegung nach Systemeinstellung | JVM-Test (Kontrast inkl. neuer Flächen), Prüfskript, Vorschau | `docs/design/dateien-vorschau.png` |

## Anforderungen des Auftrags (Stand nach Phase 3)

| § | Anforderung | Stand | Geprüft |
|---|---|---|---|
| 3.1–3.4 | Liquid Glass, Dark Mode, keine festen Schriftfarben, Bewegungssystem | ✔ | JVM-Test (Kontrast), Prüfskript, Vorschau |
| 4.1 | Header mit Identität, Statuszeile, Einstellungen, **globale Suche** | ✔ | Typprüfung (Suche unter „Dateien“) |
| 4.2–4.4 | Speichervisualisierung, Gerätestatus, Empfehlungen aus realen Befunden | ✔ | JVM-Test, Typprüfung |
| 4.5 | Schnellzugriffe | ✔ | Typprüfung (Übersicht und „Dateien“) |
| 5 | Dateimanager: Navigation, Kategorien, Liste/Raster, Sortierung, Auswahl, Kopieren, Verschieben, Umbenennen, Löschen (Papierkorb), Teilen, Öffnen, Informationen, Suche, Favoriten, zuletzt verwendet, Archive | ✔ | JVM-Test (Engine), Typprüfung (Oberfläche) |
| 5 | Datensicherheit: Original erst nach verifizierter Kopie löschen, nie automatisch löschen | ✔ | JVM-Test (u. a. Prüfsumme, Abbruch, volle Ziele, Absturz-Journal) |
| 6 | microSD/USB | ✔ | Typprüfung · Gerät ausstehend (Pixel: USB-OTG, Xiaomi: SD) |
| 7 | Smart Storage (Analyse, Duplikate) | – | Phase 5 (Papierkorb vorgezogen) |
| 8.1–8.3 | Geräteübersicht, Temperatur, Thermalstatus | ✔ | JVM-Test, Typprüfung |
| 8.4–8.6 | Sensor-Explorer, Live, Diagnose | ◐ | „Bewegung“ (GPS, Barometer, Kompass) live · Sensorliste Phase 6 |
| 9 | Live-Werte nur während der Nutzung | ✔ | Typprüfung (WhileSubscribed, Abmelden; Bewegung ohne Hintergrund) |
| 10.1–10.5 | Themes, Akzente, Effektstärke, Tokens | ✔ | JVM-Test, Prüfskript |
| 10.4 | Personalisierung | ◐ | Darstellung, Dateiansicht, Sortierung, versteckte Objekte · Startseite Phase 7 |
| 11 | Fünf Bereiche, schwebende Navigation, adaptiv | ✔ | Typprüfung |
| 12.4 | Minimale Berechtigungen | ✔ | Manifest, [BERECHTIGUNGEN.md](BERECHTIGUNGEN.md) |
| 12.5 | Lokal, keine Telemetrie, kein Internet | ✔ | Manifest (keine `INTERNET`-Berechtigung) |
| 14 | Zugänglichkeit: Kontraste, Touch-Ziele, TalkBack (Rollen, Aktionen, Ansagen), nicht nur Farbe | ✔ | JVM-Test (Kontrast), Durchsicht · TalkBack auf Gerät ausstehend |
| 15 | Fehlerbehandlung: entfernte Karte, volle Ziele, gesperrte Ordner, Konflikte, Abbruch | ✔ | JVM-Test (Engine), Typprüfung |
| 16 | Tests | ◐ | siehe [TESTPLAN.md](TESTPLAN.md) – kein Gradle-Build/Gerät in dieser Umgebung |
