# Panora installieren

1. `Panora.dmg` öffnen und **Panora** auf **Programme** ziehen.
2. Die App ist noch nicht notarisiert (die Signierung kommt später separat). Beim ersten Start meldet macOS,
   dass die App nicht geöffnet werden kann:
   - **Systemeinstellungen → Datenschutz & Sicherheit** öffnen, ganz unten bei „Panora wurde blockiert“
     auf **Trotzdem öffnen** klicken und bestätigen.
   - Alternativ im Terminal: `xattr -dr com.apple.quarantine /Applications/Panora.app`
3. In Panora unter **Speicher** die externe SSD als Ziel für Modelle wählen („Für Modelle verwenden“).
4. Unter **Entdecken** ein Modell laden – Empfehlung für 64 GB: **Qwen3.6 35B A3B** (ca. 21 GB) für Coding und
   Alltag, dazu **Qwen3.6 27B** für Planung und Review und ein kleines Modell wie **Qwen3 8B**.
5. Danach funktioniert Panora ohne Internet.

Optional: Unter **Einstellungen → Externe Experten** API-Schlüssel für OpenAI oder Anthropic hinterlegen.
Ohne Schlüssel und ohne Klick auf „Zweitmeinung“ verlässt nichts den Mac.

Systemvoraussetzungen: Mac mit Apple Silicon, macOS 14 oder neuer.
