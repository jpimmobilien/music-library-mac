#!/bin/bash
# Prüft die eingebundenen Quelltexte gegen die offiziellen Veröffentlichungen:
#   LAME 3.100   – Tarball von SourceForge, SHA-256 gegen die Prüfsumme aus Homebrew (brew info --json=v2 lame)
#   libFLAC 1.5.0 – Tarball von Xiph, SHA-256 gegen Homebrew (falls dort ebenfalls 1.5.0), sonst nur Dateivergleich
# und vergleicht jede eingebundene Datei mit der Datei im Tarball (Unterschiede werden aufgelistet).
#
#   scripts/verify_vendor.sh          → Exit 0, wenn Prüfsummen und alle Dateien übereinstimmen
#
# Läuft auf CI (macOS mit Homebrew); braucht curl, tar, shasum, python3 und Netzzugang.
set -uo pipefail
cd "$(dirname "$0")/.."
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
STATUS=0

sha256() { shasum -a 256 "$1" | awk '{print $1}'; }

# Homebrew-Angaben: „Version URL Prüfsumme“
brew_stable() {
    command -v brew >/dev/null 2>&1 || return 1
    brew info --json=v2 "$1" 2>/dev/null | python3 -c '
import json, sys
f = json.load(sys.stdin)["formulae"][0]
print(f["versions"]["stable"], f["urls"]["stable"]["url"], f["urls"]["stable"]["checksum"])'
}

# Prüfsumme einer älteren Homebrew-Formel (falls Homebrew inzwischen eine neuere Version führt):
# sucht in der Git-Geschichte von homebrew-core die letzte Formel mit dem gesuchten Tarball.
brew_history_checksum() {
    local formula="$1" tarball="$2" letter
    letter="$(printf '%s' "$formula" | cut -c1)"
    curl -fsSL "https://api.github.com/repos/Homebrew/homebrew-core/commits?path=Formula/${letter}/${formula}.rb&per_page=30" 2>/dev/null |
        python3 -c 'import json, sys
for c in json.load(sys.stdin): print(c["sha"])' 2>/dev/null |
        while read -r sha; do
            body="$(curl -fsSL "https://raw.githubusercontent.com/Homebrew/homebrew-core/${sha}/Formula/${letter}/${formula}.rb" 2>/dev/null)" || continue
            if printf '%s' "$body" | grep -q "/${tarball}\""; then
                sum="$(printf '%s\n' "$body" | grep -m1 -E '^[[:space:]]*sha256 "[0-9a-f]{64}"' | sed -E 's/.*"([0-9a-f]{64})".*/\1/')"
                echo "${sum} ${sha}"
                break
            fi
        done
}

# Vergleicht eingebundene Dateien (Paare „eingebunden|Tarball“ auf stdin). Unterschiede, die nur aus
# nicht expandierten CVS-Kennungen ($Id$ statt $Id: … $) bestehen, werden gesondert gezählt.
compare_files() {
    local name="$1" same=0 differ=0 missing=0 cvs=0
    while IFS='|' read -r ours theirs; do
        if [ ! -f "$theirs" ]; then
            echo "  FEHLT im Tarball: ${ours}"
            missing=$((missing + 1))
        elif cmp -s "$ours" "$theirs"; then
            same=$((same + 1))
        elif cmp -s <(sed -E 's/\$Id:[^$]*\$/$Id$/g' "$ours") <(sed -E 's/\$Id:[^$]*\$/$Id$/g' "$theirs"); then
            echo "  NUR CVS-KENNUNG (\$Id\$ nicht expandiert): ${ours}"
            cvs=$((cvs + 1))
        else
            echo "  UNTERSCHIED: ${ours}"
            diff -u "$theirs" "$ours" | head -40 | sed 's/^/    /'
            differ=$((differ + 1))
        fi
    done
    echo "  ${name}: ${same} Dateien identisch, ${cvs} nur mit anderer \$Id\$-Kommentarzeile, ${differ} mit inhaltlichem Unterschied, ${missing} nicht im Tarball"
    [ "$differ" -eq 0 ] && [ "$missing" -eq 0 ]
}

echo "== LAME 3.100 =="
LAME_URL="https://downloads.sourceforge.net/project/lame/lame/3.100/lame-3.100.tar.gz"
if curl -fsSL --retry 3 -o "$TMP/lame.tar.gz" "$LAME_URL"; then
    SUM="$(sha256 "$TMP/lame.tar.gz")"
    echo "  Tarball: $LAME_URL"
    echo "  SHA-256: $SUM"
    if INFO="$(brew_stable lame)"; then
        read -r BV BURL BSUM <<<"$INFO"
        echo "  Homebrew lame: Version $BV, $BURL"
        echo "  Homebrew SHA-256: $BSUM"
        if [ "$BV" = "3.100" ]; then
            if [ "$BSUM" = "$SUM" ]; then echo "  OK: Prüfsumme stimmt mit Homebrew überein"; else echo "  FEHLER: Prüfsumme weicht von Homebrew ab"; STATUS=1; fi
        else
            echo "  Homebrew führt inzwischen $BV – suche die Formel für 3.100 in der Geschichte von homebrew-core …"
            HIST="$(brew_history_checksum lame lame-3.100.tar.gz)"
            if [ -n "$HIST" ]; then
                read -r HSUM HSHA <<<"$HIST"
                echo "  Homebrew (homebrew-core ${HSHA:0:12}) lame 3.100 SHA-256: $HSUM"
                if [ "$HSUM" = "$SUM" ]; then echo "  OK: Prüfsumme stimmt mit der Homebrew-Formel für 3.100 überein"; else echo "  FEHLER: Prüfsumme weicht ab"; STATUS=1; fi
            else
                echo "  FEHLER: Homebrew-Formel für 3.100 nicht abrufbar (GitHub-API) – Prüfsumme nicht verglichen"
                STATUS=1
            fi
        fi
    else
        echo "  WARNUNG: Homebrew nicht verfügbar – Prüfsumme nicht verglichen"
        STATUS=1
    fi
    tar -xzf "$TMP/lame.tar.gz" -C "$TMP"
    L="$TMP/lame-3.100"
    {
        echo "Sources/CLame/include/lame.h|$L/include/lame.h"
        for f in Sources/CLame/libmp3lame/*.c Sources/CLame/libmp3lame/*.h Sources/CLame/libmp3lame/vector/*.h; do
            echo "$f|$L/${f#Sources/CLame/}"
        done
    } | compare_files "LAME" || STATUS=1
    echo "  Nicht übernommen (bewusst): $(cd "$L/libmp3lame" && ls -d i386 vector/xmm_quantize_sub.c mpglib_interface.c 2>/dev/null | tr '\n' ' ')"
else
    echo "  FEHLER: Tarball nicht ladbar ($LAME_URL)"
    STATUS=1
fi

echo "== libFLAC 1.5.0 =="
FLAC_URL="https://downloads.xiph.org/releases/flac/flac-1.5.0.tar.xz"
if curl -fsSL --retry 3 -o "$TMP/flac.tar.xz" "$FLAC_URL"; then
    SUM="$(sha256 "$TMP/flac.tar.xz")"
    echo "  Tarball: $FLAC_URL"
    echo "  SHA-256: $SUM"
    if INFO="$(brew_stable flac)"; then
        read -r BV BURL BSUM <<<"$INFO"
        echo "  Homebrew flac: Version $BV, $BURL"
        if [ "$BV" = "1.5.0" ]; then
            if [ "$BSUM" = "$SUM" ]; then echo "  OK: Prüfsumme stimmt mit Homebrew überein"; else echo "  FEHLER: Prüfsumme weicht von Homebrew ab ($BSUM)"; STATUS=1; fi
        else
            echo "  HINWEIS: Homebrew hat Version $BV – Prüfsumme von 1.5.0 dort nicht vorhanden, nur Dateivergleich"
        fi
    fi
    tar -xJf "$TMP/flac.tar.xz" -C "$TMP"
    F="$TMP/flac-1.5.0"
    {
        for f in Sources/CFLAC/include/FLAC/*.h; do echo "$f|$F/include/FLAC/$(basename "$f")"; done
        for f in Sources/CFLAC/vendor/include/share/*.h; do echo "$f|$F/include/share/$(basename "$f")"; done
        for f in $(cd Sources/CFLAC/vendor && find src -type f | sort); do echo "Sources/CFLAC/vendor/$f|$F/$f"; done
    } | compare_files "libFLAC" || STATUS=1
else
    echo "  FEHLER: Tarball nicht ladbar ($FLAC_URL)"
    STATUS=1
fi

if [ "$STATUS" -eq 0 ]; then echo "== Ergebnis: alles in Ordnung =="; else echo "== Ergebnis: Abweichungen (siehe oben) =="; fi
exit "$STATUS"
