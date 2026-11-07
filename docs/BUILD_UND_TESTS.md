# Build- und Testergebnis

AETHER 0.2.0 · Stand 7. November 2026 · Release-Build: Lauf 4 (GitHub-Lauf 42384028279) (`3ae5b9f`)

Gebaut und geprüft wurde auf **echten macOS-Rechnern** von GitHub Actions, Workflow
[`aether-macos.yml`](../.github/workflows/aether-macos.yml), Zweig `aether-macos`. Alle Protokolle, Selbsttests,
Bildschirmfotos und die DMG liegen im Zweig `ci-ergebnisse-aether-macos`.

## 1. Ergebnis

| Prüfung | Ergebnis |
|---|---|
| Datei | `AETHER-macOS-Universal.dmg` · 5 567 247 Bytes (5,3 MB) · SHA-256 `f96700c5a4f932723076cba163be8810f29d2ca8d68c8dc27222b5547bb3b085` |
| Architekturen (`lipo -archs`) | `x86_64 arm64` – beide nativ, kein Rosetta-Zwang |
| Mindest-macOS je Architektur | 13.0 (arm64 und x86_64) |
| SDK / Compiler | macOS SDK 26.5, Xcode 26.6, Swift 6.3.3 |
| Signatur | ad-hoc (`flags=0x2`), keine Developer-ID hinterlegt → **nicht notarisiert** |
| Verknüpfte Bibliotheken | nur `/System/Library` und `/usr/lib` |
| Netzwerk-APIs in der Programmdatei | keine (geprüft mit `nm -u`) |

## 2. Ausgeführte Schritte (§3.3 des Auftrags)

| # | Schritt | Wo | Ergebnis |
|---|---|---|---|
| 1 | Clean Build (`rm -rf .build build`) | macOS 26 (Apple Silicon) und macOS 15 (Intel) | ✓ |
| 2 | Universal-Build arm64 + x86_64 (`swift build --triple …`, `lipo -create`) | beide | ✓ |
| 3 | Prüfung der Architekturen (`lipo -archs`, `-verify_arch arm64 x86_64`, `otool` minos/sdk) | beide | ✓ |
| 4 | App-Bundle-Struktur (`Contents/MacOS`, `Info.plist`, `PkgInfo`, `Resources`) | beide | ✓ |
| 5 | Ressourcenprüfung (`plutil -lint`, Icon, en/de.lproj, Lokalisierungsabgleich, nur Systembibliotheken, keine Netzwerk-APIs) | beide | ✓ |
| 6 | DMG erstellen (`dmgbuild`, UDZO, Hintergrund 1×/2×, Volume-Symbol, Link „Programme“) | beide | ✓ |
| 7 | Mount-Test (`hdiutil verify`, `attach`, Inhalt, Link, Architekturen, `codesign --verify --deep --strict`, Byte-Vergleich mit dem Build) | beide | ✓ |
| 8 | Prüfung der enthaltenen App: aus der DMG installiert und gestartet (Selbsttest) | macOS 26 nativ (arm64), macOS 26 über Rosetta (x86_64), macOS 15 Intel (x86_64) | ✓ |
| 9 | Unabhängige Prüfung der fertigen DMG ohne macOS (eigene Decoder für UDIF, HFS+, Mach-O: `tools/dmg_inspect/verify.py`) | Arbeitsumgebung | ✓ |

## 3. Tests

**Unit-Tests (AetherCore, 44 Tests):** Linux (x86_64), macOS 26 (arm64), macOS 15 Intel (x86_64) – alle bestanden.
Geprüft werden unter anderem:

- CPU-Auslastung aus Zählerständen, inklusive 32-Bit-Überlauf und „keine verstrichenen Ticks → kein Wert“;
- Speicheraufteilung wie die Aktivitätsanzeige;
- Raten mit Zählerrücksetzung;
- Puls-Regeln mit Haltezeiten, keine Warnung aus fehlenden Werten;
- Formatierung Deutsch/Englisch;
- WCAG-Kontraste aller 6 Themes und Akzentfarben;
- Parser für `system_profiler` (Hardware, Grafik), auch mit „Unknown“ und kaputten Daten;
- Batterie-Mathematik (Plausibilität, vorzeichenbehafteter Strom);
- Volumes mit löschbarem Platz;
- Übersichtslayout aus beschädigten gespeicherten Werten.

**Selbsttest der fertigen App (echte Messwerte des jeweiligen Rechners):**

- CPU gesamt (Summe = 100 %);
- Kernzahl = logische CPUs;
- Speicheraufteilung plausibel;
- Speicherdruck;
- Swap;
- Startvolume;
- SSD-Aktivität;
- Netzraten;
- Thermalstatus;
- Batterie: vorhanden oder sauber „kein Akku“ ohne Ersatzwerte;
- GPU-Liste;
- GPU-Auslastung: Wert oder Grund;
- Modell, Prozessor, Architektur, Rosetta-Erkennung;
- Lokalisierung en/de;
- sichtbares Fenster.

| Rechner | Prozess | Ergebnis |
|---|---|---|
| macOS 26.7 · Apple Silicon (virtuell, „Apple M2 Pro“) | arm64 nativ | ✓ 18/18 Prüfungen |
| macOS 26.7 · Apple Silicon | x86_64 über Rosetta | ✓ 18/18 – Rosetta korrekt erkannt, echte Hardware (Apple Silicon) gemeldet |
| macOS 15.7 · Intel (virtuell) | x86_64 nativ | ✓ 18/18 |
| macOS 15.7 · Intel – Installation der macOS-26-DMG wie ein Nutzer | x86_64 | ✓ 18/18 |

**Bildschirmfotos:**

- alle 6 Themes, kompaktes und ausführliches Layout, Anpassen-Modus, Einstellungen, Bereich in Arbeit, Glasintensität 0;
- macOS 26 mit nativem Liquid Glass und mit erzwungenem Rückfall;
- macOS 15 Intel (Rückfall);
- Englisch und Deutsch.

Siehe `ci-ergebnisse-aether-macos/logs-build-*/snapshots/`. Die Build-Rechner haben „Transparenz reduzieren“
eingeschaltet. Im Fotomodus wird das ignoriert, damit das Glasdesign sichtbar ist; im normalen Betrieb gilt die
Systemeinstellung.

**Eigenverbrauch** (Selbsttest, Sekundentakt, direkt nach dem Start einschließlich `system_profiler`): 4–8 % eines
Kerns, 30–40 MB Speicher. Im normalen Betrieb (2 s) liegt er niedriger; die Optimierung und eine Messung im
Dauerbetrieb sind Teil von Phase 8.

**Bemerkenswert aus den Messungen:** `/bin/ps` ist auf macOS 26 und 15 mit Systemrechten installiert (`-rwsr-xr-x
root`). Die in Phase 4 geplante Prozessliste mit CPU- und Speicherwerten auch für Systemprozesse ist damit ohne
Administratorrechte machbar.

## 4. Im Build gefunden und behoben (ehrlich protokolliert)

| Lauf | Befund | Ursache | Behebung |
|---|---|---|---|
| 1 | Selbsttest auf macOS 15 Intel: Absturz (`SIGABRT`) | `MTLCopyAllDevices()` → Metal-Assertion „Target device architecture is nil“ auf dem virtuellen Intel-Mac | GPU-Liste aus `system_profiler SPDisplaysDataType` (eigener Prozess) statt Metal |
| 1 | Bildschirmfotos fehlten | Ausblenden des Hauptfensters beendete die App („nach letztem Fenster beenden“) | gilt nur noch im normalen Betrieb |
| 2 | Absturz auf Intel bestand weiter | SwiftUI-Effekte, die Metal-Shader laden (Canvas, Zahlenübergang `numericText`, `AngularGradient`) | durch einfache Formen und Verläufe ersetzt |
| 3 | Fotos zeigten kein Glas | Build-Rechner haben „Transparenz reduzieren“ an (AETHER folgt dem korrekt) | im Fotomodus ignoriert und vermerkt; Einstellungen nennen den Grund |
| 3 | „Chip: Unknown“ auf dem Intel-Rechner | `system_profiler` meldet dort „Unknown“ | wird ignoriert, die Kernelangabe gilt; virtuelle Macs über `kern.hv_vmm_present` erkannt |
| 3 | Fotos alle gleich groß | Fenster wurden auf den kleinen virtuellen Bildschirm begrenzt | Fotofenster werden nicht mehr begrenzt; Manifest nennt die tatsächliche Größe |

## 5. Nicht durchgeführt

- **Physische Hardware:** Alle Rechner waren virtuelle Macs (Apple Silicon und Intel). Nicht geprüft sind deshalb
  echte Akkuwerte, SMC-Sensoren (noch nicht umgesetzt, Phase 5), Lüfter, die GPU-Treiberauslastung auf echter
  Hardware sowie die Darstellung auf einem echten Retina-Display.
- **macOS 13 und 14:** GitHub bietet dafür keine Rechner mehr an. Mindestversion 13.0 ist im Binary gesetzt und
  geprüft; ein Start auf 13/14 ist nicht getestet.
- **Notarisierung:** nicht möglich ohne Apple-Developer-Zugangsdaten. Der Weg ist vorbereitet (`scripts/notarize.sh`,
  GitHub-Secrets).
- **Xcode-Projektdatei:** Das Swift-Paket öffnet sich direkt in Xcode. Eine `.xcodeproj` folgt in Phase 9.
