# KI-Musik – technische Analyse und Machbarkeit (Phase 1)

Stand: 13.11.2026. Grundlage: Quelltext von ACE-Step 1.5 (Stand `ca1e85f`, 29.08.2026), Modellkarten auf
Hugging Face und zwei Prüfläufe („KI-Probe“) auf Apple-Silicon-Rechnern von GitHub. **Ich kann Audio nicht hören.**
Alle Aussagen zur Klangqualität stützen sich auf Messwerte und automatische Spracherkennung; der eigentliche Hörtest
steht aus und ist Sache des Nutzers.

## Ergebnis in Kürze

| Frage | Antwort |
|---|---|
| Läuft ACE-Step 1.5 lokal auf einem Mac? | **Ja, nachgewiesen** auf Apple Silicon (virtueller M1, macOS 15.8): Installation, Modelle, Erzeugen von Instrumentals, deutschem Gesang, Varianten und Remix. |
| Ohne Cloud, Konto, Kosten? | **Ja.** Einmaliger Download (Pakete ca. 1,2 GB, Modelle ca. 10,4 GB), danach rein lokal. Der Rechenprozess läuft in einer Sandbox ohne Netzwerkzugriff. |
| Intel-Mac? | **Nein.** Für macOS gibt es PyTorch und MLX nur noch für Apple-Chips (ACE-Step verlangt `torch ≥ 2.9.1` nur für `darwin/arm64`). Die App zeigt auf Intel-Macs eine klare Meldung; die Bibliothek bleibt voll nutzbar. |
| Geschwindigkeit auf dem M5 Pro (48 GB)? | **Nicht gemessen.** Auf dem virtuellen 3-Kern-M1 mit 7 GB (ohne nutzbaren Grafikspeicher) dauerten 30 s Musik ca. 9 Minuten. Ein Erfahrungsbericht nennt ca. 29 s je 100 s Musik auf einem M1 Max – unbestätigt. Die App lernt die Dauer aus den eigenen Läufen und zeigt eine Schätzung. |
| Deutscher Gesang? | **Verständlich:** Ein vorgegebener deutscher Text wurde gesungen; die Spracherkennung (Whisper large-v3-turbo) erkannte 80 % der Wörter richtig (Wortfehlerrate 0,205). |
| Deutsche Songtexte von der KI? | **Mit dem kleinen Sprachmodell (0.6B) schlecht** (sinnarme Wiederholungen, falsche Stilbeschreibung). Das 1.7B-Modell (im Grundpaket) und das 4B-Modell sollen deutlich besser sein – auf dem 7-GB-Prüfrechner nicht prüfbar. Eigener Text bleibt immer möglich. |
| Gesang entfernen / Spuren trennen? | **Technisch ja** mit demucs-mlx (4 Spuren: Gesang, Schlagzeug, Bass, Rest; 30–40 s Audio in 40–90 s auf dem Prüfrechner). **Lizenz der Gewichte ungeklärt** (siehe unten). |
| Remix? | **Ja:** ACE-Step „cover“ (Neuinterpretation einer Vorlage mit neuer Beschreibung) lieferte eine Datei; Qualität nicht hörbar geprüft. |
| Stimmumwandlung (Voice Conversion)? | **Nicht mit ACE-Step.** Braucht ein eigenes Modell (RVC: MIT, muss pro Stimme trainiert werden; Seed-VC: GPL-3.0, archiviert). Noch nicht geprüft. |

## Was ACE-Step 1.5 kann (aus dem Quelltext belegt)

- **Text zu Musik** (`text2music`): Beschreibung (bis 512 Zeichen empfohlen), Songtext mit Abschnitten
  (`[Verse]`, `[Chorus]` …) oder `[Instrumental]`, Gesangssprache aus **50 Sprachen** (u. a. Deutsch, Englisch,
  Französisch, Spanisch, Italienisch, Portugiesisch, Niederländisch), BPM, Tonart, Taktart, Länge **10 bis 600 Sekunden**,
  Startwert (Seed), mehrere Varianten auf einmal.
- **Planung durch ein Sprachmodell** (0.6B, 1.7B, 4B; Qwen3-Basis): erzeugt aus einer kurzen Idee Beschreibung,
  Text und Metadaten (`create_sample`) bzw. überarbeitet einen Text (`format_sample`).
- **Remix/Cover** (`cover`, Stärke 0–1), **Ausschnitt neu erzeugen** (`repaint`, Inpainting) – mit dem Turbo-Modell.
- **Spuren extrahieren/hinzufügen, Fortsetzen** (`extract`, `lego`, `complete`) – **nur mit dem Basismodell**
  (`acestep-v15-base`, zusätzlicher Download, nicht geprüft).
- **Modelle:** turbo (2B, 8 Schritte – Grundpaket), sft/base (2B, 50 Schritte), XL-turbo/XL-sft (4B, laut Entwicklern
  höhere Klangqualität, ca. 9 GB).
- **Apple Silicon:** Musikmodell und VAE wahlweise in MLX (Metal) oder PyTorch (MPS/CPU); Sprachmodell in MLX oder PyTorch.
- **Ausgabe:** FLAC/WAV/MP3/Opus/AAC, 48 kHz Stereo (MP3/AAC über FFmpeg – die App nutzt FLAC und wandelt selbst).

## Messungen der KI-Probe

Rechner: virtueller Apple M1, 3 Kerne, 7 GB, GitHub Actions. Nicht repräsentativ für den M5 Pro.

| Schritt | macOS 15.8 | macOS 26.7 |
|---|---|---|
| Installation (`uv sync`) | 18 s, 1,2 GB | 23 s, 1,2 GB |
| Download Modelle (Grundpaket + LM 0.6B) | 88 s, 11 GB | 96 s, 11 GB |
| Musikmodell laden | MPS: zu wenig Grafikspeicher → CPU, 249 s | ebenso → CPU, 314 s |
| Sprachmodell 0.6B (MLX) laden | 70 s | 71 s |
| 30 s Instrumental (EN-Beschreibung) | 562 s | – (MLX-Kernel scheitern) |
| 30 s Instrumental (DE-Beschreibung) | 506 s | – |
| 40 s deutscher Gesang (eigener Text) | 541 s | – |
| KI schreibt deutschen Text (0.6B) | 37 s | – |
| 2 Varianten à 20 s, ohne Planung | 389 s | – |
| Remix (cover) 30 s | 335 s | – |
| Gesangstrennung (demucs-mlx, 40 s) | 77–92 s | – |

Objektive Kennwerte der Dateien (ersetzen keinen Hörtest): richtige Länge, 48 kHz Stereo, Spitzenpegel −1 dBFS
(Normalisierung von ACE-Step), keine Übersteuerung, Pegel −15 bis −20 dBFS RMS, kein Rauschen
(spektrale Flachheit ≤ 0,0006), kaum Stille. Whisper „hört“ im Instrumental fälschlich „Bis zum nächsten Mal.“ –
eine bekannte Halluzination bei Musik, kein Gesang.

**macOS 26 (virtuell):** MLX wählte für Matrixmultiplikationen neue „NAX“-Kernel (für Apple-GPUs der M5-Reihe), die
sich auf der virtuellen Grafik nicht übersetzen ließen. Auf echter Hardware nicht geprüft. Die App fällt in diesem
Fall automatisch auf PyTorch zurück; bei zu wenig Grafikspeicher rechnet das Musikmodell auf dem Prozessor.

## Prüfstand KI-E2E (Code der App, 13./14.11.2026)

Der Prüfstand richtet die KI-Umgebung mit `KIInstaller` ein und erzeugt über `KIEngine` – derselbe Code wie in der
App, Rechenprozess in der Sandbox ohne Netz. Rechner: virtueller M1, 7 GB, ohne nutzbaren Grafikspeicher.
Endstand 14.11.: **macOS 15.8 alle 5 Prüfungen bestanden**, macOS 26.7 vier von fünf (siehe letzte Zeile).

| Schritt | macOS 15.8 | macOS 26.7 |
|---|---|---|
| Umgebung (uv, ACE-Step `ca1e85f`, Python 3.12, Pakete) | 45 s | 41 s |
| Grundpaket (10,1 GB, Stand `19671f4`) + LM 0.6B (1,4 GB) | 70 s, Fortschritt bis 100 % | 78 s |
| Zweiter Aufruf der Einrichtung | 8 s (nichts neu geladen) | 8 s |
| Platz nach der Einrichtung | Umgebung 1,4 GB, Modelle 11 GB (uv-Zwischenspeicher gelöscht) | ebenso |
| Sandbox: Verbindung ins Netz aus Python | gesperrt (URLError) | gesperrt |
| Modelle laden | 277 s (Grafikspeicher reicht nicht → Prozessor, automatisch) | 282 s (ebenso) |
| 20 s Instrumental, englisch, ohne Planung | 323 s | 635 s |
| 2 × 20 s, deutsche Beschreibung, mit Planung | 414 s | 751 s (über der früheren 600-s-Grenze von ACE-Step, die die App jetzt aufhebt) |
| KI schreibt deutschen Text (LM 0.6B) | 33 s – inhaltlich schwach („Komm wir machen Schnaps …“) | 101 s (PyTorch) – ebenfalls schwach |
| 30 s deutscher Gesang mit diesem Text | 493 s; Whisper gibt die ersten elf Zeilen fast wörtlich wieder | ✗ Sprachmodell auf PyTorch/MPS: zu wenig Speicher (7 GB-Rechner) |
| Abbrechen während des Erzeugens | Prozess beendet, „Abgebrochen.“, danach erneutes Laden und Erzeugen ✓ | ✓ |
| Fehlermeldung bei unbekanntem Modell | klar, ohne Absturz ✓ | ✓ |
| MLX-Sprachmodell scheitert (NAX-Kernel) | – | automatisch auf PyTorch umgestellt ✓ |

Der Fehlschlag auf macOS 26 betrifft nur Rechner mit sehr wenig Speicher: Die App lädt auf Macs unter 12 GB gar kein
Sprachmodell (nur „Schnell“ mit eigenem Text oder Instrumental) – der Prüfstand hat es dort absichtlich erzwungen.
Die Zeiten gelten für den Prozessor eines virtuellen Rechners und sind kein Maß für den M5 Pro.

## Lizenzen

| Bestandteil | Quelltext | Gewichte | Kommerziell | Weitergabe durch die App |
|---|---|---|---|---|
| ACE-Step 1.5 | MIT (© 2026 ACEStep) | MIT (Modellkarte); laut Entwicklern lizenzierte, gemeinfreie und synthetische Trainingsdaten | ja, auch die erzeugte Musik | nicht nötig – Laden auf Wunsch von GitHub/Hugging Face |
| Qwen3-Embedding / Qwen3-Basis der LMs | Apache-2.0 | Apache-2.0 bzw. MIT (ACE-Step-Karten) | ja | wie oben |
| VAE (im Grundpaket) | – | MIT laut Grundpaket; eigene Herkunft nicht angegeben | – | wie oben |
| Python-Pakete (154, Liste im Prüflauf) | überwiegend MIT/BSD/Apache; frozendict LGPL-3.0 | – | ja | werden auf dem Mac des Nutzers von PyPI installiert, nicht mitgeliefert |
| demucs-mlx | MIT | Demucs-Gewichte von Meta: Modellkarte „MIT“, frühere Aussagen im Demucs-Projekt „nur Forschung“ – **offene, unbeantwortete Nachfrage** | **unklar** | nicht mitliefern; für private Nutzung vertretbar, für Weitergabe klären |
| RVC | MIT | je Stimme selbst trainiert | ja (eigene Stimmen) | – |
| Seed-VC | **GPL-3.0** | – | – | nicht in die App einbauen |

Die App selbst enthält keine Modelle und kein Python – nur zwei kleine Skripte (`Resources/KIEngine`), die den
lokalen Prozess steuern.

## Architektur (umgesetzt)

```
SwiftUI (KIMusicView, Einstellungen „KI-Musik“)
  ↓
KIMusicModel (Zustand, Warteschlange einer Erzeugung, Kreationen, Leerlauf-Entladen)
  ↓
KIEngine / KIEngineClient – JSON-Zeilen über stdin/stdout, kein Netzwerk-Port
  ↓
Python-Prozess engine.py in Sandbox ohne Netz (sandbox-exec), niedrige Priorität (QoS utility)
  ↓
ACE-Step 1.5 (MLX/PyTorch) → FLAC → ~/Music/KI-Musik (nicht Teil der Bibliothek)
  ↓
„In Bibliothek übernehmen“ → Warteschlange von „Hinzufügen“ (Format, Ziel, Tags wie dort)
```

- **Einrichtung** (`KIInstaller`): uv 0.13.8 (SHA-256 geprüft), ACE-Step im festen Stand `ca1e85f`, Python 3.12 von uv,
  Pakete per `uv sync`; Modelle einzeln per Knopf (Fortsetzen nach Abbruch). Alles unter
  `~/Library/Application Support/Music Library/KI-Musik`, vollständig entfernbar.
- **Prozess:** startet beim ersten Erzeugen, lädt die Modelle einmal, wird nach einstellbarer Leerlaufzeit
  (Standard 10 min) beendet – dann ist der Speicher frei, im Leerlauf rechnet nichts. Abbrechen beendet den Prozess.
  Absturz → Fehlermeldung mit Protokoll, die nächste Anfrage startet neu. Die Bibliothek ist davon unabhängig.

## Risiken

1. **Geschwindigkeit und Stabilität auf echter Hardware sind ungeprüft** (kein Apple-Silicon-Mac mit voller GPU im
   Prüfstand). Erster echter Test: auf dem M5 Pro.
2. **MLX auf macOS 26:** NAX-Kernel scheiterten im virtuellen Rechner; Rückfall auf PyTorch ist eingebaut.
3. **Qualität deutscher KI-Texte** hängt am Sprachmodell; 0.6B ist ungeeignet. 4B (empfohlen ab 32 GB) muss geprüft werden.
4. **Trennung (Demucs):** Gewichtslizenz offen; Qualität bei echten Songs nicht hörbar geprüft.
5. **Lange Stücke:** ACE-Step erzeugt bis 10 Minuten in einem Stück – eine eigene „Segmentierung“ ist nicht nötig
   und wird nicht vorgetäuscht.
6. **Speicher:** Grundpaket 10,4 GB; XL-Modell weitere ~9 GB, 4B-Sprachmodell weitere Gigabyte.

## Prüfplan (15 Testfälle des Auftrags)

| # | Fall | Stand |
|---|---|---|
| 1 | Instrumental, englische Beschreibung | Probe ✓ (Datei, Messwerte); App-Pfad: Prüfstand KI-E2E |
| 2 | Instrumental, deutsche Beschreibung | Probe ✓ |
| 3 | Deutscher Songtext von der KI | Probe ✓ technisch, **inhaltlich schwach mit 0.6B** |
| 4 | Englischer Songtext von der KI | offen |
| 5 | Song mit Gesang | Probe ✓ (deutsch, 80 % Wörter erkannt) |
| 6 | Kurzes Stück | Probe ✓ (20 s) |
| 7 | Möglichst langes Stück | offen (bis 600 s laut Modell; auf dem Prüfrechner zu langsam) |
| 8 | Mehrere Varianten | Probe ✓ (2 Varianten) |
| 9 | MP3 → Instrumental | Probe ✓ technisch (demucs-mlx); in der App noch nicht |
| 10 | Gesang extrahieren | Probe ✓ technisch; in der App noch nicht |
| 11 | Remix eines Teststücks | Probe ✓ technisch (eigenes erzeugtes Stück als Vorlage) |
| 12 | Voice Conversion | offen (eigenes Modell nötig) |
| 13 | Export in die Bibliothek | App: über „Hinzufügen“ – automatischer Test mit Ersatzdatei ✓ |
| 14 | Offlinebetrieb | Prüfstand KI-E2E ✓ (Sandbox ohne Netz, Erzeugen gelingt) |
| 15 | Fehler und Abbruch | Prüfstand KI-E2E: Fehlermeldung ✓, Abbruch mit Neustart ✓ |

Hörtests (Klang, Natürlichkeit, Übergänge, Aussprache) kann nur ein Mensch machen.

## Quellen

- ACE-Step 1.5: https://github.com/ace-step/ACE-Step-1.5 (README „Model Zoo“, docs/en/INFERENCE.md, GPU_COMPATIBILITY.md, LICENSE)
- Modellkarte: https://huggingface.co/ACE-Step/Ace-Step1.5
- demucs-mlx: https://pypi.org/project/demucs-mlx/
- Lizenzfrage HTDemucs-Gewichte: https://huggingface.co/adefossez/HTDemucs/discussions/1
- Prüfläufe: Zweige `ci-ki-macos-15`, `ci-ki-macos-26` (Audio als MP3, `probe.json`, `listen.json`, Lizenzlisten)
