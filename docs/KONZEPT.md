# Panora – Produktkonzept, Architektur und Roadmap

Stand: 16.11.2026 · Version 0.1 (erste DMG)

## 1. Produktzweck

Panora ist eine **lokale KI-Anwendung für macOS**, die möglichst viele bisherige Claude-Aufgaben ohne Cloud-Abo
erledigt. Die eigentliche Arbeit macht der Mac (MacBook Pro, M5 Pro, 64 GB Unified Memory) mit Open-Weight-Modellen.
Cloud-Dienste (OpenAI, Anthropic) sind nur optionale „externe Experten“ auf ausdrücklichen Klick.

Panora ist **kein Frontend für Ollama**: Aufgabenerkennung, Modellrouting, Kontextverwaltung und (später)
Agentenorchestrierung sind eigene Schichten. MLX und Ollama sind austauschbare Rechenwerke.

## 2. Leitlinien

| Leitlinie | Umsetzung in Panora |
| --- | --- |
| Lokal zuerst | Chat, Modellverwaltung, Projektanalyse laufen ohne Internet. Offline werden nur Downloads, Hugging-Face-Suche und Experten als „nicht verfügbar“ markiert. |
| Keine heimliche Cloud | Kein automatischer Cloud-Aufruf. Vor jeder Zweitmeinung zeigt Panora den vollständigen Text, der den Mac verlässt. Schlüssel liegen im Schlüsselbund. |
| AUTO zuerst, MANUELL respektiert | AUTO wählt und wechselt Modelle selbst und zeigt warum. Ein manuell gewähltes Modell wird nie ersetzt – höchstens nach Rückfrage. |
| Transparenz | An jeder Antwort steht das Modell, der Modus (AUTO/MANUELL), die erkannte Aufgabe und auf Wunsch die Begründung. Wechsel erscheinen als Hinweis im Gespräch. |
| Lizenzen sichtbar | Offenheit („Open Source“ nur OSI-konform, sonst „Open Weight“) und Bedingungen (frei, mit Auflagen, nicht kommerziell) getrennt; Regionssperren blockieren die Installation. |
| Externe SSD | Große Modelle bevorzugt auf der Samsung-SSD; Laufwerke werden erkannt, fehlende Laufwerke klar gemeldet, Modelle nach dem Anschließen automatisch wieder verfügbar. |

## 3. Architektur

```
┌──────────────────────────── Panora.app (SwiftUI, Liquid Glass) ────────────────────────────┐
│ Navigation oben (wie die Musik-App) · Chat · Verlauf · Modelle · Entdecken · Projekte ·     │
│ Hardware · Speicher · Einstellungen · schwebende Eingabe mit Modell-Scheibe unten            │
├──────────────────────────────── Intelligenzschicht (PanoraCore) ────────────────────────────┤
│ TaskAnalyzer → TaskProfile   ModelRouter (+ MemoryPlanner)   ContextEngine   ExpertAPI       │
│ ModelCatalog + Lizenzen      HuggingFace-API   ProjectScanner   ReasoningSplitter            │
├──────────────────────────────── Dienste (App) ──────────────────────────────────────────────┤
│ ChatController · InferenceCoordinator · ModelLibrary · DownloadManager · HardwareMonitor ·  │
│ StorageMonitor · NetworkMonitor · ProjectStore · ChatStore · Keychain                        │
├──────────────────────────────── Rechenwerke ─────────────────────────────────────────────────┤
│ MLX (mlx-swift-lm 3.32, Metal, Unified Memory)      Ollama (lokaler Dienst, optional)        │
└──────────────────────────────────────────────────────────────────────────────────────────────┘
```

**PanoraCore** ist reine Logik ohne Apple-Frameworks und wird in der CI auch unter Linux getestet.

### 3.1 AUTO MODE

1. **Aufgabe erkennen** (`TaskAnalyzer`): feste, nachvollziehbare Regeln für Deutsch und Englisch –
   Code-Blöcke, Dateiendungen, Fehlermeldungen, Schlüsselwörter für Analyse, Architektur, Implementierung,
   Review, Text, Übersetzung, Mathe. Ergebnis: Aufgabenart, Schwierigkeit 1–5, Tempo-Wunsch, Kontextgröße,
   Belege für die Begründung. Kurze Fortsetzungen („mach weiter“) behalten die vorherige Aufgabe.
2. **Hart filtern** (`ModelRouter`): nicht verfügbar (Laufwerk fehlt), Regionssperre, zu kleines
   Kontextfenster, fehlende Fähigkeit, passt nicht ins Speicherbudget.
3. **Bewerten**: erwartete Qualität (vier Achsen: Allgemein, Coding, Reasoning, Texte – gewichtet je Aufgabe),
   erwartetes Tempo (aus Speicherbandbreite und aktiven Parametern, später gemessen), Ladezeit (Größe ÷
   gemessene SSD-Geschwindigkeit), Entladekosten. Bei Software-Arbeit zählt Qualität mindestens 78 %.
   Ein kleineres Spezialmodell kann so ein größeres Allround-Modell schlagen.
4. **Nicht unnötig wechseln**: Das laufende Modell bleibt, wenn es fast so gut ist (einstellbar).

### 3.2 Modellwechsel mitten im Chat

Beispiel Android-App: Qwen3.6 27B analysiert und plant, Qwen3.6 35B A3B implementiert, für das Review kann
wieder das dichte Modell übernehmen. Bei jedem Wechsel baut die **Context Engine** ein Paket für das Zielmodell:

- Systemanweisung + Übergabehinweis („Du übernimmst von …, Grund …“)
- Arbeitsstand: Entscheidungen, offene Aufgaben (erledigte `- [x]` fallen weg), Ergebnisse je Modell, erwähnte Dateien
- Projektkontext (Struktur, README, Build-Dateien, angefragte Dateien – gekürzt auf ein Viertel des Budgets)
- Zusammenfassung älterer Nachrichten, die nicht mehr ins Kontextfenster passen
- die jüngsten Nachrichten im Wortlaut; Rollen werden für strenge Chat-Vorlagen zusammengeführt

### 3.3 MANUELL

Schalter „Auto | Manuell“ direkt in der Eingabe, gilt pro Chat. Im manuellen Modus wählt der Nutzer ein Modell;
Panora ersetzt es nie. Ist es nicht nutzbar (z. B. Laufwerk getrennt), meldet Panora das mit einem Vorschlag.
Mit „Wechsel nach Rückfrage erlauben“ erscheinen bessere Modelle nur als Vorschlag mit Knopf.

### 3.4 Speicher- und Hardwaremanagement

- Modellbudget: Anteil der 64 GB (Standard 70 % ≈ 45 GB); der Rest bleibt für macOS, Xcode, Android Studio, Emulator.
- Bedarf = Gewichte + KV-Cache (aus `config.json`: Schichten × KV-Köpfe × Kopfgröße) + Puffer.
- Vor dem Laden entlädt der Planer, was am längsten ungenutzt ist; nach einstellbarem Leerlauf wird alles entladen.
- Live: verfügbarer Speicher, CPU- und GPU-Auslastung, geladene Modelle, Token-Raten je Modell (gemessen).

### 3.5 Externe SSD

Konfigurierbare Modellordner, Downloadziel wählbar, automatische Erkennung angeschlossener Laufwerke
(inklusive Gerätename und Anschluss über `diskutil`), Speicherplatzanzeige, Tempomessung (USB-C allein sagt
nichts über das Tempo), Warnungen bei fehlendem Laufwerk, Wiederherstellung nach erneutem Anschließen.
Downloads landen erst als `….partial` und werden nach dem letzten Byte freigeschaltet.

### 3.6 Externe Experten

„Zweitmeinung“-Menü in der Eingabe: „Mit ChatGPT überprüfen“, „Mit Claude überprüfen“. Panora fasst
Arbeitsstand und letzten Verlauf zusammen, zeigt den Text vollständig an und sendet erst nach Bestätigung.
Die Antwort erscheint als eigene Karte; „Von Panora bewerten lassen“ lässt die lokale KI sie kritisch prüfen.

## 4. Was Version 0.1 kann

- Lokaler Chat mit MLX-Modellen (Streaming, Gedankengang getrennt, Markdown und Code) und Ollama-Modellen
- AUTO MODE mit Begründung, Modellwechsel mitten im Chat inklusive Kontextübergabe, MANUELL mit Rückfrage
- Model Manager: Katalog mit Lizenzen, Hugging-Face-Suche (alle MLX-Modelle), Download auf die SSD,
  Laden/Entladen, Entfernen (Papierkorb), Modelle anderer Ordner (auch LM-Studio-Struktur) werden erkannt
- Projekte: Ordner lesend analysieren und als Kontext an den Chat hängen
- Hardware- und Speicherseiten, Offline-Erkennung, Offline-Modus erzwingen
- Zweitmeinung von ChatGPT/Claude mit Vorschau

## 5. Roadmap

| Priorität | Meilenstein | Inhalt |
| --- | --- | --- |
| 1 | 0.1 (diese DMG) | Lokale Inference (MLX, Ollama), Modellverwaltung, SSD, Hardware |
| 2 | 0.2 | AUTO MODE lernt aus Messungen (Antwortrate, Abbrüche, Nutzerbewertung), Vorladen des nächsten Modells, Hilfsmodell für Titel und Zusammenfassungen, Apple-Systemmodell (macOS 27) für die Aufgabenerkennung |
| 3 | 0.3 | Agentisches Coding: Planer-Agent mit Schritten (Analyse → Architektur → Implementierung → Review), Werkzeuge Dateien lesen/schreiben mit Bestätigung, Diff-Ansicht, Embedding-Suche im Projekt |
| 4 | 0.4 | Builds und Tests: Gradle, xcodebuild, swift test; Fehler automatisch an das Coding-Modell |
| 5 | 0.5 | Office und Kreativ: Dokumente, Tabellen, Präsentationen (lokal erzeugt), Bildgenerierung (FLUX.2 klein, Z-Image) |
| 6 | 0.6 | Externe Experten ausbauen (Vergleichsansicht, Kostenanzeige), weiterhin nur auf Klick |
| – | 1.0 | Signierung und Notarisierung (Developer ID), automatische Updates |

Die Cloud-Integration darf die lokalen Kernfunktionen nicht verzögern; sie bleibt eine dünne, optionale Schicht.
