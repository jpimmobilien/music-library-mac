# Version 2.5 – KI-Musik (lokal, ACE-Step 1.5)

Neuer Eintrag **„KI-Musik“** in der Navigation (⌘8, zwischen „Studio“ und „Hinzufügen“). Musik aus einer
Beschreibung erzeugen – vollständig auf dem Mac, ohne Cloud, Konto oder Kosten. Grundlage und Messungen:
[KI_MUSIK_MACHBARKEIT.md](KI_MUSIK_MACHBARKEIT.md).

## Voraussetzungen

- Mac mit **Apple-Chip** (M1 oder neuer) und macOS 14 oder neuer. Auf Intel-Macs zeigt „KI-Musik“ nur einen
  Hinweis – die Bibliothek bleibt unverändert nutzbar.
- Einmalige Einrichtung auf Knopfdruck: Python-Umgebung mit ACE-Step 1.5 (ca. 1,2 GB) und das Grundpaket der
  Modelle (ca. 10,4 GB). Abbrechen jederzeit, ein neuer Versuch setzt fort. Alles liegt unter
  `~/Library/Application Support/Music Library/KI-Musik` und lässt sich in den Einstellungen vollständig entfernen.

## Erzeugen

- Große Beschreibung („Create your own sound.“) mit Vorlagen (Synthwave, Deutscher Pop, Lo-Fi, Akustik, Orchester,
  House) und Verlauf der letzten Beschreibungen; der Entwurf wird automatisch gespeichert.
- **Gesang und Text:** Instrumental · KI schreibt den Text · eigener Text · Text überarbeiten lassen; Sprache des
  Gesangs aus 50 Sprachen (Deutsch, Englisch, Französisch, Spanisch, Italienisch, Portugiesisch und Niederländisch
  oben). Deutsche Texte werden nicht übersetzt. Schnellknöpfe für `[Verse]`, `[Chorus]` usw.
- **Länge** 30 s bis 6 min per Knopf oder frei von 10 s bis 10 min (Grenze von ACE-Step 1.5), **1–4 Varianten**,
  **Qualität:** Schnell (2B, ohne Planung) · Ausgewogen (2B mit Planung durch das Sprachmodell) · Hohe Qualität
  (Musikmodell XL, ca. 9 GB zusätzlich), **Erweitert:** BPM, Tonart, Taktart, Startwert (Seed).
- Während des Erzeugens: bewegte Wellenform, Schritt, Fortschritt, verstrichene und geschätzte Zeit (die Schätzung
  lernt aus den eigenen Läufen), **Abbrechen**.

## Meine KI-Kreationen

- Eigener Ordner `~/Music/KI-Musik` – **nicht** Teil der Bibliothek. Filter (Alle, Songs, Instrumentals, Remixes,
  Gesang, Favoriten) und Suche; je Stück Art, Länge, Sprache, Datum, Startwert und Beschreibung.
- Anhören (eigener Vorhör-Player, der Hauptplayer bleibt unberührt), Favorit, Umbenennen, Erneut erzeugen (gleicher
  Startwert), Neue Variation, Im Finder zeigen, In den Papierkorb.
- **In die Bibliothek übernehmen:** über die Warteschlange von „Hinzufügen“ – Format, Ziel und Dateiname wie dort,
  Interpret „KI-Musik“.

## Technik und Datenschutz

- Ein eigener Python-Prozess rechnet (Musikmodell und VAE mit MLX, Sprachmodell mit MLX; Rückfall auf PyTorch bzw.
  den Prozessor, wenn MLX-Kernel scheitern oder der Grafikspeicher nicht reicht). Verbindung über stdin/stdout,
  **kein Netzwerk-Port**; der Prozess läuft in einer **Sandbox ohne Netzwerkzugriff** und mit niedriger Priorität.
- Der Prozess startet erst beim Erzeugen und wird nach einstellbarer Leerlaufzeit (Standard 10 min) beendet –
  dann ist der Arbeitsspeicher frei. Abbrechen beendet ihn sofort.
- Einstellungen → **KI-Musik:** Eignung des Macs, freier Speicher, Umgebung, Modelle (Größe, Stand, Laden,
  Entfernen), Leerlaufzeit, Protokoll, Ordner der Kreationen, vollständiges Entfernen, Lizenzen.

## Noch nicht enthalten

Gesang entfernen/Spuren trennen, Remix eigener Songs, Stimmumwandlung und Mehrspuransicht sind geprüft bzw. geplant,
aber noch nicht in der App – siehe [NICHT_UMGESETZT.md](NICHT_UMGESETZT.md).
