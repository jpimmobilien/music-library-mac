#!/bin/bash
# Bindet libFLAC 1.5.0 (BSD-3, Xiph.Org) als Quelltext in Sources/CFLAC ein – ohne Ogg, ohne
# Assembler/Intrinsics (SSE/AVX/NEON), ohne Werkzeuge. Die Dateien werden UNVERÄNDERT kopiert;
# config.h ist handgeschrieben und wird nicht überschrieben.
#
#   scripts/vendor_flac.sh            → aktualisiert Sources/CFLAC/{include/FLAC,vendor}
#
# Prüfung gegen den offiziellen Tarball: scripts/verify_vendor.sh
set -euo pipefail
cd "$(dirname "$0")/.."

REPO="https://github.com/xiph/flac"
TAG="1.5.0"
COMMIT="1507800de4b70e21be71f38caa0d9079d0bc6e45"
DEST="Sources/CFLAC"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
git clone -q --depth 1 -b "$TAG" "$REPO" "$TMP/flac"
GOT="$(git -C "$TMP/flac" rev-parse HEAD)"
if [ "$GOT" != "$COMMIT" ]; then
    echo "Unerwarteter Commit für $TAG: $GOT (erwartet $COMMIT)" >&2
    exit 1
fi
S="$TMP/flac"

rm -rf "$DEST/include/FLAC" "$DEST/vendor"
mkdir -p "$DEST/include/FLAC" "$DEST/vendor/include/share" "$DEST/vendor/src/libFLAC/include/private" \
         "$DEST/vendor/src/libFLAC/include/protected" "$DEST/vendor/src/libFLAC/deduplication"

# Öffentliche Kopfdateien (SwiftPM bildet aus include/ das Modul CFLAC)
cp "$S"/include/FLAC/*.h "$DEST/include/FLAC/"

# Interne Hilfsköpfe (nur die von libFLAC benutzten)
for h in alloc.h compat.h endswap.h macros.h private.h win_utf8_io.h; do
    cp "$S/include/share/$h" "$DEST/vendor/include/share/$h"
done

# Bibliothek ohne Ogg und ohne Intrinsics
for c in bitmath.c bitreader.c bitwriter.c cpu.c crc.c fixed.c float.c format.c lpc.c md5.c memory.c \
         metadata_iterators.c metadata_object.c stream_decoder.c stream_encoder.c stream_encoder_framing.c window.c; do
    cp "$S/src/libFLAC/$c" "$DEST/vendor/src/libFLAC/$c"
done
# Von bitreader.c und lpc.c per #include eingebundene Teile (werden nicht einzeln übersetzt)
for c in bitreader_read_rice_signed_block.c lpc_compute_autocorrelation_intrin.c; do
    cp "$S/src/libFLAC/deduplication/$c" "$DEST/vendor/src/libFLAC/deduplication/$c"
done
for h in "$S"/src/libFLAC/include/private/*.h; do
    case "$(basename "$h")" in ogg_*) continue ;; esac
    cp "$h" "$DEST/vendor/src/libFLAC/include/private/"
done
cp "$S"/src/libFLAC/include/protected/*.h "$DEST/vendor/src/libFLAC/include/protected/"

cp "$S/COPYING.Xiph" "Resources/Licenses/FLAC-BSD-3-Clause.txt"
echo "libFLAC $TAG ($COMMIT) nach $DEST kopiert"
