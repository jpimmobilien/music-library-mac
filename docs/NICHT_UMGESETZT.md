# Noch nicht umgesetzt bzw. noch nicht geprüft

## Noch nicht geprüft

Gebaut, automatisch getestet und auf macOS 26 und 14 gestartet ist die App (siehe [STATUS.md](STATUS.md)).
**Nicht** geprüft sind die Bedienung von Hand, die Wiedergabe über Lautsprecher, das Einlesen einer echten
Sammlung, macOS 13 Ventura und die Oberfläche auf echter Intel-Hardware.

## Nicht umgesetzt

| Thema | Stand |
|---|---|
| **Opus und Ogg FLAC** abspielen | Tags werden gelesen/geschrieben, die Titel erscheinen in der Bibliothek, Abspielen meldet „nicht unterstützt“. Ogg **Vorbis** wird abgespielt. |
| **WMA, WavPack, TTA, DSD (DSF/DFF), APE, Musepack, Speex** | werden beim Scan nicht aufgenommen (macOS kann sie nicht abspielen); Tag-Bearbeitung wäre vorhanden |
| **Lückenlose Wiedergabe** (gapless) | der nächste Titel wird nach dem Ende des vorigen geladen – kurze Pause möglich (Live-Alben, DJ-Mixe) |
| **Widgets** (Schreibtisch/Mitteilungszentrale) | nicht umgesetzt – braucht eine App-Erweiterung mit Xcode-Projekt und Signierung. Ersatz: Mini-Player-Fenster und Player in der Menüleiste |
| **Notarisierung / Developer-ID** | nicht möglich ohne Apple-Entwicklerkonto; die App ist ad-hoc signiert (Erststart siehe INSTALLATION.md) |
| **Anzeige, wann der Limiter tatsächlich eingreift** | angezeigt wird, dass über 100 % verstärkt wird und der Limiter aktiv ist – nicht die tatsächliche Pegelbegrenzung |
| **Übernahme aus Apple Music / iTunes** (Playlists, Wertungen, Wiedergabezahlen der Musik-App) | nicht umgesetzt; die App liest die Dateien aus den gewählten Ordnern |
| **AirPlay-Auswahl in der App** | keine eigene Schaltfläche; die Ausgabe lässt sich über das Kontrollzentrum von macOS wählen |
| **Sprachen** | nur Deutsch |
| **VoiceOver** | Bedienelemente sind beschriftet, aber nicht mit VoiceOver getestet |
| **Hörtest / Messung auf echter Hardware** | nicht durchgeführt; die App-Tests messen die Klangkette offline, wurden aber noch nicht ausgeführt |
