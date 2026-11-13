# Version 2.3 – Titel bearbeiten

Titel der Bibliothek dauerhaft verändern: **Rechtsklick auf einen Titel → „Titel bearbeiten …“** (auch in der
Warteschlange des Players) oder im Studio bei einem Bibliothekstitel oben **„Schneiden | Bearbeiten“**.

## Werkzeuge

| Bereich | Was es tut |
|---|---|
| **Beschneiden** | Start und Ende in der Wellenform bzw. auf die Millisekunde, Ein-/Ausblenden (wie beim Schneiden) |
| **Lautstärke** | −12 … +12 dB; Spitzen werden weich auf −1 dB begrenzt (nichts übersteuert) |
| **Automatisch verbessern** | Lautheit angleichen (EBU R 128: −14 LUFS „Streaming“, −16, −11 oder −23 LUFS – gemessen nach allen anderen Änderungen), Rumpeln und Gleichanteil unter 25 Hz entfernen, Übersteuerung verhindern (−1 dB), Stille am Anfang und Ende entfernen (unter −60 dB, kurze Ränder bleiben). Verlorene Qualität einer schwachen MP3 lässt sich damit nicht zurückholen |
| **Tempo** | 0,5× … 2,0× – mit gleicher Tonhöhe (Zeitdehnung in Android-Qualität) oder „wie eine Schallplatte“ (schneller = höher) |
| **Tonhöhe** | −12 … +12 Halbtöne, Feinstimmung ±50 Cent, Tempo bleibt |
| **Stimmung (Kammerton)** | erkennt, auf welchem Kammerton der Titel steht (z. B. „A4 ≈ 441,6 Hz“), und stimmt auf 432, 440, 442, 444 Hz oder einen eigenen Wert um – Tempo und Länge bleiben |
| **Auto-Tune** | zieht Gesang auf die Töne einer Tonart (Dur, Moll oder chromatisch; erkannte Tonart per Klick), Stärke von „natürlich“ bis „Roboter“. Am besten bei Einzelstimmen; in fertig gemischten Songs verschiebt es den ganzen Mix (siehe unten) |
| **Equalizer** | 10 Bänder (31 Hz – 16 kHz, ±12 dB) und Bass, alle Voreinstellungen und eigene Presets, „Wie im Player“ übernimmt die aktuelle Einstellung des Players – dieselben Filter wie im Player |

- **Vorhören:** Leertaste bzw. Abspielknopf; „Original | Bearbeitet“ schaltet an derselben Stelle um. Änderungen
  sind nach einem Moment zu hören (die Wiedergabe setzt an derselben Stelle neu an). Der Hauptplayer bleibt unberührt.
- **Speichern:** standardmäßig **Original ersetzen** – mit Bestätigung, Sicherung (Prüfsumme) und „Rückgängig“ im
  Verlauf; Favoriten, Playlists, Statistik, Hinzufügedatum, Tags, Cover und Liedtexte bleiben. Oder **als neue Datei**
  „… (bearbeitet)“ neben dem Original. Format wie das Original (MP3/AAC werden dafür mit gleicher Bitrate neu
  kodiert, WAV/FLAC/AIFF/ALAC verlustfrei) oder ein anderes Format.
- Der Verlauf zeigt, was geändert wurde („Tempo 1,1× · 441,6 → 432 Hz · Equalizer „Pop“ …“).

## Technik

- Neue Bausteine in `MLCore/Audio/Edit` (reine Logik, auch unter Linux getestet): Biquad-Filter, Lautheit nach
  ITU-R BS.1770-4 (K-Bewertung für jede Abtastrate wie libebur128), Begrenzer mit 5 ms Vorausschau,
  Grundfrequenzerkennung (McLeod), Stimmungs- und Tonarterkennung (Spektralspitzen, Krumhansl-Kessler-Profile),
  Auto-Tune (TD-PSOLA), `EditChain` (Hochpass → Equalizer → Auto-Tune → Tempo/Tonhöhe mit der vorhandenen
  `TimePitchEngine` → Verstärkung → Begrenzer).
- Export: Messdurchgang (Lautheit nach der Bearbeitung, hörbarer Bereich), dann Verarbeitung blockweise – nie die
  ganze Datei im Speicher. Vor dem Ersetzen wird die Länge geprüft (Tempo berücksichtigt; „Stille entfernen“ darf
  kürzen).
- Keine Datenbankänderung. Verlauf und Einstellungen bleiben mit 2.2 lesbar.

## Grenzen

- **Auto-Tune bei fertigen Songs:** Stimme und Instrumente lassen sich nicht trennen. Erkannt wird nur, wo eine
  Melodie deutlich vorherrscht; die Korrektur verschiebt dort den ganzen Mix. Gut geeignet für A-cappella-,
  Gesangs- und Sprachaufnahmen.
- **Stimmungs-/Tonarterkennung** ist eine Schätzung (bei elektronischer oder atonaler Musik oft „nicht eindeutig“) –
  Ausgangswert und Tonart lassen sich von Hand setzen.
- Vorhören folgt Reglern mit kurzer Verzögerung; die Lautheitsangleichung ist beim Vorhören geschätzt (aus dem
  Original), beim Speichern genau gemessen.
- Bedienung von Hand und Klang über Lautsprecher: siehe [STATUS.md](STATUS.md).
