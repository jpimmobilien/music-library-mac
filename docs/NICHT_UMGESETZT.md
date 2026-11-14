# Einschränkungen und offene Punkte (Version 2.5)

## „Hinzufügen“ und „Studio“ (2.4)

| Punkt | Stand |
|---|---|
| **Auto-Tune bei fertigen Songs** | Weiterhin kaum hörbar (siehe 2.3): Dafür muss erst der Gesang vom Rest getrennt werden. Das geht technisch mit einem KI-Modell (demucs-mlx, im Machbarkeitsbericht geprüft) und kommt mit der KI-Musik; die Lizenz der Demucs-Gewichte ist ungeklärt. |
| **Titelauswahl im Studio** | Zeigt den laufenden Titel, die 40 zuletzt hinzugefügten und bis zu 80 Suchtreffer – keine vollständige Bibliotheksliste (dafür Rechtsklick in „Titel“). |
| **Ältere Verlaufseinträge** | Einträge von 2.2/2.3 tragen noch nicht, ob sie zu einem Bibliothekstitel gehören: Ersetzte Originale erscheinen im Studio, „als neue Datei geschnittene“ Bibliothekstitel aus 2.3 unter „Hinzufügen“. |
| **Bedienung von Hand** | Wechsel zwischen den Bereichen, Titelauswahl, Ziehen auf das Studio als Vorschaubild und in automatischen Abläufen geprüft, nicht von Hand bedient. |

## KI-Musik (2.5)

| Punkt | Stand |
|---|---|
| **Nur Apple Silicon** | Auf Intel-Macs gibt es PyTorch/MLX nicht mehr; „KI-Musik“ zeigt dort nur einen Hinweis. |
| **Geschwindigkeit auf echter Hardware** | Nicht gemessen. Geprüft nur auf virtuellen M1-Rechnern (3 Kerne, 7 GB, ohne nutzbaren Grafikspeicher): 20 s Musik in 8–11 Minuten auf dem Prozessor. Auf einem M5 Pro mit 48 GB rechnet das Modell auf der Grafik – deutlich schneller, aber ungeprüft. Die Zeitschätzung lernt aus den eigenen Läufen. |
| **Klang** | Nicht gehört. Geprüft sind Länge, Pegel, keine Stille/kein Rauschen und die Verständlichkeit deutschen Gesangs per Spracherkennung. |
| **KI-geschriebene Texte** | Mit dem kleinen Sprachmodell (0.6B) inhaltlich schwach („Komm wir machen Schnaps …“). Standard auf Macs ab 24 GB ist das 1.7B-Modell, ab 40 GB das 4B-Modell (separat laden) – beide ungeprüft. Eigener Text geht immer. |
| **„Hohe Qualität“** | Braucht das XL-Modell (ca. 9 GB, separat laden); nicht geprüft. |
| **Gesang entfernen, Spuren trennen, Remix eigener Songs, Stimmumwandlung, Mehrspuransicht** | Noch nicht in der App. Trennung und Remix sind technisch geprüft (demucs-mlx bzw. ACE-Step „cover“); Lizenz der Demucs-Gewichte ungeklärt; Stimmumwandlung braucht ein eigenes Modell. |
| **macOS 13** | Nicht unterstützt (KI-Musik braucht macOS 14+); geprüft nur macOS 15 und 26. |
| **Bedienung von Hand** | Oberfläche als Vorschaubild und mit Ersatz-Rechenprozess geprüft; Einrichtung und Erzeugen mit echtem ACE-Step im Prüfstand über den Code der App, nicht durch Klicken. |

## Titel bearbeiten (2.3)

| Punkt | Stand |
|---|---|
| **Auto-Tune in fertig gemischten Songs** | Stimme und Instrumente lassen sich nicht trennen; erkannt wird nur eine deutlich vorherrschende Melodie, die Korrektur verschiebt dann den ganzen Mix. Für Einzelstimmen gebaut und mit synthetischen Stimmen gemessen (452 Hz → 438–440 Hz), nicht mit echten Gesangsaufnahmen angehört. |
| **Stimmungs- und Tonarterkennung** | Schätzung aus Spektralspitzen; mit synthetischen Akkorden geprüft (442 Hz → 442,1 Hz, C-Dur erkannt), nicht mit einer Sammlung echter Titel. Unsichere Ergebnisse werden als „unsicher“ bzw. „nicht eindeutig“ angezeigt. |
| **Vorhören** | Folgt Reglern mit kurzer Verzögerung (Wiedergabe setzt neu an); Lautheitsangleichung beim Vorhören geschätzt. |
| **MP3/AAC** | Werden für die Bearbeitung neu kodiert (gleiche Bitrate) – minimaler Generationsverlust. |
| **Bedienung und Klang** | Regler, Vorhören und Speichern über Vorschaubilder und automatische Abläufe geprüft, nicht von Hand bedient; Klang gemessen, nicht über Lautsprecher angehört. |

## Audio Studio (2.2)

| Punkt | Stand |
|---|---|
| **Spotify-Audio** | Nicht umgesetzt – kopiergeschützt (DRM). Spotify-Links liefern nur Titel und Cover. |
| **YouTube** | Umgesetzt (yt-dlp + Deno), aber **auf echten YouTube-Inhalten nicht nachgewiesen**: YouTube verlangt auf den GitHub-Testrechnern eine Anmeldung („Sign in to confirm you're not a bot“). Das wurde nicht umgangen. Diese Sperre trifft vor allem Rechenzentren und VPNs; ob es an deinem Anschluss funktioniert, ist nicht geprüft. Ändert YouTube etwas, hilft meist „Werkzeuge → Aktualisieren“. |
| **SoundCloud** | Mit einem CC-lizenzierten Titel von der Analyse bis zum MP3-Export geprüft. Kostenpflichtige Go+-Titel liefern nur eine Hörprobe und werden abgelehnt. |
| **Instagram** (2.2.3) | Öffentliche Reels und Videos: mit einem Reel des NASA-Kontos von der Analyse bis zum MP3-Export auf den GitHub-Testrechnern geprüft (ohne Anmeldung erreichbar). Private, altersbeschränkte oder nur angemeldet sichtbare Beiträge werden nicht geladen; begrenzt Instagram die Abrufe, kommt eine verständliche Meldung. Ob Instagram an deinem Anschluss gleich antwortet, ist nicht geprüft. Bietet Instagram keine reine Tonspur an, wird ein Video (höchstens 720p) geladen – dieser Weg ist mit nachgebauten Dateien geprüft, nicht mit einem echten Beitrag. |
| **Anmeldung, Cookies, Altersgrenzen, private Inhalte** | Bewusst nicht unterstützt. |
| **Bedienung von Hand** | Ziehen der Auswahl, Zoom, Ablegen von Dateien, Tastatur und Dialoge sind gebaut und als Vorschaubild geprüft, aber nicht automatisch bedient. |
| **Anhören** | Klang über Messungen (Störabstand, Bitgenauigkeit, Klickmarken) geprüft, nicht über Lautsprecher. |
| **Rohes AAC (.aac)** | Kann keine Tags/kein Cover speichern und die Encoder-Verzögerung nicht kennzeichnen (Datei ≈ 60 ms länger). Für die Bibliothek M4A verwenden. |
| **MP3-Dauer in macOS** | Bei 160 und 224 kbit/s meldet macOS (AVFoundation) einen Frame (26 ms) mehr als die tatsächliche Länge; die Datei selbst ist exakt (mit FFmpeg geprüft). |
| **Opus/WebM/MKV-Dateien** | Nur mit installiertem FFmpeg (z. B. Homebrew); ohne FFmpeg verständliche Meldung. |
| **Sicherungen** | Ersetzte Originale werden unter „Audio Studio/Backups“ aufbewahrt und nicht automatisch gelöscht. |
| **Warteschlange** | Wird beim Beenden nicht gespeichert (keine Downloads ohne Nutzeraktion beim nächsten Start); der Verlauf bleibt. |
| **Fenster 940 × 660** | Die schwebende Exportleiste überdeckt den unteren Teil der Wellenform; man muss scrollen. |
| **Voller Datenträger** | Wird erkannt und gemeldet, aber nicht getestet. |

# Einschränkungen aus Version 2.1

## Nicht geprüft (kein Gerät bzw. nicht automatisierbar)

| Thema | Stand |
|---|---|
| **macOS 13 Ventura** | Die App ist für macOS 13 gebaut (Mindestversion 13.0 in beiden Architekturen, keine neueren Schnittstellen ohne Abfrage). GitHub bietet keinen macOS-13-Rechner mehr an – **auf Ventura nicht gestartet**. |
| **Echter Intel-Mac** | Alle Tests laufen nativ auf einem Intel-Rechner (macOS 15). Die fertige DMG wurde auf einem Intel-Rechner (virtueller Mac, macOS 26) installiert und gestartet: Einlesen, Datenbank-Aktualisierung und Messlauf liefen dort nativ in x86_64. Vorschaubilder gibt es von Intel nicht (keine Metal-Grafik). **Auf echter Intel-Hardware mit Grafikkarte (z. B. MacBook Pro 2017) ist die Oberfläche nicht gesehen.** |
| **Bedienung von Hand** | Klicken, Ziehen & Ablegen, Kontextmenüs, Tastenkürzel, Trackpad-Gesten (Zoom, Wischen mit drei Fingern), Medientasten, Menüleiste, Vollbild. Neu in 2.1 ebenso: Aufziehen der Auswahl mit der Maus, Klicks im Löschdialog, „Als Album zusammenfassen“, macOS-Farbwähler, Größenwechsel des Mini-Players mit Animation. Diese Teile sind gebaut und als Vorschaubild geprüft, aber nicht automatisch bedienbar. |
| **Apple-Musik-Übernahme** | Die Zuordnung (Pfad bzw. Titel/Interpret/Album/Dauer) und das Lesen einer Mediathek-XML sind getestet. Der Zugriff über das iTunesLibrary-Framework braucht die Freigabe „Medien & Apple Music“ und eine echte Musik-Mediathek – **auf den Build-Rechnern nicht möglich, nicht ausprobiert**. |
| **Wiedergabe über Lautsprecher** | Die Klangkette (EQ mit jedem Preset, Bass, Tonhöhe, Tempo, Lautstärke über 100 % mit Limiter, Pegelanalyse) ist offline gemessen; über ein echtes Audiogerät **nicht angehört**. Die Klangqualität der Tonhöhe ist mit Messsignalen (Akkord, Anschläge, Sinustöne) belegt, nicht mit echter Musik im Hörvergleich. |
| **Echte Musiksammlung** | Gemessen mit einer erfundenen Bibliothek mit 10.000 Titeln. Echte Dateien nur im Aktualisierungstest (9 erzeugte Testdateien, AAC und WAV, ohne Tags): Einlesen und Hinzufügedatum geprüft; Dateiüberwachung und externe Laufwerke nicht. |
| **DMG auf Apple Silicon** | Am 06.11.2026 teilte GitHub keine Apple-Silicon-Rechner zu: Installation aus der DMG und Start des Intel-Teils über Rosetta **nicht geprüft**. Das App-Bundle in der DMG ist dasselbe, das im Build-Lauf auf Apple Silicon getestet und mit allen 97 Ansichten gestartet wurde. |
| **Gatekeeper beim ersten Start** | Nach Apples Dokumentation beschrieben (INSTALLATION.md), nicht ausprobiert. |
| **Signieren/Beglaubigen mit Developer ID** | Vorbereitet (`scripts/notarize.sh`, Build-Schritte), aber ohne Entwicklerkonto nicht ausführbar und deshalb ungetestet. |

## Bekannte Schwächen

| Thema | Stand |
|---|---|
| **Kompaktes Raster bei sehr vielen Titeln** | Im Bereich *Titel* mit 10.000 Einträgen ist das kompakte Raster (viele kleine Kacheln je Zeile) die langsamste Ansicht beim Scrollen (siehe PERFORMANCE.md). Liste, Detailliste und normales Raster sind deutlich flüssiger. |
| **Ansicht wechseln** | Das erste Umschalten auf eine andere Ansicht dauert bei 10.000 Titeln einige Zehntelsekunden (die Ansicht wird neu aufgebaut). |
| **Liquid Glass** | Nur auf macOS 26 (natives `glassEffect`). Auf macOS 13–15 gleichwertige Glas-Darstellung aus Unschärfe, Tönung und Glanzkante. |
| **Bewegung reduzieren** | Ist die Systemeinstellung „Bewegung reduzieren“ an, stehen Platte, CD, Spulen und Lichtring still und die Pegelbalken sind ausgeblendet (gewollt). |
| **Tonhöhe (2.1)** | Solange die Tonhöhe verändert ist, verzögert die Verarbeitung den Klang um ≈ 0,14 s (wie bei Android); Zeit- und Liedtext-Anzeige laufen dann um diesen Betrag vor. Beim ersten Verstellen aus „Original“ entsteht eine kurze Pause von ≈ 0,14 s; Wechsel zwischen zwei Tonhöhen und zurück auf „Original“ sind lückenlos. Bei stehenden Akkorden ist Apples bisheriges Verfahren messbar etwas sauberer (−53 statt −49 dB Störanteil), bei Anschlägen (Schlagzeug, Klavier) ist das Android-Verfahren deutlich besser (Vorecho −25 bis −32 dB statt −6 bis −10 dB). Dateien mit mehr als zwei Kanälen nutzen weiter Apples Verfahren. |
| **Hinzufügedatum (2.1)** | Ohne Apple-Musik-Daten gilt das Erstellungsdatum der Datei. Wurden Dateien vor dem Import kopiert (z. B. von einer Festplatte), ist das der Zeitpunkt des Kopierens. Das genaue iTunes-Datum gibt es nur mit „Aus Apple Musik übernehmen …“ bzw. der freigegebenen Mediathek-XML. |
| **Leerlauf (2.1)** | Auf demselben Rechner braucht 2.1 bei laufender Wiedergabe im Hauptthread ≈ 1,5 Prozentpunkte mehr als 2.0 (13,5 % statt 12 % auf einem virtuellen Intel-Mac); Scrollen, Bereichswechsel und Suche sind gleich schnell (PERFORMANCE.md, Abschnitt 4). Ursache nicht eingegrenzt. |
| **Raster (2.1)** | Die Spaltenbreite ist fest aus der Fenstergröße berechnet (Absturzschutz, s. Änderungsübersicht); rechts bleibt dadurch bis zu 16 pt mehr Rand. |

## Nicht umgesetzt

| Thema | Stand |
|---|---|
| **Opus und Ogg FLAC** abspielen | Tags werden gelesen/geschrieben, die Titel erscheinen in der Bibliothek, Abspielen meldet „nicht unterstützt“. Ogg **Vorbis** wird abgespielt. |
| **WMA, WavPack, TTA, DSD, APE, Musepack, Speex** | werden beim Einlesen nicht aufgenommen (macOS kann sie nicht abspielen) |
| **Lückenlose Wiedergabe** (gapless) | zwischen zwei Titeln ist eine kurze Pause möglich |
| **Widgets** | brauchen eine App-Erweiterung mit Xcode-Projekt und Signierung; Ersatz: Mini-Player-Fenster und Player in der Menüleiste |
| **Übernahme aus Apple Music / iTunes** | Playlists, Wertungen und Wiedergabezahlen der Musik-App werden nicht übernommen |
| **AirPlay-Auswahl in der App** | Ausgabe über das Kontrollzentrum von macOS wählen |
| **Sprachen** | nur Deutsch |
| **VoiceOver** | Bedienelemente sind beschriftet, aber nicht mit VoiceOver getestet |
