# Technische Entscheidungen

Stand 26.10.2026 · Phase 1. Kurz begründet; Änderungen in späteren Phasen werden hier ergänzt.

## 1. Werkzeugkette: identisch mit deinen anderen Projekten

AGP 9.3.1, Gradle 9.6.1, Kotlin 2.4.21, Compose-BOM 2026.09.00, Activity 1.13.0, Lifecycle 2.11.0, DataStore 1.3.0,
Core 1.19.1, kotlinx-coroutines 1.11.0 – genau die Versionen aus Filmbibliothek 7.4.2, Musikbibliothek 1.3.0 und
DriveGlass 1.1.0. Vorteil: Android Studio auf deinem Mac hat alles bereits geladen; die Kombination ist laut
JetBrains-Kompatibilitätstabelle freigegeben (Kotlin 2.4.21 unterstützt AGP bis 9.3.1). `compileSdk 37`,
`targetSdk 36`, `minSdk 31` (Android 12) wie in den anderen Projekten – Android 12 bringt `RenderEffect` für echtes
Glas, `StorageVolume.getDirectory()` und die thermische Reserve mit.

## 2. Module

| Modul | Art | Inhalt | Warum getrennt |
|---|---|---|---|
| `app` | Android-App | Aktivität, Navigation, Bildschirme, ViewModels, Einstellungen | |
| `ui:designsystem` | Android-Bibliothek | Themes, Farben, Schrift, Glas, Symbole, Bausteine, Diagramme | ein Ort für jede Farbe und jeden Abstand |
| `core:model` | reines Kotlin | Datenmodelle, Formatierung, Deutungsregeln (Akku, Thermal, Speicher), Hinweise, Einstellungsformat | schnell auf der JVM testbar, ohne Android |
| `core:files` | reines Kotlin | Dateiarten, Sortierung, Namensregeln, Auflisten, Papierkorb, **alle Dateivorgänge** (Kopieren, Verschieben, Löschen, Umbenennen, ZIP, Text sichern), Suche im Dateisystem | sicherheitskritisch – gegen echte Dateien auf der JVM getestet |
| `platform:storage` | Android-Bibliothek | Speichervolumes, Kapazität, „Zugriff auf alle Dateien“, Medienindex (Kategorien, Suche), Vorschaubilder, Übergabe an andere Apps (FileProvider), Medienindex nachziehen | Dateizugriffe nie aus der Oberfläche |
| `platform:device` | Android-Bibliothek | Akku, Thermalstatus, Geräteübersicht, **GPS/GNSS, Barometer, Kompass** | Systemdienste hinter klaren Schnittstellen |

Abhängigkeiten nur in eine Richtung: `app` → alles; `ui:designsystem` und `platform:*` → `core:*`; `core:files` und
`core:model` → nichts (außer kotlinx-coroutines). Geplant: `core:analysis` (Phase 5).

Bewusst **kein** eigenes „domain“-Modul mit Use-Case-Klassen: Bei dieser Größe würde es nur Weiterleitungen
enthalten. Die Deutungsregeln liegen dort, wo sie testbar sind – in `core:model`.

## 3. Keine Navigationsbibliothek

Eigene kleine Navigation (`navigation/Navigator.kt`, ca. 150 Zeilen): fünf Bereiche mit je eigenem Verlauf, Zurück
schließt erst Unterseiten, dann geht es zur Übersicht; erneutes Antippen führt an den Anfang bzw. nach oben. Zustand
übersteht Drehen und Prozessende. Navigation Compose bzw. Navigation 3 hätten neue Abhängigkeiten gebracht, ohne dass
Phase 1–3 etwas davon brauchen, was nicht schon da ist. Sollte später Tiefennavigation (Links von außen) nötig werden,
lässt sich der Navigator austauschen, ohne Bildschirme zu ändern (sie bekommen nur Rückrufe).

## 4. Zustand und Datenfluss

* `platform:*` liefern `Flow`s; `AppGraph` teilt laufende Quellen (`shareIn` mit `WhileSubscribed(5 s)`): Akku,
  Thermalstatus und Speicher werden nur gelesen, solange ein Bildschirm sie zeigt.
* ViewModels kombinieren die Flüsse zu einem Zustand je Bildschirm (`stateIn`); die Oberfläche liest ihn mit
  `collectAsStateWithLifecycle`.
* Jeder Wert ist ein `Reading` – entweder Wert mit Herkunft (gemeldet/berechnet/geschätzt + Quelle) oder ein
  beschriebener Grund für sein Fehlen (`Missing`). Es gibt keinen Weg, „0“ oder einen Ersatzwert anzuzeigen, wenn
  Android nichts liefert.

## 5. Speicher: Zahlen wie in den Android-Einstellungen

Interner Speicher über `StorageStatsManager` (Kapazität wie im Handel angegeben, „frei“ inklusive Zwischenspeicher,
den Android selbst löscht) – dieselben Zahlen wie in den Einstellungen; ergänzend `StatFs` der Datenpartition.
Daraus werden zwei **gekennzeichnete** Werte berechnet: freigebbarer Zwischenspeicher (= frei − sofort verfügbar) und
der Teil außerhalb der Datenpartition (System, Firmware, Rundung). Einheiten dezimal (1 GB = 10⁹ Byte) wie Android.

## 6. Thermalstatus ≠ Temperatur

Angezeigt werden Akku-Temperatur, Thermalstatus und thermische Reserve – jeweils mit Quelle. Keine Auswertung von
`/sys/class/thermal` o. Ä. (unzuverlässig, teils gesperrt, vom Auftrag ausgeschlossen). Keine eigenen Grenzwerte für
„zu heiß“ – die Einstufung kommt von Android.

## 7. Designsystem

* Farbwerte als reine Zahlen in `PaletteSpec.kt` (ohne Compose) → automatischer Kontrasttest auf der JVM für jede
  Kombination aus Theme und Akzent. Die Systemfarbe (Material You) wird zur Laufzeit mit denselben Regeln geprüft und
  bei zu wenig Kontrast durch Ocean Blue ersetzt (die Einstellungen sagen das).
* `LocalContentColor` wird zentral gesetzt (Lehre aus Musikbibliothek 1.3.0); ein Prüfskript stellt sicher, dass
  jede Schrift und jedes Symbol seine Farbe ausdrücklich aus dem Theme bezieht.
* Glas: Technik aus Musikbibliothek 1.3.0 (auf dem Gerät erprobt) – Inhalt als RenderNode aufzeichnen, Ausschnitt
  hinter der Leiste mit `RenderEffect` weichzeichnen, deckender Grund in der Quelle. Unschärfe nur für schwebende
  Elemente.
* Eigener Symbolsatz „Aether Line“ (Pfade im Code, Vorschau ohne Gerät), statt Material Symbols – eigenständige
  Identität, keine Ressourcendateien.
* Schrift Inter / Inter Display (SIL OFL 1.1) – dieselben Dateien wie in DriveGlass (Latein-Untermenge mit Umlauten,
  gleich breite Ziffern).

## 8. Einstellungen: DataStore statt Room

Phase 1 speichert vier Werte. DataStore Preferences genügt; Room kommt erst, wenn strukturierte Daten entstehen
(Favoriten, Suchverlauf, Analyse-Ergebnisse). Unbekannte Werte fallen auf die Vorgabe zurück (`AppearanceCodec`,
getestet). Sicherung und Geräteübertragung sind ausgeschlossen (`allowBackup=false`, `data_extraction_rules.xml`).

## 9. Berechtigungen nur für echte Funktionen, keine Internet-Berechtigung

`INTERNET` ist nicht deklariert – die App kann technisch keine Daten senden. Ab Phase 3 kommen „Zugriff auf alle
Dateien“, Standort (nur „Bewegung“), Benachrichtigungen (Fortschritt), Vordergrunddienst und „Apps installieren“
hinzu – jeweils mit Erklärung und erst im passenden Moment ([BERECHTIGUNGEN.md](BERECHTIGUNGEN.md)).

## 10. Texte direkt im Code (deutsch)

Wie in deinen anderen Projekten stehen die (deutschen) Texte im Kotlin-Code. Eine Übersetzung ist nicht verlangt;
sollte sie kommen, werden die Texte in `strings.xml` überführt.

## 11. Dateimanager: „Zugriff auf alle Dateien“ als Hauptmodus (Phase 3)

Ein vollwertiger Dateimanager braucht unter Android 11+ `MANAGE_EXTERNAL_STORAGE`: Ohne sie sieht eine App keine
fremden Nicht-Mediendateien (Dokumente, APKs, Archive), darf weder das Hauptverzeichnis noch „Download“ als Ordner
freigeben lassen und schreibt auf SD-Karten nur über den langsamen Umweg des Storage Access Framework. Entschieden
(mit dir abgestimmt): Zugriff auf alle Dateien als Hauptmodus. Ein eingeschränkter Modus ohne ihn ist nicht gebaut –
ohne Zugriff erklärt „Dateien“, wozu er dient.

Folgen der Entscheidung:
* Dateivorgänge über `java.io`/`java.nio` direkt auf den Pfaden – schnell, und SD-Karte/USB funktionieren genauso
  wie der interne Speicher (kein SAF). Deshalb liegt die gesamte Logik in `core:files` und ist auf der JVM gegen echte
  Dateien getestet.
* Kategorien und schnelle Suche über den Medienindex (`MediaStore.Files`, alle eingebundenen Speicher) – mit „Zugriff
  auf alle Dateien“ enthält er auch Dokumente, Archive und APKs.

## 12. Sicherheitsregeln der Dateivorgänge

* **Erst vollständig schreiben, dann ersetzen.** Jede neue Datei entsteht als `*.aether-part` daneben und wird erst
  nach dem letzten Byte (und `fsync`) umbenannt. Eine vorhandene Datei wird bei „Ersetzen“ erst dann ersetzt.
* **Verschieben über Speichergrenzen = Kopieren + Prüfen + Löschen.** Prüfsumme beim Schreiben, Kopie erneut lesen und
  vergleichen; hat sich die Quelle währenddessen geändert, bleibt sie. Erst dann wird das Original gelöscht.
* **Verschieben auf demselben Speicher** ist ein atomares Umbenennen – nichts wird kopiert.
* **Papierkorb je Speicher** (`.AetherTrash` in der Wurzel, mit `.nomedia`): Umbenennen statt Kopieren, mit
  Metadaten neben dem Objekt (wiederherstellbar auch nach Neuinstallation oder in einem anderen Telefon). Geht das
  nicht, wird nicht ersatzweise gelöscht.
* **Nie automatisch löschen.** Endgültiges Löschen nur nach Bestätigung; der Papierkorb leert sich nie von selbst.
* **Absturzsicher:** Ein Journal (app-privat) merkt sich unfertige Dateien; der nächste Start räumt sie auf oder
  vollendet einen begonnenen Austausch.
* **Konflikte** fragt AETHER (Ersetzen, Beide behalten, Überspringen, bei Ordnern Zusammenführen; „für alle“), ohne
  Rücksicht auf Groß-/Kleinschreibung – so behandelt Android den gemeinsamen Speicher. Ein Ordner wird nie gelöscht,
  um Platz für eine Datei zu machen.
* **Ersetzen trifft nur genau den gemeinten Namen.** Auf Speichern, die Groß-/Kleinschreibung unterscheiden (z. B.
  ext4-/NTFS-Sticks), überschreibt das Angleichen der Schreibweise nie eine dritte, anders geschriebene Datei (Befund
  der Durchsicht, mit Tests abgesichert).
* **Berichte sagen, was wirklich geschah** – auch nach einem Abbruch mitten in einem Ordner (jede bereits verschobene
  oder gelöschte Datei wird gemeldet; „nichts geändert“ nur, wenn sich nichts geändert hat).
* **Texte nur verlustfrei bearbeiten:** Lässt sich eine Datei nicht verlustfrei lesen, ist Bearbeiten gesperrt.
* **Namen** nach den Regeln von FAT/exFAT geprüft – ein gültiger Name funktioniert auf jedem Speicher.
* **Unsichere ZIP-Einträge** (`..`, absolute Pfade) werden übersprungen und gemeldet.
* **Vorgänge laufen nacheinander** (eine Warteschlange) – zwei Vorgänge können sich nicht gegenseitig die Dateien
  wegnehmen. Lange Vorgänge laufen in einem Vordergrunddienst (`dataSync`) weiter, wenn man die App verlässt.

## 13. Bewegung als eigene Seite unter „Gerät“

Geschwindigkeit, Höhe, Kurs, Satelliten, Luftdruck und Kompass gehören zur „Device Intelligence“ (Auftrag §8) und
sind aus Phase 6 vorgezogen, weil du sie ausdrücklich wünschst. GPS und Sensoren laufen nur, solange die Seite
sichtbar ist (5 s Nachlauf), es gibt keinen Standort im Hintergrund und keinen Dienst dafür. Die Rechenregeln
(Stillstand, Strecke, Anstieg, Druckhöhe, Kompass-Glättung über Nord) liegen in `core:model` und sind JVM-getestet.

## 14. Eigene Bausteine für Blätter, Dialoge, Felder und Werkzeugleiste

Material-Komponenten bleiben die Grundlage (Verhalten, Zugänglichkeit), werden aber vollständig mit den Farbrollen von
AETHER gestaltet: Aktionsblatt wie in iOS, Dialoge mit zwei gleich breiten Schaltflächen (zerstörerisch = rote
Schrift), Werkzeugleiste der Auswahl an der Stelle der Reiterleiste. `ContrastTest` prüft die neuen Flächen (Füllung,
Auswahl, Blätter) in jeder Theme-/Akzent-Kombination.
