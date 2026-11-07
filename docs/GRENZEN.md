# Ehrliche Grenzen

Stand 7. November 2026 · AETHER 0.2.0 (Phase 1 und 2)

## Was macOS einer Drittanbieter-App nicht gibt (und AETHER deshalb nicht zeigt)

| Wert | Warum nicht | Was AETHER stattdessen zeigt |
|---|---|---|
| Aktueller CPU-Takt (Apple Silicon und Intel) | nur `powermetrics` mit Root-Rechten | Intel: Nenntakt laut Prozessorbezeichnung; sonst „nicht verfügbar“ |
| Leistungsaufnahme je Komponente (CPU/GPU/ANE in Watt) | nur `powermetrics` (Root) bzw. private Schnittstelle `IOReport` | – |
| Auslastung der Neural Engine | keine öffentliche Schnittstelle | Neural Engine nur als Hardwareangabe (ab Phase 5) |
| GPU-Auslastung auf jedem Mac | nicht jeder Grafiktreiber meldet sie | Treiberangabe, wenn vorhanden, sonst „nicht verfügbar“ mit Grund |
| Datenmenge je Prozess im Netzwerk | nur private Schnittstelle `NetworkStatistics` | ab Phase 7: Verbindungen, ohne Datenmenge je Prozess |
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
  zählt derselbe Verkehr deshalb zweimal (Image und SSD). Die Aufteilung je Laufwerk folgt in Phase 6.
- **Netzwerkraten** zählen nur Schnittstellen „en*“ (Ethernet, WLAN, Thunderbolt/USB-Ethernet). VPN-Tunnel werden
  nicht zusätzlich gezählt, damit nichts doppelt erscheint. Verkehr über Mobilfunk-Tethering per USB kann unter
  einem anderen Namen laufen und fehlt dann.
- **Kapazität der Batterie** ist berechnet (volle Ladekapazität ÷ Designkapazität) und ausdrücklich nicht Apples
  „Maximale Kapazität“. Apples Angabe aus den Systeminformationen folgt in Phase 5.
- **Restlaufzeit** ist eine Schätzung von macOS und als solche gekennzeichnet.
- **Speicheraufteilung** folgt der Berechnungsweise der Aktivitätsanzeige: App = anonyme Seiten ohne löschbare;
  Zwischenspeicher = dateigestützte und löschbare Seiten. Kleine Abweichungen zur Aktivitätsanzeige sind möglich, weil
  beide zu leicht unterschiedlichen Zeitpunkten messen.

## Was im Build nicht geprüft werden kann

Die Build-Rechner von GitHub sind **virtuelle Macs**. Dort gibt es keine Batterie, meist kein SMC, keine Lüfter und
keine NVMe-SMART-Daten. Geprüft wird dort, dass diese Bereiche **sauber „nicht vorhanden“ bzw. „nicht verfügbar“**
melden und keine Ersatzwerte erscheinen.

Ob Akkuwerte (Zyklen, Kapazitäten, Spannung, Strom, Temperatur) auf echter Hardware stimmen, ist **nicht geprüft**,
bis es auf einem physischen MacBook bestätigt ist. Gleiches gilt für die GPU-Treiberangabe auf echter Hardware.
