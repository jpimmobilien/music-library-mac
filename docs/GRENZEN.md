# Ehrliche Grenzen

Stand 27.10.2026 · AETHER 0.3.0 (Phase 3)

## Was Android einer gewöhnlichen App nicht gibt (und AETHER deshalb nicht zeigt)

* **CPU-, GPU-, Gehäuse- oder SoC-Temperatur.** Nur die Akku-Temperatur ist allgemein zugänglich. Der Thermalstatus
  ist eine Einstufung der Drosselung, keine Temperatur.
* **CPU- und GPU-Auslastung, Prozessliste anderer Apps, Taktfrequenzen.**
* **Akkuverschleiß in Prozent.** Nur Zustandsstufen und – ab Android 14, wenn das Gerät es unterstützt – Ladezyklen.
* **Thermische Reserve** nur, wenn der Hersteller sie implementiert.
* **Art eines Wechseldatenträgers** nur aus der Bezeichnung von Android („Wechseldatenträger“, wenn nicht eindeutig).
* **`Android/data` und `Android/obb`** anderer Apps – auch mit „Zugriff auf alle Dateien“ gesperrt.

## Dateien

* **Medienindex (Kategorien, schnelle Suche):** Android pflegt ihn selbst. Er enthält keine versteckten Ordner und
  kann nach Änderungen durch andere Apps kurz hinterherhinken. Nach eigenen Vorgängen meldet AETHER die betroffenen
  Pfade sofort zum Neueinlesen. Die **gründliche Suche** durchsucht das Dateisystem direkt (auch Verstecktes), ist
  aber langsamer.
* **Kategorien mit sehr vielen Dateien** zeigen die 5 000 neuesten und sagen das ausdrücklich („Die 5 000 neuesten
  von 23 412“).
* **Live-Aktualisierung geöffneter Ordner** über Dateisystem-Meldungen: Auf dem gemeinsamen Speicher kommen sie seit
  Android 11 nicht für jede Änderung jeder App an. AETHER lädt zusätzlich nach eigenen Vorgängen und beim Zurückkehren
  in die App neu.
* **FAT32 (viele SD-Karten und USB-Sticks):** höchstens 4 GB je Datei. Das zeigt sich beim Schreiben als „Zu groß für
  das Dateisystem des Ziels“ – eine Prüfung vorab ist ohne Kenntnis des Dateisystems nicht möglich. Das Original
  bleibt immer erhalten.
* **Groß-/Kleinschreibung:** Der gemeinsame Speicher von Android unterscheidet sie nicht („Foto.jpg“ = „foto.JPG“).
  Namenskonflikte werden deshalb ohne Rücksicht darauf erkannt; reines Ändern der Schreibweise ist möglich.
* **Papierkorb je Speicher:** Objekte bleiben auf ihrem Speicher (Umbenennen, nicht Kopieren). Geht das nicht (z. B.
  schreibgeschützter Stick), sagt AETHER „Papierkorb nicht verfügbar“ und bietet „Endgültig löschen“ an – es wird nie
  ersatzweise gelöscht. Der Papierkorb leert sich nie von selbst; Objekte belegen weiter Platz.
* **Archive:** Erstellen und Entpacken von ZIP. RAR, 7z, TAR, verschlüsselte ZIPs: „nicht unterstützt“ (öffnen mit
  einer anderen App).
* **Prüfung beim Verschieben über Speichergrenzen:** Beim Schreiben bildet AETHER die Prüfsumme (SHA-256) des
  Originals, liest die fertige Kopie danach erneut und vergleicht – erst bei Gleichheit wird das Original entfernt.
  Das Zurücklesen kann aus dem Zwischenspeicher von Android kommen; es findet Übertragungs- und Programmfehler, nicht
  unbedingt einen Defekt im Speicherchip.
* **Schnellansicht:** Bilder (Zoom bis 5×, Wischen durch den Ordner), Text, PDF, ZIP-Inhalt. Videos und Musik öffnen
  in einer anderen App (kein eigener Player). Animierte GIF/WebP erscheinen als Standbild (mit Hinweis). PDF: ohne
  Passwort, ohne Textauswahl; beim Zoomen bis 3× wird die Seite nicht neu gezeichnet (Schrift wird weicher). Im
  vergrößerten Bild wechselt Wischen nicht zum nächsten Bild – erst verkleinern. Archive, die Android nicht öffnen
  kann (BZip2, Deflate64, verschlüsselt), werden aufgelistet, lassen sich aber nicht entpacken.
* **Texte bearbeiten:** angezeigt werden die ersten 512 KB, bearbeiten lassen sich Dateien bis 256 KB. Gesperrt (mit
  Erklärung) sind Dateien, die sich nicht verlustfrei lesen lassen (z. B. gemischte Kodierung) – Sichern würde sonst
  Bytes verändern, die man nie angefasst hat. Wird AETHER von Android im Hintergrund beendet, gehen ungesicherte
  Änderungen verloren (zu groß für den gespeicherten Zustand). Eine Textdatei, die eine Verknüpfung ist, lässt sich
  nicht sichern („inzwischen geändert“). Auf FAT-Speichern sind Änderungszeiten nur auf 2 s genau – eine fremde
  Änderung in genau diesem Fenster bemerkt der Schutz vor dem Überschreiben nicht.
* **App-Pakete:** Ob eine App bereits installiert ist, kann AETHER oft nicht feststellen (Paketsichtbarkeit seit
  Android 11; die Berechtigung, alle Apps zu sehen, fragt AETHER bewusst nicht an). Dann steht dort „Nicht
  feststellbar“ – der Android-Installer zeigt es vor der Installation selbst.
* **Änderungszeiten:** Beim Kopieren übernimmt AETHER die Änderungszeit des Originals; manche Speicher verweigern das
  (dann trägt die Kopie die aktuelle Zeit).

## Bewegung

* **Geschwindigkeit** nur aus GPS. Liegt sie unter ihrer eigenen Messgenauigkeit, heißt es „Stillstand innerhalb der
  Messgenauigkeit“ statt einer erfundenen 0.
* **Höhe über dem Meeresspiegel** ab Android 14 (Geoid-Modell auf dem Gerät, ohne Internet). Darunter nur die Höhe
  über dem Ellipsoid (in Deutschland rund 35–50 m mehr), ausdrücklich so bezeichnet.
* **Druckhöhe** nach Standardatmosphäre, nicht kalibriert (ohne Internet kein örtlicher Luftdruck): Die absolute Höhe
  folgt dem Wetter und kann um bis zu einige hundert Meter abweichen; Änderungen (Treppe, Berg) misst das Barometer
  auf etwa einen Meter genau.
* **Kompass** zeigt die Richtung der Geräteoberkante und wird bei stark gekipptem Gerät unzuverlässig (Hinweis).
  Geografisch Nord nur, wenn eine Position bekannt ist; sonst magnetisch Nord – so beschriftet.
* **Zwei Frequenzen (L1 + L5)** nur erkennbar, wenn der Empfänger Trägerfrequenzen meldet.
* **Strecke und Anstieg** zählen nur, solange die Seite offen ist, und lieber zu wenig als zu viel (ungenaue Fixes
  und Sprünge werden verworfen). Als „berechnet“ gekennzeichnet.
* **Keine Karte** – dafür bräuchte es Internet.

## Darstellung

* „Bewegung reduzieren“ in AETHER wirkt auf alle eigenen Übergänge. Blätter und Menüs, die von Material stammen
  (Aktionsblatt, Darstellungsmenü), folgen nur der Android-Einstellung „Animationen entfernen“.

## Was diese Version noch nicht kann

* Speicherassistent (große Dateien, Duplikate, alte Downloads) – Phase 5.
* Sensor-Explorer mit allen Sensoren – Phase 6 (Bewegung ist vorgezogen).
* Anpassbare Startseite – Phase 7.
* Ordnerfreigabe über den Android-Auswahldialog als Alternative zu „Zugriff auf alle Dateien“ (eingeschränkter
  Modus) – nicht umgesetzt; ohne den Zugriff erklärt „Dateien“, wozu er dient.
* USB-Speicher, die Android nicht als Speicher einbindet (z. B. NTFS ohne Treiber), sind nicht erreichbar.

## Was in dieser Umgebung nicht geprüft werden konnte

* **Kein Gradle-Build, kein APK, kein Gerät, kein Emulator** (kein Android-SDK, kein Zugriff auf Google Maven). Geprüft
  wurde, was ohne SDK möglich ist – siehe [TESTPLAN.md](TESTPLAN.md).
* Verhalten auf echtem FUSE-Speicher (Groß-/Kleinschreibung, Änderungszeiten), echte SD-Karte/USB-Stick, MediaStore
  und FileProvider zur Laufzeit, Vordergrunddienst, GPS, Barometer und Kompass auf Hardware.
