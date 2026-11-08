#!/bin/bash
# Audio Studio (2.2) – Prüfung echter Internet-Quellen mit frei lizenzierten Testinhalten.
#
#   scripts/studio_webcheck.sh <ausgabeordner>
#
# Installiert yt-dlp und Deno über den StudioToolManager der App (in <ausgabeordner>/Tools, SHA-256-geprüft,
# von den offiziellen GitHub-Veröffentlichungen) und prüft über YtDlpSourceProvider Analyse, Vorschaubild,
# Download, Lesen mit AVFoundation und Export nach MP3 (Tests/StudioEngineTests/RemoteWebCheckTests.swift):
#   - YouTube:    „Big Buck Bunny“, Blender Foundation, CC BY 3.0 – https://www.youtube.com/watch?v=aqz-KE-bpKQ
#   - SoundCloud: Scott Buckley – „Echoes“, CC BY 4.0             – https://soundcloud.com/scottbuckley/echoes-cc-by
#   - Spotify:    nur Metadaten (oEmbed); der Download muss mit dem DRM-Hinweis abgelehnt werden
# Keine Cookies, keine Anmeldung. Blockiert ein Dienst den Rechner (z. B. „Sign in to confirm you're not a bot“),
# steht das als BLOCKIERT im Bericht – es wird nicht umgangen.
set -u
OUT="${1:-out/webcheck}"
mkdir -p "$OUT"
OUT="$(cd "$OUT" && pwd)"
cd "$(dirname "$0")/.."

export ML_STUDIO_WEBTEST=1
export ML_STUDIO_WEBCHECK_OUT="$OUT"
echo "== Audio Studio: Internet-Quellen ($(date -u '+%Y-%m-%d %H:%M UTC'), $(uname -m))"

if ! swift build --build-tests > "$OUT/build-tests.log" 2>&1; then
  echo "Bauen der Tests fehlgeschlagen:"
  grep -n "error:" "$OUT/build-tests.log" | sort -u | head -60
  exit 1
fi
swift test --skip-build --filter RemoteWebCheckTests > "$OUT/test.log" 2>&1
STATUS=$?
grep -E "\[Studio\]|error:|passed|failed|skipped|Executed" "$OUT/test.log" | head -200

# Unabhängige Prüfung der geladenen und exportierten Dateien mit ffprobe (falls vorhanden)
if command -v ffprobe >/dev/null 2>&1; then
  : > "$OUT/ffprobe.txt"
  for f in "$OUT"/media/*/* "$OUT"/export-*.mp3; do
    [ -f "$f" ] || continue
    echo "-- $(basename "$f")" >> "$OUT/ffprobe.txt"
    ffprobe -v error -show_entries format=duration,bit_rate,format_name:stream=codec_name,sample_rate,channels:format_tags=title,artist \
      -of default=nw=1 "$f" >> "$OUT/ffprobe.txt" 2>&1
  done
  echo "== ffprobe"
  cat "$OUT/ffprobe.txt"
fi

# Werkzeuge und geladene Medien nicht in den Ergebnis-Zweig übernehmen (groß)
rm -rf "$OUT/Tools" "$OUT/media" "$OUT/spotify"
find "$OUT" -name "*.mp3" -size +3M -delete 2>/dev/null

echo "== Bericht"
cat "$OUT/report.txt" 2>/dev/null || echo "(kein Bericht – siehe test.log)"
exit $STATUS
