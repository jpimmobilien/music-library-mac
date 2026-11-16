# KI-Hörbücher & Hörspiele – technische Analyse und Machbarkeit (Phase 1)

Stand: 16.11.2026. Grundlage: Quelltext von mlx-audio 0.6.5 (Stand `b5fcbe9`, 14.11.2026), Modellkarten auf Hugging Face,
Recherche zum Stand der offenen Modelle (Quellen unten) und die Prüfläufe „Hoerspiel-Probe“ auf GitHub-Rechnern.
**Ich kann Audio nicht hören.** Alle Aussagen zu Klang, Natürlichkeit und Aussprache stützen sich auf Messwerte und
automatische Spracherkennung (Whisper). Der eigentliche Hörtest steht aus und ist Sache des Nutzers.

<!-- ERGEBNIS -->

## Vorhandene Architektur und Einbindung

Die App hat mit „KI-Musik“ (2.5) bereits alles, was ein lokales KI-Studio braucht – das Hörspielstudio baut darauf auf,
ohne bestehende Funktionen zu verändern:

```
SwiftUI (HoerspielView: 7 Bereiche, Einstellungen „KI-Hörbücher“)
  ↓
HoerspielModel – Zustand, Ablauf Schritt für Schritt, nach jedem Teilschritt gespeichert (Fortsetzen nach Abbruch)
  ↓                                         ↘ Musik: KIMusicModel.instrumental → bestehender ACE-Step-Prozess
HSEngine / KIEngineClient – JSON-Zeilen über stdin/stdout, kein Netzwerk-Port
  ↓
Python-Prozess Resources/HoerspielEngine/engine.py in Sandbox ohne Netz (sandbox-exec), niedrige Priorität
  ├─ hs_story   Geschichte: Konzept → Szenen (Zeilenformat) → Prüfung (Länge, Wiederholung, Sprecher)  [mlx-lm]
  ├─ hs_voice   Stimmen: Voice Design → Referenzsatz → jede Zeile geklont                              [mlx-audio]
  ├─ hs_analyze Referenz: VAD, Sprechertrennung (ECAPA + Gruppierung), Whisper, Tonhöhe, Klang          [mlx-audio, mlx-whisper]
  ├─ hs_produce Geräusche, Musikplan, Zeitleiste, Raumklang, Ducking, Retro-Klang, Lautheit (EBU R128)  [numpy/scipy]
  └─ hs_text    Zahlen ausschreiben, Abkürzungen, Drehbuchformat
  ↓
~/Music/KI-Hörspiele/<Produktion>/ (nicht Teil der Bibliothek) → Export über den Exporter der App (MP3/M4A/FLAC/WAV)
```

- **Eigene Umgebung** unter `~/Library/Application Support/Music Library/KI-Hoerspiel` (uv, Python 3.12, feste Pakete,
  Modelle im Hugging-Face-Zwischenspeicher). Getrennt von KI-Musik, damit keine Paketkonflikte mit ACE-Step entstehen.
- **Keine Datenbankänderung:** Produktionen, Stimmen, Referenzen und Geräusche liegen als JSON und Audiodateien in
  einem eigenen Ordner. Die Bibliotheksdatenbank bleibt unberührt; eine Migration ist nicht nötig.
- **Musik** kommt aus der vorhandenen KI-Musik (ACE-Step 1.5, Qualität „Schnell“, instrumental): Titel, Übergang,
  Spannung, Finale, Abspann – je Produktion nur einmal erzeugt und wiederverwendet.

<!-- MODELLE -->

<!-- MESSUNGEN -->

<!-- REFERENZ -->

## Stimmrechte: drei Arten von Stimmprofilen

| Art | Was gespeichert wird | Kann sprechen? |
|---|---|---|
| **Entworfen** | Einstellungen/Beschreibung, Startwert, ein synthetischer Referenzsatz | ja |
| **Stilprofil** (aus Referenzanalyse) | nur Beschreibung allgemeiner Merkmale (Tonlage, Tempo, Klangfarbe, Ausdruck) – kein Audio, kein Stimmabdruck | nein – daraus lässt sich eine eigenständige Stimme entwerfen |
| **Berechtigt** | Stimmprobe + gesprochene Einwilligung derselben Person (+ optional Dokument), Prüfergebnis | nur wenn die Prüfung bestanden ist |

Prüfung einer berechtigten Stimme (umgesetzt, nicht nur ein Häkchen):
1. Die Person spricht den Einwilligungssatz mit ihrem Namen selbst ein („Ich, …, erlaube, dass meine Stimme … nachgebildet wird.“).
2. Whisper hört mit: Name und Einwilligungswörter müssen erkannt werden.
3. Stimmvergleich (ECAPA) zwischen Einwilligung und Stimmprobe muss über der kalibrierten Schwelle liegen.

Aufnahmen aus Hörspielen, Filmen oder dem Internet erfüllen das nicht – eine Nachbildung bekannter Sprecher alter
Hörspiele ist damit ohne deren eigene Einwilligung nicht möglich. Die Oberfläche zeigt bei jedem Profil die Art an.

<!-- LIZENZEN -->

<!-- RISIKEN -->

<!-- PLAN -->

<!-- QUELLEN -->
