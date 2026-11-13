# Technische Risiken

Stand 27.10.2026 · nach Phase 3 (Stand der Lösungen jeweils am Ende). Testgeräte laut deinen bisherigen Projekten: **Google Pixel 6 Pro**
(kein Kartensteckplatz, USB-C mit OTG) und ein **Xiaomi** mit SD-Karte (HyperOS/MIUI).

Legende Auswirkung/Wahrscheinlichkeit: hoch · mittel · gering.

## R1 – Dateizugriff unter Android 11+ (Scoped Storage)

**Problem.** Seit Android 11 sieht eine App ohne Sonderrecht nur Mediendateien (über MediaStore) und ihre eigenen
Dateien. Dokumente, PDFs, Archive und APKs anderer Apps sind unsichtbar. Der Android-Ordnerauswahldialog
(`ACTION_OPEN_DOCUMENT_TREE`) erlaubt **nicht** das Hauptverzeichnis des internen Speichers, „Download“ oder
`Android/data` freizugeben.

**Auswirkung:** hoch – ohne Lösung wäre kein vollwertiger Dateimanager möglich.

**Lösung (Vorschlag für Phase 3).**
* Hauptmodus „Zugriff auf alle Dateien“ (`MANAGE_EXTERNAL_STORAGE`): Der Nutzer erteilt ihn selbst in den
  Android-Einstellungen; AETHER öffnet die Seite nur auf Tippen nach einer Erklärung. Damit funktionieren Dateisystem-
  Zugriffe (`java.io`/`java.nio`) im gesamten gemeinsamen Speicher und auf SD-Karten (Erfahrung Filmbibliothek 7.4.2).
* Eingeschränkter Modus ohne diese Berechtigung: Medien über MediaStore (`READ_MEDIA_IMAGES/VIDEO/AUDIO`, Android 14+
  auch Teilfreigabe), einzelne Ordner über den Auswahldialog. Die Oberfläche zeigt klar, was in diesem Modus fehlt.
* `Android/data` und `Android/obb` bleiben auch mit Sonderrecht gesperrt – das wird angezeigt, nicht umgangen.

**Google Play:** `MANAGE_EXTERNAL_STORAGE` ist für Dateimanager eine zulässige Kernfunktion, verlangt aber eine
Deklaration und Prüfung. Für die private Nutzung ohne Play Store spielt das keine Rolle.

**Stand 0.3.0:** Hauptmodus umgesetzt (mit dir abgestimmt). Der eingeschränkte Modus ist nicht gebaut; ohne Zugriff
erklärt „Dateien“, wozu er dient, und alle anderen Bereiche funktionieren. Restrisiko: Einzelne Hersteller kennen die
direkte Einstellungsseite nicht – dann öffnet AETHER die Liste aller Apps bzw. die App-Info.

## R2 – SD-Karten

**Problem.** Hersteller binden Karten unterschiedlich ein; die Bezeichnung („SD-Karte von SanDisk“) ist die einzige
öffentliche Unterscheidung zwischen SD und USB. Schreibzugriff ohne Sonderrecht nur per Ordnerauswahldialog.
FAT32-Karten haben eine 4-GB-Grenze je Datei und verbieten Zeichen wie `:*?"<>|`. Karten können mitten im Vorgang
entnommen werden.

**Stand Phase 1:** Erkennung über `StorageManager.getStorageVolumes()`, Zustand (eingebunden, nur lesbar, entfernt,
nicht lesbar …) und Kapazität über `StatFs`; Änderungen werden über `StorageVolumeCallback` sofort gemeldet. Die Art
(SD/USB) wird nur aus der Android-Bezeichnung abgeleitet und ist sonst „Wechseldatenträger“.

**Stand 0.3.0 (vorgezogen aus Phase 4):** Kopien immer in eine Teildatei (`*.aether-part`), Prüfsumme beim
Schreiben, Kopie erneut lesen und vergleichen, dann Umbenennen; Original erst danach löschen. Freier Platz wird vorab
geprüft (mit Reserve); Namen nach FAT-Regeln; volle oder schreibgeschützte Ziele beenden den Vorgang mit genauer
Liste. Entnahme der Karte → Lese-/Schreibfehler, unfertige Dateien werden entfernt, Bericht „unvollständig“.
**Offen:** Die FAT32-Grenze (4 GB) wird erst beim Schreiben erkannt (Android nennt das Dateisystem nicht
zuverlässig) – das Original bleibt dabei unberührt.

## R3 – USB-Speicher (OTG)

**Problem.** Viele Geräte binden USB-Sticks als öffentliches Speichervolume ein (dann wie SD-Karte nutzbar), manche
nur über den Dateiauswahldialog, manche gar nicht (z. B. NTFS ohne Herstellerunterstützung). Die `UsbManager`-API
liefert nur Rohzugriff auf Geräte – ein eigener Dateisystemtreiber kommt nicht infrage.

**Lösung:** Nur, was Android einbindet; sonst Hinweis „Von Android nicht als Speicher eingebunden“. Auf dem Pixel 6
Pro ist USB-Massenspeicher (FAT32/exFAT) erfahrungsgemäß eingebunden – das prüft der Gerätetest (Testplan §3).
**Stand 0.3.0:** Eingebundene USB-Speicher erscheinen unter „Dateien › Speicherorte“ und funktionieren wie die
SD-Karte.

## R4 – Temperaturen

**Problem.** Gewöhnliche Apps erhalten **keine CPU-, GPU- oder Gehäusetemperatur**. Dateien unter
`/sys/class/thermal` sind je nach Hersteller gesperrt, unbeschriftet oder unzuverlässig; der Auftrag verbietet zu
Recht, sie auszulesen. `HardwarePropertiesManager.getDeviceTemperatures` ist Geräteeigentümern vorbehalten.

**Verfügbar und umgesetzt:**
* Akku-Temperatur (`EXTRA_TEMPERATURE`, Zehntelgrad; unplausible Werte werden nicht angezeigt),
* Thermalstatus (`PowerManager`, sieben Stufen von „Normal“ bis „Abschalten erforderlich“) – ausdrücklich als
  Einstufung, nicht als Temperatur gekennzeichnet,
* genutzter thermischer Spielraum (`getThermalHeadroom`): 100 % = Schwelle zur starken Drosselung; steigt laut
  Android zwischen 0 und 100 % etwa linear mit der Temperatur, 0 % entspricht aber keiner bestimmten Temperatur;
  liefert auf manchen Geräten keinen Wert (`NaN`) → „Nicht verfügbar auf diesem Gerät“.

**Risiko für den Nutzer:** gering – die App verspricht nichts, was Android nicht liefert.

## R5 – Sensoren

**Problem.** Ausstattung und Koordinatensysteme unterscheiden sich; manche Sensoren liefern erst nach Bewegung Werte
(Näherung, Schritte). Hohe Abtastraten kosten Akku; ab Android 12 braucht >200 Hz eine Berechtigung. Ein
registrierter Sensor beweist keine fehlerfreie Hardware.

**Lösung Phase 6:** Nur `SensorManager`; `SENSOR_DELAY_UI`; Abmelden beim Verlassen; Diagnose in Stufen
(vorhanden → Daten empfangen → Werte ändern sich); Einheiten je Sensortyp aus einer getesteten Tabelle in `core:model`.
Schrittzähler/Herzfrequenz brauchen eigene Laufzeitberechtigungen – nur, wenn sie wirklich gebraucht werden.

## R6 – Glas-Effekte und Leistung

**Problem.** Echtzeit-Unschärfe (`RenderEffect`) kostet GPU-Zeit; auf Mittelklassegeräten oder bei großen
Bildlisten kann Scrollen ruckeln. Manche Hersteller hatten Darstellungsfehler mit `RenderEffect`.

**Lösung:** Unschärfe nur für schwebende Leisten; Inhaltskarten nutzen gezeichnetes Glas ohne Unschärfe. Effektstärke
„Minimal“ (zugleich Leistungsmodus) schaltet Unschärfe, Atmosphäre und Glanz ab; Low-RAM-Geräte automatisch ohne
Unschärfe. Die Lesbarkeit hängt nie von der Unschärfe ab (Tönung ist so gewählt, dass Text selbst über rein weißem
bzw. schwarzem Inhalt ≥ 4,5 : 1 behält – geprüft in `ContrastTest`).

## R7 – Kein Build in der Entwicklungsumgebung

**Problem.** Hier gibt es weder Android-SDK noch Zugriff auf Google Maven. Gradle-Build, Ressourcen-Linking,
Manifest-Zusammenführung und Lint laufen erst in Android Studio.

**Gegenmaßnahmen:** Kernlogik auf der JVM kompiliert und getestet; Android-Code gegen aus den offiziellen
API-Beschreibungen erzeugte Schnittstellen typgeprüft (siehe [TESTPLAN.md](TESTPLAN.md)); Build-Dateien nach dem
Muster deiner bereits gebauten Projekte. Restrisiko: kleine Meldungen beim ersten Bau – bitte dann einfach mitschicken.

## R8 – Herstelleranpassungen (Xiaomi)

**Problem.** HyperOS/MIUI ändern Berechtigungsseiten („Verwaltung aller Dateien“), beschränken Hintergrundarbeit
aggressiv und benennen Speicher anders.

**Lösung:** Keine Hintergrundarbeit außer laufenden Dateivorgängen; Hinweise in der App nennen auch die
Xiaomi-Menünamen; lange Vorgänge laufen als Vordergrunddienst mit sichtbarem Fortschritt. **Restrisiko:** HyperOS
kann auch Vordergrunddienste beenden, wenn „Akku sparen“ für AETHER aktiv ist – dann bricht der Vorgang ab, unfertige
Dateien räumt der nächste Start auf, Originale bleiben erhalten. Abhilfe: Einstellungen › Apps › Aether › Akku sparen
› „Keine Einschränkungen“.
