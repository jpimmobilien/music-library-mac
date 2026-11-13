# AETHER – Files & Device Intelligence

Dateimanager, Speicherassistent und Gerätediagnose für Android – mit einer eigenständigen Liquid-Glass-Oberfläche.
„PROJECT AETHER“ ist der interne Projektname; der Anzeigename steht zentral in `gradle.properties`
(`aether.appName`).

> **Stand dieses Projekts – bitte zuerst lesen**
>
> * **Version 0.3.0 – Phase 3: Dateimanager und Bewegung.** Neu: vollwertiger Dateimanager mit „Zugriff auf alle
>   Dateien“ für internen Speicher, **SD-Karte und USB-Speicher** (Durchsuchen, Kategorien, Suche, Kopieren,
>   Verschieben, Umbenennen, Papierkorb, endgültig Löschen, ZIP, Textdateien bearbeiten, Schnellansicht, Teilen,
>   APK-Installation) und **„Gerät › Bewegung“** mit Geschwindigkeit, Höhe, Kurs, Satelliten, Luftdruck und Kompass.
> * Erstellt in einer Umgebung **ohne Android-SDK und ohne Zugriff auf Google Maven**: Ein Gradle-Build und damit ein
>   **APK konnten hier nicht erzeugt werden**. Es liegt kein APK bei. Geprüft wurde, was ohne SDK möglich ist
>   ([docs/TESTPLAN.md](docs/TESTPLAN.md)):
>   * **226 JVM-Tests grün** – davon **155 Dateivorgänge gegen echte Dateien** (Kopieren, Verschieben mit Prüfsumme,
>     Papierkorb, Abbruch, Absturz, Groß-/Kleinschreibung …), 65 Fachlogik (inkl. Bewegung), 6 Kontrast in jeder
>     Theme-/Akzent-Kombination.
>   * Alle sieben Module gegen Android-API-36- und AndroidX-Schnittstellen **typgeprüft: 0 Fehler, 0 Warnungen**.
>     Das ist kein vollständiger Build: Ressourcen-Linking, Manifest und Lint liefen nicht.
>   * Prüfskript: jede Schrift und jedes Symbol bezieht ihre Farbe aus dem Theme.
>   * Zwei unabhängige Durchsichten: 5 kritische, 5 hohe und alle mittleren Befunde behoben (u. a. ein Fall, in dem
>     „Ersetzen“ auf einem USB-Stick eine zweite, anders geschriebene Datei überschrieben hätte).
> * **Nicht** geprüft: Lauf auf einem Gerät, echte SD-Karte/USB-Stick, GPS/Barometer/Kompass auf Hardware. Der erste
>   Bau in Android Studio ist der erste echte Build – siehe [Öffnen und Bauen](#öffnen-und-bauen).

---

## Inhalt

1. [Was die App kann](#was-die-app-kann)
2. [Sicherheit deiner Dateien](#sicherheit-deiner-dateien)
3. [Architektur](#architektur)
4. [Öffnen und Bauen](#öffnen-und-bauen)
5. [Installation und erster Start](#installation-und-erster-start)
6. [Gerätetest](#gerätetest)
7. [Weitere Dokumente](#weitere-dokumente)

## Was die App kann

| Bereich | Inhalt |
|---|---|
| **Übersicht** | Gerätename, Statuszeile, Speicherring, Schnellzugriff (Downloads, Bilder, Dokumente, Zuletzt hinzugefügt, Bewegung), Hinweise aus echten Befunden, Gerätestatus, weitere Speicherorte |
| **Dateien** | Zugriff mit Erklärung; Suche (schnell im Medienindex oder gründlich im Dateisystem); Speicherorte mit Belegung; Favoriten; Schnellzugriff; elf Kategorien; zuletzt geöffnet; Papierkorb |
| **Ordner** | Liste/Raster mit Vorschaubildern, Sortierung (Name natürlich, Datum, Größe, Art), versteckte Objekte, Pfadleiste, Auswahl mit Werkzeugleiste, Aktionsblatt (Öffnen, Öffnen mit, Teilen, Informationen, Umbenennen, Kopieren/Verschieben nach, Duplizieren, Komprimieren, Entpacken, Favorit, Papierkorb, Endgültig löschen) |
| **Schnellansicht** | Bilder (Zoom, Wischen), Text (Lesen, Bearbeiten, sicheres Sichern), PDF, ZIP-Inhalt; sonst Informationen und „Öffnen mit …“ |
| **Vorgänge** | Fortschritt mit Restzeit, Abbrechen, Konfliktfrage mit Vergleich, Bericht, „Widerrufen“ nach dem Löschen, Warteschlange, Benachrichtigung bei langen Vorgängen |
| **Speicher** | jeder Speicherort mit Zustand, Kapazität, Belegung; intern zusätzlich Datenpartition, sofort verfügbarer Platz, freigebbarer Zwischenspeicher |
| **Gerät** | Akku, Akku-Temperatur, Thermalstatus, thermische Reserve, Geräteübersicht, Arbeitsspeicher, Display, Sensoren; **Bewegung**: Geschwindigkeit, Kurs, Höhe über Meeresspiegel/Ellipsoid/Druckhöhe, Satelliten je System, Kompass, Messung seit dem Öffnen |
| **Einstellungen** | Theme, Akzentfarbe, Effektstärke, Bewegung reduzieren; Dateien (versteckte Objekte, Verlauf); Datenschutz mit aktuellem Stand jeder Berechtigung; Lizenzen |

Grundsätze, die überall gelten: Jeder Wert nennt seine Quelle oder sagt ausdrücklich „Nicht verfügbar auf diesem
Gerät“ – nichts wird erfunden. Kein Text kann in einem Theme unlesbar werden (Kontrast automatisch geprüft).
Animationen folgen „Animationen entfernen“. Keine Internet-Berechtigung, keine Telemetrie.

## Sicherheit deiner Dateien

* **Nichts wird automatisch gelöscht.** „Löschen“ legt in den Papierkorb des jeweiligen Speichers (mit „Widerrufen“);
  endgültig gelöscht wird nur nach ausdrücklicher Bestätigung.
* **Erst vollständig schreiben, dann ersetzen.** Neue Dateien entstehen als `*.aether-part` und werden erst nach dem
  letzten Byte umbenannt.
* **Verschieben zwischen Speichern** (z. B. intern → SD-Karte): Kopie mit SHA-256-Prüfung, Kopie erneut lesen und
  vergleichen – erst dann wird das Original entfernt. (Das Zurücklesen kann aus dem Zwischenspeicher von Android
  kommen: Es findet Übertragungs- und Programmfehler, aber nicht sicher eine gefälschte oder defekte Speicherkarte.)
* **Abbruch und Absturz:** Bereits Erledigtes bleibt, Unfertiges wird entfernt; nach einem Absturz räumt der nächste
  Start auf.
* Details: [docs/ENTSCHEIDUNGEN.md](docs/ENTSCHEIDUNGEN.md) §11–12, Grenzen: [docs/GRENZEN.md](docs/GRENZEN.md).

## Architektur

```
Aether/
├─ app/                 Aktivität, Navigation, Bildschirme, ViewModels, Dateiaktionen, Vorgangs-Warteschlange
│                       und Vordergrunddienst, Einstellungen (DataStore)
├─ ui/designsystem/     Themes, Farbrollen (PaletteSpec), Schrift, Glas, Symbole, Bausteine (Blätter, Dialoge,
│                       Felder, Werkzeugleiste, Kompass), Diagramme
├─ core/model/          Reines Kotlin: Modelle, Formatierung, Deutungsregeln, Hinweise, Bewegung (JVM-getestet)
├─ core/files/          Reines Kotlin: Dateiarten, Sortierung, Namen, Papierkorb, alle Dateivorgänge, Suche
│                       (JVM-getestet gegen echte Dateien)
├─ platform/storage/    Speichervolumes, Kapazität, Dateizugriff, Medienindex, Vorschaubilder, FileProvider
├─ platform/device/     Akku, Thermalstatus, Geräteübersicht, GPS/GNSS, Barometer, Kompass
├─ tools/ui-check/      Prüfskript: jede Schrift/jedes Symbol mit Theme-Farbe
├─ tools/icons/         Vorschau des Symbolsatzes ohne Gerät
├─ tools/design-preview/ nachgebaute Design-Vorschauen (echte Farbwerte, kein Bildschirmfoto)
├─ tools/typecheck/     Prüfwerkzeuge ohne Android-SDK (Typprüfung, JVM-Tests; check-all.sh)
└─ docs/design/         Design-Vorschauen und Symbolübersicht als Bild
```

Datenfluss: Android-Systemdienst bzw. Dateisystem → `platform:*` / `core:files` → `AppGraph` → ViewModel → Compose.
Die Oberfläche greift nie selbst auf Systemdienste oder Dateien zu. Begründungen:
[docs/ENTSCHEIDUNGEN.md](docs/ENTSCHEIDUNGEN.md).

## Öffnen und Bauen

Voraussetzungen wie bei deinen anderen Projekten: Android Studio mit Unterstützung für **AGP 9.3.1**, JDK 17 (bringt
Android Studio mit), Android SDK Platform **37**. Mindestversion **Android 12**, Ziel **Android 16**.

1. ZIP entpacken, in Android Studio **File › Open** und den Ordner `Aether` wählen.
2. Warten, bis **Gradle Sync** fertig ist. Fehlt `local.properties`, sucht `settings.gradle.kts` das SDK am
   Standardort (macOS `~/Library/Android/sdk`) und legt die Datei an.
3. **Build › Make Project** – oder im Terminal `./gradlew assembleDebug`.
4. Tests: `./gradlew :core:model:test :core:files:test :ui:designsystem:testDebugUnitTest`
5. Empfohlen beim ersten Bau: `./gradlew :app:lintDebug` (Lint lief in der Entwicklungsumgebung nicht).

Weil hier kein vollständiger Gradle-Build möglich war, können beim ersten Bau noch Meldungen auftreten, die nur ein
echter Build findet (Ressourcen-Linking, Manifest, Lint). Bitte die Meldung dann einfach mitschicken.

## Installation und erster Start

* **Pixel 6 Pro:** per USB verbinden, in Android Studio **Run ▶**.
* **Xiaomi:** zusätzlich in den Entwickleroptionen **„Über USB installieren“** einschalten, dann **Run ▶**.
* `versionCode` ist jetzt **2** (Version 0.3.0) – die Installation über 0.1.0 behält deine Einstellungen.
* **Dateien:** Beim ersten Öffnen erklärt AETHER den „Zugriff auf alle Dateien“. „In den Einstellungen erlauben“
  öffnet die passende Android-Seite (Xiaomi: „Verwaltung aller Dateien erlauben“); nach der Rückkehr ist alles da.
* **Bewegung** (Gerät › Bewegung): Android fragt nach dem Standort – „Bei Nutzung der App“ und **„Genau“** wählen.
* **Benachrichtigungen:** Android fragt einmal beim ersten langen Vorgang (z. B. Kopieren) – für den Fortschritt,
  wenn du die App währenddessen verlässt.
* **Xiaomi-Tipp:** Für lange Kopiervorgänge im Hintergrund Einstellungen › Apps › Aether › Akku sparen ›
  „Keine Einschränkungen“.

## Gerätetest

Bitte die Checkliste in [docs/TESTPLAN.md](docs/TESTPLAN.md) §3 durchgehen und mir Punkte mit ✘ oder Auffälligkeiten
schicken (ein Bildschirmfoto hilft sehr). Besonders wichtig in dieser Version:

* **Xiaomi mit SD-Karte:** Ordner der Karte öffnen, eine Datei auf die Karte **kopieren** und eine zurück
  **verschieben**; Papierkorb auf der Karte; Karte in den Android-Einstellungen auswerfen, während ein Ordner von ihr
  offen ist.
* **Pixel 6 Pro mit USB-Stick:** erscheint er unter „Dateien › Speicherorte“? Kopieren auf den Stick (FAT32: Datei
  über 4 GB → verständliche Meldung, Original bleibt).
* **Bewegung** draußen: Satelliten, Geschwindigkeit gegen Tacho, Höhe gegen eine Karte.

## Weitere Dokumente

| Dokument | Inhalt |
|---|---|
| [docs/PLAN.md](docs/PLAN.md) | Implementierungsplan Phase 1–8 |
| [docs/STATUS.md](docs/STATUS.md) | Umsetzungsstand je Anforderung |
| [docs/TESTPLAN.md](docs/TESTPLAN.md) | Ausgeführte Prüfungen, Ergebnisse, Gerätecheckliste |
| [docs/BERECHTIGUNGEN.md](docs/BERECHTIGUNGEN.md) | Jede Berechtigung: wofür, wann gefragt, was ohne sie geht |
| [docs/GRENZEN.md](docs/GRENZEN.md) | Was Android nicht bereitstellt und was diese Version noch nicht kann |
| [docs/ENTSCHEIDUNGEN.md](docs/ENTSCHEIDUNGEN.md) | Architektur, Dateimanager-Modell, Sicherheitsregeln |
| [docs/RISIKEN.md](docs/RISIKEN.md) | Technische Risiken: Dateizugriff, SD-Karten, USB, Temperatur, Sensoren, Glas, Xiaomi |
| [docs/DESIGN.md](docs/DESIGN.md) | Designsystem: Themes, Farbrollen, Kontraste, Material, Bewegung, Symbole |
| [docs/design/](docs/design/) | Design-Vorschauen (Übersicht, Dateien, Bewegung) und Symbolübersicht |
| [docs/REFERENZANALYSE.md](docs/REFERENZANALYSE.md) | Was aus deinen vier Projekten übernommen wurde |
| [CHANGELOG.md](CHANGELOG.md) | Versionen |
