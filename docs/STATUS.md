# Prüfstand – was gebaut und getestet ist (ehrlich)

Stand: 06.11.2026 · Version 2.1.0 (Build-Lauf 18, Commit `a5dae52`)

## Umgebung

Entwickelt unter Linux (Logik und Tonhöhen-Verfahren dort zusätzlich nativ übersetzt und geprüft), gebaut und
geprüft mit GitHub Actions:

| Rechner | System | Werkzeuge | Aufgabe |
|---|---|---|---|
| Apple Silicon | macOS 26.7 | Xcode 26, Swift 6.3.3 | Universal-Build (arm64 + x86_64), **alle Tests**, alle Vorschaubilder **mit echtem Liquid Glass** und in der Rückfall-Darstellung, Messlauf mit 10.000 Titeln, DMG |
| Intel (x86_64) | macOS 15 | Xcode 16 | **alle Tests nativ in x86_64** |
| Apple Silicon | macOS 26 | Xcode 26 | Nachstellen und Beheben eines Absturzes (Raster), Version 2.0 und 2.1 im Vergleich |

**Hinweis:** GitHub bietet macOS 14 seit November 2026 nicht mehr an („configuration … is not supported“);
Apple-Silicon-Rechner mit macOS 15 bzw. 26 wurden am 06.11.2026 zeitweise nicht zugeteilt („not acquired …
capacity constraints“). Der Starttest der fertigen DMG (Einhängen, Installieren, alle Ansichten) lief deshalb
nur, sofern unten ausdrücklich angegeben.

## Übersicht

| Stufe | Ergebnis |
|---|---|
| **App gebaut** | ✅ Universal Binary (`x86_64 arm64`), Mindestversion in beiden Teilen macOS 13.0, ad-hoc signiert, `codesign --verify` ohne Befund („valid on disk“, „satisfies its Designated Requirement“) |
| **DMG** | ✅ `Music Library.dmg` (≈ 14,0 MB), `hdiutil verify` gültig, SHA-256 `34b15bba0a4323e34fd6519efc6773a7d7189b32dd4f647e4a17db9c7de4f55a` |
| **Tests macOS 26, Apple Silicon** | ✅ **470 von 470 bestanden** |
| **Tests macOS 15, Intel** | ✅ **470 von 470 bestanden** |
| davon neu in 2.1 | 44 Tests: Hinzufügedatum (Auswahl der Quelle, Rekonstruktion, Speicherung je Datei, nie überschrieben, Erhalt nach Neustart, Sortierung Titel und Alben in beiden Richtungen, Apple-Musik-XML, Datenbank-Ergänzung einer 2.0-Datenbank), Zufall nach Alben (Titelreihenfolge, kein direktes Wiederholen, alle Reihenfolgen kommen vor, Ein/Aus), neue Einstellungen, 20 Tests des portierten Tonhöhen-Verfahrens, Klangtests |
| **Equalizer im Klang** | ✅ jedes Preset (Neutral, Bass Boost, Rock, Pop, Klassik, Jazz, Gesang, Elektronisch) an fünf Frequenzen gemessen und mit der Filterformel verglichen (Abweichung ≤ 1,5 dB); EQ aus → neutral |
| **Tonhöhe im Klang** | ✅ Frequenz ±0,1 / +0,5 / ±1 / +3 / +12 Halbtöne, Mono und Stereo, Bass (55 Hz) und Höhen (3 kHz); kein Übersteuern. **Anschläge** (+2 / −3 Halbtöne): Vorecho Apple-Verfahren (2.0) −6,0 / −10,2 dB, Android-Verfahren (2.1) **−25,0 / −31,9 dB**. **Stehender Akkord** (+2): Störanteil Apple −53,0 dB, Android-Verfahren −48,7 dB |
| **Pegelanalyse (Visualizer)** | ✅ 1-kHz-Ton landet im richtigen Band (Pegel 0,90 bei −6 dBFS, übrige Bänder 0,00); ohne neues Audio → Ruhe; Rechenzeit je Bild 0,41 ms (Testbuild ohne Optimierung) |
| **Vorschaubilder macOS 26** | ✅ **alle 97 Ansichten × hell/dunkel = 194 Bilder mit echtem Liquid Glass** und 194 in der Rückfall-Darstellung, fehlerfrei; die neuen Ansichten wurden angesehen |
| **Absturz macOS 26 (auch 2.0)** | ✅ nachgestellt (2.0 und 2.1 stürzen im kompakten Album-Raster ab), Ursache belegt (Rollbalken ↔ Kachelgröße), behoben und mit immer sichtbaren Rollbalken erneut geprüft |
| **Messlauf 10.000 Titel** | ✅ auf macOS 26 (Apple Silicon) – siehe [PERFORMANCE.md](PERFORMANCE.md) |

## Testplan des Auftrags (§ 15)

| Bereich | Prüfung |
|---|---|
| Sortierung Hinzugefügt (Titel/Alben, beide Richtungen, nach Neustart) | Test (Logik + Datenbank + Neustart) und Vorschaubild |
| Löschen (entfernen, Papierkorb, Album) | Logik vorhanden seit 2.0 (`removeTracks`); Dialog als Vorschaubild; **Klicks nicht automatisiert** |
| Visualizer | Test der Analyse; Vorschaubild der Balken (feste Werte, klein und groß) |
| Tonhöhe | Klangtests (s. o.); **nicht über Lautsprecher angehört** |
| Equalizer | jedes Preset im Klang gemessen; Fenster an/aus als Vorschaubild; eigene Presets (Vorschaubild + Speichertest) |
| Zufall (Titel, Alben, Playlist, Interpret, Genre, Favoriten) | Logik getestet (Alben-Modus, Durchgänge, Codierung); Zuordnung der Schaltflächen im Code geprüft |
| Mehrfachauswahl, Sammelbearbeitung, Album erstellen | Vorschaubilder (Auswahlleiste, Dialog); Schreiben nur geänderter Felder ist Logik seit 2.0; **Aufziehen mit der Maus nicht automatisiert** |
| Cover und Hintergrund | Vorschaubilder (größte Covergröße, sechs Hintergründe, hell/dunkel) |
| Mini-Player in fünf Größen | Vorschaubilder aller fünf Größen, „Sehr groß“ und „Riesig“ zusätzlich im schmalen Fenster |

## Nicht geprüft

Siehe [NICHT_UMGESETZT.md](NICHT_UMGESETZT.md): Bedienung von Hand, Wiedergabe über Lautsprecher, echte
Musiksammlung, Apple-Musik-Zugriff mit echter Mediathek, macOS 13, echte Intel-Hardware, Gatekeeper.
