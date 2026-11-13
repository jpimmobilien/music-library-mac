# Referenzanalyse – was aus deinen Projekten übernommen wurde

Mitgeliefert waren Filmbibliothek 7.4.2, Musikbibliothek 1.3.0 („CD-Player, Dark-Mode-Fix“), DriveGlass 1.1.0 und
Leseraum 1.0.0. Keines davon ist ein Dateimanager – AETHER ist ein neues Projekt. Übernommen wurden bewährte
Grundlagen und Lehren, nicht Oberflächen.

| Aus | Übernommen | Warum |
|---|---|---|
| allen | Werkzeugkette (AGP 9.3.1, Gradle 9.6.1, Kotlin 2.4.21, Compose-BOM 2026.09.00), Gradle-Wrapper, `minSdk 31`/`targetSdk 36`/`compileSdk 37`, Paketschema `de.privateapp.*` | auf deinem Mac erprobt; nichts Neues zu laden |
| Musikbibliothek, DriveGlass | Block in `settings.gradle.kts`, der das SDK findet („SDK location not found“) | erprobt nach Neu-Entpacken |
| DriveGlass | Mehrmodul-Aufbau mit reinen Kotlin-Modulen (`org.jetbrains.kotlin.jvm`) neben Android-Bibliotheken; zentrale App-Verdrahtung; App-Name in `gradle.properties` | testbare Logik ohne Emulator |
| DriveGlass | Beobachtung von „Animationen entfernen“ (ContentObserver auf `ANIMATOR_DURATION_SCALE`) | sofortige Reaktion ohne Neustart |
| DriveGlass | Schriftdateien Inter / Inter Display (Untermenge mit Umlauten, `tnum`) und OFL-Lizenztext | gleiche Qualität, bekannte Größe |
| Musikbibliothek | Glas-Technik: Inhalt als RenderNode aufzeichnen, Ausschnitt mit `RenderEffect` + Sättigung weichzeichnen, deckender Grund in der Quelle, Glas fängt Berührungen ab | auf dem Gerät erprobt (1.3.0 behob „Inhalt scheint scharf durch“) |
| Musikbibliothek | **Lehre Dunkelmodus:** `LocalContentColor` zentral setzen; Prüfskript für Text ohne Farbe; Kontrastprüfung aus dem Quelltext | genau der Fehler, den der Auftrag als kritische Regel nennt |
| Musikbibliothek | **Lehre `BoxWithConstraints`:** Werte sofort festhalten, nicht aus tieferen Row/Column-Bereichen auf den Scope zugreifen | Übersetzungsfehler aus 1.1.0 |
| Filmbibliothek | Kapazität intern über `StorageStatsManager`, ersatzweise `StatFs`; SD-Karte über `StatFs`; nichts schätzen | gleiche Zahlen wie die Einstellungen |
| Filmbibliothek | Für Phase 4: geprüfte Kopie vor dem Löschen, FAT32-Grenzen, unzulässige Zeichen, Zurücklesen aus dem Zwischenspeicher, Xiaomi-Menünamen („Verwaltung aller Dateien“), `MANAGE_EXTERNAL_STORAGE` für das Kartenverzeichnis | teuer erkaufte Erfahrung mit SD-Karten |
| Leseraum | Datenschutz-Seite in Klartext, Lizenzen in der App | Transparenz |
| DriveGlass, Musikbibliothek | Dokumentationsaufbau (README mit ehrlichem Stand, STATUS, TESTPLAN, ENTSCHEIDUNGEN, GRENZEN, BERECHTIGUNGEN) und Prüfweg ohne SDK (JVM-Tests + Typprüfung) | bekannt und nachvollziehbar |

**Bewusst nicht übernommen:** Farbpaletten und Glasfarben (AETHER hat eine eigene Identität „Licht und Luft“),
Material-Symbols-Ressourcen (eigener Symbolsatz), Room, Media3, OkHttp/jsoup (nicht gebraucht), die Instrumente von
DriveGlass.
