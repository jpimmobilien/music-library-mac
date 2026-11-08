#!/bin/bash
# Bindet LAME 3.100 (LGPL) als Quelltext in Sources/CLame ein – nur der Encoder (libmp3lame), ohne
# Assembler (i386/), ohne SSE (vector/), ohne mpglib/Decoder. Die Dateien werden UNVERÄNDERT kopiert;
# config.h ist handgeschrieben (Sources/CLame/config/config.h) und wird nicht überschrieben.
#
#   scripts/vendor_lame.sh            → aktualisiert Sources/CLame/{include,libmp3lame}
#
# Prüfung gegen den offiziellen Tarball: scripts/verify_vendor.sh
set -euo pipefail
cd "$(dirname "$0")/.."

REPO="https://github.com/ShiftMediaProject/lame"
TAG="RELEASE__3_100"
COMMIT="d9ae340aa2a8185fa541c24d7883c2a2f6246765"
DEST="Sources/CLame"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
git clone -q --depth 1 -b "$TAG" "$REPO" "$TMP/lame"
GOT="$(git -C "$TMP/lame" rev-parse HEAD)"
if [ "$GOT" != "$COMMIT" ]; then
    echo "Unerwarteter Commit für $TAG: $GOT (erwartet $COMMIT)" >&2
    exit 1
fi
grep -q "LAME_MINOR_VERSION    100" "$TMP/lame/libmp3lame/version.h" || { echo "version.h ist nicht 3.100" >&2; exit 1; }

rm -rf "$DEST/libmp3lame" "$DEST/include"
mkdir -p "$DEST/libmp3lame" "$DEST/include"
cp "$TMP/lame/include/lame.h" "$DEST/include/lame.h"
for f in "$TMP/lame/libmp3lame/"*.c "$TMP/lame/libmp3lame/"*.h; do
    name="$(basename "$f")"
    # Decoder-Anbindung (mpglib) wird nicht gebraucht
    [ "$name" = "mpglib_interface.c" ] && continue
    cp "$f" "$DEST/libmp3lame/$name"
done
# fft.c bindet vector/lame_intrin.h immer ein (nur Prototypen) – der SSE-Code selbst
# (vector/xmm_quantize_sub.c) wird nicht übernommen und nicht übersetzt (HAVE_XMMINTRIN_H fehlt).
mkdir -p "$DEST/libmp3lame/vector"
cp "$TMP/lame/libmp3lame/vector/lame_intrin.h" "$DEST/libmp3lame/vector/lame_intrin.h"
cp "$TMP/lame/COPYING" "Resources/Licenses/LAME-LGPL-2.0.txt"
echo "LAME 3.100 ($COMMIT) nach $DEST kopiert: $(ls "$DEST/libmp3lame" | wc -l | tr -d ' ') Dateien"
