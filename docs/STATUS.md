# Prüfstand – was gebaut und getestet ist (ehrlich)

Stand: 05.11.2026 · Version 1.0.0 (erste macOS-Fassung)

## Umgebung

Entwickelt in einer Linux-Umgebung **ohne macOS und ohne Xcode**. Verfügbar war ein Swift-5.9.2-Compiler
für Linux (mit Foundation und XCTest, ohne SwiftUI/AppKit/AVFoundation). Ein GitHub-Konto war nicht
verbunden, deshalb konnte die vorbereitete macOS-CI (GitHub Actions) **nicht laufen**.

## Übersicht

| Stufe | Ergebnis |
|---|---|
| **Reine Module kompiliert** (MLCore, MLStore, MLTags + TagLib 2.3.2, MLRender, OggVorbis + stb_vorbis) | ✅ fehlerfrei (Swift 5.9.2, Linux) |
| **Unit-Tests der reinen Module** | ✅ **337 von 337 bestanden** – MLCore 199, MLTags 76, MLRender 46, MLStore 11, OggVorbis 5 |
| davon Abgleich mit Android | ✅ Sortierreihenfolge, Hashwerte, EQ-Kurven, Coverfarben, Zahlenformate mit dem Kotlin-Code auf der JVM berechnet; Bildebenen der vier Player-Grafiken mit den Kotlin-Renderern verglichen |
| **Tags schreiben – Unversehrtheit der Musik** | ✅ 16 Formate: Audiodaten nach Bearbeiten, Leeren und erneutem Bearbeiten bit-identisch (ffmpeg-MD5); dazu 37-MB-ALAC, 6-MB-MP3, 3-MB-FLAC |
| **App (SwiftUI/AppKit) kompiliert** | ❌ **nicht möglich** (kein macOS) |
| Ersatzprüfung der App | ⚠️ zwei unabhängige Durchsichten aller ≈ 12 300 Zeilen gegen die echten Schnittstellen und macOS 13 als Mindestversion. Gefunden und behoben: ein nicht aufrufbarer Initialisierer, verlorene Tupel-Bezeichner, `[weak self]` in verschachtelten nebenläufigen Closures (rund ein Dutzend Stellen), viermal mehr als 10 Elemente in einem ViewBuilder (unter macOS 13 ein Fehler) sowie vier Absturz-/Darstellungsfehler (Pegelanzeige bei niedriger Abtastrate, Umschalt-Klick nach Filtern, Sternbewertung > 100, verzerrte Cover-Labels). Syntaxprüfung (`swiftc -parse`) aller Dateien fehlerfrei; Suchskripte für Elementgrenzen, unbekannte Namen und private Typen ohne Befund. **Kein Ersatz für einen echten Build** – der erste Build kann noch einzelne Fehler melden. |
| **App-Tests** (`Tests/MusicLibraryTests`, 24 Tests: Klangkette offline gemessen – Lautstärke, Limiter, EQ, Bass, Tonhöhe, Tempo, Drehzahl –, Pegelanzeige, Mehrfachbearbeitung, Symbole, Ogg-Wiedergabe) | ⚠️ geschrieben, **nicht ausgeführt** |
| **Vorschaubilder der 17 Ansichten** (hell/dunkel, mehrere Fenstergrößen, mit und ohne Liquid Glass) | ❌ nicht erzeugt – braucht macOS; die CI erzeugt sie automatisch (`--snapshot`) |
| **Universal Binary, Ad-hoc-Signatur, DMG** | ❌ **nicht erstellt** – Skripte fertig (`scripts/build_app.sh`, `scripts/make_dmg.sh`, `Build.command`), aber nicht ausgeführt |
| App-Icon, DMG-Hintergrund | ✅ gerendert und angesehen |
| Installationsanleitung | ✅ geschrieben; Erststart-Schritte nach Apples dokumentiertem Gatekeeper-Verhalten, hier nicht ausprobiert |

## Was als Nächstes geprüft werden muss (in dieser Reihenfolge)

1. Erster Build auf macOS (CI oder `Build.command`) – Übersetzungsfehler beheben.
2. `swift test` auf macOS: 337 + 24 Tests (Klangkette, Ogg, Metadaten-Sitzung, Symbole).
3. Vorschaubilder aller Ansichten hell/dunkel ansehen; Liquid Glass (macOS 26) und Rückfall (macOS 13–15).
4. Starttest der fertigen DMG auf Intel und Apple Silicon.
5. Von Hand: Wiedergabe mit echter Musik, Medientasten, Tags schreiben + Rückgängig an Kopien, Ordner auf
   externem Laufwerk, große Bibliothek (Geschwindigkeit).
