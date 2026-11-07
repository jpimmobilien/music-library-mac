# Ehrliche Grenzen

Stand 7. November 2026 · AETHER 0.2.0 (Phase 1 und 2)

## Was macOS einer Drittanbieter-App nicht gibt (und AETHER deshalb nicht zeigt)

| Wert | Warum nicht | Was AETHER stattdessen zeigt |
|---|---|---|
| Aktueller CPU-Takt (Apple Silicon und Intel) | nur `powermetrics` mit Root-Rechten | Intel: Nenntakt laut Prozessorbezeichnung; sonst „nicht verfügbar“ |
| Leistungsaufnahme je Komponente (CPU/GPU/ANE in Watt) | nur `powermetrics` (Root) bzw. private Schnittstelle `IOReport` | – |
| Auslastung der Neural Engine | keine öffentliche Schnittstelle | Neural Engine nur als Hardwareangabe (ab Phase 5) |
| GPU-Auslastung auf jedem Mac | nicht jeder Grafiktreiber meldet sie | Treiberangabe, wenn vorhanden, sonst „nicht verfügbar“ mit Grund |
| Datenmenge je Prozess im Netzwerk | nur private Schnittstelle `NetworkStatistics` | Verbindungen mit Prozess (aus `netstat`), ohne Datenmenge je Prozess |
| CPU/Speicher von Prozessen anderer Benutzer über libproc | nur mit Root | ab Phase 4: über `/bin/ps`, falls mit Systemrechten installiert (wird geprüft, nicht angenommen) |
| Temperaturgrenzwerte | Apple veröffentlicht keine | Warnungen nur aus dem Thermalstatus von macOS |

## Diese Version (0.2.0)

- **Detailseiten** von Aktivität, CPU & GPU, Arbeitsspeicher, Temperatur & Lüfter, Batterie, Hardware, Speicher,
  Dateien und Netzwerk folgen in den Phasen 4–7. Die Seiten sagen das ausdrücklich und nennen, was schon in der
  Übersicht live ist.
- **Temperatursensoren und Lüfter (SMC)** folgen in Phase 5. Jetzt verfügbar sind der Thermalstatus (macOS) und die
  Akkutemperatur.
- **Kernzuordnung** zu Leistungs- und Effizienzkernen erfolgt nur als Anzahl, nicht je Kern (Phase 4).
- **SSD-Aktivität** summiert alle Blockgeräte, eingehängte Disk-Images eingeschlossen. Beim Lesen aus einer DMG
  zählt derselbe Verkehr deshalb zweimal (Image und SSD). Eine Aufteilung je Laufwerk zeigt AETHER nicht.
- **Netzwerkraten** zählen nur Schnittstellen „en*“ (Ethernet, WLAN, Thunderbolt/USB-Ethernet). VPN-Tunnel werden
  nicht zusätzlich gezählt, damit nichts doppelt erscheint. Verkehr über Mobilfunk-Tethering per USB kann unter
  einem anderen Namen laufen und fehlt dann.
- **Kapazität der Batterie** ist berechnet (volle Ladekapazität ÷ Designkapazität) und ausdrücklich nicht Apples
  „Maximale Kapazität“. Apples Angabe aus den Systeminformationen folgt in Phase 5.
- **Restlaufzeit** ist eine Schätzung von macOS und als solche gekennzeichnet.
- **Speicheraufteilung** folgt der Berechnungsweise der Aktivitätsanzeige: App = anonyme Seiten ohne löschbare;
  Zwischenspeicher = dateigestützte und löschbare Seiten. Kleine Abweichungen zur Aktivitätsanzeige sind möglich, weil
  beide zu leicht unterschiedlichen Zeitpunkten messen.

## Speicher (Phase 6)

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

## Netzwerk und Verlauf (Phase 7)

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

## Bekannte Schönheitsfehler (Phase 3 – Liquid-Glass-Feinschliff)

- In der dreispaltigen Ansicht bricht in der Speicherkarte die Zeile „… belegt · inkl. … löschbar“ um, und auf
  Deutsch wird „Zwischenspeicher“ in der Speicherkarte gekürzt.
- Auf dem virtuellen Apple-Silicon-Build-Rechner meldet `system_profiler` keinen Grafikprozessor. AETHER zeigt dann
  „Kein Grafikprozessor gemeldet“, statt einen zu erfinden. Auf dem virtuellen Intel-Rechner kamen Modell, Grafikspeicher
  und Metal-Stufe korrekt an; auf einem physischen Mac ist die Abfrage noch nicht geprüft.

## Was im Build nicht geprüft werden kann

Die Build-Rechner von GitHub sind **virtuelle Macs**. Dort gibt es keine Batterie, meist kein SMC, keine Lüfter und
keine NVMe-SMART-Daten. Geprüft wird dort, dass diese Bereiche **sauber „nicht vorhanden“ bzw. „nicht verfügbar“**
melden und keine Ersatzwerte erscheinen.

Ob Akkuwerte (Zyklen, Kapazitäten, Spannung, Strom, Temperatur) auf echter Hardware stimmen, ist **nicht geprüft**,
bis es auf einem physischen MacBook bestätigt ist. Gleiches gilt für die GPU-Treiberangabe auf echter Hardware.
