# Build- und Testergebnis

AETHER 1.1.0 („Studio“ und Monitoring 2.0) · Stand 8. November 2026 · Release-Build: Lauf 18 (GitHub-Lauf 42497645629) (`95b30f2`)

Vorversion 1.0.0: Lauf 13 (`70cb4a6`), DMG-SHA-256 `189c9750aca9cc30da9f1b9417a9d69da5b9c9e833014d2abc31fb12bec47a5a` – bis zum erfolgreichen
Build von 1.1.0 unverändert gelassen und danach gesichert.

Gebaut und geprüft wurde auf **echten macOS-Rechnern** von GitHub Actions, Workflow
[`aether-macos.yml`](../.github/workflows/aether-macos.yml), Zweig `aether-macos`. Alle Protokolle, Selbsttests,
Bildschirmfotos, Absturzberichte und die DMG liegen im Zweig `ci-ergebnisse-aether-macos`.

## 1. Ergebnis

| Prüfung | Ergebnis |
|---|---|
| Datei | `AETHER-macOS-Universal.dmg` · 11 268 068 Bytes (10,7 MB) · SHA-256 `dc42254809329c57494be71ebce06f43d62fe78c6973dec54cfc63f6ad32e223` |
| Version | 1.1.0 (Build 18), `de.projectaether.macos` |
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
| 5 | Unit-Tests | Linux, macOS 26, macOS 15 Intel | ✓ 127/127 |
| 6 | Selbsttest der gebauten App mit echten Messwerten, inkl. Leistungsmessung je Bereich | beide | ✓ 34/34 |
| 7 | DMG erstellen (`dmgbuild`) und Mount-Test (`hdiutil verify/attach`, Inhalt, Link, Architekturen, `codesign --verify --deep --strict`, Byte-Vergleich) | beide | ✓ |
| 8 | Aus der DMG installieren und starten (Selbsttest) | macOS 26 nativ, macOS 26 über Rosetta, macOS 15 Intel | ✓ 34/34 |
| 9 | Fertige DMG auf einem zweiten Intel-Mac wie ein Nutzer installieren und starten | macOS 15 Intel | ✓ 34/34 |
| 10 | Xcode-Projekt erzeugen und universal bauen | macOS 26 | ✓ |
| 11 | Unabhängige Prüfung der fertigen DMG ohne macOS (eigene Decoder für UDIF, HFS+, Mach-O: `tools/dmg_inspect/verify.py`) | Arbeitsumgebung | ✓ |

## 3. Tests

**Unit-Tests (AetherCore, 127 Tests)** – Linux (x86_64), macOS 26 (arm64), macOS 15 Intel (x86_64), alle bestanden.
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
- Formatierung Deutsch/Englisch und WCAG-Kontraste aller Themes;
- Monitoring 2.0: zeitabhängige Glättung (`alpha = 1 − exp(−Δt/τ)`, unabhängig vom Takt), schneller Anstieg/langsamer
  Abfall, Spitzenfenster 10 s, Anzeigeraster, Ringpuffer mit Überlauf, Min/Max-Bündelung ohne Verlust von Spitzen,
  Überbrückung seltener Messungen und echte Lücken, „schöne“ Achsenobergrenzen, routbare Adressen (T2-Brücke).

**Selbsttest der fertigen App** (34 Prüfungen, echte Messwerte des jeweiligen Rechners). Nicht verfügbare Werte
bestehen nur, wenn sie mit Grund gemeldet werden – erfundene Ersatzwerte würden die Prüfung scheitern lassen.

- CPU, Kerne, Speicheraufteilung, Druck, Swap;
- Startvolume, SSD-Aktivität, Verschlüsselungsangabe, NVMe-SMART;
- Netzraten, Schnittstellen, Verbindungen (inkl. Prozessspalte), WLAN;
- Thermalstatus, SMC-Sensoren und -Lüfter, SMC-Lesepfad;
- Batterie;
- Verlauf: Datenbank im Testordner schreiben, lesen und löschen; Standard „aus“;
- Systembericht ohne Seriennummer;
- GPU, Modell, Prozessor, Architektur/Rosetta;
- Lokalisierung en/de, sichtbares Fenster;
- Monitoring 2.0: geglätteter und roher CPU-Wert im gültigen Bereich, Verlauf vorhanden, Last je Kern für alle
  logischen Kerne, Netz- und Speicherwerte verfügbar;
- **Leistung:** CPU-Zeit des eigenen Prozesses im Dauerbetrieb (Grundtakt 1 s) je Bereich, Grenze 50 % eines Kerns
  für die Übersicht.

| Rechner | Prozess | Ergebnis |
|---|---|---|
| macOS 26.7 · Apple Silicon (virtuell) – gebaut | arm64 nativ | ✓ 34/34 |
| macOS 26.7 · Apple Silicon – aus der DMG installiert | arm64 nativ | ✓ 34/34 |
| macOS 26.7 · Apple Silicon – aus der DMG installiert | x86_64 über Rosetta | ✓ 34/34 |
| macOS 15.7 · Intel (virtuell) – gebaut | x86_64 nativ | ✓ 34/34 |
| macOS 15.7 · Intel – aus der DMG installiert | x86_64 nativ | ✓ 34/34 |
| macOS 15.7 · Intel, zweiter Rechner – macOS-26-DMG wie ein Nutzer installiert | x86_64 nativ | ✓ 34/34 |

**Bemerkenswert aus den Messungen:**

- Die Verbindungsliste nennt auf macOS 26 und 15 zu jedem Socket den Prozess (`netstat -anv`, ohne
  Administratorrechte).
- Auf dem virtuellen Intel-Rechner ließ sich das (nachgebildete) SMC öffnen: 653 Schlüssel, 28 Temperaturschlüssel,
  1 Lüfter. Damit ist der Lesepfad in C geprüft. Angezeigt werden diese Werte auf virtuellen Macs bewusst nicht, weil
  sie keine Messungen echter Hardware sind.
- NVMe-SMART: Die SDK-Schnittstelle ist vorhanden. Virtuelle Macs liefern keine Daten, deshalb steht dort „nicht
  verfügbar“ mit Grund.

**Bildschirmfotos** – macOS 26 mit Liquid Glass, mit erzwungenem Rückfall und auf Deutsch: je 28 Bilder (neu: ganze
Übersicht in hohem Fenster, Rohwerte, Diagnose-Anzeige), alle Bereiche
einschließlich Speicher, Dateien, Netzwerk und Live-Monitor. Die Build-Rechner haben „Transparenz reduzieren“ an; im
Fotomodus wird das ignoriert, damit das Glasdesign sichtbar ist.

**Eigenverbrauch im Dauerbetrieb** (Selbsttest, Grundtakt 1 s, Fenster sichtbar, je Bereich 8 s; Anteil eines
CPU-Kerns, alle Threads des Prozesses):

| Rechner | Übersicht | Einstellungen | Arbeitsspeicher | Netzwerk | CPU & GPU¹ | Aktivität¹ |
|---|---|---|---|---|---|---|
| macOS 26 · Apple Silicon (gebaut) | 3,4 % | 2,5 % | 3,6 % | 3,6 % | 8,0 % | 7,8 % |
| macOS 26 · Apple Silicon (aus DMG) | 3,0 % | 2,1 % | 2,7 % | 3,2 % | 5,4 % | 4,4 % |
| macOS 26 · über Rosetta (aus DMG) | 6,4 % | 3,4 % | 5,5 % | 4,5 % | 10,1 % | 10,1 % |
| macOS 15 · Intel (gebaut) | 5,3 % | 1,0 % | 4,4 % | 2,2 % | 9,6 % | 17,9 % |
| macOS 15 · Intel (aus DMG) | 5,9 % | 1,2 % | 5,8 % | 3,5 % | 12,4 % | 21,4 % |
| macOS 15 · Intel, zweiter Rechner | 4,9 % | 1,5 % | 10,6 % | 13,5 % | 23,3 % | 32,5 % |

¹ Diese Bereiche messen zusätzlich alle Prozesse (alle 2 s, `libproc` und `/bin/ps`) und zeichnen die Prozesstabelle.
Die virtuellen Intel-Rechner haben kein Grafikgerät mit Metal; dort zeichnet macOS in Software.

Vor der Korrektur (Lauf 16, gleicher Rechner) lag jeder Bereich bei 93–101 % eines Kerns – Ursache und Lösung in
[DESIGN_STUDIO.md, Abschnitt 4](DESIGN_STUDIO.md). Arbeitsspeicher von AETHER: 65–86 MB.

## 4. Im Build gefunden und behoben (ehrlich protokolliert)

| Lauf | Befund | Ursache | Behebung |
|---|---|---|---|
| 0.2.0 | Absturz auf dem virtuellen Intel-Mac | `MTLCopyAllDevices()` bzw. Shader-Effekte (Canvas, `numericText`, `AngularGradient`) → Metal-Assertion „Target device architecture is nil“ | GPU-Liste aus `system_profiler`, einfache Formen statt Shader-Effekten |
| 8 | Intel-Rechner zeigte Temperaturen (z. B. 81,6 °C) und einen Lüfter mit 0 U/min | der Hypervisor bildet ein SMC nach | SMC-Werte auf virtuellen Macs nicht anzeigen („Virtueller Mac ohne physische Sensoren“); der Lesepfad wird im Selbsttest trotzdem geprüft |
| 10 | Build-Aufträge starteten nicht | GitHub-Abrechnung (privates Repository) | Repository öffentlich gestellt (Entscheidung des Nutzers) |
| 11 | Selbsttest der installierten App auf Intel hing 180 s | nach den Abstürzen der Fotoläufe fragte macOS beim Start, ob die Fenster wieder geöffnet werden sollen | automatische Läufe starten mit `-ApplePersistenceIgnoreState YES` |
| 11 | Deutsche Beschriftungen in der Übersicht abgeschnitten | „Zwischenspeicher“, „verfügbar inkl. … löschbar“ | „Cache“, „inkl. … löschbar“ |
| 12/13 | Fotos auf dem virtuellen Intel-Mac: Absturz bei allen **hellen** Szenarien | siehe Abschnitt 5 | nicht in AETHER behebbar; dokumentiert |
| 14 (1.1) | Neue Leistungsprüfung im Selbsttest schlägt fehl: 99,6 % eines Kerns auf der Übersicht | siehe Lauf 16 | Messung je Bereich und Profil ergänzt |
| 16 (1.1) | Alle Bereiche 93–101 %, auch Einstellungen und Übersicht ohne Bewegung; Messmaschine nur 3,8 ms je Takt | Profil: `MenuBarExtra`-Beschriftung ändert sich jede Sekunde → SwiftUI wertet jedes Fenster komplett neu aus; segmentierte Picker vermessen sich bei jedem Layout | Menüleiste als AppKit-Statusobjekt, Zeitraumwahl in reinem SwiftUI → 2–8 % (Lauf 17) |
| 16 (1.1) | Fotos: Kernsäulen bei 3 Kernen als „Kugeln“, Zeitraumwahl auf der Temperaturseite ohne Verlauf, abgeschnittene Beschriftung im Speicher-Modul | Säulenbreite nur durch Fensterbreite begrenzt | Säulen höchstens 18 pt, mittig; Auswahl nur mit Verlauf; Beschriftung = Volumename |

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
  und Lüfter, NVMe-SMART, WLAN-Details, die GPU-Treiberauslastung und die Darstellung auf einem Retina-Display –
  und damit auch die neuen Visualisierungen Batteriezelle (mit Laden), Wärmekarte mit Sensorpunkten und Lüfterwerte.
  Diese sind an echte Messwerte gebunden; auf den Build-Rechnern erscheinen sie ehrlich als „nicht vorhanden“ bzw.
  „nicht verfügbar“.
- **macOS 13 und 14:** GitHub bietet dafür keine Rechner mehr an. Die Mindestversion 13.0 ist im Binary gesetzt und
  geprüft, alle verwendeten Schnittstellen sind für macOS 13 freigegeben. Ein Start auf 13/14 ist nicht getestet.
- **Notarisierung:** nicht möglich ohne Apple-Developer-Zugangsdaten. Der Weg ist vorbereitet
  (`scripts/notarize.sh`, GitHub-Secrets).
