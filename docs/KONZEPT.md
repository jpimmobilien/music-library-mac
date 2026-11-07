# PROJECT AETHER – macOS Edition · Produkt- und Machbarkeitskonzept

*System Intelligence & File Explorer* · Phase 1 · Stand 7. November 2026

Dieses Konzept führt zwei Perspektiven zusammen:

- **Rolle A – Design:** wie Apple die App als neue Systemanwendung gestalten würde.
- **Rolle B – Systemtechnik:** was macOS einer Drittanbieter-App auf Intel und Apple Silicon wirklich preisgibt.

Wo sich beide widersprechen, gewinnt die Ehrlichkeit der Daten. Eine schöne Anzeige für einen Wert, den es nicht
gibt, ist ein Fehler.

Ausgewertet wurden vorab die vorhandenen Projekte: *Music Library* und *Android Bridge* (beide DMGs, das Repository
`music-library-mac`, der Zweig `android-bridge`). Übernommen werden der bewährte Build-Weg (SwiftPM, Universal-Build
per `lipo`, ad-hoc-Signatur, `dmgbuild`, Prüfung auf echten macOS-Rechnern von GitHub), die Liquid-Glass-Technik mit
Rückfall für macOS 13–15 sowie Selbsttest und Bildschirmfotos im Build.

---

## 1 · Produktvision

> **Ein Ort, an dem man seinen Mac versteht – und jeder Zahl trauen kann.**

Die Aktivitätsanzeige zeigt Tabellen, die Systeminformationen zeigen Listen, der Finder zeigt Dateien. Keines der drei
sagt, *wie es dem Mac geht*. AETHER beantwortet diese Frage in einem Satz und lässt jede Antwort bis zum Messwert und
seiner Quelle zurückverfolgen.

### Drei Leitideen

1. **Ruhe zuerst.** Die Übersicht beginnt mit einem Satz („Dein Mac arbeitet ruhig.“), nicht mit 40 Zahlen. Details
   öffnen sich dort, wo man hinsieht. Warnfarben erscheinen nur, wenn ein Messwert sie begründet.
2. **Herkunft jeder Zahl.** Jeder Wert trägt eine Herkunftsangabe. Ein Klick auf das kleine Herkunftssymbol zeigt
   Quelle, Art und Zeitpunkt: *gemessen*, *berechnet*, *Systemangabe*, *Schätzung* oder *nicht verfügbar*, jeweils mit
   Begründung. Das ist das Markenzeichen von AETHER. Es setzt die Regel „keine erfundenen Werte“ so um, dass man sie
   sehen kann.
3. **Ein Werkzeug, keine Last.** AETHER misst nur, was gerade jemand ansieht oder was der Verlauf aufzeichnen soll. Im
   Hintergrund und im Sparmodus ruhen die Messungen.

### Was AETHER zusätzlich mitbringt

| Idee | Nutzen |
|---|---|
| **Puls** – Systemstatus als Satz mit Belegen | „Arbeitsspeicher stark beansprucht“, darunter die Belege (Speicherdruck *Warnung*, Swap 6,2 GB). Ein Klick zeigt die Regel, die gegriffen hat. |
| **Herkunftsangaben** an jedem Wert | Unterscheidet Messung, Berechnung und Schätzung – auch für Fachleute nachprüfbar. |
| **App-Familien** in der Aktivität | Hilfsprozesse (Renderer, XPC-Dienste, Helfer) werden unter ihrer App gruppiert und summiert. So sieht man, was *Safari insgesamt* braucht. |
| **Zeitachse** (optionaler lokaler Verlauf) | CPU-, Speicher-, Temperatur- und Netzverläufe auf einer gemeinsamen Achse. Ein Klick auf eine Spitze zeigt, welche Prozesse damals oben lagen. |
| **Live-Monitor-Fenster** | Kleines, frei wählbares Kachelfenster (optional „immer im Vordergrund“). |
| **Menüleisten-Anzeige** (optional, sichtbar) | Kompakte Werte in der Menüleiste. Kein versteckter Hintergrundprozess: Beenden über das Menü. |
| **SSD-Gesundheit** | Verschleiß, Temperatur, geschriebene Datenmenge und Betriebsstunden über die NVMe-SMART-Schnittstelle. |
| **Systembericht** | Export als Markdown/JSON/PDF – die Seriennummer nur, wenn man sie ausdrücklich einschließt. |
| **Befehlspalette** (⌘K) | Bereich, Prozess, Datei oder Einstellung direkt ansteuern. |

---

## 2 · Navigationsstruktur

Ein Fenster mit schwebender Glas-Seitenleiste, ausgeblendeter Titelleiste und Inhalt bis an den Fensterrand.

```
┌──────────────────────┐
│ ● ● ●                │  Ampelknöpfe über der Leiste
│                      │
│  ◉ Overview      ⌘1  │  Übersicht
│                      │
│  LEISTUNG            │
│  ◎ Activity      ⌘2  │  Prozesse, App-Familien
│  ◎ CPU & GPU     ⌘3  │
│  ◎ Memory        ⌘4  │
│                      │
│  HARDWARE & ENERGIE  │
│  ◎ Temperature   ⌘5  │  Temperatur & Lüfter
│  ◎ Battery       ⌘6  │
│  ◎ Hardware      ⌘7  │
│                      │
│  DATEN               │
│  ◎ Storage       ⌘8  │  Volumes, SSD, große Dateien, Duplikate
│  ◎ Files         ⌘9  │  Finder Plus
│  ◎ Network       ⌘0  │
│                      │
│ ──────────────────── │
│  ⚙ Settings      ⌘,  │  unten angeheftet
│  [Mini-Status: CPU · Speicher · °C]
└──────────────────────┘
```

| Element | Verhalten |
|---|---|
| Seitenleiste | 232 pt, einklappbar (⌃⌘S). Auswahl als sanft verschmelzende Glaskapsel, Hover leicht aufgehellt. Am unteren Rand ein Mini-Status mit drei Live-Werten. |
| Kopfbereich jeder Seite | Großer Titel, Untertitel mit Kontext („Apple M3 Pro · 12 Kerne“). Rechts Werkzeuge in einer Glaskapsel: Intervall, Suche, Ansicht, Anpassen. |
| Detailbereiche | Prozessdetails, Dateiinformationen und Sensordetails als Inspektor rechts (⌥⌘I), ab ca. 1 100 pt Breite. Darunter als Blatt. |
| Fenstergrößen | Mindestens 960 × 640 (MacBook Air 13″ mit Dock); bis Vollbild auf 6K. Die Raster passen sich an: 2–5 Kartenspalten. |
| Zusatzfenster | Live-Monitor (⌥⌘M), Systembericht, Quick Look (Leertaste). |
| Menüs | Ablage, Bearbeiten, Darstellung (Bereiche, Dichte, Seitenleiste), Fenster, Hilfe – mit den nativen Kurzbefehlen. |

Lokalisierung: Englische Bereichsnamen wie im Auftrag. Auf Deutsch heißen sie *Übersicht, Aktivität, CPU & GPU,
Arbeitsspeicher, Temperatur & Lüfter, Batterie, Hardware, Speicher, Dateien, Netzwerk, Einstellungen*.

---

## 3 · Dashboard-Konzept (Overview)

```
┌────────────────────────────────────────────────────────────────────────────────────┐
│  MacBook Pro 14″ · Apple M3 Pro · macOS 26.1                         [⟳ 2 s] [✎]   │
│  ● Dein Mac arbeitet ruhig.                                                         │
│    CPU 12 %  ·  Speicherdruck normal  ·  Thermalstatus normal  ·  412 GB frei        │
├───────────────┬───────────────┬───────────────┬───────────────────────────────────┤
│  CPU          │  Arbeitsspeich│  Thermik      │  Batterie                         │
│   ◜ 12 % ◝    │  ◜ normal ◝   │  ◜ 46 °C ◝    │   ◜ 82 % ◝  wird geladen           │
│  User 8 · Sys │  ▇▇▇▅▃░░ 18/36│  SoC, Mittel  │   312 Zyklen · 91 % (berechnet)    │
│  ⌇⌇⌇⌇⌇⌇⌇⌇ 60 s│  Swap 0 B     │  Lüfter 0 U/m │                                   │
├───────────────┴──────┬────────┴───────────────┼───────────────────────────────────┤
│  Netzwerk            │  Speicher               │  GPU                              │
│  ↓ 2,4 MB/s ↑ 180 KB/s│ Macintosh HD ▇▇▇▇░ 59 %│  18 % (Treiberangabe)             │
│  ∿∿∿∿∿∿∿ 60 s        │ SSD ↓ 12 MB/s ↑ 3 MB/s  │  Apple M3 Pro · 18 Kerne          │
├──────────────────────┴─────────────────────────┴───────────────────────────────────┤
│  Top-Prozesse (CPU)                         │  Dieser Mac                           │
│  Xcode  34 %  ·  Safari (7)  9 %  · …       │  Mac15,6 · 36 GB · 1 TB · 2 Displays  │
└────────────────────────────────────────────────────────────────────────────────────┘
```

**Aufbau**

1. **Identitätszeile:** Modell, Chip, macOS-Version, dazu ein Gerätesymbol (SF Symbol passend zur Modellfamilie).
2. **Puls:** ein Satz und vier bis fünf Belegchips. Ein Statuspunkt in Grün, Gelb, Rot oder Grau – Rot nur bei einer
   kritischen Systemmeldung (Speicherdruck *kritisch*, Thermalstatus *kritisch*, Volume fast voll).
3. **Hauptkarten:** CPU-Ring (Benutzer/System zweifarbig), Speicherdruck mit gestapeltem Balken (App, Fest
   zugeordnet, Komprimiert, Zwischenspeicher, Frei), Thermik (heißester verfügbarer Sensorbereich *oder* Thermalstatus,
   wenn es keine Sensoren gibt), Batterie (Ring, Zyklen, berechneter Zustand – oder „Netzbetrieb, kein Akku“ beim
   Mac mini/Studio).
4. **Aktivitätskarten:** Netzwerk (↓/↑ mit 60-s-Kurve), Speicher (Startvolume und externe Laufwerke, SSD-Lese- und
   Schreibrate), GPU (Auslastung laut Grafiktreiber, *falls* vorhanden – sonst Modell und Metal-Familie mit dem
   Hinweis „Auslastung nicht verfügbar“).
5. **Unterer Bereich:** Top-Prozesse als App-Familien sowie „Dieser Mac“ in Kurzform.

**Regeln**

- Jede Karte führt per Klick in ihren Bereich und behält dabei den Kontext. Beispiel: Ein Klick auf einen Top-Prozess
  öffnet die Aktivität mit diesem Prozess ausgewählt.
- **Anpassen (✎):** Karten ein- und ausblenden und per Ziehen umsortieren. Dichte *kompakt*, *standard* oder
  *ausführlich*. Gespeichert wird lokal.
- **Puls-Regeln** stehen in `AetherCore/SystemStatus` (unit-getestet). Schwellen und Haltezeiten verhindern Flackern;
  ein Hinweis erscheint erst, wenn der Zustand mindestens 2 Messungen lang besteht:

| Hinweis | Bedingung (nur echte Messwerte) |
|---|---|
| Hohe CPU-Auslastung | Gesamtauslastung ≥ 85 % über ≥ 10 s |
| Arbeitsspeicher stark beansprucht | Systemmeldung Speicherdruck *Warnung* oder *Kritisch* |
| Hohe Swap-Nutzung | Swap ≥ 25 % des RAM **und** Speicherdruck ≥ *Warnung* |
| Ungewöhnlich hohe Temperatur | Thermalstatus ≥ *ernst* (Systemmeldung). Sensorwerte allein lösen keine Warnung aus – es gibt keine öffentlichen Grenzwerte von Apple. |
| Wenig freier Speicher | Startvolume: verfügbar für wichtige Nutzung < 10 % bzw. < 10 GB |
| Hohe Netzwerkaktivität | ↓ + ↑ ≥ 50 MB/s über ≥ 10 s (nur ein Hinweis, keine Warnfarbe) |
| Akku: Service empfohlen | Zustandsangabe von macOS (nicht der berechnete Wert) |

Keine dieser Regeln „diagnostiziert“ etwas. Sie geben wieder, was das System meldet oder was ein Messwert über eine
Schwelle zeigt – mit der Schwelle im Klartext.

---

## 4 · Designsystem

### 4.1 Material und Tiefe

| Ebene | macOS 26 (Tahoe) | macOS 13–15 (Rückfall) |
|---|---|---|
| Fensterhintergrund | Atmosphäre: sehr weiche, statische Farbinseln (je Theme) | identisch |
| Seitenleiste, Werkzeugkapseln, schwebende Leisten | natives **Liquid Glass** (`glassEffect`, `GlassEffectContainer` für verschmelzende Formen) | `NSVisualEffectView` mit echter Hintergrundunschärfe, Tönung, Lichtkante (Verlauf 0,8 pt) und Glanz |
| Karten | Glas mit stärkerer Tönung (Lesbarkeit der Zahlen) | Tönung, Lichtkante, weicher Schatten |
| Blätter und Popover | System (auf 26 automatisch Liquid Glass) | System |

Das Glas sitzt auf der Navigations- und Werkzeugebene. Inhalte (Diagramme, Tabellen) stehen auf ruhigen, stärker
getönten Flächen. So handhabt es Apple selbst: Glas für Steuerung, nicht für Text. Der Schalter `--force-fallback`
und die Umgebungsvariable `AETHER_FORCE_GLASS_FALLBACK=1` erzwingen den Rückfall auch auf macOS 26, damit beide Wege
im Build fotografiert werden.

### 4.2 Themes

Alle Themes sind vollständige Datensätze (`ThemeSpec`): Hintergrund, Flächen, Glas-Tönung, Kanten, Schatten,
Textstufen, Diagrammpalette, Statusfarben und Erscheinungsbild. Sie färben also nicht nur den Hintergrund.

| Theme | Charakter |
|---|---|
| **Liquid Glass Dark** | Tiefes Nachtblau-Schwarz, Atmosphäre aus Indigo, Petrol und Violett. Glas mit kühler Lichtkante. Signatur-Theme. |
| **Liquid Glass Light** | Perlweiß, Atmosphäre aus Eisblau und Flieder, sehr dezente Schatten, keine überstrahlten Flächen. |
| **Minimal Dark** | Flache, fast schwarze Flächen, Haarlinien statt Glas, keine Atmosphäre. Maximale Datenklarheit, ideal für OLED-artige Ruhe. |
| **Minimal Light** | Papierweiß, Haarlinien, keine Transparenz. |
| **Graphite** | Mittel-dunkles neutrales Grau, entsättigte Diagrammfarben, Akzent Graphit. Für lange Sitzungen. |
| **System (adaptiv)** | Folgt Hell/Dunkel und der Akzentfarbe des Systems. Nutzt Liquid Glass Light/Dark. |

Zusätzlich gibt es:

- **Akzentfarbe:** System, Ätherblau (Standard), Minze, Violett, Orange, Rosa, Graphit.
- **Glasintensität:** Regler 0–100 %. Er steuert Tönung, Unschärfe-Material, Lichtkante und Glanz. Bei 0 % gibt es
  undurchsichtige Flächen. Zusätzlich wird „Transparenz reduzieren“ der Bedienungshilfen beachtet.
- **Bewegung:** voll, reduziert oder aus. Die Systemeinstellung „Bewegung reduzieren“ hat immer Vorrang.
- **Informationsdichte:** kompakt, standard oder ausführlich. Sie beeinflusst Abstände, Kartenhöhe und Zusatzzeilen.

### 4.3 Typografie

Apple würde die **Systemschrift** verwenden: SF Pro, dazu SF Mono für technische Kennungen. Es werden also keine
Schriften mitgeliefert, und das Lizenzthema entfällt.

- Zahlen immer mit `monospacedDigit()`, damit Live-Werte nicht zappeln.
- Einheiten kleiner und sekundär („12 **%**“, „2,4 **MB/s**“).
- Hierarchie: Seitentitel 28/Bold, Kartentitel 13/Semibold in Großbuchstaben-Abstand, Kennzahl 30/Semibold Rounded,
  Fließtext 13, Fußnoten 11.

### 4.4 Raster, Formen, Farbe

- Abstände im 4-pt-Raster, Seitenrand 28 pt.
- Radien: Karte 20, Kapsel 999, Steuerelement 10, Fenster konzentrisch.
- **Semantische Messfarben:** gleich in allen Themes, je Theme in Helligkeit abgestimmt. CPU Benutzer = Cyanblau,
  CPU System = Koralle, GPU = Violett, Arbeitsspeicher = Minze, Speicher/SSD = Bernstein, Netzwerk ↓ = Türkis,
  Netzwerk ↑ = Magenta, Batterie = Grün → Gelb → Rot nach Ladestand.
- **Status:** normal (Grün), erhöht (Bernstein), kritisch (Rot), nicht verfügbar (Grau, gestrichelte Kontur).
- **Herkunftssymbole:**

  | Symbol | Bedeutung |
  |---|---|
  | ● | gemessen |
  | ◐ | berechnet |
  | ◇ | Systemangabe / Herstellerangabe |
  | ○ | Schätzung |
  | ⊘ | nicht verfügbar |

  Die Symbole sind als Formen gestaltet, nicht nur als Farben. Sie bleiben also auch bei Farbfehlsichtigkeit eindeutig.

### 4.5 Bewegung

- Federn (`interpolatingSpring`, Dämpfung ≈ 0,86) für Auswahl, Navigation, Aufklappen.
- Ausklingkurven (0,22 / 1 / 0,36 / 1) für Werte und Diagramme.
- Diagramme animieren **nur** beim Eintreffen neuer Werte (≤ 0,35 s). Es gibt **keine Daueranimationen**.
- Ringe laufen bei Wertänderung weich nach.
- Themewechsel als kurze Überblendung (0,25 s).
- Beim Wechsel des Bereichs blendet der Inhalt mit leichtem Versatz (8 pt) und Unschärfe ein.

### 4.6 Barrierefreiheit

- Für alle Diagramme gibt es `accessibilityLabel` und Werte.
- Kontraste nach WCAG AA werden für alle Themes per Unit-Test geprüft (die Paletten liegen als Daten in AetherCore).
- Vollständig per Tastatur bedienbar.
- VoiceOver liest die Herkunft eines Werts mit („82 Prozent, gemessen“).
- „Kontrast erhöhen“ verstärkt Kanten und Text.

---

## 5 · Funktionsübersicht

Legende:

- **Q** = Quelle
- **H** = Herkunftsart
- ● = gemessen
- ◐ = berechnet
- ◇ = Systemangabe
- ○ = Schätzung

| Bereich | Funktionen |
|---|---|
| **Overview** | Puls, Karten (Abschnitt 3), Anpassen, Live-Monitor-Fenster, Menüleisten-Anzeige (optional). |
| **Activity** | Alle Prozesse mit Name, PID, Benutzer, Zustand, CPU %, Speicher, Threads, Energie (falls vorhanden), Pfad, Startzeit, App, Architektur (nativ/Rosetta). App-Familien. Filter (Alle, Meine, System, Apps, hohe CPU, hoher Speicher), Suche, Sortierung. Detailinspektor. Aktionen: Beenden, Sofort beenden (mit Bestätigung), Im Finder zeigen, App aktivieren. Schutzliste kritischer Prozesse. |
| **CPU & GPU** | Gesamt, Benutzer, System, Leerlauf. Je Kern, gruppiert nach Leistungs- und Effizienzkernen (Apple Silicon) bzw. physischen Kernen und Threads (Intel). Durchschnittslast 1/5/15 min, Verlauf, Spitzen. Taktangaben nur, wo vorhanden (Intel: Nenntakt). GPU: Modell, Kerne, Metal-Familie, Speicherbudget, Auslastung laut Treiber, falls vorhanden. |
| **Memory** | Physischer RAM, App-Speicher, fest zugeordnet, komprimiert, Zwischenspeicher, frei. Swap, Speicherdruck (Systemmeldung), Ein- und Auslagerungen, Komprimierungsrate, Verlauf, größte Verbraucher. Apple Silicon: „Unified Memory – gemeinsam für CPU, GPU und Neural Engine“. |
| **Temperature & Fans** | Thermalstatus (immer). Sensoren über SMC (wo vorhanden), gruppiert nach Bereich, einzeln und aggregiert (Mittel/Max, gekennzeichnet). Akku- und SSD-Temperatur. Lüfter: Anzahl, U/min, Min/Max/Ziel, Verlauf. Für jeden Wert: Quelle, Zeitstempel, Verfügbarkeit. |
| **Battery** | Ladestand, Lade- und Netzteilzustand, Restzeit (Systemschätzung ○). Zyklen, Design- und volle Kapazität, berechneter Zustand ◐ neben Apples Angabe ◇. Spannung, Strom, Leistung ◐, Temperatur, Netzteil (W). Lokaler Verlauf ab Aktivierung. |
| **Storage** | Volumes (intern, extern, Netz), Dateisystem, Container, Belegung, „verfügbar für wichtige Nutzung“ inkl. löschbarem Platz. SSD-Aktivität. SSD-Gesundheit (NVMe-SMART). Größte Ordner und Dateien (Filter 100 MB / 500 MB / 1 GB / eigene Grenze). Kategorien, Duplikate (SHA-256, Klonerkennung). Bereinigungsvorschläge – immer mit Bestätigung, über den Papierkorb. |
| **Files** | Finder Plus: Seitenleiste (Benutzerordner, Programme, Volumes, Favoriten, Zuletzt verwendet). Liste, Symbole, Spalten. Mehrfachauswahl, Drag & Drop, Kopieren/Verschieben mit Fortschritt, Umbenennen (auch mehrere), Neuer Ordner, Papierkorb mit Widerrufen (⌘Z). Teilen, Informationen, Quick Look, Spotlight-Suche und Filter. Im Finder zeigen, Pfad kopieren, Öffnen mit. Ordnergrößen auf Wunsch. |
| **Network** | Schnittstellen (WLAN, Ethernet, VPN, Thunderbolt-Brücke, Sonstige) mit Status und IPv4/IPv6. Rate ↓/↑ live und als Verlauf, Gesamtvolumen seit Start, aktive Verbindungen (TCP/UDP, Zustand, Gegenstelle, Prozess soweit zuordenbar). WLAN: Signal, Rauschen, Kanal, Datenrate, Sicherheit. Den Netzwerknamen gibt es nur mit Ortungsfreigabe (Apple-Vorgabe); Passwörter nie. |
| **Hardware** | Modell, Modellkennung, Chip/Prozessor, Kerne, Cache, RAM, GPU(s), Neural Engine (als Hardwareangabe), Displays, Speichermedien, Batterie, Netzwerkhardware. Software: macOS, Build, Kernel, Uptime. Seriennummer nur auf Klick. Export als Systembericht. |
| **Settings** | Theme, Akzent, Glas, Bewegung, Dichte, Intervall (1/2/5/10 s), Sparmodus, Verlauf (an/aus, Dauer, löschen), Menüleiste, Sensoren über SMC lesen (an/aus mit Erklärung), Sprache, Datenschutz-Übersicht, Info. |

---

## 6 · Technische Architektur

### 6.1 Module (Swift Package, für Xcode und Kommandozeile)

```
AETHER (Swift Package, swift-tools 5.9, macOS 13+)
├─ AetherCore        reine Swift-Logik, ohne Apple-Frameworks – auch unter Linux getestet
│   Measurement & Provenance · Ringpuffer/Verlauf · CPU-Tick-Mathematik · Speicheraufteilung
│   Raten mit Zählerüberlauf/-rücksetzung · Batterie-Mathematik · Puls-Regeln · Formatierung
│   SMC-Wertdekodierung (sp78, fpe2, flt, ui8–32) · Parser (ps, system_profiler-JSON)
│   Prozessklassifizierung & Schutzliste · Duplikat-Gruppierung · Einstellungsmodelle
├─ AetherSystem      nur macOS: Provider über Darwin, IOKit, Metal, SystemConfiguration,
│   CoreWLAN, DiskArbitration, Network – jeweils hinter einem Protokoll mit Fähigkeitserkennung
├─ AetherC           nur macOS, minimal C: SMC-Strukturen, NVMe-SMART-Plugin (COM-Schnittstelle)
└─ AETHER            die App: SwiftUI + AppKit · Designsystem · Bereiche · Stores · Selbsttest/Fotos
```

Die Xcode-Datei wird aus `project.yml` (XcodeGen) im Build erzeugt und mit `xcodebuild` geprüft. Alternativ öffnet
Xcode `Package.swift` direkt.

### 6.2 Datenfluss

```
 Provider (CPU, Memory, Disk, Net, GPU, SMC, Battery, Process …)
        │  synchrone, kurze Systemaufrufe – nie im Hauptthread
        ▼
 MonitorEngine (actor)  ── Takt (1/2/5/10 s), Abonnements, Sparmodus, Pause wenn verborgen
        │  SystemSnapshot (Sendable, unveränderlich)
        ▼
 Stores (@MainActor, je Bereich ein ObservableObject: CPUStore, MemoryStore …)
        │  nur geänderte Bereiche lösen Neuzeichnen aus
        ▼
 SwiftUI-Ansichten  ── lesen nur Stores, rufen nie selbst Systemfunktionen auf
        ▲
 HistoryRecorder (optional) ── SQLite (System-libsqlite3) in ~/Library/Application Support/AETHER
```

- **Abonnements:** Ein Bereich meldet beim Erscheinen an, was er braucht (`.cpu`, `.processes(detail: true)` …),
  und beim Verschwinden wieder ab. Die Prozessliste läuft nur, solange Aktivität, Übersicht (Top 5) oder Verlauf sie
  brauchen.
- **Takte:**
  - schnell (Intervall): CPU, Speicher, Netz, SSD-Aktivität, GPU;
  - mittel (≥ 5 s): Batterie, SMC-Sensoren, Volumes;
  - einmalig/bei Änderung: Hardware (`system_profiler` im Hintergrund, zwischengespeichert), Displays,
    Mount-Ereignisse.
- **Sparmodus:** Mindestintervall 5 s, keine Prozessdetails außerhalb der Aktivität, Diagramme ohne Animation,
  Sensoren alle 10 s.
- **Eigenverbrauch:** Er wird im Selbsttest gemessen und unter Einstellungen → Info angezeigt („AETHER selbst:
  0,4 % CPU, 62 MB“).
- **Fehlermodell:** Jeder Wert ist `Reading<T>`, also `.value(T, Provenance)` oder `.unavailable(Reason)`. Gründe sind
  lokalisierte Erklärungen, etwa „Für Prozesse anderer Benutzer gibt macOS diesen Wert nur Programmen mit
  Administratorrechten“ oder „Dieser Mac meldet keine Lüfter“.

### 6.3 Persistenz und Datenschutz

- **Einstellungen:** `UserDefaults` (Domäne der App).
- **Verlauf:** Er ist nur nach Aktivierung aktiv. Die Aufbewahrung ist wählbar (24 h / 7 / 30 Tage). Daten liegen nur
  lokal und lassen sich mit einem Klick löschen.
- **Keine Netzwerkzugriffe** der App. Keine Telemetrie, keine Konten, keine Passwörter. Das wird im Build geprüft: Die
  Programmdatei darf keine URLSession-, Network-Verbindungs- oder Analyse-Symbole außer der lokalen
  Pfadüberwachung nutzen (`NWPathMonitor`).

### 6.4 Leistung der Oberfläche

- Prozessliste und Dateilisten als `Table` (NSTableView darunter, Zeilen-Recycling).
- Stabile IDs, Diff statt Neuaufbau.
- Sparklines als `Canvas` (kein Swift Charts für Mini-Diagramme). Detaildiagramme mit Swift Charts und begrenzter
  Punktzahl (Downsampling).
- Zahlen in eigenen kleinen Ansichten, damit eine neue CPU-Zahl nicht die ganze Karte neu aufbaut.

---

## 7 · Intel- und Apple-Silicon-Kompatibilität

### 7.1 Universal Binary

Zwei Release-Builds (`arm64-apple-macosx13.0`, `x86_64-apple-macosx13.0`) werden per `lipo` zusammengeführt und mit
`lipo -verify_arch arm64 x86_64` geprüft. Die App läuft auf beiden Architekturen **nativ**. Rosetta wird im Build
nur zusätzlich getestet: Startet jemand die App absichtlich „mit Rosetta“, zeigt sie einen Hinweis und meldet
dennoch die echte Hardware (`hw.optional.arm64`).

### 7.2 Hardwareprofil und Fähigkeitserkennung

Beim Start ermittelt `HardwareProfile` die Fähigkeiten. Die Oberfläche fragt nur Fähigkeiten ab, nie Modelllisten.

| Fähigkeit | Ermittlung |
|---|---|
| Architektur des Macs / dieses Prozesses | `hw.optional.arm64`, `sysctl.proc_translated` |
| Kerncluster (P/E) | `hw.nperflevels`, `hw.perflevelN.{name,physicalcpu,logicalcpu,l2cachesize}` |
| Intel-Kerne/Threads, Hyper-Threading | `machdep.cpu.core_count`, `machdep.cpu.thread_count`, `hw.physicalcpu` < `hw.logicalcpu` |
| Takt | Intel: `hw.cpufrequency(_max)` (Nenntakt ◇). Apple Silicon: nicht verfügbar. |
| GPUs | `system_profiler SPDisplaysDataType -json` (eigener Prozess): Modell, Hersteller, integriert/dediziert/extern, VRAM, Metal-Stufe, Displays. **Nicht** über Metal direkt: `MTLCopyAllDevices()` bricht auf virtuellen Intel-Macs mit einer internen Assertion ab („Target device architecture is nil“) – im ersten Build beobachtet. |
| GPU-Kerne (Apple Silicon) | IORegistry `AGXAccelerator` → `gpu-core-count` (undokumentierter Schlüssel, ◇) |
| SMC, Temperaturen, Lüfter | `AppleSMC` öffnen; Schlüssel `#KEY`, `FNum`; Temperaturschlüssel per Plausibilitätsprüfung |
| Batterie | `IOPSCopyPowerSourcesInfo` hat eine interne Batterie? |
| NVMe-SMART | Eigenschaft `NVMe SMART Capable` am Speicher-Controller |

### 7.3 Was sich je Architektur unterscheidet

| Thema | Apple Silicon | Intel |
|---|---|---|
| CPU-Darstellung | Cluster: Leistungs- und Effizienzkerne getrennt | Physische Kerne × Threads, Hyper-Threading-Hinweis |
| Takt | „Nicht verfügbar – Apple stellt die aktuelle Frequenz nur `powermetrics` mit Root-Rechten bereit“ | Nenntakt ◇, aktueller Takt nicht verfügbar |
| GPU | Integrierte SoC-GPU, Kernzahl, Unified Memory – **kein** eigener Grafikspeicher | Intel iGPU und ggf. AMD dGPU, getrennt; VRAM der dGPU ◇ |
| Speicher | „Unified Memory“, Seitengröße 16 KB | Klassischer RAM, Seitengröße 4 KB |
| Neural Engine | als Hardwareangabe ◇, Auslastung nicht verfügbar | nicht vorhanden – wird nicht angezeigt |
| Temperaturen | SMC-Schlüssel je Chipgeneration verschieden (M1…M5), Zuordnung über Präfixe | SMC-Schlüssel seit Jahren stabil (TC0P, TC0D, TG0P …) |
| Lüfter | MacBook Air: keine – „Dieser Mac hat keinen Lüfter“ | 1–2 Lüfter |
| Energie je Prozess | `proc_pid_rusage` Energiewerte (◇, wo der Kernel sie führt) | meist nicht vorhanden |

Wichtig: Die Seitengröße kommt aus `vm_kernel_page_size`, nicht aus `vm_page_size`. Unter Rosetta meldet
`vm_page_size` sonst 4 KB, obwohl die Kernelseiten 16 KB groß sind. Das würde alle Speicherwerte um den Faktor 4
verfälschen.

---

## 8 · API- und Berechtigungsanalyse

### 8.1 Klassen von Quellen

| Klasse | Beispiele | Bewertung |
|---|---|---|
| **A – öffentlich dokumentiert** | `host_processor_info`, `host_statistics64`, `sysctl`, `getloadavg`, `ProcessInfo.thermalState`, IOPowerSources, `FileManager`-Volume-Schlüssel, DiskArbitration, `getifaddrs`, SystemConfiguration, `NWPathMonitor`, CoreWLAN, QuickLook, `NSWorkspace`, `proc_listallpids`/`proc_pidinfo`/`proc_pid_rusage` (libproc), `kill`, IOBlockStorageDriver-Statistik, NVMe-SMART (`NVMeSMARTLibExternal.h`) | uneingeschränkt nutzbar |
| **B – öffentliche Funktion, undokumentierte Schlüssel** | IORegistry: `AppleSmartBattery` (Zyklen, Kapazitäten, Spannung, Strom, Temperatur), `IOAccelerator` → `PerformanceStatistics` (GPU-Auslastung), `AGXAccelerator` → `gpu-core-count` | nutzbar mit Plausibilitätsprüfung; fehlt ein Schlüssel → „nicht verfügbar“ |
| **C – undokumentiertes Protokoll über öffentliche IOKit-Funktionen** | **SMC** (`IOServiceOpen("AppleSMC")` + `IOConnectCallStructMethod`): Temperaturen, Lüfter | siehe Risikoanalyse 8.3 |
| **D – Systemwerkzeuge von Apple** | `system_profiler -json` (Modellname, GPU-Kerne, Displays, Apples Batteriezustand), `/bin/ps` (CPU/Speicher aller Prozesse, da mit Systemrechten installiert), `tmutil listlocalsnapshots` | öffentliche, stabile Werkzeuge; Ausgabe wird geparst und unit-getestet. Ob `/bin/ps` mit Systemrechten installiert ist, prüft die App beim Start, statt es anzunehmen. |
| **E – nur mit Root** | aktueller CPU-/GPU-Takt, Leistungsaufnahme je Komponente (`powermetrics`), Prozessdetails anderer Benutzer über libproc | **nicht genutzt**; erklärt als „nicht verfügbar“ |
| **F – nur über private Frameworks** | `IOHIDEventSystemClient` (Temperatursensoren), `NetworkStatistics` (Datenmenge je Prozess), `IOReport` (Energie/Takt) | **nicht genutzt** |

### 8.2 Datenquellen im Einzelnen

| Wert | Quelle | Klasse | H |
|---|---|---|---|
| CPU gesamt / je Kern, Benutzer/System/Leerlauf | `host_processor_info(PROCESSOR_CPU_LOAD_INFO)`, Differenz der Ticks | A | ◐ aus ● |
| Durchschnittslast | `getloadavg` | A | ● |
| Speicher: App, fest, komprimiert, Zwischenspeicher, frei | `host_statistics64(HOST_VM_INFO64)` × `vm_kernel_page_size`. Aufteilung wie die Aktivitätsanzeige: App = intern − löschbar; Zwischenspeicher = extern + löschbar | A | ◐ |
| Swap | `sysctl vm.swapusage` | A | ● |
| Speicherdruck | `sysctl kern.memorystatus_vm_pressure_level` + `DispatchSource.makeMemoryPressureSource` | A | ◇ |
| Prozesse eigener Benutzer | libproc: `PROC_PIDTASKALLINFO`, `proc_pid_rusage` (phys_footprint, Energie), `proc_pidpath` | A | ● |
| Prozesse anderer Benutzer/System | Name, PID, Benutzer, Eltern, Start, Zustand und Rosetta-Kennzeichen über `sysctl KERN_PROC`. CPU/Speicher über `/bin/ps`, falls mit Systemrechten installiert. Sonst „nur mit Administratorrechten“. | A/D | ● |
| App-Zuordnung, Symbol | `NSWorkspace.runningApplications`, Pfad → `.app` | A | ● |
| Beenden | `NSRunningApplication.terminate/forceTerminate`, sonst `kill(SIGTERM/SIGKILL)`; EPERM → Erklärung | A | – |
| GPU-Modell, Hersteller, Art, VRAM, Metal-Stufe | `system_profiler SPDisplaysDataType` (Metal direkt wäre Klasse A, stürzt aber auf manchen virtuellen Macs ab) | D | ◇ |
| GPU-Auslastung | IORegistry `IOAccelerator.PerformanceStatistics["Device Utilization %"]` | B | ◇ (Treiberangabe) |
| Thermalstatus | `ProcessInfo.thermalState` + Benachrichtigung | A | ◇ |
| CPU-/GPU-/SoC-Temperaturen, Lüfter | SMC | C | ● |
| Akku: Ladestand, Laden, Netzteil, Restzeit | IOPowerSources, `IOPSCopyExternalPowerAdapterDetails` | A | ●/○ |
| Akku: Zyklen, Kapazitäten, Spannung, Strom, Temperatur | IORegistry `AppleSmartBattery` | B | ● |
| Akku: Zustand berechnet | volle Ladekapazität ÷ Designkapazität × 100 | – | ◐ |
| Akku: Apples Zustand / „Maximale Kapazität“ | `system_profiler SPPowerDataType -json` | D | ◇ |
| Volumes | `URLResourceValues` (Kapazität, verfügbar, *für wichtige Nutzung* inkl. löschbar, Format, intern/extern, verschlüsselt), `statfs`, DiskArbitration (Bus, Gerät, Medium) | A | ●/◇ |
| SSD-Aktivität | IORegistry `IOBlockStorageDriver` → `Statistics` (öffentliche Konstanten) | A | ◐ aus ● |
| SSD-Gesundheit | NVMe-SMART: Temperatur, Verschleiß %, Reserve, geschriebene/gelesene Daten, Betriebsstunden, unsichere Abschaltungen, Medienfehler | A | ● |
| Netzwerkraten | `sysctl NET_RT_IFLIST2` (64-Bit-Zähler; `getifaddrs` hat nur 32 Bit und läuft bei 4 GB über) | A | ◐ aus ● |
| Schnittstellen, Typ, IPs | `getifaddrs`, `SCNetworkInterfaceCopyAll`, `NWPathMonitor` | A | ● |
| WLAN-Details | CoreWLAN: RSSI, Rauschen, Kanal, Rate, Sicherheit. SSID/BSSID nur mit Ortungsfreigabe (seit macOS 14). | A | ● |
| Verbindungen | Kernel-Socket-Tabellen (`net.inet.tcp/udp.pcblist_n`, wie `netstat`), Prozesszuordnung über den letzten Besitzer des Sockets, soweit vorhanden | A | ● |
| Datenmenge je Prozess | nur private API | F | ⊘ „nicht zuverlässig zuordenbar“ |
| Modellname, Displays | `system_profiler`, `NSScreen`, `CGDisplay*` | A/D | ◇ |
| Seriennummer | IORegistry `IOPlatformSerialNumber` – nur auf Klick, nie im Export ohne Häkchen | B | ◇ |
| Lokale Snapshots | `tmutil listlocalsnapshots /` | D | ◇ |

### 8.3 Risikoanalyse SMC (Klasse C)

*Begründung:*

- Für CPU-, GPU- und SoC-Temperaturen sowie Lüfterdrehzahlen gibt es in macOS **keine** öffentliche API.
  `thermalState` ist nur eine Einstufung.
- Der Auftrag verlangt „möglichst viele echte Sensorwerte“.
- Das SMC liefert echte Sensorwerte. Der Zugriff geschieht über die öffentlichen IOKit-Funktionen `IOServiceOpen` und
  `IOConnectCallStructMethod`. Es werden **keine privaten Symbole** gelinkt und **keine** Frameworks per `dlopen`
  geladen.
- Werkzeuge wie smcFanControl oder iStat nutzen diesen Weg seit über 15 Jahren.

*Risiken und Gegenmaßnahmen:*

| Risiko | Gegenmaßnahme |
|---|---|
| Apple ändert Schlüssel oder Strukturgröße (z. B. bei neuen Chips) | Eigener Provider hinter Protokoll. Strukturgröße wird geprüft; bei Fehler gilt „nicht verfügbar“ statt eines falschen Werts. Werte außerhalb von −20…130 °C werden verworfen. |
| Bedeutung der Schlüssel ist nicht von Apple dokumentiert | Anzeige mit Schlüssel („SMC Tp09“). Ein Bereichsname nur bei etablierter Zuordnung, gekennzeichnet „Zuordnung nach Erfahrungswerten“. Aggregate (Mittel/Max) als ◐. |
| App Sandbox blockiert den Zugriff | Die App ist bewusst nicht gesandboxt (8.4). |
| Schreiben könnte Hardware beeinflussen | Es wird **ausschließlich gelesen**. Es gibt keine Lüftersteuerung und keine Schreibfunktion im Code. |
| Virtuelle Macs (z. B. Build-Rechner) | Dort fehlt das SMC; die App zeigt dann „nicht verfügbar“ mit Grund. |

In den Einstellungen lässt sich das Lesen über SMC abschalten. Danach bleiben Thermalstatus, Akku- und
SSD-Temperatur verfügbar.

**Klasse B** (undokumentierte IORegistry-Schlüssel) wird genauso behandelt: lesen, prüfen, kennzeichnen, sonst
„nicht verfügbar“.

### 8.4 App Sandbox – Entscheidung

| Funktion | in der Sandbox |
|---|---|
| CPU, Speicher, Thermalstatus, Akku (IOPS), Netzraten | möglich |
| Prozesse anderer Apps auflisten/Details, beenden | stark eingeschränkt bzw. nicht möglich |
| SMC (Temperaturen, Lüfter) | nicht möglich |
| `ps`, `system_profiler` starten | erben die Sandbox – teilweise unbrauchbar |
| Finder Plus (freie Navigation, Kopieren, Löschen) | nur über einzelne Freigaben und Security-Scoped Bookmarks |

**Entscheidung:** AETHER ist **nicht gesandboxt** und wird außerhalb des Mac App Store vertrieben.

- Ziel ist Developer ID mit Notarisierung und Hardened Runtime. Die Hardened Runtime ist mit allen genannten
  Zugriffen vereinbar; Ausnahme-Berechtigungen (`allow-jit`, `disable-library-validation` o. Ä.) werden nicht benötigt.
- Für die WLAN-SSID kommt bei signierter Verteilung `com.apple.security.personal-information.location` hinzu.
- **Konsequenzen:** kein Mac App Store. Gatekeeper braucht für eine reibungslose Installation eine Developer-ID-Signatur
  samt Notarisierung (kostenpflichtiges Apple-Entwicklerkonto). Bis dahin ist die App ad-hoc signiert, und der erste
  Start braucht „Dennoch öffnen“.

### 8.5 Berechtigungen, die der Nutzer sieht

| Berechtigung | Wann | Ohne Freigabe |
|---|---|---|
| Schreibtisch, Dokumente, Downloads (TCC) | beim ersten Öffnen in *Files* oder bei einer Speicheranalyse | der Ordner erscheint als „Kein Zugriff – erlauben in Systemeinstellungen“ |
| Wechselmedien, Netzlaufwerke (TCC) | beim ersten Zugriff | wie oben |
| Festplattenvollzugriff (optional) | nur auf Wunsch, für vollständige Speicheranalyse (z. B. Mail, Nachrichten) | Analyse zählt „nicht lesbar (Datenschutz)“ getrennt aus |
| Ortungsdienste (optional) | nur für den WLAN-Namen | Anzeige „Netzwerkname: Freigabe nötig“ |
| Administratorrechte | **nie** | – |

Ein privilegierter Helfer (SMAppService) für Prozessdetails anderer Benutzer ist **nicht** vorgesehen. Er würde eine
Developer-ID-Signatur voraussetzen und dauerhaft mit Root-Rechten laufen; das widerspricht „keine unnötigen
Administratorrechte“.

---

## 9 · Entwicklungsreihenfolge

Jede Phase endet mit einem echten Build auf macOS-Rechnern und einer prüfbaren DMG:

- Unit-Tests auf Apple Silicon und Intel;
- Universal-Build;
- DMG mit Mount-Test;
- Selbsttest nativ, über Rosetta und auf Intel;
- Bildschirmfotos in allen Themes.

| Phase | Inhalt | Ergebnis |
|---|---|---|
| 1 | Dieses Konzept, Analyse der Vorprojekte, API- und Risikoanalyse | `docs/KONZEPT.md` |
| 2 | Paket, Core + Tests, Build-/DMG-Skripte, CI. Designsystem mit 6 Themes, Navigation, Einstellungen, Lokalisierung en/de. **Übersicht mit ersten echten Messwerten** (CPU, Speicher, Volumes, Netz, Akku, Thermalstatus, Hardware). | erste Universal-DMG |
| 3 | Liquid Glass vollendet: Kartenraster mit Anpassen, Animationen, Fensterverhalten, Live-Monitor-Fenster, Menüleiste | |
| 4 | Systemmonitor: CPU & GPU (je Kern, Cluster, GPU-Treiberwerte), Memory, **Activity** (Prozesse, App-Familien, Aktionen, Schutzliste) | |
| 5 | Hardwarediagnose: SMC-Temperaturen und Lüfter, Batterie komplett, SSD-SMART, Hardware-Bereich, Systembericht | |
| 6 | Finder Plus und Storage: Dateien, Operationen, Quick Look, Suche, große Dateien, Duplikate, Bereinigung | |
| 7 | Netzwerk komplett, lokaler Verlauf (SQLite) mit Zeitachse, Exporte | |
| 8 | Feinschliff: Leistung (Eigenverbrauch), Barrierefreiheit, Intel-/ARM-Tests, Kontrastprüfung | |
| 9 | Release: Universal-Build, Xcode-Projekt, Signatur/Notarisierung (falls Zugangsdaten vorhanden), DMG, Prüfung, Release-Notiz | `AETHER-macOS-Universal.dmg` |

---

## 10 · Release- und DMG-Strategie

### 10.1 Build-Weg

In der Arbeitsumgebung dieses Projekts gibt es kein Xcode. Gebaut wird deshalb wie bei Android Bridge auf **echten
macOS-Rechnern von GitHub Actions** im eigenen Zweig `aether-macos` des Repositorys `music-library-mac`. Lokal geht es
genauso: `Build.command` doppelklicken oder `scripts/build_app.sh && scripts/make_dmg.sh` aufrufen.

| Job | Rechner | Schritte |
|---|---|---|
| **build** (Matrix) | macOS 26 · Apple Silicon · Xcode 26 *und* macOS 15 · Intel (Ausweichrechner) | Clean Build (`rm -rf .build build dist`) → Unit-Tests → arm64 + x86_64 → `lipo -create` → **`lipo -archs` / `-verify_arch`** → Bundle-Aufbau und Ressourcenprüfung (Info.plist `plutil -lint`, Icon, Lokalisierungen, nur System-Bibliotheken) → ad-hoc-Signatur → Selbsttest → Bildschirmfotos (alle Themes, Glas und Rückfall) → DMG → **Mount-Test** (`hdiutil verify/attach`, App vorhanden, Link „Programme“, Architekturen, `codesign --verify --deep --strict`) → Installieren aus der DMG und Start, nativ und über Rosetta |
| **smoke** | macOS 15 · Intel | Die fertige DMG wie ein Nutzer installieren und starten, Selbsttest, Bildschirmfotos |
| **intel** | macOS 15 · Intel | Unit-Tests in x86_64 |
| **results** | Ubuntu | DMG, Prüfsumme, Protokolle, Bildschirmfotos → Zweig `ci-ergebnisse-aether-macos` |

### 10.2 Inhalt der DMG `AETHER-macOS-Universal.dmg`

- Volume „AETHER“: HFS+, UDZO komprimiert.
- Hintergrundbild in 1× und 2× (TIFF), das Volume-Symbol.
- `AETHER.app`.
- Verknüpfung „Programme“ → `/Applications`.
- Pfeil-Gestaltung zum Hineinziehen.
- App-Icon als eigenes Motiv: eine schwebende Glaslinse über einem leuchtenden Äther-Ring. Erzeugt als `.icns` mit
  allen Größen.

### 10.3 Signatur und Notarisierung

- **Jetzt:** ad-hoc signiert (`codesign --sign -`), ehrlich dokumentiert. Die Installationsanleitung erklärt
  „Dennoch öffnen“.
- **Vorbereitet:** `SIGN_IDENTITY` (Developer ID Application, Hardened Runtime, Zeitstempel) und
  `scripts/notarize.sh`. Liegen die GitHub-Secrets `MACOS_CERT_P12_BASE64`, `NOTARY_APPLE_ID`, `NOTARY_TEAM_ID` und
  `NOTARY_PASSWORD` vor, signiert, notarisiert und heftet der Build automatisch an. Sonst überspringt er diese
  Schritte mit Meldung. Es werden keine Zertifikate oder Zugangsdaten erfunden.

### 10.4 Prüfung vor „fertig“

Eine DMG gilt erst als fertig, wenn alle Punkte erfüllt sind:

1. Die DMG lässt sich einhängen.
2. `AETHER.app` ist enthalten, und `lipo -archs` meldet `x86_64 arm64`.
3. Die Signatur ist gültig.
4. Der Selbsttest der *installierten* App hat auf Apple Silicon (nativ und Rosetta) und auf Intel bestanden.
5. Prüfsumme und Größe sind dokumentiert.

Die DMG wird anschließend ins Projektverzeichnis übernommen und dort noch einmal unabhängig geprüft: UDIF-Struktur,
HFS+-Inhalt und Mach-O-Architekturen mit eigenen Werkzeugen.

### 10.5 Ehrliche Grenzen der Tests

GitHub-Rechner sind virtuelle Macs. Dort gibt es:

- keine Batterie;
- meist kein SMC;
- keine Lüfter;
- keine NVMe-SMART-Daten.

Diese Pfade werden im Build daher nur auf „sauber nicht verfügbar“ geprüft. Ob echte Sensorwerte stimmen, lässt sich
nur auf einem physischen Mac prüfen. Das steht in jedem Testbericht ausdrücklich als *nicht durchgeführt*, bis es auf
echter Hardware bestätigt ist.
