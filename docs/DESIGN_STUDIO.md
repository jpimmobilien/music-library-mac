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
| GPU (Treiber) | 2× | τ 1 s / 3 s | Maximum der letzten 10 s |
| Arbeitsspeicher | 2× | τ 4 s symmetrisch, Anzeige-Hysterese 0,05 GB | – |
| Temperatur, Lüfter (SMC) | 3 s | τ 6 s / 4 s | – |
| Batterie | 10 s **und** sofort bei Netzteilwechsel (IOPS-Benachrichtigung) | keine – nur echte Änderungen | – |
| Volumes | 30 s und bei Ein-/Aushängen | – | – |
| Prozesse | 2 s, nur wenn sichtbar | CPU je Prozess τ 2 s | – |

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
- Diagnosemodus (Einstellungen → Entwickler): Eigenverbrauch CPU/RAM, aktive Messaufgaben, Takt, Verarbeitungsdauer
  je Quelle, Verzögerung des Takts, Veröffentlichungen pro Sekunde.

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
  folgen (0 B/s → Stillstand), und Lüfterrotoren nach Drehzahl.
- Alles respektiert „Bewegung reduzieren“ und die Einstellung „Bewegung“.
- Bewegte Teile laufen mit höchstens 30 Bildern/s und nur, solange sie sichtbar sind.

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
- schlanke, schwebende Glasleiste (Breite 212 pt), Gruppen ohne Überschriften-Lärm;
- aktiver Bereich als ruhige Lichtkapsel;
- Mini-Werte unten bleiben.

**Ehrlichkeit:**
- Dekorative Elemente (Bühnenlicht, Glanz) tragen keine Daten und sehen auch nicht danach aus.
- Fehlt ein Wert, bleibt seine Visualisierung dunkel und trägt den Grund („nicht verfügbar – …“).
- Keine Zufallsbewegung, die als Aktivität gelesen werden könnte.
