# CFLAC – libFLAC 1.5.0 (FLAC-Encoder)

| | |
|---|---|
| Version | libFLAC 1.5.0 |
| Herkunft | <https://github.com/xiph/flac>, Tag `1.5.0`, Commit `1507800de4b70e21be71f38caa0d9079d0bc6e45` („Release FLAC 1.5.0“, 11.02.2025) |
| Prüfung | `scripts/verify_vendor.sh` vergleicht die Dateien mit dem offiziellen Tarball `flac-1.5.0.tar.xz` (Xiph) |
| Lizenz | BSD-3-Clause (Xiph.Org) – `Resources/Licenses/FLAC-BSD-3-Clause.txt` (wird mit der App ausgeliefert) |
| Einbinden | `scripts/vendor_flac.sh` |

## Inhalt

```
include/FLAC/*.h                    öffentliche Schnittstelle (unverändert; SwiftPM bildet daraus das Modul CFLAC)
vendor/include/share/*.h            interne Hilfsköpfe (unverändert, nur die benötigten)
vendor/src/libFLAC/*.c              Bibliothek (unverändert)
vendor/src/libFLAC/deduplication/   per #include eingebundene Teile (unverändert, nicht einzeln übersetzt)
vendor/src/libFLAC/include/…        private/protected Köpfe (unverändert, ohne ogg_*)
config/config.h                     handgeschrieben (ersetzt die CMake/configure-Ausgabe)
```

Nicht übernommen: Ogg (`ogg_*.c/h`), alle Intrinsics-Dateien (`*_intrin_*.c`: SSE2/SSSE3/SSE4.1/AVX2/FMA/NEON),
Werkzeuge (`flac`, `metaflac`), C++-Schnittstelle, Tests, Dokumentation.

## Änderungen

Keine Änderungen an den libFLAC-Quelltexten. Einstellungen nur über `config/config.h` und `Package.swift`:
`FLAC__HAS_OGG 0`, `FLAC__NO_ASM`, `FLAC__HAS_X86INTRIN 0`, `FLAC__HAS_NEONINTRIN 0` – arm64 und x86_64
verwenden denselben portablen C-Code; ohne `HAVE_PTHREAD` (einfädig); `NDEBUG` gesetzt, `DEBUG` (von
SwiftPM im Debug-Build) wieder entfernt; Warnungen unterdrückt (`-w`), `-O2` auch im Debug-Build.
