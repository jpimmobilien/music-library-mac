# Testplan und Testergebnisse

Stand 27.10.2026 · AETHER 0.3.0 (Phase 3)

**Kurz:** **226 JVM-Tests grün** – 65 Fachlogik (`core:model`, davon 25 Bewegung), **155 Dateivorgänge gegen echte
Dateien** (`core:files`), 6 Kontrast über alle Theme-/Akzent-Kombinationen. Alle sieben Module gegen Android-API-36-
und AndroidX-Schnittstellen typgeprüft: **0 Fehler, 0 Warnungen**. Prüfskript Theme-Farben: 215 Aufrufe, 0 Verstöße.
Zwei unabhängige Durchsichten: 5 kritische, 5 hohe und alle mittleren Befunde behoben (§1.5). **Nicht** gebaut und
**nicht** auf einem Gerät ausgeführt (kein Android-SDK, kein Google Maven in der Entwicklungsumgebung).

Alles auf einmal (ohne Android Studio): `TOOLCHAIN=… bash tools/typecheck/check-all.sh` (siehe
`tools/typecheck/TOOLCHAIN.md`). In Android Studio: `./gradlew :core:model:test :core:files:test
:ui:designsystem:testDebugUnitTest`.

## 1. Was ausgeführt wurde

### 1.1 JVM-Tests `core:files` – Dateivorgänge gegen echte Dateien (155)

Jeder Test legt echte Ordner und Dateien in einem temporären Verzeichnis an, führt den Vorgang mit der echten
`FileOperationEngine` aus und prüft danach das Dateisystem Byte für Byte. Speichergrenzen (intern ↔ SD-Karte),
volle Ziele, Schreibfehler und Abbrüche werden über Testhaken simuliert.

| Testklasse | Tests | Inhalt |
|---|---|---|
| `CopyTest` | 15 | Dateien und Ordnerbäume samt versteckter Dateien, Inhalte und Änderungszeiten identisch; Kopie in denselben Ordner = Duplikat ohne Rückfrage; Konflikte (Ersetzen, Beide behalten → „Name 2“, Überspringen, Zusammenführen, „für alle“ getrennt für Dateien/Ordner) ohne Rücksicht auf Groß-/Kleinschreibung; **Schreibfehler beim Ersetzen zerstört das Original nie**; Platz wird vorab geprüft, kein Platz beendet den Rest; Ordner in sich selbst verweigert; Verknüpfungen werden gemeldet, nicht verfolgt; eigene Teildateien/Papierkorb werden nie kopiert |
| `CaseSensitivityTest` | 9 | **neu nach der Durchsicht:** Ersetzen/Umbenennen auf Speichern, die Groß-/Kleinschreibung unterscheiden, trifft nur genau den gemeinten Namen – eine dritte, anders geschriebene Datei bleibt immer erhalten |
| `PartialReportTest` | 7 | **neu nach der Durchsicht:** Abbruch mitten im Verschieben/Löschen/Kopieren meldet jede bereits verschobene, gelöschte bzw. fertige Datei; Verknüpfungen werden wahrheitsgemäß als „bewusst nicht kopiert“ gemeldet |
| `MoveTest` | 11 | gleicher Speicher = atomares Umbenennen; anderer Speicher = Kopie + SHA-256-Prüfung + erst dann Löschen; **Prüfung schlägt fehl → Original bleibt**; **Quelle während der Kopie geändert → Original bleibt**; unerwarteter Speicherwechsel → ebenfalls geprüfte Kopie; Ersetzen/Zusammenführen; übersprungene Objekte bleiben in der Quelle; Ordner in sich selbst und Speicherwurzel verweigert; Platz vorab geprüft |
| `TrashTest` | 11 | in den Papierkorb desselben Speichers; **geht Umbenennen nicht, wird weder kopiert noch gelöscht**; außerhalb bekannter Speicher und Speicherwurzel verweigert; Wiederherstellen an den Ursprungsort (fehlende Ordner werden angelegt, belegter Name → beide behalten); aus dem Papierkorb löschen; gefälschte/veraltete Einträge werden nicht gefunden; beschädigte Einträge übergangen, nicht gelöscht; endgültig löschen folgt keinen Verknüpfungen |
| `ArchiveTest` | 10 | ZIP mit Ordnern und Zeiten erstellen (nie überschreiben, Name geprüft); Entpacken in einen Ordner neben dem Archiv, Inhalt identisch; **Zip-Slip-Einträge werden nie geschrieben**; alte IBM437-Namen; kein ZIP → „nicht unterstützt“; Platz vorab geprüft; gleiche Namen im Archiv überschreiben sich nicht |
| `RenameCreateTest` | 9 | Umbenennen (auch nur Schreibweise), ungültige und reservierte Namen, Konflikte, Ordner erstellen |
| `WriteTextTest` | 8 | sicheres Sichern über Teildatei, inzwischen geänderte Datei wird **nicht** überschrieben, Kodierung bleibt erhalten, BOM, Absturz-Journal |
| `DirectoryReaderTest` | 7 | Auflisten, versteckte Objekte zählen, eigene Dateien von AETHER ausgeblendet, `Android/data` als gesperrt gemeldet, fehlende Ordner |
| `TextPreviewReaderTest` | 9 | Kodierungen, Kürzen bei 512 KB, Binärdateien erkennen, **nicht verlustfrei lesbare Dateien erkennen** (Bearbeiten gesperrt) |
| `FileNamesTest` | 6 | FAT/exFAT-Regeln, Länge in Byte, freie Namen wie im Finder („Foto 2.jpg“, „Urlaub 2024 2“, „.tar.gz“) |
| `TempJournalTest` | 6 | nach einem Absturz nur die eingetragenen Teildateien entfernen; begonnenen Austausch vollenden statt löschen; Sonderzeichen in Pfaden; beschädigtes Journal wird toleriert |
| `OperationTextsTest` | 10 | Titel und Zusammenfassungen sagen genau, was geschah (abgebrochen, unvollständig, übersprungen, geteiltes Verschieben), „3 von 12 Objekten“ |
| `CancellationTest` | 5 | Abbruch mitten im Kopieren (keine Teildateien, Teilbericht), beim Verschieben über Speicher (Quelle bleibt), beim Entpacken (Teilordner entfernt), während der Konfliktfrage (nichts geschrieben) |
| `FileSearchTest` | 5 | gründliche Suche: Groß-/Kleinschreibung, Umlaute in beiden Unicode-Formen, Papierkorb und Teildateien ausgeschlossen, Trefferobergrenze |
| `FileSortingTest` | 5 | natürliche Sortierung, Ordner zuerst, alle Kriterien und Richtungen |
| `IoErrorsTest` | 5 | Fehler in verständliche Gründe übersetzt (kein Platz, nur lesbar, zu groß für FAT32 …) |
| `FileTypesTest` | 4 | Endung → Art und MIME-Typ, MIME-Typ hat Vorrang, Kategorien-Endungen |
| `ZipContentsTest` | 11 | ZIP-Inhalt auflisten, unsichere Einträge, Verschlüsselung und nicht unterstützte Packverfahren erkennen, selbstentpackende Archive, präpariertes ZIP64 ohne Überlauf, Obergrenze, SHA-256 |
| `FolderStatsCalculatorTest` | 2 | Ordnergröße und -inhalt, unlesbare Teile als „unvollständig“ |

Hinweis zur Umgebung: Tests mit Umlauten in Dateinamen brauchen eine UTF-8-Umgebung (`LC_ALL=C.UTF-8`, so in
`check-all.sh`) – wie Android selbst. In Android Studio auf dem Mac ist das Standard.

### 1.2 JVM-Tests `core:model` (65) und Kontrast (6)

| Testklasse | Tests | Inhalt |
|---|---|---|
| `MotionModelsTest` | 25 | Satellitensysteme, Zweifrequenz ohne Doppelzählung, Stillstand innerhalb der Messgenauigkeit, Kurs nur in Bewegung, Höhenquellen, Kompass über Nord, Himmelsrichtungen, geografisch/magnetisch Nord, Druckhöhe wie `SensorManager.getAltitude`, Strecke (Stillstand, gerade Strecke, ungenaue Fixes und Sprünge verworfen), Anstieg mit Schwelle und ohne Wechsel der Höhenbezugsart, Pausen, Durchschnitt nur über Bewegung, Zahlenformate |
| `FmtTest` | 9 | wie 0.1.0, neu: Dateidatum („Heute, 14:32“, „Gestern“, „12. März“, „12.03.24“, Zukunft) |
| `ByteFormatTest` | 3 | Dezimal-Einheiten wie Android |
| `StorageModelsTest`, `BatteryInterpreterTest`, `ThermalTest`, `DeviceSummaryTest`, `StatusLineTest`, `InsightsTest`, `AppearanceCodecTest` | 28 | wie 0.1.0 |
| `ContrastTest` | 6 | wie 0.1.0, **neu:** Text auf gefüllten Flächen, ausgewählten Zeilen und in Blättern/Dialogen in jeder Theme-/Akzent-Kombination. Fand zunächst Werte bis hinunter auf 2,9 : 1 (Akzent-Auswahl im dunklen Glas) – behoben (neutrale Auswahl, Platzhalter in Sekundärschrift, zerstörerische Bestätigung als rote Schrift auf neutraler Fläche) |

### 1.3 Typprüfung des Android-Codes

Alle Kotlin-Quellen von `app` (43 Dateien), `ui/designsystem` (15), `platform/storage` (12), `platform/device` (5)
und `core:files` (22) in Abhängigkeitsreihenfolge mit Kotlin 2.4.21 samt Compose-Compiler, Warnungen als Fehler.
Schnittstellen: Android **API 36** aus den offiziellen API-Beschreibungen – für Phase 3 **erweitert um
`android.location`** (LocationManager, GnssStatus, AltitudeConverter) **und `android.graphics.pdf`** (PdfRenderer),
die in eigenen Modulen der AOSP-Quellen liegen – sowie AndroidX (Compose 1.12, Material 3 1.4, Activity 1.13,
Lifecycle 2.11, Core 1.19, DataStore 1.3).

**Ergebnis: 0 Fehler, 0 Warnungen.** Gefunden und behoben während der Entwicklung u. a.: Namensüberdeckung eines
Zustands in `produceState` (hätte den falschen Wert gesetzt), Composable-Zugriff in einer Übergangs-Lambda.

Nicht abgedeckt: Ressourcen-Linking, Manifest-Zusammenführung, Lint (`NewApi` …), Bytecode, R8, Laufzeit.

### 1.4 Statische Prüfungen und Vorschauen

* `tools/ui-check/uncolored.py`: 215 `Text`/`Icon`-Aufrufe, jeder mit Farbe aus dem Theme; keine festen Farben
  außerhalb des Designsystems. **0 Verstöße.**
* `tools/icons/preview.py`: alle 70 Symbole hell/dunkel gerendert und begutachtet (`docs/design/symbole.png`).
* `tools/design-preview/files_preview.py`: nachgebaute Vorschau von Dateien, Ordner mit Auswahl, Raster mit
  Fortschritt, Bewegung (`docs/design/dateien-vorschau.png`). Befund: Kategoriekacheln brachen auf 360 dp um →
  Anzahl und Größe jetzt in zwei Zeilen, alle Kacheln gleich hoch.

### 1.5 Unabhängige Durchsicht Phase 3

Zwei getrennte Prüfdurchgänge ohne Kenntnis der Entstehung – einer für Engine, Plattform, Vorgänge, Oberfläche und
Bewegung, einer für Schnellansicht und Informationen. Beide haben die Befunde der Engine mit eigenen Tests gegen
echte Dateien nachgestellt. **Alle Befunde der Stufen KRITISCH, HOCH und MITTEL sind behoben**, dazu die meisten
niedrigen; was bewusst bleibt, steht in [GRENZEN.md](GRENZEN.md).

**Kritisch (Datenverlust/Absturz) – behoben:**
1. „Ersetzen“ konnte auf Speichern, die Groß-/Kleinschreibung unterscheiden (z. B. ext4/NTFS-Stick), beim
   anschließenden Angleichen der Schreibweise eine **zweite, anders geschriebene Datei überschreiben**
   („A.txt“/„a.txt“). → Der letzte Umbenennungsschritt ersetzt nie; genaue Namen haben Vorrang. Neue Tests.
2. Sichern einer Textdatei mit einzelnen ungültigen Bytes veränderte **Bytes, die man nie angefasst hat** (und
   wechselte ggf. still zu UTF-8). → Solche Dateien werden erkannt; Bearbeiten ist dann gesperrt, mit Erklärung.
3. Ungesicherte Änderungen gingen beim erneuten Antippen des Bereichs bzw. über die Pfadleiste **ohne Rückfrage**
   verloren. → Navigation fragt vorher („Änderungen verwerfen?“).
4. „Verwerfen“ hielt ein noch wartendes Sichern nicht auf. → Wartendes Sichern wird abgebrochen.
5. Ein präpariertes ZIP ließ die Größensumme überlaufen → **Absturz** in der Anzeige. → Summen begrenzt.

**Hoch – behoben:**
6. Abbruch beim Verschieben über Speichergrenzen / endgültigen Löschen meldete „Es wurde nichts geändert“, obwohl
   schon Dateien verschoben bzw. gelöscht waren. → Bericht zählt auch Teile, Text sagt, was wo liegt.
7. „Widerrufen“ nach dem Löschen in den Papierkorb funktionierte nie (Papierkorb-Pfade fehlten im Bericht).
8. „Installiert: Nein“ für installierte Apps (Paketsichtbarkeit) → „Nicht feststellbar“.
9. Texteditor schrumpfte bei offener Tastatur auf wenige Zeilen (Tastaturhöhe doppelt abgezogen).

**Mittel – behoben (Auswahl):** geschlossene Seiten gaben ihre ViewModels nie frei (alte Auswahl kam zurück,
Dateibeobachter liefen weiter); Vorgang blieb bis zu 15 s „bei 100 %“ stehen (Medienindex wird jetzt danach im
Hintergrund abgeglichen); Vordergrunddienst konnte beim Beenden bzw. bei aufgebrauchtem Tageskontingent (Android 15+)
abstürzen; „Für alle übernehmen“ ohne TalkBack-Zustand; Fortschritt überflutete TalkBack; Sortieren großer Ordner im
Hauptthread; Medienindex behielt Einträge bewegter Dateien; PDF schloss den Renderer im Hauptthread; Bilder wurden
beim schnellen Wischen unbegrenzt dekodiert; …

**Niedrig – behoben (Auswahl):** deutsche Formen („3 von 12 Objekten“), Berührflächen < 48 dp (Pfadleiste),
doppelte Listenschlüssel bei zwei gleich benannten Speichern (Absturz), Rückmeldung respektiert „Zeit zum Reagieren“,
Tastaturfokus in Dialogen, „x.zip.zip“, Werkzeugleiste ohne Schreibrecht, Favoriten in gelöschten Ordnern, …

### Durchsicht Phase 1 (0.1.0)

Ein getrennter Prüfdurchgang ohne Kenntnis der Entstehung hat den gesamten Code auf Build-, Laufzeit- und
Regelverstöße durchgesehen. Kein Build-Fehler; gefunden und **behoben**:

1. Seitenleiste auf Telefonen im Querformat zu niedrig (Einstellungen abgeschnitten) → Seitenleiste erst ab 600 dp
   Breite **und** 480 dp Höhe, sonst Reiterleiste.
2. Nach einmaligem erneuten Antippen sprang ein Bereich bei jeder Rückkehr nach oben → nur neue Antipp-Ereignisse.
3. Nach > 5 s Abwesenheit kurz „Wird gelesen …“ und springende Geräteliste → laufende Werte als `StateFlow` mit
   letztem Stand; Geräteübersicht im ViewModel gehalten.
4. Falsches Theme blitzte beim Start/Drehen auf → Einstellungen beim App-Start geladen, Startbildschirm bleibt bis
   dahin stehen (höchstens 600 ms).
5. Einstellungen zeigten kurz die Vorgaben → bereits geladene Werte.
6. Zwei Datenträger ohne UUID mit gleicher Bezeichnung → doppelter Listenschlüssel (Absturz) → eindeutige Kennung.
7. **Falsche Aussage** über die thermische Reserve („nicht linear zur Temperatur“) – laut Android steigt sie zwischen
   0 und 1 etwa linear → Text korrigiert, Zeile heißt jetzt „Genutzter thermischer Spielraum“.
8. „Belegt“ war berechnet, aber nicht so gekennzeichnet → Kennzeichnung ergänzt.
9. „Wird gelesen …“ konnte stehen bleiben, wenn Android keinen internen Speicher meldet → eigener Hinweis.
10. Bildschirmdichte als Anzeigedichte gekennzeichnet; erste NaN-Antwort der Reserve gilt als „wird gelesen“; ohne
    Akku keine Akkuwerte; Zeitangaben sagen „zuletzt geändert“ bzw. „gelesen“.
11. TalkBack: Hinweise der Übersicht sind jetzt selbst Schaltflächen (vorher leere Schaltfläche + nicht bedienbarer Text).
12. Schalter als Schalter (statt „ausgewählt“), Zurück-Schaltfläche als Schaltfläche (statt Reiter) angesagt.
13. Akzent-Beschriftungen zweizeilig statt abgeschnitten; Legendenpunkt „Frei“ in der Farbe der Ringspur.
14. Geschlossene Unterseiten vergessen ihre Scrollposition; die Speicherorte unter „Dateien“ springen nicht mehr in
    einen anderen Bereich.

Unsicher, aber vorsorglich angepasst: `path="."` in den Sicherungsregeln (Lint).

## 2. Was in dieser Umgebung nicht geprüft werden konnte

* Gradle-Build, APK, Lint; Lauf auf Gerät/Emulator.
* Echter FUSE-Speicher (Groß-/Kleinschreibung, Änderungszeiten), echte SD-Karte und USB-Stick, MediaStore- und
  FileProvider-Verhalten zur Laufzeit, Vordergrunddienst und Benachrichtigung, Paketinstaller.
* GPS, GNSS, Barometer und Kompass auf Hardware.

## 3. Checkliste für den Gerätetest (Pixel 6 Pro und Xiaomi)

Bitte Punkte mit ✘ oder Auffälligkeiten melden – am besten mit Bildschirmfoto. Punkte aus 0.1.0, die schon geprüft
wurden, müssen nicht wiederholt werden; neu sind §3.2–§3.9.

### 3.1 Bau und Start
- [ ] `./gradlew assembleDebug` ohne Fehler; `./gradlew :core:model:test :core:files:test :ui:designsystem:testDebugUnitTest` grün
- [ ] Installation über 0.1.0: Einstellungen (Theme, Akzent) bleiben erhalten
- [ ] Start ohne Berechtigungsabfrage; kein falsch gefärbtes Aufblitzen

### 3.2 Zugriff auf alle Dateien
- [ ] „Dateien“ zeigt die Erklärung; „In den Einstellungen erlauben“ öffnet **direkt** die Seite für AETHER
      (Xiaomi: „Verwaltung aller Dateien erlauben“) – sonst bitte melden, welche Seite erscheint
- [ ] Erlauben, zurück → Dateien-Startseite erscheint sofort (ohne Neustart), Kategorien füllen sich
- [ ] In den Android-Einstellungen wieder entziehen, zurück → Erklärung erscheint wieder; nichts stürzt ab
- [ ] Einstellungen › Datenschutz: Stand aller Berechtigungen stimmt; Antippen öffnet die passende Seite

### 3.3 Durchsuchen und Ansicht
- [ ] Speicherorte: intern und SD-Karte (Xiaomi) bzw. USB-Stick (Pixel) mit Belegung wie in den Einstellungen
- [ ] Ordner öffnen, Pfadleiste antippen (springt zurück), Zurück-Geste, Liste ↔ Raster, Sortierung (Name A→Z
      natürlich: „Foto 2“ vor „Foto 10“), versteckte Objekte ein/aus
- [ ] Vorschaubilder: Fotos, Videos, Albumcover, PDF (erste Seite), APK (App-Symbol) – flüssiges Scrollen in DCIM/Camera
- [ ] `Android/data` öffnen → „Von Android gesperrt“ mit Erklärung (kein leerer Ordner)
- [ ] Mit einer anderen App eine Datei im offenen Ordner anlegen → erscheint (spätestens beim Zurückkehren in AETHER)
- [ ] Kategorien: Zahlen plausibel (z. B. Bilder ≈ Galerie); „Downloads“ und „Zuletzt hinzugefügt“

### 3.4 Vorgänge (bitte mit Testdateien!)
- [ ] Neuer Ordner, Umbenennen (auch nur Groß-/Kleinschreibung: „test“ → „Test“), Endung ändern → Warnhinweis
- [ ] Kopieren und Verschieben in einen anderen Ordner; Konflikt (gleicher Name) → Vergleich und Auswahl; „Beide
      behalten“ ergibt „Name 2“
- [ ] Duplizieren; Komprimieren (ZIP) und wieder Entpacken – Inhalt identisch
- [ ] In den Papierkorb → „Widerrufen“ in der Meldung stellt wieder her; Papierkorb: Wiederherstellen, Endgültig
      löschen, Leeren (jeweils mit Rückfrage)
- [ ] Großen Ordner (> 1 GB) kopieren: Fortschritt mit Restzeit; App verlassen → Benachrichtigung mit Fortschritt und
      „Abbrechen“; Abbrechen → keine halbfertige Datei im Ziel
- [ ] Ordner in sich selbst verschieben → gesperrt mit Erklärung
- [ ] Textdatei öffnen, bearbeiten, sichern; Zurück mit ungesicherten Änderungen → Rückfrage
- [ ] Öffnen mit …, Teilen (eine und mehrere Dateien), APK antippen → Android-Installer (einmalig „Aus dieser Quelle
      zulassen“)

### 3.5 SD-Karte (Xiaomi) und USB-Stick (Pixel)
- [ ] Datei intern → SD **verschieben**: danach auf der Karte vollständig, intern weg; umgekehrt ebenso
- [ ] Papierkorb auf der Karte (eigener Bereich „SD-Karte“ im Papierkorb)
- [ ] Datei > 4 GB auf FAT32-Stick/-Karte kopieren → verständliche Meldung, Original unverändert
- [ ] Karte/Stick in den Einstellungen auswerfen, während ein Ordner davon offen ist → „Ordner nicht mehr
      vorhanden“; Favorit von der Karte erscheint als „gerade nicht verfügbar“
- [ ] Nach dem Kopieren erscheinen Fotos in der Galerie (Medienindex nachgezogen)

### 3.6 Suche
- [ ] Schnell: findet Dateien und Ordner auf allen Speichern, auch mit Umlauten („Übung“, „übung“)
- [ ] Gründlich: findet zusätzlich Versteckte; Fortschritt „… Ordner durchsucht“
- [ ] Suchverlauf erscheint und lässt sich löschen

### 3.7 Bewegung (Gerät › Bewegung)
- [ ] Erklärung vor der Standortabfrage; „Genau“ vs. „Ungefähr“ (ungefähr → Erklärung, Kompass geht trotzdem)
- [ ] Zweimal ablehnen → „App-Einstellungen öffnen“ führt zur richtigen Seite (auch Xiaomi)
- [ ] Standort in den Schnelleinstellungen aus → Hinweis ohne Neustart; wieder an → Suche beginnt selbst
- [ ] Draußen: Zeit bis zur ersten Position, Satellitensysteme, am Pixel 6 Pro L1 + L5 (Zweifrequenz) erwartet
- [ ] Geschwindigkeit gegen Tacho; im Stand „Stillstand innerhalb der Messgenauigkeit“
- [ ] Höhe über Meeresspiegel gegen eine Karte; Ellipsoidhöhe in Deutschland rund 35–50 m höher
- [ ] Eine Etage Treppe → Druckhöhe „Änderung seit Beginn“ etwa +3 m
- [ ] Kompass gegen eine andere Kompass-App: kein Springen über Nord, richtig im Querformat, Kalibrierhinweis in der
      Nähe eines Magneten, Hinweis bei stark gekipptem Gerät
- [ ] GPS-Symbol in der Statusleiste verschwindet etwa 5 s nach Verlassen der Seite
- [ ] Gerät ohne Barometer (falls vorhanden): „Nicht verfügbar auf diesem Gerät“, Anstieg aus GPS

### 3.8 Darstellung und Bedienungshilfen
- [ ] Alle fünf Themes hell/dunkel: Dateilisten, Blätter, Dialoge, Auswahl, Werkzeugleiste gut lesbar
- [ ] „Animationen entfernen“: Blätter/Leisten blenden nur kurz über, Kompass springt
- [ ] Große Systemschrift: Zeilen und Kacheln abgeschnitten?
- [ ] TalkBack: Datei wird mit Name, Art, Größe, Datum angesagt; „Aktionen“ als Aktion verfügbar; in der Auswahl
      „ausgewählt/nicht ausgewählt“; Fortschritt wird angesagt
- [ ] Querformat/Tablet: Liste zweispaltig, Raster passt sich an

### 3.9 Datenschutz
- [ ] Android-Einstellungen › Apps › Aether › Berechtigungen: Dateien, Standort (nur bei Nutzung), Benachrichtigungen –
      kein Internet

### 3.10 Schnellansicht und Bearbeiten (nach der Durchsicht)
- [ ] Notiz bearbeiten, dann „Dateien“ erneut antippen bzw. in der Pfadleiste springen → Rückfrage „Änderungen verwerfen?“
- [ ] Während eines großen Kopiervorgangs sichern → „Wartet auf einen laufenden Vorgang …“; „Sichern abbrechen“ und
      „Verwerfen“ schreiben nichts
- [ ] Tastatur offen (hoch und quer): Editor bleibt sichtbar, Werkzeugleiste über der Tastatur
- [ ] Datei mit gemischter Kodierung bzw. > 256 KB → Bearbeiten gesperrt mit Erklärung
- [ ] Datei während des Bearbeitens in einer anderen App löschen, dann sichern → Hinweis; „Als Kopie sichern“ legt
      „Name 2.txt“ an und öffnet sie
- [ ] Foto in einer anderen App zuschneiden/löschen, zurück → Schnellansicht zeigt den neuen Stand; schnelles Wischen
      durch einen großen Kamera-Ordner ohne Fehlermeldung
- [ ] PDF mit 2×: Kopf von Seite 1 erreichbar; PDF mit > 1000 Seiten öffnet zügig; langer Kassenbon nicht gestaucht
- [ ] ZIP aus 7-Zip/Windows (BZip2/Deflate64) und verschlüsseltes ZIP: Inhalt sichtbar, Entpacken gesperrt mit Hinweis
- [ ] Foto mit ungültigem EXIF-Datum → Aufnahmezeit „Nicht verfügbar“; Foto mit GPS → Hinweis „Enthält Standortdaten“
- [ ] App-Paket: Informationen zeigen „Installiert: Nicht feststellbar“ oder die installierte Version
