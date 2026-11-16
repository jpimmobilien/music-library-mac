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

## Modelle: Auswahl und Vergleich

Alle Repos wurden am 16.11.2026 über die Hugging-Face-API geprüft (`scripts/hoerspiel/catalog_check.py`, Lauf
„Modellkatalog“): Es gibt sie, sie sind frei zugänglich (nicht „gated“), Größe = Summe aller Dateien. Die App lädt
genau den geprüften Stand (Commit), nicht den jeweils neuesten.

### Geschichten (Sprachmodell, mlx-lm)

| Modell | Größe | Lizenz | Einsatz |
|---|---|---|---|
| **Gemma 4 26B-A4B** (4 bit, MoE, 3,8 Mrd. aktiv) | 15,4 GB | Apache-2.0 | **Standard ab 32 GB** (M5 Pro 48 GB) |
| Qwen3.5 9B (4 bit) | 6,0 GB | Apache-2.0 | Macs mit 16–32 GB |
| Qwen3.5 4B (4 bit) | 3,1 GB | Apache-2.0 | Macs mit 8–16 GB, deutlich schwächer |
| Qwen3.6 35B-A3B (4 bit) | 20,4 GB | Apache-2.0 | geprüft, nicht im Katalog: kaum Vorteil bei mehr Speicher |
| Qwen3.5 27B (4 bit, dicht) | 16,1 GB | Apache-2.0 | geprüft, nicht im Katalog: dicht = deutlich langsamer als MoE |

Gemma 4 wurde gewählt, weil es unter den offenen Modellen dieser Größe das beste Deutsch schreibt und als MoE mit
3,8 Mrd. aktiven Parametern schnell genug für lange Geschichten ist. Der Prüfstand nutzt dasselbe Modell als GGUF
(Q3_K_M) mit llama.cpp auf einem Linux-Rechner, weil dort genug Arbeitsspeicher frei ist – die 3-bit-Fassung ist
etwas schwächer als die 4-bit-Fassung der App.

### Stimmen (Sprachausgabe, mlx-audio 0.6.5)

| Modell | Größe | Lizenz | Deutsch | Ergebnis |
|---|---|---|---|---|
| **Qwen3-TTS 1.7B VoiceDesign** | 4,5 GB | Apache-2.0 | ja | **gewählt**: Stimme aus einer Beschreibung entwerfen |
| **Qwen3-TTS 1.7B Base** | 4,5 GB | Apache-2.0 | ja | **gewählt**: jede Zeile aus dem entworfenen Referenzsatz klonen (gleiche Stimme über alle Kapitel) |
| VoxCPM2 (8 bit) | 3,2 GB | Apache-2.0 | ja (30 Sprachen) | Vergleich im Prüfstand |
| Chatterbox Multilingual v3 | 2,7 GB | MIT (Wasserzeichen „Perth“) | ja | Vergleich; Regler für Ausdrucksstärke |
| Piper (thorsten-high) | klein | Code GPL-3.0 | ja | nur Messlatte „klassische Sprachausgabe“, nicht in der App |
| XTTS-v2 | – | CPML, nicht kommerziell; Coqui eingestellt | ja | ausgeschlossen |
| Kokoro | – | Apache-2.0 | nein | ausgeschlossen (kein Deutsch) |
| Voxtral TTS, Fish S2, Higgs Audio | – | nicht kommerziell | teils | ausgeschlossen (Lizenz) |
| MOSS-TTS (4B/8B) | groß | Apache-2.0 | ja | Kandidat für später, auf dem Prüfrechner zu groß |

### Referenzanalyse

| Modell | Größe | Lizenz | Aufgabe |
|---|---|---|---|
| Silero VAD | 2 MB | MIT | Sprache erkennen |
| SpeechBrain ECAPA (MLX) | 42 MB | Apache-2.0 | Sprecher unterscheiden, Stimmen vergleichen, Einwilligung prüfen |
| Whisper large-v3-turbo | 1,6 GB | MIT | Text mit Wortzeiten |
| eigene Tonhöhenmessung (YIN), Raum- und Klangmerkmale | – | eigener Code | Stimm- und Aufnahmeprofil |

Nicht verwendet: Sortformer (CC BY-NC, höchstens 4 Sprecher), pyannote (Zugang nur nach Anmeldung), Nemotron-
Sprechertrennung (nur zur Evaluierung).

### Geräusche und Musik

| Modell | Größe | Lizenz | Aufgabe |
|---|---|---|---|
| Stable Audio 3 small-sfx (MLX) | 3,5 GB | Stability AI Community License | Geräusche und Atmosphären aus Beschreibung (Bibliothek mit Herkunftsangabe je Datei) |
| ACE-Step 1.5 (vorhandene KI-Musik) | – | Apache-2.0 | Titel, Übergang, Spannung, Finale, Abspann (instrumental, 1980er-Synthesizer) |

Die Stability AI Community License erlaubt die Nutzung kostenlos für Privatpersonen und Organisationen unter
1 Mio. US-Dollar Jahresumsatz; darüber ist eine Unternehmenslizenz nötig. Eigene Geräusche (Import) sind jederzeit möglich.


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

## Lizenzen (Code und Gewichte getrennt geprüft)

**Code, den die App mitbringt:** nur eigene Python-Skripte (`Resources/HoerspielEngine`) und Swift-Code. Die
Python-Pakete werden **nicht** mit der App ausgeliefert, sondern auf Knopfdruck in die eigene Umgebung des Nutzers
installiert (feste Versionen, `requirements.txt`):

| Paket | Lizenz |
|---|---|
| mlx, mlx-lm, mlx-whisper, mlx-audio | MIT |
| huggingface_hub | Apache-2.0 |
| numpy, scipy, soundfile | BSD-3-Clause (soundfile bindet libsndfile, LGPL-2.1, dynamisch) |

Die vollständige Paketliste mit Lizenzen erzeugt der Prüflauf (`lizenzen-pakete.md` im Ergebnis-Zweig).
Piper (GPL-3.0) wird nur im Prüfstand als Vergleich installiert, nicht in der App.

**Gewichte:** siehe Tabellen oben. Kommerziell ohne Einschränkung: Qwen3-TTS, Gemma 4, Qwen3.5, Whisper, Silero,
ECAPA, ACE-Step. Mit Bedingung: Stable Audio 3 (Umsatzgrenze 1 Mio. US-Dollar), Chatterbox (MIT, setzt aber ein
unhörbares Wasserzeichen – nur im Vergleich, nicht in der App).

**Stimmen und Ergebnisse:** Entworfene Stimmen sind synthetisch und gehören zu keiner realen Person. Stilprofile aus
Referenzaufnahmen enthalten nur allgemeine Merkmale (kein Audio, kein Stimmabdruck) und können nicht sprechen. Eine
individuelle Stimme nachzubilden ist nur mit geprüfter Einwilligung der Person möglich (siehe oben). Für erzeugte
Geschichten gilt: Das Sprachmodell soll eigene Geschichten schreiben; genannte Serien dienen nur als allgemeine
Stilrichtung (Epoche, Atmosphäre, Erzähltempo) – der Systemauftrag verbietet Figuren, Namen und Handlungen
bestehender Werke.


<!-- RISIKEN -->

<!-- PLAN -->

## Quellen

- Modellkarten und Lizenzangaben: Hugging-Face-API, abgefragt am 16.11.2026 (Ergebnis im Zweig `ci-hoerspiel-catalog`,
  Dateien `katalog.md`/`katalog.json`) – u. a.
  [Qwen3-TTS VoiceDesign (MLX)](https://huggingface.co/mlx-community/Qwen3-TTS-12Hz-1.7B-VoiceDesign-bf16),
  [Qwen3-TTS Base (MLX)](https://huggingface.co/mlx-community/Qwen3-TTS-12Hz-1.7B-Base-bf16),
  [Gemma 4 26B-A4B (MLX)](https://huggingface.co/mlx-community/gemma-4-26b-a4b-it-4bit),
  [VoxCPM2](https://huggingface.co/openbmb/VoxCPM2),
  [Chatterbox Multilingual (MLX)](https://huggingface.co/mlx-community/chatterbox-multilingual-v3),
  [Stable Audio 3 small-sfx (MLX)](https://huggingface.co/mlx-community/stable-audio-3-small-sfx),
  [SpeechBrain ECAPA (MLX)](https://huggingface.co/aufklarer/SpeechBrain-ECAPA-VoxCeleb-20M-MLX),
  [Whisper large-v3-turbo (MLX)](https://huggingface.co/mlx-community/whisper-large-v3-turbo)
- [Gemma 4 Modellkarte (Google)](https://ai.google.dev/gemma/docs/core/model_card_4),
  [Gemma 4 unter Apache 2.0 (VentureBeat)](https://venturebeat.com/technology/google-releases-gemma-4-under-apache-2-0-and-that-license-change-may-matter)
- [Stability AI Lizenzen](https://stability.ai/license),
  [Stable Audio 3 (Stability AI)](https://stability.ai/news-updates/meet-stable-audio-3-the-model-family-built-for-artistic-experimentation-with-open-weight-models)
- [XTTS-v2: Lizenz und Einstellung von Coqui (Diskussion)](https://github.com/coqui-ai/TTS/discussions/4145)
- [mlx-audio](https://github.com/Blaizzy/mlx-audio) (Quelltext 0.6.5),
  [ACE-Step 1.5](https://github.com/ace-step/ACE-Step-1.5)

