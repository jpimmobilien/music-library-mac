# Version 2.4 – „Hinzufügen“ und „Studio“ getrennt

Bis 2.3 lag alles im Audio Studio: Musik aus dem Netz laden, Dateien umwandeln, Titel der Bibliothek schneiden und
bearbeiten. Ab 2.4 sind das zwei eigene Einträge in der Navigation:

| Eintrag | Kürzel | Wofür |
|---|---|---|
| **Hinzufügen** | ⌘7 | Neue Musik: Adressen (YouTube, SoundCloud, Instagram und weitere über yt-dlp) und Audio-/Videodateien vom Mac laden, Ausschnitt wählen, umwandeln, Metadaten und Cover setzen, in die Bibliothek übernehmen. Werkzeuge für Internet-Quellen, Warteschlange und Verlauf der Downloads. |
| **Studio** | ⌘8 | Nur Bearbeitung von Titeln, die schon in der Bibliothek sind: **Bearbeiten** (Lautstärke, Verbesserung, Tempo, Tonhöhe, Stimmung, Auto-Tune, Equalizer, Beschneiden) und **Schneiden** (verlustfrei, wenn möglich). Original ersetzen mit Sicherung und „Rückgängig“ oder neue Datei. |

Die sechs Bereiche der Bibliothek behalten ⌘1 … ⌘6; eine feine Linie trennt sie in der Navigation von den beiden
Arbeitsbereichen.

## Studio

- Ohne geöffneten Titel zeigt das Studio, was es kann, und eine **Titelauswahl**: den gerade laufenden Titel,
  die zuletzt hinzugefügten und eine Suche (Titel, Interpret, Album). Ein Klick öffnet den Titel zum
  **Bearbeiten**, „Schneiden“ nur zum Schneiden. Nicht erreichbare Dateien sind gekennzeichnet.
- Weiterhin auch per Rechtsklick auf einen Titel: „Titel bearbeiten …“ bzw. „Im Studio schneiden …“.
- Eine Datei aus der Bibliothek auf das Studio ziehen öffnet sie zum Bearbeiten; andere Dateien und Links gehen
  automatisch an „Hinzufügen“.
- Das Studio hat kein Adressfeld mehr und keine Werkzeuge für Internet-Quellen.

## Gemeinsam

- **Eine Warteschlange, ein Verlauf**: Beide Bereiche nutzen dieselbe Warteschlange (Aufträge laufen
  nacheinander), aber jeder zeigt nur seine eigenen Aufträge und Einträge. „Erledigte entfernen“ und
  „Verlauf löschen“ wirken nur im jeweiligen Bereich.
- Einstellungen (Format, Ziel, Dateiname, „Im Finder zeigen“) gelten für beide und stehen unter
  Einstellungen → „Hinzufügen & Studio“.
- Vorhören, Leertaste, I/O und das Menü „Studio“ wirken auf den gerade offenen Bereich. Beide Bereiche merken sich
  ihren Zustand: Wer in „Hinzufügen“ einen Link lädt, ins Studio wechselt und zurückkommt, findet den Link wieder.

## Technik

- Zwei Modelle derselben Art (`StudioModel`): „Hinzufügen“ führt Warteschlange, Verlauf und Einstellungen; das
  Studio reicht Aufträge dorthin weiter und spiegelt die Einstellungen. Kein zweiter Hintergrundprozess, keine
  zweite Warteschlange.
- Verlaufseinträge tragen neu `fromLibrary` (Bearbeitung eines Bibliothekstitels). Ältere Einträge ohne dieses
  Feld: Ein ersetztes Original zählt zum Studio, alles andere zu „Hinzufügen“. Der Verlauf bleibt mit 2.3 lesbar
  (2.3 übergeht das neue Feld).
- Keine Datenbankänderung, Ordner und Dateien wie bisher (`~/Music/Audio Studio`, Application Support).
