# Panora

Lokale KI für den Mac: Open-Weight-Modelle laufen direkt auf Apple Silicon (MLX), Panora wählt im AUTO MODE
selbst das passende Modell, wechselt mitten im Chat ohne Kontextverlust und funktioniert ohne Internet.
ChatGPT und Claude sind nur optionale externe Experten auf Klick.

- Konzept, Architektur, Roadmap: [docs/KONZEPT.md](docs/KONZEPT.md)
- Installation der DMG: [docs/INSTALLATION.md](docs/INSTALLATION.md)

## Aufbau

| Ordner | Inhalt |
| --- | --- |
| `Sources/PanoraCore` | Intelligenzschicht ohne Apple-Frameworks: Aufgabenerkennung, Router, Speicherplanung, Context Engine, Katalog, Lizenzen, Hugging Face, Projektanalyse, externe Experten |
| `Sources/Panora` | macOS-App (SwiftUI): Oberfläche, MLX- und Ollama-Rechenwerk, Downloads, Laufwerke, Hardware |
| `Tests/PanoraCoreTests` | Tests der Kernlogik (laufen auch unter Linux) |
| `project.yml` | Xcode-Projekt (XcodeGen) – MLX braucht xcodebuild für die Metal-Shader |
| `scripts/` | Build, DMG, Automatikmodi |
| `.github/workflows/panora-macos.yml` | CI: Tests, Build, Selbsttest, Bildschirmfotos, E2E mit echtem Modell, DMG |

## Selbst bauen

```bash
brew install xcodegen
VERSION=0.1.0 scripts/build_app.sh   # build/Panora.app
scripts/make_dmg.sh                  # dist/Panora.dmg
```

Voraussetzungen: Apple-Silicon-Mac, macOS 14 oder neuer, Xcode 26 oder neuer.
