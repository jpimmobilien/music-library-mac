# Designsystem „Aether“

Stand 26.10.2026 · Quellcode: `ui/designsystem/src/main/java/de/privateapp/aether/design/`

## 1. Haltung

**Licht und Luft.** Die Oberfläche ist fast farblos: kühles Perlgrau bzw. tiefes Blaugraphit, darauf Glas. Farbe trägt
Bedeutung – der Akzent dort, wo man tippen kann oder etwas ausgewählt ist; Grün, Bernstein und Rot nur für echte
Zustände und nie allein, sondern immer mit Symbol und Text. Keine Neonfarben, kein Dauerleuchten, kein Pulsieren.
Ein Systemwerkzeug, das sich hochwertig anfühlt – nicht eine Spielerei.

## 2. Themes

| Theme | Charakter | Hintergrund | Inhaltsflächen | Schwebende Leisten |
|---|---|---|---|---|
| **Adaptiv** (Vorgabe) | folgt hell/dunkel von Android | wie Liquid Glass Hell bzw. Dunkel | | |
| **Liquid Glass Hell** | „Morgenluft“ | Verlauf #F4F7FB → #EDF1F6 → #E5EAF1, drei weiche Lichtfelder (Akzent, kühl, warm) | weißes Glas 78 → 62 % mit Glanz, Lichtkante, weichem Schatten | Glas 80 % über Unschärfe |
| **Liquid Glass Dunkel** | „Nachthimmel“ | #0F141C → #0A0E14 → #06080C, Lichtfelder | Glas 7,5 → 4 % Weiß, helle Lichtkante, kein Schatten | Glas 82 % |
| **Minimal Hell** | ruhig, deckend | #F5F6F8 einfarbig, keine Atmosphäre | weiß, feine Linie | fast deckend, ohne Unschärfe |
| **Deep Dark** | echtes Schwarz (OLED) | #000000 | Glas 6 → 4,5 % Weiß, sehr zurückhaltende Kanten | Glas 84 % |

Themewechsel blenden alle Farbrollen weich über (450 ms); bei reduzierter Bewegung sofort.

## 3. Farbrollen (Auszug, siehe `PaletteSpec.kt`)

| Rolle | Glas Hell | Glas Dunkel | Minimal Hell | Deep Dark |
|---|---|---|---|---|
| Text | #0E141C | #F2F4F7 | #0E141C | #F5F5F7 |
| Sekundärtext | #454F5C | #AEB6C1 | #47505C | #A3A6AD |
| Tertiärtext | #535D6A | #A0A9B5 | #58616D | #8E9199 |
| Erfolg | #0F6A39 | #5DD394 | #0F6A39 | #5DD394 |
| Warnung | #8A4E00 | #F2B44C | #8A4E00 | #F2B44C |
| Kritisch | #AD2822 | #FF7B70 | #AD2822 | #FF7B70 |
| Hinweis | #245885 | #93C6EA | #245885 | #93C6EA |

**Akzentfarben** (hell / dunkel): Ocean Blue #1B58B3 / #8DB9FF · Arctic Cyan #006680 / #6DD3EA · Violet #5F41C2 /
#BBA6FF · Emerald #156E45 / #6CD6A1 · Amber #8A5000 / #F3B556 · Rose #A82B58 / #FF92B6 · Graphite #38424E / #C8D0DA ·
**Systemfarbe** (Material You aus dem Hintergrundbild, wird zur Laufzeit geprüft).

### Kontrast – Nachweis

`ContrastTest` (JVM, `./gradlew :ui:designsystem:testDebugUnitTest`) prüft **jede Kombination aus Theme und Akzent**:

* Text, Sekundär-, Tertiär-, Akzent-, Erfolgs-, Warn-, Kritisch- und Hinweistext ≥ **4,5 : 1** auf allen Untergründen:
  Hintergrund (oben/Mitte/unten), derselbe mit jedem Lichtfeld in voller Stärke, Inhaltsglas darüber, deckende
  Flächen, Glas ohne Unschärfe.
* Text und Sekundärtext auf **schwebendem Glas über rein weißem und rein schwarzem Inhalt** ≥ 4,5 : 1 (Reiterleiste
  über Bildvorschauen in Phase 3).
* Schrift auf Akzentflächen ≥ 4,5 : 1; Diagrammbogen (Akzent und Verlaufsende) gegen seine Spur ≥ 3 : 1.
* **Neu in Phase 3:** Text und Sekundärtext auf **gefüllten Flächen** (Kategorien, Suchfeld, ausgewählte Zeilen)
  über jedem Untergrund; alle Rollen inklusive Akzent und Kritisch auf **Aktionsgruppen in Blättern und Dialogen**.
  Der Test fand zunächst zu geringe Kontraste (Sekundär-, Tertiär-, Akzent- und Kritisch-Text auf Füllung bzw. Akzent-Auswahl, bis
  hinunter auf 2,9 : 1) – behoben: Auswahl jetzt neutral gefüllt (plus Haken), Platzhalter in Sekundärschrift,
  zerstörerische Bestätigung als rote Schrift auf neutraler Fläche wie bei Apple.

Ergebnis: **alle Paare erfüllt** (knappste Werte ≈ 4,5–4,7 : 1, z. B. Emerald-Akzenttext auf dem hellen Hintergrund
im Lichtfeld). Der Test hat während der Entwicklung drei Verstöße gefunden (Verlaufsende des Rings bei Emerald und
Amber im hellen Theme, 2,9 : 1; Emerald-Akzenttext bei einem zu kräftigen Akzent-Lichtfeld, 4,4 : 1) – behoben.

## 4. Material

* **Inhaltsglas** (`Modifier.glassPanel`): senkrechter Verlauf, Glanz im oberen Drittel, Lichtkante oben (hell →
  transparent), Schattenkante unten; im hellen Thema ein weicher Schatten (Tiefe), im dunklen trägt Licht die Tiefe.
  Keine Echtzeit-Unschärfe – ruhig, lesbar, sparsam.
* **Schwebendes Glas** (`GlassSurface`): Ausschnitt des Inhalts dahinter mit `RenderEffect`-Unschärfe und leicht
  erhöhter Sättigung, Tönung, Glanz, zweifarbige Kante. Fängt Berührungen ab (nichts „rutscht“ zum Inhalt durch).
* **Atmosphäre**: drei radiale Lichtfelder, statisch. Der Akzent färbt eines davon leicht.
* **Kantenübergang** unter der Statusleiste: zeichnet dieselbe Atmosphäre und blendet sie mit einer Maske aus – keine
  sichtbare Farbkante.

## 5. Effektstärke

| | Minimal (Leistungsmodus) | Ausgewogen (Vorgabe) | Immersiv |
|---|---|---|---|
| Unschärfe schwebender Leisten | aus | 26 dp, Sättigung 1,35 | 38 dp, Sättigung 1,6 |
| Inhaltsglas | deckende Flächen mit Linie | Glas | Glas |
| Atmosphäre | aus | 70 % | 100 % (= geprüfter Höchstwert) |
| Glanz, Lichtkanten | aus | 80 % | 100 % |
| Dekorative Bewegung (Einblenden der Übersicht) | aus | an | an |

„Immersiv“ macht Glas **nicht** durchsichtiger als die geprüfte Tönung – Lesbarkeit geht vor Effekt. Auf
Low-RAM-Geräten bleibt die Unschärfe automatisch aus.

## 6. Typografie

Inter (Oberfläche) und Inter Display (Titel, große Zahlen), SIL OFL 1.1. Alle Zahlenstile mit gleich breiten Ziffern
(`tnum`). Stufen: Bildschirmtitel 32 sp, Kartentitel 19 sp, Überschrift 16 sp, Text 15 sp, Erläuterung 13 sp,
Beschriftung 12 sp, Reiter 11 sp (wächst nur bis 130 % mit der Systemschrift). Alle Größen in sp.

## 7. Abstände, Radien, Bewegung

* Raster 4 dp; Seitenrand 20 dp; Karten 18 dp Innenabstand, 14 dp Abstand; Inhalt höchstens 760 dp breit.
* Radien: 10 · 14 · 24 (Karten) · 30 · 32 dp (Leisten) – bewusst nur fünf Stufen.
* Bewegung: Rückmeldung 110–160 ms, Übergänge 300–420 ms, Themewechsel 450 ms. Bereichswechsel als Überblendung mit
  leichter Tiefe, Unterseiten gleiten von rechts. Auswahl-Linsen als Feder ohne Überschwingen. Speicherring läuft beim
  ersten Wert ruhig ein (900 ms), danach gleitet er kurz. Bei „Animationen entfernen“ (Android) bzw. „Bewegung
  reduzieren“ (App): kurze Überblendungen, Werte springen.

## 8. Symbole „Aether Line“

Eigener Satz (70 Symbole, davon 37 neu in Phase 3: Dateiarten, Dateiaktionen, Bewegung): 24-dp-Raster, 1,7-dp-Linie, runde Enden und Ecken; Punkte als gefüllte Kreise.
Vorschau ohne Gerät: `python3 tools/icons/preview.py out.html`. Keine Marken- oder Herstellersymbole.

## 9. Navigation

* **Telefon:** Reiterleiste aus Glas mit vier Bereichen (Übersicht, Dateien, Speicher, Gerät) und daneben eine runde
  Glasschaltfläche für die Einstellungen – so bleiben die Beschriftungen lesbar und alle fünf Bereiche einen Tipp
  entfernt. Die Auswahl zeigt eine gleitende Linse (nicht nur Farbe).
* **Breite Fenster (≥ 600 dp):** Leiste links mit allen fünf Bereichen.
* Beide schweben über dem Inhalt, der mit Unschärfe durchscheint, und halten Systemgesten frei.

## 10. Bausteine

`Panel`, `PanelHeader`, `ScreenTitle`, `SectionLabel`, `InfoRow`, `ReadingRow` (zeigt Wert oder Grund des Fehlens,
kennzeichnet „berechnet“), `StatusBadge`, `Notice`, `NavRow`, `ToggleRow`, `SegmentedControl`, `AccentSwatch`,
`ThemeTile` (Vorschau mit den echten Farben des Themes), `PillButton`, `ValueWithUnit`, `IconBadge`; Diagramme
`StorageRing`, `CapacityBar`, `LevelScale`, `BatteryGlyph`. Alle mit TalkBack-Beschriftung; Berührflächen ≥ 48 dp.

**Neu in Phase 3:**
* `GlassSheet` (Blatt von unten wie das Aktionsblatt in iOS), `SheetHeader`, `ActionGroup`/`ActionRow`/`ActionDivider`.
* `GlassDialog` (zwei gleich breite Schaltflächen, bestätigende rechts; zerstörerisch = rote Schrift) und `GlassModal`
  (für Fragen, die beantwortet werden müssen – z. B. Namenskonflikt; nicht versehentlich schließbar).
* `GlassTextField` (gefüllt, Fehler in Worten unter dem Feld, Löschen-Knopf).
* `GlassToolbar` (Werkzeugleiste der Auswahl an der Stelle und in der Höhe der Reiterleiste), `SelectionMark`
  (Kreis bzw. Kreis mit Haken – Bedeutung durch Form, nicht nur Farbe).
* `CompassDial`, `MetricTile`, `HeroValue` (Bewegung).
* Im App-Modul: Dateizeile und Dateikachel mit Vorschaubild, Pfadleiste, Darstellungsmenü, Fortschrittskapsel mit
  Restzeit, Rückmeldung mit „Widerrufen“.

Bewegung ist ruhig und folgt „Bewegung reduzieren“: Blätter und Leisten blenden kurz über, der Kompass springt statt
zu gleiten, Vorschaubilder blenden ein.
