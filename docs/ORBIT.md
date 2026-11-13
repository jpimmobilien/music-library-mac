# ORBIT 2.0 – „Spatial Liquid Glass“ (macOS)

Mit Version 2.0 heißt die App **ORBIT** (vorher AETHER) und bekommt das Designsystem *Spatial Liquid Glass*.
Grundlage ist der Auftrag „ORBIT – Master Prompt – The Ultimate Visual Experience Upgrade“. Die Android-App
(ORBIT Android 0.4.0) nutzt dieselben Grundfarben, Effektprofile und Regeln.

## 1. Umbenennung und Symbol

| | vorher | jetzt |
|---|---|---|
| App | AETHER.app | **ORBIT.app** (Programmdatei `ORBIT`) |
| DMG | AETHER-macOS-Universal.dmg | **ORBIT-macOS-Universal.dmg** (Volume „ORBIT“, neuer Hintergrund) |
| Xcode | AETHER.xcodeproj, Ziel „AETHER-App“ | **ORBIT.xcodeproj**, Ziel und Schema „ORBIT“ |
| Symbol | Glaslinse über Ring | **Vorlage des Auftraggebers** (blauer Verlauf, Chip mit „i“) |
| Bundle-ID | `de.projectaether.macos` | **unverändert** – Einstellungen bleiben erhalten |
| Verlauf | `~/Library/Application Support/AETHER` | `…/ORBIT` – der alte Ordner wird beim ersten Start einmalig **umbenannt** (nicht kopiert, nichts gelöscht); schlägt das fehl, bleibt ORBIT beim alten Ordner |

Das Symbol wird reproduzierbar aus `Resources/OrbitIconSource.png` erzeugt (`tools/art/make_orbit_icon.py`): Form aus
der Farbsättigung freigestellt (vierfach überabgetastet, weiße Chipfläche als Loch gefüllt), nach Apples Raster
gesetzt (1024er Fläche, Körper 824 pt ab Punkt 100, weicher Schatten), danach Iconset und `.icns`. Die Grafik selbst
bleibt unverändert. Interne Modulnamen (`AetherCore`, `AetherSystem`, Swift-Produkt `AETHER`) bleiben – eine
Umbenennung hätte nur Risiko und keinen Nutzen (Regel „keine unnötigen Architekturänderungen“).

## 2. Designsystem

**Grundfarben** (`OrbitPalette` in AetherCore, identisch mit Android): Arctic Blue `#3D8BFF`, Electric Cyan
`#18D6F0`, Deep Ocean `#07142B`, Sapphire `#2446C8`, Soft Violet `#8C7CFF`, Pearl White `#F4F7FB`, Graphite `#2B2F38`.

**Bedeutung:** Blau = System (CPU), Cyan = Datenströme (Netzwerk, Dateivorgänge), Violett = Auswertungen/Speicher,
Grün = positiver Zustand, Orange = erhöhte Werte, Rot nur für kritische Zustände. Farbe ist nie alleiniger Träger:
Zahlen, Beschriftungen und Symbole stehen immer dabei.

**Themes:** Liquid Glass Dunkel = „Deep Ocean“, Liquid Glass Hell = „Pearl White“, dazu unverändert Minimal Dunkel,
Minimal Hell, Graphit und System. Lesbarkeit aller Textrollen ist unit-getestet (WCAG, `testAllThemesHaveReadableText`).
Neuer Akzent **Electric Cyan**; der Standardakzent heißt jetzt **Arctic Blue**.

**Materialebenen:** Hintergrund (Verlauf) → Ambient (Lichtfelder) → Glasfläche (Karten, Seitenleiste) → interaktive
Fläche (Reflexion, Hervorhebung) → Information (Text, Werte, Diagramme).

## 3. Effektprofile

Einstellungen → Darstellung → **Effekte**: *Minimal* · *Ausgewogen* (Standard) · *Immersiv*. Vorrang:
Systemeinstellung „Bewegung reduzieren“ > Einstellung „Animationen“ (voll/reduziert/aus) > Effektprofil
(`OrbitEffects.resolve`, unit-getestet).

| Effekt | Minimal | Ausgewogen | Immersiv | Technik |
|---|---|---|---|---|
| Auftakt beim Start (≈ 0,9 s, über fertigem Inhalt, keine Eingabesperre) | – | ✓ | ✓ | SwiftUI, einmal pro Start |
| Lichtfelder im Hintergrund | – | ✓ ruhend | ✓ | Core Animation (`CAGradientLayer`, radial) |
| Lichtfelder gleiten beim Bereichswechsel (1,4 s) | – | ✓ | ✓ | CA-Transaktion |
| Sehr langsame Drift der Lichtfelder (Umlauf 52–70 s) | – | – | ✓ | CA-Keyframe, `preferredFrameRateRange` ≤ 12 Bilder/s |
| Glasreflexion unter dem Zeiger, Lichtkante | – | ✓ | ✓ | eigene Ebene, beobachtet nur die Zeigerposition |
| Magnetisches Schweben (≤ 2,5 pt) | – | – | ✓ | nur Module, Kacheln, klickbare Karten |
| Räumliche Übergänge zwischen Bereichen | – | ✓ | ✓ | Skalierung + Tiefe statt nur Überblendung |
| Verwandelbare Karten (ORBIT Core → Detail) | ✓* | ✓ | ✓ | dieselbe Fläche wächst (Feder) |
| Rollende Zahlen (große Kennzahlen) | – | – | ✓ | Übergang nur bei geänderter Anzeige |
| Datenfluss, Ladefluss, Fortschrittsschimmer | ✓* | ✓ | ✓ | nur bei **echter** Aktivität |

\* nur ohne „Bewegung reduzieren“. Mit „Bewegung reduzieren“ entfällt jede Bewegung; der Auftakt wird zur 0,2-s-Überblendung.

## 4. Visualisierungen aus echten Daten

- **ORBIT Core** (Übersicht): Kern mit sechs Bahnen – CPU, GPU, Arbeitsspeicher, Massenspeicher (Startvolume),
  Netzwerk, Akku. Jeder Bogen ist ein gemessener Anteil aus der Telemetrie (Monitoring 2.0), auf 0,5 % gerastert,
  Bewegung nur bei sichtbarer Änderung. Das Netzwerk hat keinen festen Höchstwert: sein Bogen ist **ausdrücklich
  bezogen auf die Spitze der letzten 5 Minuten** (Untergrenze 64 kB/s, `RollingPeak`, unit-getestet). Fehlt ein Wert
  (kein Akku, GPU-Auslastung vom Treiber nicht gemeldet, zweite Messung steht aus), bleibt die Bahn gestrichelt leer
  und die Legende sagt warum. Der Lichtpunkt auf der Netzwerkbahn kreist nur, solange Daten fließen; seine
  Geschwindigkeit folgt dem Durchsatz (phasentreu umgestellt). Ein Klick auf eine Zeile verwandelt sie in eine
  Detailkarte (Verlauf 5 min bzw. Belegung, Grundlage des Bogens, Sprung in den Bereich).
- **Datenfluss** (Netzwerk, Übersicht): unverändert aus Studio 1.1 – Teilchenstrom nach Durchsatz, jetzt in Cyan.
- **Akku-Flüssigkeit:** In der Akku-Zelle läuft ein Lichtfluss nur, solange macOS „lädt“ meldet.
- **Arbeitsspeicher-Schichten**, **Wärmekarte**, **Live-Diagramme** (Rohwert und geglättet unterscheidbar,
  Lücken überbrückt statt Sprünge): aus Studio 1.1/1.2, in den ORBIT-Farben.
- **Statusrückmeldung:** Ändert sich ein Statuspunkt (z. B. Systemzustand der Übersicht), läuft einmal ein Ring nach
  außen – kein Dauerpulsieren.

## 5. Dateien

Kopieren/Bewegen zeigen einen **flüssigen Fortschrittsbalken** (Füllung = echter Fortschritt in Bytes bzw. Objekten,
Schimmer nur während der Vorgang arbeitet). Die Erfolgsmeldung erscheint erst im Abschluss-Handler des Vorgangs –
dann springt das Bestätigungssymbol kurz auf. Leere und fehlerhafte Ordner zeigen eine eigene Illustration
(ORBIT-Zeichen mit Symbol) statt eines grauen Symbols.

## 6. Leistung

Regeln: Dauerbewegung nur über Core Animation und gedrosselt; Zeigerverfolgung zeichnet nur die Reflexionsebene neu;
keine Canvas-/Metal-/`drawingGroup`-Effekte (Intel-VMs ohne Metal-Gerät); App-Szene beobachtet keine häufig
veröffentlichenden Objekte (Lehre aus 1.1). Der Selbsttest misst die eigene CPU-Last der Übersicht zusätzlich mit den
Profilen *Immersiv* und *Minimal* (`overview-immersive`, `overview-minimal`) – Ergebnisse in
[BUILD_UND_TESTS.md](BUILD_UND_TESTS.md).
