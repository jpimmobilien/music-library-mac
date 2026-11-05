# Architektur

Ein Swift-Paket (SwiftPM), sechs Bibliotheksmodule plus die App. Alles, was keine Apple-Frameworks
braucht, ist davon getrennt und auch unter Linux bau- und testbar.

```
MusicLibrary (App, nur macOS)  SwiftUI + AppKit + AVFoundation + MediaPlayer
 ├─ MLCore      reine Logik: Modelle, Gruppierung, Sortierung, Suche, Smart-Playlists, Duplikate,
 │              Warteschlange/Zufall/Wiederholen, Zähl-/Verlaufs-/Fortsetzregeln, Sleep-Timer,
 │              Equalizer-/Pitch-Modell, Liedtext (LRC), Coverfarben, Einstellungen, SVG-Pfade
 ├─ MLStore     SQLite (Bibliothek, Ordner, Playlists, Favoriten, Statistik, Verlauf, Fortsetzpunkte)
 ├─ MLTags      Tags lesen/schreiben (TagLib) + SafeTagWriter (Sicherung → Kopie → Prüfung → Ersetzen → Rückgängig)
 │   └─ TagBridge  TagLib 2.3.2 (C++, unverändert) mit schmaler C-Schnittstelle
 ├─ MLRender    Raster-Renderer der Player-Designs (Plattenspieler, Kassette, Portable CD) – Port der Kotlin-Renderer
 └─ OggVorbis   Ogg-Vorbis-Decoder (stb_vorbis 1.22)
```

## App (Sources/MusicLibrary)

| Ordner | Inhalt |
|---|---|
| `Design` | Farben/Typografie/Abstände aus den Android-Tokens, Glas (Liquid Glass ab macOS 26, sonst Unschärfe), Steuerelemente, Symbole (Android-Vektorpfade), Cover-Zwischenspeicher, Genre-Grafiken |
| `App` | `AppModel` (Zustand, Navigation, abgeleitete Listen), Szenen, Menüs, Tastaturkürzel, Dock-Menü |
| `Library` | Ordnerverwaltung, Scan, Dateiüberwachung (FSEvents), Laufwerke |
| `Audio` | `AudioEngine` (Player → TimePitch → Varispeed → EQ → Limiter → Mischer), `PlayerService` (Warteschlange, Zählregeln, Fortsetzen, Sleep-Timer, Kontrollzentrum), Ogg-Umwandlung |
| `Views` | Bibliotheksansichten, Detailansichten, Titellisten (Mehrfachauswahl, Ziehen & Ablegen), Werkzeuge |
| `Player` | Mini-Player, Vollbild-Player mit vier Designs, Seitenleisten, Equalizer/Pitch/Sleep-Timer, Mini-Fenster, Menüleiste |
| `Metadata` | Informationsfenster (Details, Cover, Liedtext, Sortierung, Datei), Schreiben über `SafeTagWriter` |
| `Settings` | Einstellungen (Darstellung, Bibliothek, Wiedergabe, Metadaten, Über) |
| `Snapshot` | Vorschaumodus `--snapshot <Ordner>`: erfundene Beispielbibliothek, alle Ansichten hell/dunkel als PNG (für CI) |

## Datenfluss

Dateien → `LibraryService` (Scan, `SyncPlanner`) → `TagFile.read` → `LibraryStore` (SQLite) →
`AppModel` (`LibraryIndex`, Sortierung/Suche je Bereich) → SwiftUI.
Wiedergabe: `AppModel.play…` → `PlayerService` (`PlayQueue`) → `AudioEngine`; Zählung/Verlauf/Fortsetzen
über die Regeln aus MLCore → `LibraryStore`.
Tags ändern: Informationsfenster (`EditorSession`) → `MetadataService` → `SafeTagWriter` (Journal) →
Datei neu einlesen → `LibraryStore`.

## Build

`scripts/build_app.sh` baut arm64 und x86_64 getrennt (`--triple …-apple-macosx13.0`), fügt sie mit
`lipo` zusammen, erstellt das App-Bundle (Info.plist, Icon, Schriften, Genre-Bilder, Lizenzen) und signiert
ad-hoc. `scripts/make_dmg.sh` erzeugt die DMG (dmgbuild, Hintergrund, Verknüpfung „Programme“).
`.github/workflows/build.yml` führt Build, Vorschaubilder, DMG und Tests auf macOS 26 (Apple Silicon)
sowie Starttests der DMG auf Intel (macOS 15) und Apple Silicon (macOS 14) aus.
