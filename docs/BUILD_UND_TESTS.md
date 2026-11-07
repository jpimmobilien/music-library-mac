# Build- und Testergebnis

AETHER 1.0.0 · Stand 7. November 2026 · Release-Build: Lauf 13 (GitHub-Lauf 42400099751) (`70cb4a6`)

Gebaut und geprüft wurde auf **echten macOS-Rechnern** von GitHub Actions, Workflow
[`aether-macos.yml`](../.github/workflows/aether-macos.yml), Zweig `aether-macos`. Alle Protokolle, Selbsttests,
Bildschirmfotos, Absturzberichte und die DMG liegen im Zweig `ci-ergebnisse-aether-macos`.

## 1. Ergebnis

| Prüfung | Ergebnis |
|---|---|
| Datei | `AETHER-macOS-Universal.dmg` · 9 809 219 Bytes (9,4 MB) · SHA-256 `189c9750aca9cc30da9f1b9417a9d69da5b9c9e833014d2abc31fb12bec47a5a` |
| Version | 1.0.0 (Build 13), `de.projectaether.macos` |
| Architekturen (`lipo -archs`) | `x86_64 arm64` – beide nativ |
| Mindest-macOS je Architektur | 13.0 (arm64 und x86_64) |
| SDK / Compiler | macOS SDK 26.5, Xcode 26.6, Swift 6.3.3 (Intel-Rechner: Xcode 26.3, Swift 6.2.4) |
| Xcode-Projekt | aus `project.yml` erzeugt und mit `xcodebuild` gebaut: `x86_64 arm64` ✓ |
| Signatur | ad-hoc (`flags=0x2`), keine Developer-ID hinterlegt → **nicht notarisiert** |
| Verknüpfte Bibliotheken | nur `/System/Library` und `/usr/lib` |
| Netzwerk-APIs in der Programmdatei | keine (geprüft mit `nm -u`) |

## 2. Ausgeführte Schritte

| # | Schritt | Wo | Ergebnis |
|---|---|---|---|
| 1 | Clean Build (`rm -rf .build build`) | macOS 26 (Apple Silicon) und macOS 15 (Intel) | ✓ |
| 2 | Universal-Build arm64 + x86_64 (`swift build --triple …`, `lipo -create`) | beide | ✓ |
| 3 | Prüfung der Architekturen (`lipo -archs`, `-verify_arch arm64 x86_64`, `otool` minos/sdk) | beide | ✓ |
| 4 | App-Bundle und Ressourcen (`plutil -lint`, Icon, en/de.lproj inkl. `InfoPlist.strings`, Lokalisierungsabgleich, nur Systembibliotheken, keine Netzwerk-APIs) | beide | ✓ |
| 5 | Unit-Tests | Linux, macOS 26, macOS 15 Intel | ✓ 106/106 |
| 6 | Selbsttest der gebauten App mit echten Messwerten | beide | ✓ 29/29 |
| 7 | DMG erstellen (`dmgbuild`) und Mount-Test (`hdiutil verify/attach`, Inhalt, Link, Architekturen, `codesign --verify --deep --strict`, Byte-Vergleich) | beide | ✓ |
| 8 | Aus der DMG installieren und starten (Selbsttest) | macOS 26 nativ, macOS 26 über Rosetta, macOS 15 Intel | ✓ 29/29 |
| 9 | Fertige DMG auf einem zweiten Intel-Mac wie ein Nutzer installieren und starten | macOS 15 Intel | ✓ 29/29 |
| 10 | Xcode-Projekt erzeugen und universal bauen | macOS 26 | ✓ |
| 11 | Unabhängige Prüfung der fertigen DMG ohne macOS (eigene Decoder für UDIF, HFS+, Mach-O: `tools/dmg_inspect/verify.py`) | Arbeitsumgebung | ✓ |

## 3. Tests

**Unit-Tests (AetherCore, 106 Tests)** – Linux (x86_64), macOS 26 (arm64), macOS 15 Intel (x86_64), alle bestanden.
Unter anderem:

- CPU- und Speichermathematik, Raten mit Zählerrücksetzung, Puls-Regeln;
- Prozesslogik;
- SMC-Dekodierung (`sp78`, `fpe2`, `flt`, Ganzzahlen, NaN) und Plausibilität;
- Sensorzuordnung, Mittel/Maximum je Bereich, Lüfteranteil;
- Batterie-Parser der Systeminformationen, Netzteileinheiten;
- Systembericht: Seriennummer nur mit Häkchen, Maskierung, Dateiname;
- Speicheranalyse: Kategorien, Duplikate inkl. harter Links, NVMe-SMART-Dekodierung;
- Dateilogik: eindeutige Namen wie „Beide behalten“, Namensprüfung, Stapel-Umbenennung mit Konflikten, Pfade, Rechte;
- Netzwerk: `netstat`-Formate mit und ohne Prozessspalte, Schnittstellenarten, Verlauf (Minutenmittel, Zeitachse, CSV);
- Formatierung Deutsch/Englisch und WCAG-Kontraste aller Themes.

**Selbsttest der fertigen App** (29 Prüfungen, echte Messwerte des jeweiligen Rechners). Nicht verfügbare Werte
bestehen nur, wenn sie mit Grund gemeldet werden – erfundene Ersatzwerte würden die Prüfung scheitern lassen.

- CPU, Kerne, Speicheraufteilung, Druck, Swap;
- Startvolume, SSD-Aktivität, Verschlüsselungsangabe, NVMe-SMART;
- Netzraten, Schnittstellen, Verbindungen (inkl. Prozessspalte), WLAN;
- Thermalstatus, SMC-Sensoren und -Lüfter, SMC-Lesepfad;
- Batterie;
- Verlauf: Datenbank im Testordner schreiben, lesen und löschen; Standard „aus“;
- Systembericht ohne Seriennummer;
- GPU, Modell, Prozessor, Architektur/Rosetta;
- Lokalisierung en/de, sichtbares Fenster.

| Rechner | Prozess | Ergebnis |
|---|---|---|
| macOS 26.7 · Apple Silicon (virtuell) – gebaut | arm64 nativ | ✓ 29/29 |
| macOS 26.7 · Apple Silicon – aus der DMG installiert | arm64 nativ | ✓ 29/29 |
| macOS 26.7 · Apple Silicon – aus der DMG installiert | x86_64 über Rosetta | ✓ 29/29 |
| macOS 15.7 · Intel (virtuell) – gebaut | x86_64 nativ | ✓ 29/29 |
| macOS 15.7 · Intel – aus der DMG installiert | x86_64 nativ | ✓ 29/29 |
| macOS 15.7 · Intel, zweiter Rechner – macOS-26-DMG wie ein Nutzer installiert | x86_64 nativ | ✓ 29/29 |

**Bemerkenswert aus den Messungen:**

- Die Verbindungsliste nennt auf macOS 26 und 15 zu jedem Socket den Prozess (`netstat -anv`, ohne
  Administratorrechte).
- Auf dem virtuellen Intel-Rechner ließ sich das (nachgebildete) SMC öffnen: 653 Schlüssel, 28 Temperaturschlüssel,
  1 Lüfter. Damit ist der Lesepfad in C geprüft. Angezeigt werden diese Werte auf virtuellen Macs bewusst nicht, weil
  sie keine Messungen echter Hardware sind.
- NVMe-SMART: Die SDK-Schnittstelle ist vorhanden. Virtuelle Macs liefern keine Daten, deshalb steht dort „nicht
  verfügbar“ mit Grund.

**Bildschirmfotos** – macOS 26 mit Liquid Glass, mit erzwungenem Rückfall und auf Deutsch: je 24 Bilder, alle Bereiche
einschließlich Speicher, Dateien, Netzwerk und Live-Monitor. Die Build-Rechner haben „Transparenz reduzieren“ an; im
Fotomodus wird das ignoriert, damit das Glasdesign sichtbar ist.

**Eigenverbrauch** (Selbsttest, nur die ersten 3 Sekunden einschließlich Start, Sensor- und Schnittstellensuche):
ungefähr ein Kern, 40 MB Speicher. Den Dauerbetrieb misst der Build nicht. Die Übersicht zeigt ihn im laufenden
Betrieb unter „AETHER selbst“ live an.

## 4. Im Build gefunden und behoben (ehrlich protokolliert)

| Lauf | Befund | Ursache | Behebung |
|---|---|---|---|
| 0.2.0 | Absturz auf dem virtuellen Intel-Mac | `MTLCopyAllDevices()` bzw. Shader-Effekte (Canvas, `numericText`, `AngularGradient`) → Metal-Assertion „Target device architecture is nil“ | GPU-Liste aus `system_profiler`, einfache Formen statt Shader-Effekten |
| 8 | Intel-Rechner zeigte Temperaturen (z. B. 81,6 °C) und einen Lüfter mit 0 U/min | der Hypervisor bildet ein SMC nach | SMC-Werte auf virtuellen Macs nicht anzeigen („Virtueller Mac ohne physische Sensoren“); der Lesepfad wird im Selbsttest trotzdem geprüft |
| 10 | Build-Aufträge starteten nicht | GitHub-Abrechnung (privates Repository) | Repository öffentlich gestellt (Entscheidung des Nutzers) |
| 11 | Selbsttest der installierten App auf Intel hing 180 s | nach den Abstürzen der Fotoläufe fragte macOS beim Start, ob die Fenster wieder geöffnet werden sollen | automatische Läufe starten mit `-ApplePersistenceIgnoreState YES` |
| 11 | Deutsche Beschriftungen in der Übersicht abgeschnitten | „Zwischenspeicher“, „verfügbar inkl. … löschbar“ | „Cache“, „inkl. … löschbar“ |
| 12/13 | Fotos auf dem virtuellen Intel-Mac: Absturz bei allen **hellen** Szenarien | siehe Abschnitt 5 | nicht in AETHER behebbar; dokumentiert |

Die Durchsicht vor dem ersten Kompilieren fand einen wahrscheinlichen Fehler: Eine veränderliche Variable wurde in
einem nebenläufigen Block eingefangen. Behoben in `5e9214f`. Danach kompilierte der Code von Phase 6–9 im ersten
Durchlauf.

## 5. Offene Punkte

- **Virtueller Intel-Mac ohne echtes Grafikgerät, helles Erscheinungsbild:** Jedes Fenster im hellen Erscheinungsbild
  bricht dort mit „Target device architecture is nil“ ab. Ein Diagnoselauf (Lauf 13, `AETHER_SNAPSHOT_PROBE`) hat
  das eingegrenzt. Es betrifft auch ein **leeres** Fenster (`Color.clear`), einfachen Text und jedes andere Element
  für sich. Alle dunklen Varianten laufen.
  - Ursache ist also die Darstellung des Fensters durch macOS auf diesem Grafikgerät (`Apple Paravirtualized
    Graphics Device`), nicht ein Element von AETHER.
  - Echte Intel-Macs haben ein Grafikgerät mit Metal-Architektur; ob dort alles läuft, ist ohne physischen Intel-Mac
    aber nicht geprüft.
  - Der Selbsttest (dunkel) und alle dunklen Fotos laufen auf demselben Rechner fehlerfrei.
- **Physische Hardware:** Alle Rechner waren virtuelle Macs. Nicht geprüft sind deshalb echte Akkuwerte, SMC-Sensoren
  und Lüfter, NVMe-SMART, WLAN-Details, die GPU-Treiberauslastung und die Darstellung auf einem Retina-Display.
- **macOS 13 und 14:** GitHub bietet dafür keine Rechner mehr an. Die Mindestversion 13.0 ist im Binary gesetzt und
  geprüft, alle verwendeten Schnittstellen sind für macOS 13 freigegeben. Ein Start auf 13/14 ist nicht getestet.
- **Notarisierung:** nicht möglich ohne Apple-Developer-Zugangsdaten. Der Weg ist vorbereitet
  (`scripts/notarize.sh`, GitHub-Secrets).
