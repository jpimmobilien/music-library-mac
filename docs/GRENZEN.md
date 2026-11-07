# Ehrliche Grenzen

Stand 7. November 2026 · AETHER 1.0 (Phasen 1–9)

## Was macOS einer Drittanbieter-App nicht gibt (und AETHER deshalb nicht zeigt)

| Wert | Warum nicht | Was AETHER stattdessen zeigt |
|---|---|---|
| Aktueller CPU-Takt (Apple Silicon und Intel) | nur `powermetrics` mit Root-Rechten | Intel: Nenntakt; sonst „nicht verfügbar“ |
| Leistungsaufnahme je Komponente (CPU/GPU/ANE in Watt) | nur `powermetrics` (Root) bzw. private Schnittstelle `IOReport` | Batterieleistung (Spannung × Strom), wo vorhanden |
| Auslastung der Neural Engine | keine öffentliche Schnittstelle | – |
| GPU-Auslastung auf jedem Mac | nicht jeder Grafiktreiber meldet sie | Treiberangabe, wenn vorhanden, sonst „nicht verfügbar“ mit Grund |
| Datenmenge je Prozess im Netzwerk | nur private Schnittstelle `NetworkStatistics` | Verbindungen mit Prozess (aus `netstat`), ohne Datenmenge je Prozess |
| CPU/Speicher von Prozessen anderer Benutzer über libproc | nur mit Root | Werte aus `/bin/ps` (auf macOS mit Systemrechten installiert, wird geprüft), sonst „nur mit Administratorrechten“ |
| Temperaturgrenzwerte | Apple veröffentlicht keine | Warnungen nur aus dem Thermalstatus von macOS |
| Lüfter steuern, Ladegrenze setzen | nur durch Schreiben ins SMC (undokumentiert, riskant) | AETHER liest nur; Ladeeinstellungen öffnen die Systemeinstellungen |

## Messwerte

- **SSD-Aktivität** summiert alle Blockgeräte, eingehängte Disk-Images eingeschlossen. Beim Lesen aus einer DMG zählt
  derselbe Verkehr deshalb zweimal (Image und SSD).
- **Netzwerkraten gesamt** zählen nur Schnittstellen „en*“ (Ethernet, WLAN, Thunderbolt/USB-Ethernet); VPN-Tunnel
  werden je Schnittstelle gezeigt, aber nicht addiert, damit nichts doppelt erscheint.
- **Speicheraufteilung** folgt der Berechnungsweise der Aktivitätsanzeige: App = anonyme Seiten ohne löschbare;
  Zwischenspeicher = dateigestützte und löschbare Seiten. Kleine Abweichungen sind möglich, weil beide Programme zu
  leicht unterschiedlichen Zeitpunkten messen.
- **Prozesse:** CPU-Anteil eigener Prozesse aus libproc, fremder Prozesse aus `/bin/ps` (kumulierte CPU-Zeit,
  Differenz zweier Messungen). Beenden fremder Prozesse verweigert macOS ohne Rechte – AETHER erklärt das, statt
  Rechte anzufordern. Kritische Systemprozesse stehen auf einer Schutzliste.

## Temperatur & Lüfter

- **Sensoren** liest AETHER über die öffentlichen IOKit-Funktionen `IOServiceOpen`/`IOConnectCallStructMethod` aus dem
  System Management Controller. Das Protokoll und die Schlüssel sind von Apple **nicht dokumentiert** (Risikoanalyse:
  Konzept 8.3). AETHER **liest nur** (keine Schreibbefehle im Code), prüft jeden Wert auf Plausibilität (5–130 °C)
  und lässt sich in den Einstellungen abschalten.
- **Bereiche** (CPU, Grafik, Speicher …) ordnet AETHER nach Erfahrungswerten aus den Schlüsselnamen zu; Namen einzelner
  Sensoren stehen nur dort, wo die Bedeutung gesichert bekannt ist (vor allem Intel). Mittel und Maximum je Bereich
  sind berechnet und so gekennzeichnet.
- **„Kein Lüfter“** erscheint nur, wenn das SMC ausdrücklich null Lüfter meldet (z. B. MacBook Air mit Apple Silicon).
- **Virtuelle Macs:** Ein dort vorhandenes SMC ist vom Hypervisor nachgebildet. Seine Werte sind keine Messungen echter
  Hardware und werden deshalb nicht angezeigt („Virtueller Mac ohne physische Sensoren“).

## Batterie

- **Kapazität (berechnet)** = volle Ladekapazität ÷ Designkapazität. Daneben steht unverändert Apples „Maximale
  Kapazität“ aus den Systeminformationen – beide Verfahren unterscheiden sich, beide Werte werden gezeigt.
- **Restzeit** ist eine Schätzung von macOS und als solche gekennzeichnet; direkt nach dem Ab- oder Anstecken meldet
  macOS „wird berechnet“.
- **Leistung** ist Spannung × Strom der Batterie, also beim Laden die Leistung in die Batterie, nicht der
  Gesamtverbrauch des Mac.
- **Netzteilangaben** (Spannung, Strom) haben keine dokumentierten Einheiten; AETHER zeigt nur plausible Werte.

## Hardware

- **Seriennummer:** nur nach Klick auf „Anzeigen“ gelesen, nie gespeichert; im Systembericht nur mit Häkchen.
- **Bildschirmgröße in Zoll** ist aus der vom Bildschirm gemeldeten physischen Größe berechnet (≈).
- **Neural Engine:** keine öffentliche Angabe über Kerne oder Auslastung.

## Dateien

- **Nie überschreiben, nie endgültig löschen:** Namenskonflikte ergeben „Name 2“ (wie „Beide behalten“ im Finder);
  Löschen heißt immer Papierkorb, mit Widerrufen (⌘Z) bzw. „Zurücklegen“ direkt danach.
- **Fortschritt beim Kopieren** zählt ganze Objekte; eine einzelne sehr große Datei springt deshalb von 0 auf 100 %.
  Abbrechen wirkt zwischen zwei Objekten.
- **Spotlight-Suche** findet nur, was Spotlight indiziert hat; ausgeschlossene Ordner und Volumes ohne Index fehlen.
  Gezeigt werden höchstens 1 000 Treffer.
- **Quick Look** nutzt das Vorschaufenster von macOS; Pfeiltasten wechseln dort nicht automatisch die Auswahl in AETHER.
- Geschützte Ordner (Schreibtisch, Dokumente, Downloads, Mail …) öffnet AETHER erst nach Freigabe durch macOS.

## Live-Monitor und Menüleiste

- Gemessen wird nur, solange etwas davon sichtbar ist: Hauptfenster, Live-Monitor oder Menüleisten-Fenster. Mit
  eingeschalteter Menüleisten-Anzeige misst AETHER bei geschlossenem Fenster höchstens alle 5 Sekunden.

## Speicher

- **SSD-Zustand (NVMe SMART)** kommt über Apples öffentliche Plug-in-Schnittstelle `IONVMeSMARTInterface`. Externe
  Laufwerke über USB, SATA-SSDs älterer Intel-Macs und virtuelle Macs stellen sie nicht bereit – dann steht dort
  „nicht verfügbar“ mit Grund, nie ein geschätzter Wert. Die Abnutzung („percentage used“) ist die Angabe des
  Laufwerks selbst; eine Restlebensdauer rechnet AETHER daraus nicht hoch. Ob jeder Mac die Werte ohne
  Administratorrechte herausgibt, ist erst auf echter Hardware bestätigt, wenn es dort geprüft wurde.
- **Ordneranalyse** zählt den belegten Platz (`totalFileAllocatedSize`). Ordner, die macOS ohne Freigabe nicht lesen
  lässt (Mail, Nachrichten, Safari u. a. nur mit Festplattenvollzugriff), werden als „nicht lesbar“ gezählt und
  fehlen in den Summen. Andere Volumes unterhalb des gewählten Ordners werden nicht mitgezählt; symbolischen Links
  folgt AETHER nicht. Pakete (z. B. Apps) zählen als ein Objekt.
- **Kategorien** ergeben sich nur aus der Dateiendung; Inhalte werden nicht untersucht.
- **Duplikate**: gleiche Größe und gleiche SHA-256-Prüfsumme (zuerst die ersten 64 KiB, dann die ganze Datei), ab
  1 MB. Harte Links zählen einmal. APFS-Klone lassen sich mit öffentlichen Mitteln nicht sicher erkennen: AETHER zeigt
  nur den Hinweis des Dateisystems „kann Speicher teilen“ (`EF_MAY_SHARE_BLOCKS`). Der angegebene freizugebende Platz
  ist deshalb eine Obergrenze.
- **Bereinigungsvorschläge** messen nur. Papierkorb und Gerätebackups sind ohne Festplattenvollzugriff meist „nicht
  lesbar“. Gelöscht wird nie; Dateien aus den Listen gehen nur nach Bestätigung in den Papierkorb und lassen sich
  direkt danach zurücklegen. Wurde der Originalort inzwischen neu belegt, scheitert das Zurücklegen mit Meldung –
  die Datei bleibt dann im Papierkorb.
- **Löschbarer Platz** ist die Differenz „verfügbar für wichtige Nutzung“ minus „verfügbar“, wie macOS sie meldet.

## Netzwerk und Verlauf

- **WLAN-Name (SSID)**: Ab macOS 14 gibt CoreWLAN den Netzwerknamen nur an Apps mit Ortungsfreigabe heraus. AETHER
  fragt die Freigabe nur auf Klick („Ortungsfreigabe erlauben …“) und ruft den Standort selbst nie ab. Ohne Freigabe
  steht dort „Ortungsfreigabe nötig“. Die BSSID (Kennung des Zugangspunkts) zeigt AETHER bewusst nicht – sie
  verrät den Aufenthaltsort. Passwörter und Schlüssel werden nie gelesen; „Sicherheit“ nennt nur das Verfahren.
- **Signalqualität**: Der Balken ordnet RSSI grob ein (−90 dBm leer, −50 dBm voll). Das ist eine Faustregel, kein
  Messwert; gemessen sind RSSI und Rauschen, der Signal-Rausch-Abstand ist daraus berechnet.
- **Datenmenge je Prozess** gibt es nur über die private Schnittstelle `NetworkStatistics` – AETHER zeigt sie nicht.
  Verbindungen stammen aus `netstat -anv` (Socket-Tabellen des Kernels, ohne Administratorrechte). Der genannte
  Prozess ist der letzte Besitzer des Sockets laut Kernel; bei geteilten Sockets kann das ein anderer Prozess sein
  als der, der sie gerade nutzt. Ob die Prozessspalte („pid“ bzw. „process:pid“) vorhanden ist, hängt von der
  macOS-Version ab – fehlt sie, bleibt die Spalte leer (die Seite sagt das).
- **Raten je Schnittstelle** stammen aus denselben 64-Bit-Zählern wie die Gesamtrate. Die Gesamtrate summiert nur
  Ethernet/WLAN („en…“); VPN-Tunnel, AirDrop und Loopback werden einzeln gezeigt, aber nicht addiert, weil derselbe
  Verkehr sonst doppelt zählte.
- **Langzeitverlauf** ist standardmäßig aus. Eingeschaltet speichert AETHER einen Mittelwert pro Minute
  (Speicherdruck und Thermalstatus: Maximum der Minute) in `~/Library/Application Support/AETHER/history.sqlite`.
  Zeiten, in denen AETHER nicht misst (Fenster verdeckt, App beendet), bleiben Lücken – es wird nichts aufgefüllt.
  Ausschalten beendet die Aufzeichnung; vorhandene Werte bleiben, bis Sie sie löschen. Der Export (CSV) enthält
  alle gespeicherten Werte mit UTC-Zeitstempeln.

## Bekannte Schönheitsfehler

- Auf dem virtuellen Apple-Silicon-Build-Rechner meldet `system_profiler` keinen Grafikprozessor. AETHER zeigt dann
  „nicht verfügbar“, statt einen zu erfinden. Auf dem virtuellen Intel-Rechner kamen Modell, Grafikspeicher und
  Metal-Stufe korrekt an; auf einem physischen Mac ist die Abfrage noch nicht geprüft.

## Was im Build nicht geprüft werden kann

Die Build-Rechner von GitHub sind **virtuelle Macs**. Dort gibt es keine Batterie, keine echten Sensoren und Lüfter
und keine NVMe-SMART-Daten. Geprüft wird dort, dass diese Bereiche **sauber „nicht vorhanden“ bzw. „nicht verfügbar“**
melden und keine Ersatzwerte erscheinen.

Ob Akkuwerte (Zyklen, Kapazitäten, Spannung, Strom, Temperatur), SMC-Sensoren, Lüfter, NVMe-SMART, WLAN-Details und
die GPU-Treiberangabe auf echter Hardware stimmen, ist **nicht geprüft**, bis es auf einem physischen Mac bestätigt
ist. Der Selbsttest prüft auf den Build-Rechnern den Lesepfad (z. B. SMC öffnen und Schlüssel aufzählen) und dass
nicht verfügbare Werte mit Grund erscheinen.
