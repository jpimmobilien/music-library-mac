# AETHER Studio – visuelle Neuausrichtung und Monitoring 2.0

Stand 8. November 2026 · Grundlage: Bildschirmaufnahmen von AETHER 1.0 auf einem MacBook Pro 14,3 (Intel Core i7,
macOS 13.7.8) und die Produktseite des MacBook Pro als Referenz für die Designhaltung (nicht zum Nachbauen).

---

## 1. Befund (Schritt 1 – Analyse der bestehenden App)

Gemessen bzw. abgelesen in den Aufnahmen und im Code:

| # | Beobachtung | Ursache im Code |
|---|---|---|
| 1 | AETHER selbst **106–118 % CPU** auf „Aktivität“, 7–21 % auf der Übersicht; WindowServer ≈ 32 % | siehe 2–5 |
| 2 | Zahlen springen (CPU, GPU, Netz, RAM), kleine Diagramme „nervös“ | Anzeige = Rohwert der letzten Differenz; keine Glättung; Text mit wechselnder Stellenzahl; Ringe und Balken animieren bei jedem Takt neu, die Verlaufslinie springt um eine Stützstelle |
| 3 | Aktivität: Hauptthread ausgelastet | 530 Zeilen werden je Takt im Hauptthread neu gebaut (Schutzprüfung, App-Namen, `FileManager.displayName` je Familie), nach CPU neu sortiert (Zeilen tauschen ständig die Plätze), 6 Filterzählungen und Filterung/Sortierung bei **jedem** Neuzeichnen |
| 4 | Ruckeln auf Intel-Grafik | jede Karte hat ein eigenes `NSVisualEffectView` (Hintergrundunschärfe). Bei jeder Wertänderung muss WindowServer 10–14 Unschärfeflächen neu zusammensetzen |
| 5 | Alle Werte ändern sich gleichzeitig | ein einziger Takt misst alles (CPU, RAM, Netz, SSD, GPU, Puls, Prozesse) und veröffentlicht alles auf einmal; Batterie liest alle 5 s das komplette IORegistry-Wörterbuch |
| 6 | Upload zeigt immer exakt den Download-Wert (467 B/s ↔ 467 B/s) | gezählt werden alle `en*`-Schnittstellen – dazu gehört auf Intel-Macs mit T1/T2 die interne Brücke zum Sicherheitschip (`en5`, nur link-lokale IPv6-Adresse) mit symmetrischem Verkehr |
| 7 | „noch 0 s“ bei vollständig geladener Batterie | Restzeit wurde auch im Zustand „geladen“ angezeigt |
| 8 | Übersicht: viele gleichartige Karten, darunter eine große leere Fläche | Kartenraster ohne Hierarchie |

## 2. Monitoring 2.0 (Schritt 2)

**Trennung:** Erfassen (Messwarteschlange) → Normalisieren/Glätten (AetherCore, getestet) → Veröffentlichen (nur
geänderte Anzeigewerte) → Darstellen.

**Eigene Takte je Messgröße** (Grundtakt = Einstellung „Messtakt“, Standard 1 s):

| Messgröße | Takt | Glättung (Anstieg / Abfall) | Spitze |
|---|---|---|---|
| CPU gesamt und je Kern | 1× Grundtakt | τ 0,5 s / 2,5 s | Maximum der letzten 10 s |
| Netz ↓/↑ | 1× | τ 0,6 s / 3 s | Maximum der letzten 10 s (bleibt sichtbar) |
| SSD lesen/schreiben | 1× | τ 0,6 s / 3 s | Maximum der letzten 10 s |
| GPU (Treiber) | 2 s | τ 1 s / 3 s | Maximum der letzten 10 s |
| Arbeitsspeicher | 2 s | τ 4 s symmetrisch, Anzeigeraster 0,01 GB | – |
| Temperatur, Lüfter (SMC) | 3 s | τ 6 s / 4 s | – |
| Batterie | 10 s **und** sofort bei Netzteilwechsel (IOPS-Benachrichtigung) | keine – nur echte Änderungen | – |
| Volumes | 30 s und bei Ein-/Aushängen | – | – |
| Prozesse | 2 s, nur wenn sichtbar | CPU je Prozess τ 0,8 s / 2,5 s, Sortierung auf 0,5 % gerundet | – |

- Glättung: `alpha = 1 − exp(−Δt / τ)`, **asymmetrisch**. Anstiege erscheinen schnell (Lastspitzen werden nicht
  verschluckt), Abfälle beruhigen sich.
- Kurze Spitzen hält zusätzlich die Spitzenanzeige („Spitze 10 s“) fest.
- Der **Rohwert** bleibt erhalten und ist überall abrufbar: als „jetzt“-Angabe unter großen Zahlen und als
  Umschalter „Geglättet / Rohwerte“ in den Einstellungen.
- Anzeigewerte werden nur veröffentlicht, wenn sich die **gerundete** Darstellung ändert (Hysterese). Kein Flackern
  der letzten Stelle, kein Neuzeichnen ohne sichtbare Änderung.
- Verläufe: zeitbasierte Ringpuffer mit 1 h Kapazität im Grundtakt; Zeiträume 1 min / 5 min / 15 min / 1 h. Die
  Darstellung wird per **Min/Max-Bündelung** auf ≤ 240 Stützstellen reduziert – Spitzen bleiben dabei erhalten.
- Aktivität: Zeilen außerhalb des Hauptthreads aufbereiten, teure Angaben zwischenspeichern, Sortierung mit
  Hysterese, Zeilenumstellungen ohne Animation, Filterzählungen einmal je Messung.
- Glas: **eine** Unschärfeebene für die schwebende Seitenleiste; Inhaltsflächen sind getönte Schichten mit Licht-
  kante und Schatten, ohne eigene Unschärfe (auf macOS 26 natives Liquid Glass nur für schwebende Bedienelemente).
- Diagnosemodus (Einstellungen → Messung → „Entwickler-Diagnose“): Eigenverbrauch CPU/RAM, Messquellen je Takt,
  Grundtakt, Messzeit je Takt und je Quelle, Zeit im Hauptthread, Verzögerung des Takts, Anzeige-Aktualisierungen
  pro Sekunde, Zustand der Prozessliste – als Tafel in den Einstellungen und als kleine Anzeige unten rechts im Fenster.
- Verläufe mit Quellen, die seltener messen, als ein Diagrammabschnitt breit ist (Speicher 2 s, Thermik 3 s, Batterie
  10 s), werden zwischen zwei Messungen verbunden (bis 25 s); ausdrücklich fehlende Werte und längere Pausen bleiben
  Lücken.

## 3. Designsprache „Studio“ (Schritt 3)

**Haltung:** eine Produktpräsentation, die gleichzeitig ein Werkzeug ist. Jede Seite folgt dem Muster
**Überzeile → Aussage → große Visualisierung → präzise Zahlen → Details**. Dabei gilt: wenige große Elemente statt
vieler kleiner Karten, viel Luft, wenige Rahmen.

**Bühne:** tiefes, fast schwarzes Grau (Dunkel) bzw. Perlweiß (Hell). Hinter der Visualisierung liegt ein weiches,
statisches Bühnenlicht (radialer Verlauf in der Bereichsfarbe) – erkennbar dekorativ, es zeigt keine Daten.

**Typografie (SF Pro):**

| Rolle | Schrift |
|---|---|
| Überzeile | 13 pt, halbfett, Bereichsfarbe, Laufweite +0,4 |
| Aussage | 34–44 pt, fett, Laufweite −0,5 |
| Erklärung | 15 pt, sekundär, max. 60 Zeichen je Zeile |
| Große Zahl | 56–72 pt, halbfett, feste Ziffernbreite |
| Kennzahl | 28 pt |
| Beschriftung | 12 pt |

**Material „Liquid Glass 2.0“** – drei Ebenen:
- *Grund* (Bühne);
- *Schicht* (Inhaltsflächen: getönte Füllung, obere Lichtkante, feine Haarlinie, weicher Schatten – keine eigene
  Unschärfe);
- *Schwebend* (Seitenleiste, Werkzeuge: echte Hintergrundunschärfe bzw. natives Liquid Glass auf macOS 26).

**Farben:** Jede Bereichsfarbe kommt aus dem Theme (CPU blau, GPU violett, RAM grün, Thermik orange, Batterie grün,
Netz cyan/rosa, Speicher gold). Visualisierungen nutzen sie als Licht (Verläufe, Leuchten), nicht als Flächenfarbe.
Kein Neon, kein RGB.

**Bewegung:**
- Werte gleiten (Federn 0,6 s) statt zu springen.
- Dauerhafte Bewegung nur dort, wo sie Daten zeigt: Netzströme, deren Dichte und Tempo dem gemessenen Durchsatz
  folgen (0 B/s → keine Partikel).
- Alles respektiert „Bewegung reduzieren“ und die Einstellung „Bewegung“.
- Netzströme laufen als Core-Animation-Ebene im Fensterserver (CAReplicatorLayer): Die App berechnet dafür keine
  Einzelbilder; neu gestartet wird die Animation nur, wenn sich Partikelzahl oder Tempostufe ändern.

**Visualisierungen** (nur Vektorformen und Verläufe – keine Shader, damit sie auch auf Intel-Grafik ohne Last laufen):

| Bereich | Visualisierung | Daten |
|---|---|---|
| Übersicht | Mac-Silhouette passend zum Modell (MacBook, iMac, Mac mini/Studio, Mac Pro) auf der Bühne; Bildschirm zeigt Kernaktivität als Lichtsäulen; Netzströme fließen zu/vom Gerät | CPU je Kern, Netz ↓/↑ |
| CPU & GPU | Chip-Ansicht: Kerne als Kacheln (P/E bzw. Kerne), Leuchtstärke = Last; GPU-Block; Lichtbahnen am Rand | Last je Kern, GPU-Treiberwert |
| Arbeitsspeicher | „Speicherschichten“ – isometrisch gestapelte Ebenen (App, fest, komprimiert, Cache, frei) | Seitenaufteilung, Druck |
| Temperatur | schematische Draufsicht des Geräts mit Wärmepunkten je Sensorbereich (Lage schematisch, so beschriftet), Rotoren nach Drehzahl | SMC-Bereiche, Lüfter |
| Batterie | große, räumlich wirkende Zelle mit Füllstand; Lichtfluss nur beim tatsächlichen Laden | Ladung, Zustand, Laden |
| Speicher | isometrischer SSD-Baustein mit belegtem/löschbarem/freiem Anteil | Volumes |
| Netzwerk | zwei Lichtbahnen ↓/↑, Partikel nach Durchsatz | Netzraten |
| Aktivität | Prozesslandschaft – Blasen nach CPU oder Speicher, Farbe nach Art | Prozessliste |
| Hardware | Produktbild-Bühne des Geräts mit technischen Daten wie auf einer Datenseite | Modell, Chip, Speicher |

**Interaktion:**
- Jede Visualisierung ist anklickbar und führt zum zugehörigen Bereich (Übersicht → CPU, RAM, Temperatur, Batterie,
  Netz, Speicher).
- Zeigeranzeige mit Hover-Licht; Bereichswechsel mit weichem Überblenden und leichter Skalierung.

**Navigation:**
- schlanke, schwebende Glasleiste (Breite 216 pt);
- aktiver Bereich als ruhige Lichtfläche in der Bereichsfarbe mit feiner Lichtkante links;
- Mini-Werte unten bleiben.

**Ehrlichkeit:**
- Dekorative Elemente (Bühnenlicht, Glanz) tragen keine Daten und sehen auch nicht danach aus.
- Fehlt ein Wert, bleibt seine Visualisierung dunkel und trägt den Grund („nicht verfügbar – …“).
- Keine Zufallsbewegung, die als Aktivität gelesen werden könnte.

## 4. Umsetzung und Messung (Schritte 4–9)

**Gemessen im Build** (Selbsttest der gebauten App, echte Messwerte, Grundtakt 1 s, je Bereich 8 s nach 2 s
Eingewöhnung, CPU-Zeit des eigenen Prozesses über alle Threads):

| Bereich | vor der Korrektur | nach der Korrektur (macOS 26, Apple Silicon, VM) |
|---|---|---|
| Übersicht | 99,6 % eines Kerns | **2,2 %** |
| Übersicht, Bewegung aus | 100,9 % | 2,6 % |
| Einstellungen | 100,2 % | 2,9 % |
| Arbeitsspeicher | 100,1 % | 3,1 % |
| Netzwerk | 100,3 % | 3,3 % |
| Aktivität (Prozesse werden gemessen) | 100,3 % | 5,4 % |
| CPU & GPU (Prozesse werden gemessen) | 93,0 % | 6,8 % |

Messmaschine: 5,4 ms je Takt im Hintergrund, 0,65 ms je Takt im Hauptthread, ≈ 10 Anzeige-Aktualisierungen je
Sekunde für alle sichtbaren Zahlen zusammen.

**Gefundene Hauptursache** (Stichprobenprofil mit `/usr/bin/sample`, 83 % des Hauptthreads): Die Beschriftung der
Menüleisten-Anzeige (`MenuBarExtra`) beobachtete den CPU-Speicher und änderte sich jede Sekunde. Jede Änderung des
App-Graphen lässt SwiftUI die **gesamte** Ansicht jedes offenen Fensters neu auswerten und vermessen
(`scenesDidChange → updateRootView → preferenceValues → sizeThatFits`) – in jedem Bereich und auch dann, wenn die
Menüleisten-Anzeige ausgeschaltet ist. Diese Ursache steckte schon in 1.0 und erklärt einen großen Teil der dort
beobachteten Last. Lösung: Die Menüleisten-Anzeige ist jetzt ein AppKit-Statusobjekt, dessen Titel direkt gesetzt
wird; das Feld darunter ist ein `NSPopover` mit derselben SwiftUI-Ansicht.

Zweite Ursache: Die Zeitraumwahl als `Picker(.segmented)` (AppKit) vermaß bei jedem Layout-Durchgang ihre
Beschriftungen (≈ 5 %). Ersetzt durch eine reine SwiftUI-Auswahl mit fester Größe.

**Weitere Umsetzung**
- Übersicht: Aussage (Puls, Hinweise führen zum Bereich), Gerätebühne (Gerät passend zum Modell, Last je Kern auf dem
  Bildschirm, Datenströme), Live-Leiste mit Verlauf der letzten Minute, Module mit Verlauf 1 min – 1 h, anpassbar wie
  bisher.
- Detailseiten: eigene Hero-Visualisierung je Bereich (siehe Tabelle in Abschnitt 3); schematische Darstellungen sind
  beschriftet; fehlende Werte erscheinen als „–“ mit Grund, nie als Platzhalterzahl.
- Seitenleiste 216 pt, Auswahl als Lichtfläche in der Bereichsfarbe, Mini-Werte geglättet.
- Einstellungen → Messung: „Rohwerte zeigen“ und „Entwickler-Diagnose“ (Tafel und Fensteranzeige).
- Batterie: keine Restlaufzeit „0 s“ mehr (vollständig geladen bzw. am Netzteil ohne Laden).
- Netzwerk: nur Schnittstellen mit routbarer Adresse; kein Scheinverkehr über die T2-Brücke.

**Nicht im Build prüfbar:** Batterie-Darstellung mit echtem Akku, Wärmekarte mit echten Sensoren und Lüftern
(Build-Rechner sind virtuelle Macs ohne Akku und Sensoren). Diese Zustände sind im Code an echte Messwerte gebunden und
erscheinen auf den Build-Rechnern ehrlich als „nicht vorhanden“ bzw. „nicht verfügbar“.
