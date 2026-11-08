# CLame – LAME 3.100 (MP3-Encoder)

| | |
|---|---|
| Version | LAME 3.100 (`libmp3lame/version.h`: 3.100, Release) |
| Herkunft | <https://github.com/ShiftMediaProject/lame>, Tag `RELEASE__3_100`, Commit `d9ae340aa2a8185fa541c24d7883c2a2f6246765` |
| Prüfung | `scripts/verify_vendor.sh` vergleicht die Dateien mit dem offiziellen Tarball `lame-3.100.tar.gz` (SourceForge, SHA-256 aus Homebrew) |
| Lizenz | GNU LGPL 2 („Library GPL“) – `Resources/Licenses/LAME-LGPL-2.0.txt` (wird mit der App ausgeliefert) |
| Einbinden | `scripts/vendor_lame.sh` |

## Inhalt

```
include/lame.h                 öffentliche Schnittstelle (unverändert, für Swift sichtbar)
libmp3lame/*.c, *.h            Encoder (unverändert)
libmp3lame/vector/lame_intrin.h  nur Prototypen, von fft.c immer eingebunden (unverändert)
config/config.h                handgeschrieben (ersetzt die configure-Ausgabe)
```

Nicht übernommen: Assembler (`libmp3lame/i386/`), SSE-Code (`libmp3lame/vector/xmm_quantize_sub.c`),
Decoder (`mpglib/`, `libmp3lame/mpglib_interface.c`), Frontend, Dokumentation, Build-Dateien.

## Änderungen

Keine Änderungen an den LAME-Quelltexten. Einstellungen nur über `config/config.h` und `Package.swift`:
kein `HAVE_NASM`, kein `HAVE_XMMINTRIN_H`, kein `HAVE_MPGLIB`; `TAKEHIRO_IEEE754_HACK` und `USE_FAST_LOG`
sind wie beim configure-Lauf für arm64 nicht gesetzt, damit arm64 und x86_64 identisch rechnen;
`NDEBUG` gesetzt, `DEBUG` (von SwiftPM im Debug-Build) wieder entfernt; Warnungen unterdrückt (`-w`),
`-O2` auch im Debug-Build.

## LGPL-Hinweis

LAME wird statisch eingebunden. Der vollständige Quelltext der App einschließlich dieser LAME-Dateien ist
öffentlich; damit kann LAME durch eine geänderte Fassung ersetzt und die App neu gebaut werden.
