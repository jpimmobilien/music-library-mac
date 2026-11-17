# KI-Hörbücher & Hörspiele – technische Analyse und Machbarkeit (Phase 1)

Stand: 16.11.2026. Grundlage: Quelltext von mlx-audio 0.6.5 (Stand `b5fcbe9`, 14.11.2026), Modellkarten auf Hugging Face,
Recherche zum Stand der offenen Modelle (Quellen unten) und die Prüfläufe „Hoerspiel-Probe“ auf GitHub-Rechnern.
**Ich kann Audio nicht hören.** Alle Aussagen zu Klang, Natürlichkeit und Aussprache stützen sich auf Messwerte und
automatische Spracherkennung (Whisper). Der eigentliche Hörtest steht aus und ist Sache des Nutzers.

## Ergebnis in Kürze

**Machbar – und in der App umgesetzt.** Auf Apple Silicon erzeugt die gebaute App ohne Netz und ohne Cloud ein
vollständiges Hörspiel: Geschichte mit Lektorat, entworfene Stimmen, KI-Geräusche, Mischung mit Kapitelmarken und
Export; dazu Hörbuch, Stimmenstudio, Referenzanalyse und Mehrspur-Editor. Abnahme auf macOS 15.8 und 26.7: je
23 von 23 Prüfungen.

- **Sprache:** Qwen3-TTS (einmal entwerfen, dann jede Zeile klonen) – Whisper-Fehlerrate 1,3 %, Stimme über alle
  Zeilen konstant, keine Verwechslung von Figuren; Umlaute, Komposita und Zahlen korrekt. Bester der vier Kandidaten.
- **Geschichte:** Gemma 4 26B-A4B schreibt gutes Deutsch; die Handlung hatte ohne Hilfe Logikfehler. Spurenplan,
  Stand der Handlung und Lektorat finden und beheben sie (Prüflauf: 5 Fehler gefunden, 3 Szenen gezielt überarbeitet).
- **Referenzanalyse:** echte Sprecher 5 von 5 getrennt, ohne Verwechslung; Stimmprofile übernehmen nur allgemeine
  Merkmale. Einwilligungsprüfung an 14 Sprechern kalibriert.
- **Grenzen:** Klang ist ungehört (Hörtest durch dich), Geschwindigkeit auf dem M5 Pro nicht gemessen (nur virtuelle
  M1 mit 3 Kernen), Gemma 4 in der App nicht auf 48 GB geprüft (Prüfrechner: 7 GB, kleines Modell).


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

### Stimmen (Sprachausgabe, mlx-audio 0.6.6 – Qwen3-TTS-Teil unverändert gegenüber 0.6.5)

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


## Messungen

### Geschichte (Gemma 4 26B-A4B, GGUF Q3_K_M, llama.cpp auf Linux-Prozessor, 4 Kerne)

| Lauf | Ergebnis |
|---|---|
| 1 (ohne Lektorat) | 10-Minuten-Krimi: 6 Szenen, 1070 Wörter (≈ 9 min), 8 Figuren, keine Wiederholungen. Gutes Deutsch, aber Logikfehler: eine Kiste wechselt ohne Erklärung den Ort, widersprüchliche Verwandtschaft, schwache Auflösung |
| 2 (mit Spurenplan und Lektorat) | 6 Szenen, 1126 Wörter (≈ 9,5 min), 7 Figuren. Lektorat fand 5 echte Fehler (Ort Schuppen/Keller, Kiste/Kette widerspricht der Auflösung, Verwandtschaft, Ortssprung im Finale) und überarbeitete Szene 4–6: Falltür mit Treppe, Kette als Schlüssel, Verwandtschaft stimmig. Rest: ein Ortswort im Schlusssatz, Handlung eher schlicht |
| Zeit | 43 min auf dem Linux-Prozessor (3,5 Token/s), davon Lektorat 17 min – auf dem M5 Pro mit MLX nicht gemessen |

### Sprachausgabe

| Messung | Ergebnis |
|---|---|
| Hörproben, Qwen3-TTS 1.7B (PyTorch, bf16, Linux-Prozessor, 4 Kerne) | 3 Szenen der Geschichte, 43 Zeilen, 6 entworfene Stimmen, 3:34 min gemischt (−16,1 LUFS). **Whisper-Fehlerrate 1 %** (Zeilen und Prüfsätze); einzige Abweichung „Spionen-Trupp“/„Spionentrupp“ und ein ausgelassenes „Psst“. Umlaute, Komposita, Zahlen („am vierzehnten Juli neunzehnhundertvierundachtzig um zweiundzwanzig Uhr fünfzehn“) fehlerfrei erkannt. Echtzeitfaktor 3,3 (Entwerfen) bzw. 4,1 (Klonen) |
| mlx-audio auf dem Linux-Prozessor (MLX CPU) | unbrauchbar langsam: Echtzeitfaktor 82 (Entwerfen) bzw. 172 (Klonen); Satzlängen plausibel (3,5–8,7 s) |
| mlx-audio auf Apple Silicon (Code der App) | siehe unten |

Apple Silicon, macOS 26.7 (virtueller M1, 3 Kerne, 7 GB), mlx-audio 0.6.5 – 4 entworfene Rollen × 8 Prüfsätze:

| Verfahren | Whisper-Fehler | Echtzeitfaktor (virt. M1) | Ähnlichkeit zur Referenz | zwischen Rollen | innerhalb einer Rolle |
|---|---|---|---|---|---|
| **Qwen3-TTS: entwerfen → klonen (App)** | **1,3 %** | 8,1 | 0,80 | 0,24 | 0,78 |
| VoxCPM2 (8 bit, klonen) | 1,7 % | 2,8 | 0,73 | 0,26 | 0,69 |
| Chatterbox Multilingual v3 | 2,1 % | 3,5 | 0,82 | 0,25 | 0,82 |
| Piper thorsten-high | 4,3 % | 0,8 | – | – | 0,79 |
| Qwen3-TTS: jede Zeile neu entwerfen | 2,2 % | 5,7 | 0,45 | 0,39 | **0,36** |

Wiederholung auf macOS 15.8 (ebenfalls virtueller M1): gleiche Werte (Qwen-Klonen 1,3 %, Konstanz 0,78; Piper hier
1,9 %) – die Ergebnisse sind reproduzierbar (feste Startwerte).

Kleines Sprachmodell auf dem Mac (Qwen3.5 4B, MLX, virtueller M1): 13 Token/s, 3-Szenen-Geschichte mit Lektorat in
10 min. Das Lektorat fand 5 Widersprüche; eine Überarbeitung mit Wiederholungen (0,26) wurde automatisch verworfen,
die alte Fassung blieb – die Sicherung greift.

Ergebnis: Das Verfahren der App (einmal entwerfen, dann klonen) ist am besten verständlich und hält die Stimme
über alle Zeilen konstant; jede Zeile neu zu entwerfen ergibt wechselnde Stimmen (0,36). Ziffern liest Qwen auch
ohne Ausschreiben richtig (0 % Fehler). Gefühlsangaben verändern die Tonhöhenbewegung messbar kaum (z. B. Qwen
3,96 gegenüber 3,90 Halbtöne Streuung) – ob Angst, Aufregung und Flüstern hörbar sind, ist eine Hörfrage.
Speicher: Qwen-Klonen bis 7,7 GB auf dem 7-GB-Rechner (ausgelagert) – auf 48 GB unkritisch. Die Echtzeitfaktoren
stammen vom virtuellen M1 mit 3 Kernen; auf einem M5 Pro sind sie deutlich kleiner, aber nicht gemessen.

Hinweis: Die Hörproben nutzen dieselben Gewichte wie die App, aber das PyTorch-Original statt mlx-audio. Klang und
Aussprache sind übertragbar, Geschwindigkeit und Umsetzungsdetails nicht.

### 10-Minuten-Hörspiel und App-Abnahme

**App-Abnahme auf Apple Silicon (macOS 15.8, virtueller M1, 7 GB, gebaute App mit `--hoerspiel-e2e`):**

Erster Lauf (17.11., 00:09): 18 von 22 Prüfungen – gefunden und behoben: Geräuschmodell erst ab mlx-audio 0.6.6,
„MUSIK:“ ohne Klammern wurde zur Figur, Geräuschfehler brach die Produktion ab, Prüfung der Mehrspur fehlerhaft.

Zweiter Lauf nach den Korrekturen (17.11., 03:06): **23 von 23 Prüfungen bestanden.**

| Schritt | Ergebnis | Zeit |
|---|---|---|
| Einrichtung: uv, Python 3.12, Pakete, Geschichtenmodell, zwei Stimmmodelle | bereit | 134 s |
| Geräusch- und Analysemodelle laden | 4 Modelle | 57 s |
| Hörspiel (3 min Ziel): Geschichte, Lektorat (5 Hinweise, 3 Szenen überarbeitet), 4 Stimmen, 8 Geräusche/Atmosphären, Mischung | 222 s Hörspiel, −16,0 LUFS, Sprache 21,4 dB über dem Hintergrund, 3 Kapitel | 39 min |
| Replik neu formulieren / neu sprechen / neu abmischen | Text geändert, Stimme neu, Mischung neu | 20 s / 95 s / 13 s |
| Mehrspur: Atmo stumm, Sprecher-Clip verschoben, neu abmischen | übernommen | 9 s |
| Export: MP3 mit Kapitelmarken (geprüft mit ffprobe: 3 Kapitel), Kapitel als M4A, Szenen als MP3, 6 Einzelspuren als FLAC | alle Dateien | je 2–5 s |
| Hörbuch (2 min Ziel, Erzählstil märchenhaft) | 501 Wörter, 182 s | 24 min |
| Stimme im Stimmenstudio entwerfen | Referenzsatz | 65 s |
| Referenzanalyse der eigenen Produktion | 4 Stimmen erkannt (stimmt: Erzähler + 3 Figuren) | 101 s |
| Stilprofile anlegen | 4 Profile, keines kann sprechen | – |

Wiederholung auf macOS 26.7 (17.11., 04:30): ebenfalls **23 von 23** – Hörspiel 3:21 min mit 9 Geräuschen,
−16,1 LUFS, Sprache 21,6 dB über dem Hintergrund; Hörbuch 781 Wörter (4:47 min). Neuer Befund: Das kleine Modell
schrieb eine ganze Szene mit dem Platzhalter „KENNUNG:“ aus der Formatbeschreibung statt mit Figuren – behoben
(Formatbeschreibung ohne Platzhalter, solche Zeilen gelten als ungültig und die Szene wird neu geschrieben).

Die Zeiten stammen vom virtuellen M1 mit 3 Kernen und dem kleinen Geschichtenmodell; auf dem M5 Pro mit Gemma 4
sind sie nicht gemessen. Musik (KI-Musik) war in diesem Lauf nicht eingerichtet und wurde mit Hinweis übersprungen.

**10-Minuten-Hörspiel im Prüfstand (macOS 26.7, virtueller M1, mlx-audio 0.6.5):** Drehbuch aus dem ersten
Gemma-Lauf (6 Szenen, 90 Repliken, 1062 Wörter), 7 Stimmen, Musik über die vorhandene KI-Musik (ACE-Step 1.5, 4
Stücke: Titel, Spannung, Übergang, Abspann).

| Messung | Ergebnis |
|---|---|
| Länge | 8:23 min (503 s), 6 Kapitelmarken |
| Lautheit / Spitze | −16,0 LUFS / −1,0 dBFS |
| Sprache über Musik/Hintergrund | 17,9 dB |
| Whisper-Fehlerrate | 1,3 % je Replik, 1,4 % über die fertige Mischung |
| Stimmen verwechselt | 0 von 90 Repliken näher an einer anderen Figur; Ähnlichkeit zur eigenen Referenz 0,74–0,85 (eine Replik von Lena 0,41) |
| Geräusche | in diesem Lauf noch ausgefallen (mlx-audio 0.6.5, siehe App-Abnahme – mit 0.6.6 behoben) |
| Rechenzeit (virtueller M1) | Stimmen 7 min entwerfen + 62 min sprechen (Echtzeitfaktor 10), Musik: Modell laden 51 min, je Stück 6–8 min, Mischen 2 min, gesamt 2:32 h |



## Referenzanalyse – gemessen auf Apple Silicon (macOS 26.7, virtueller M1, 7 GB)

Testaufnahme mit bekannter Wahrheit: 4,5 Minuten „Hörspiel“ aus fünf echten deutschen Sprechern (Multilingual
LibriSpeech), Erzähler plus vier Rollen, mit Pausen, Raumhall und Bandbreite wie von Kassette.

| Messung | Ergebnis |
|---|---|
| Sprechertrennung, Schwelle 0,65 (bisher) | 6 statt 5 Sprecher, Fehlerrate (DER) 22,1 % – davon verpasste Sprache 17,8 %, Verwechslung 3,6 % |
| Sprechertrennung, Schwelle 0,70–0,75 | **5 von 5 Sprechern, Verwechslung 0 %**, DER 18,5 % (nur verpasste Sprache an Satzrändern) → neue Standardschwelle 0,7 |
| Rechenzeit | Sprechertrennung 17 s, Whisper-Text 150 s, gesamt 184 s für 4,5 min Audio |
| Einwilligungsprüfung (ECAPA) | 14 Sprecher, 210 gleiche und 182 verschiedene Paare: gleiche Sprecher Median 0,836 (5 %-Quantil 0,665), verschiedene Median 0,146, höchstens 0,545 → **Schwelle 0,6** (vorher 0,5: ein fremder Sprecher hätte sie übertroffen) |
| Stimmprofil → neue Stimme (erste Fassung) | Tonhöhe der entworfenen Stimmen 3,6–8,8 Halbtöne zu hoch: „female or teenage voice, medium pitch“ wurde zu 250–314 Hz statt ~200 Hz |

Zweite Prüfaufnahme: das eigene 10-Minuten-Hörspiel (8,4 min, 7 entworfene Stimmen, mit Wahrheit aus der
Zeitleiste). Entworfene Stimmen liegen im Stimmraum enger beieinander als echte Sprecher: bei 0,65–0,7 nur 4 von 7
Stimmen (Verwechslung 29 %), bei 0,5–0,6 5 von 7 (18 %). Eine feste Schwelle passt also nicht für jede Aufnahme –
für echte Hörspielaufnahmen (wie MLS) ist 0,7 richtig. Neu: Wer die Anzahl der Stimmen kennt, trägt sie in
„Referenz analysieren“ ein; dann bildet die Analyse genau so viele Gruppen.

Daraus geändert:
- Beschreibungen nennen das Geschlecht eindeutig („adult man/woman“) und die Tonlage in Worten, die das
  Stimm-Design-Modell versteht; die Klangfarbe wird relativ zu den anderen Stimmen derselben Aufnahme beurteilt
  (vorher hieß jede Stimme der bandbegrenzten Aufnahme „dunkel, warm“).
- Beim Entwerfen aus einem Stilprofil entstehen drei Kandidaten; die App misst Tonhöhe und Tempo und nimmt den
  passendsten (allgemeiner Stimmcharakter, keine Nachbildung der Person). Gemessen (macOS 26, zweiter Lauf): mit
  den neuen Beschreibungen sank der Tonhöhenfehler im Mittel von 6,1 auf 4,0 Halbtöne (Einzelwerte 1,2–6,1); das
  Stimm-Design-Modell setzt Frauenstimmen weiterhin eher zu hoch an. Deshalb zusätzlich: liegt der beste Kandidat
  mehr als 2 Halbtöne daneben, wird das Tonlagen-Wort verschoben und zweimal nachgelegt. Dritter Lauf: **mittlerer
  Fehler 1,7 Halbtöne** (Einzelwerte 0,2–2,9; vorher 6,1 bzw. 4,0).
- Neue Beschreibungen in der MLS-Aufnahme: Geschlecht jetzt eindeutig (4 Frauen, 1 Mann), Klangfarbe „ausgewogen“
  statt durchgehend „dunkel, warm“.
- Bekannte Stimmenzahl: erste Fassung („maxclust“) verschlechterte die richtige MLS-Trennung (Verwechslung 0 % →
  12 %) und half bei den KI-Stimmen nicht (29 %). Neue Fassung: erst normal gruppieren, dann nur bei Bedarf Schwelle
  senken bzw. ähnlichste Gruppen zusammenlegen – bei richtiger Schätzung identisch zum Ergebnis ohne Angabe
  (gemessen: MLS 5 von 5, Verwechslung 0 %). Bei den eng beieinanderliegenden KI-Stimmen zerfiel die Gruppierung bei
  sehr kleinen Schwellen in eine einzige Gruppe – behoben (nur noch Schritte, die mehr Gruppen ergeben). Vierter
  Lauf: KI-Hörspiel mit Angabe „7“ → 7 von 7 Stimmen, Verwechslung 22 % (ohne Angabe 4 von 7, 29 %); MLS
  unverändert 5 von 5 ohne Verwechslung. Entworfene Stimmen bleiben für die Sprechertrennung schwierig.
- Nicht verlässlich: Nachhallschätzung (1,47 s für nahe aufgenommene Hörbuchsprecher ist zu hoch) – wird nur als
  „geschätzt“ angezeigt und nicht für Entscheidungen genutzt.
- Öffentliche LibriVox-Hörspiele ließen sich vom Prüfrechner nicht laden (archive.org: HTTP 403) – Prüfung C entfiel.


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


## Risiken und Grenzen

- **Apple-Silicon-Prüfrechner:** GitHub teilt die virtuellen M1-Rechner (macOS 14/15/26) am 16.11.2026 wiederholt
  nicht zu („not acquired … capacity constraints“). Deshalb wurden Sprachausgabe, Produktion und Analyse zusätzlich
  auf Linux mit MLX auf dem Prozessor gemessen: Qualität (Erkennbarkeit, Stimmähnlichkeit, Lautheit) ist
  übertragbar, die **Geschwindigkeit nicht** – Zeiten auf dem M5 Pro sind nicht gemessen.
- **Klang ist ungehört.** Natürlichkeit, Betonung, Gefühl und „klingt nicht nach Vorleser“ lassen sich nur mit
  Ersatzwerten prüfen (Whisper-Erkennbarkeit, Tonhöhenumfang, Stimmähnlichkeit). Der Hörtest durch den Nutzer ist
  die eigentliche Abnahme.
- **Geschichten:** Das Sprachmodell schreibt gutes Deutsch, aber die Handlung des ersten Prüflaufs hatte
  Logikfehler (eine Kiste wechselt ohne Erklärung den Ort, widersprüchliche Verwandtschaft, schwache Auflösung).
  Gegenmaßnahmen sind umgesetzt (Spurenplan, Stand der Handlung, Lektorat mit gezielter Überarbeitung); wie weit sie
  tragen, zeigt der zweite Prüflauf. Bei 60–120 Minuten steigt das Risiko von Widersprüchen – das Lektorat prüft
  die ganze Geschichte, die vorige Fassung jeder überarbeiteten Szene bleibt erhalten.
- **Gefühl in der Stimme:** Qwen3-TTS steuert Gefühle über die Stimmbeschreibung; beim Klonen aus dem Referenzsatz
  bleibt die Stimme gleich, der Ausdruck kommt vor allem aus dem Text. Wie stark Flüstern/Angst/Aufregung hörbar
  werden, ist eine Hörfrage.
- **Speicher:** Gemma 4 (15,4 GB) und die Stimmen (je 4,5 GB) werden nacheinander geladen, nie gleichzeitig; mit
  48 GB bleibt die Bibliothek nutzbar. Der Rechenprozess läuft mit niedriger Priorität und blockiert die Oberfläche nicht.
- **huggingface_hub 2.x** legt Modelle sonst in einem gemeinsamen Speicher ab – die App schaltet das ab
  (`HF_HUB_DISABLE_SHARED_BLOBS`), damit Größe und „Entfernen“ stimmen (gefunden und behoben im Katalog-Lauf).
- **Rechte:** Die Stilnachahmung bekannter Serien ist auf allgemeine Merkmale begrenzt; eine originalnahe
  Wiedererkennung bestimmter Sprecher ist ohne deren Einwilligung bewusst nicht möglich.


## Stand der Umsetzung (Phasen)

| Phase | Inhalt | Stand |
|---|---|---|
| 1 Machbarkeit | Architektur, Modellvergleich, deutsche Sprachausgabe, Referenzanalyse, Stimmprofile, ≥4 Rollen, 10-Minuten-Hörspiel | ✅ fertig; Ergebnisse siehe „Messungen“ |
| 2 Hörbuch | Erzähler, Erzählstile, Kapitel, eigene Aussprache, Sprache (DE/EN/FR/ES/IT) | ✅ umgesetzt; App-Abnahme auf Apple Silicon (macOS 15.8 und 26.7): deutsches Hörbuch erzeugt. Andere Sprachen nur in der Logik getestet, nicht gehört |
| 3 Hörspiel | Mehrere Sprecher, Geräusche, Musik (KI-Musik), Raumklang, Ducking, Retro-Klang, Lektorat | ✅ umgesetzt; App-Abnahme: Hörspiel mit Lektorat, 8–9 KI-Geräuschen, −16 LUFS, 3 Kapitelmarken. Musik über KI-Musik im 10-Minuten-Lauf des Prüfstands, nicht in der App-Abnahme |
| 4 Referenzanalyse | Sprecher, Rollen, Tonhöhe, Tempo, Pausen, Aufnahme-Charakter, Musikbrücken, Stilprofile | ✅ umgesetzt; echte Sprecher 5/5 ohne Verwechslung, Einwilligungsschwelle kalibriert; in der App-Abnahme Analyse und Stilprofile |
| 5 Studio | Mehrspur (Solo/Stumm/Pegel/Verschieben/Schneiden/Blenden, Einzelspuren), Export MP3/M4A/FLAC/WAV mit Kapiteln und Cover, Fortsetzen nach Abbruch | ✅ umgesetzt; App-Abnahme: Mehrspur geändert und neu abgemischt, Export ganz/Kapitel/Szenen/Einzelspuren. Fortsetzen nach Abbruch nur in Tests, nicht mit echtem Abbruch auf dem Mac |

Die App-Abnahme (`--hoerspiel-e2e`) klickt denselben Code durch wie ein Nutzer: Einrichtung, Hörspiel, Lektorat,
Replik neu formulieren und neu sprechen, Mehrspur ändern und neu abmischen, Export (ganz mit Kapiteln, Kapitel,
Szenen, Einzelspuren), Hörbuch, Stimme entwerfen, Referenzanalyse und Stilprofile.


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

