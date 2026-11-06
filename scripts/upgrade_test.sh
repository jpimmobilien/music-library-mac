#!/bin/bash
# Echter Start mit vorhandenen Daten von Version 2.0 (Aktualisierungstest, normaler Modus – kein Vorschaumodus):
#
#   scripts/upgrade_test.sh "v20.app" "v21.app" abnahme/upgrade
#
#  1. Musikordner mit Testdateien (verschiedene Erstellungsdaten) anlegen
#  2. Version 2.0 starten: Datenbank anlegen, Ordner einlesen; danach Favoriten, Playlist, Bewertung,
#     Wiedergabezahl und Wiedergabeposition eintragen
#  3. Version 2.1 starten: Datenbank-Ergänzung, Hinzufügedatum je Datei bestimmen
#  4. Version 2.1 erneut starten, dazu eine neue Datei im Ordner: Datum bleibt, neue Datei bekommt ihr eigenes
#  5. Version 2.0 erneut starten: öffnet die ergänzte Datenbank weiterhin, nichts geht verloren
#
# Verwendet die echte Datenbank unter „~/Library/Application Support/Music Library“ – nur auf einem
# Testrechner ausführen (bricht ab, wenn dort schon eine Datenbank liegt).
set -uo pipefail
OLD="$1"; NEW="$2"; OUT="$3"
mkdir -p "$OUT"; OUT="$(cd "$OUT" && pwd)"
REPORT="$OUT/aktualisierung.txt"
: > "$REPORT"
SUPPORT="$HOME/Library/Application Support/Music Library"
DB="$SUPPORT/Library.sqlite"
MUSIC="$HOME/Abnahme-Musik"   # bewusst außerhalb geschützter Ordner (keine Rückfrage auf dem Testrechner)
PY=(python3 -I)
log() { echo "$*" | tee -a "$REPORT"; }

if [ -e "$DB" ]; then echo "Abbruch: $DB existiert bereits (kein Testrechner?)"; exit 2; fi

# --- 1. Testdateien ---------------------------------------------------------------------------------
mkdir -p "$MUSIC/Album Eins" "$MUSIC/Einzeltitel"
make_file() { # Zielpfad, Frequenz, Datum (JJJJMMTThhmm)
    local target="$1" freq="$2" stamp="$3" wav
    wav="$OUT/tmp-$RANDOM.wav"
    "${PY[@]}" - "$wav" "$freq" <<'EOF'
import math, struct, sys, wave
path, freq = sys.argv[1], float(sys.argv[2])
rate = 44100
with wave.open(path, "wb") as w:
    w.setnchannels(2); w.setsampwidth(2); w.setframerate(rate)
    frames = bytearray()
    for i in range(rate * 4):
        v = int(0.3 * 32767 * math.sin(2 * math.pi * freq * i / rate))
        frames += struct.pack("<hh", v, v)
    w.writeframes(bytes(frames))
EOF
    case "$target" in
        *.m4a) afconvert -f m4af -d aac -b 192000 "$wav" "$target" ;;
        *.wav) cp "$wav" "$target" ;;
    esac
    rm -f "$wav"
    touch -t "$stamp" "$target"
    if command -v SetFile >/dev/null 2>&1; then
        SetFile -d "${stamp:4:2}/${stamp:6:2}/${stamp:0:4} ${stamp:8:2}:${stamp:10:2}:00" "$target" 2>/dev/null || true
    fi
}
i=0
for name in "01 Morgen" "02 Mittag" "03 Abend" "04 Nacht" "05 Regen" "06 Sonne"; do
    i=$((i + 1))
    make_file "$MUSIC/Album Eins/$name.m4a" $((220 + 40 * i)) "2019$(printf %02d $i)0312$(printf %02d $((i * 7)))"
done
make_file "$MUSIC/Einzeltitel/Einzeltitel A.wav" 330 202003151200
make_file "$MUSIC/Einzeltitel/Einzeltitel B.m4a" 440 201811201830
log "Testdateien: $(find "$MUSIC" -type f | wc -l | tr -d ' ') (Erstellungsdaten 2018–2020)"

# --- Hilfen -----------------------------------------------------------------------------------------
PID=""
start_app() { # App, Name
    local bin="$1/Contents/MacOS/MusicLibrary"
    "$bin" > "$OUT/$2.log" 2>&1 &
    PID=$!
    log "▸ $2 gestartet (PID $PID, $(lipo -archs "$bin" 2>/dev/null) · Rechner $(uname -m))"
}
alive() { kill -0 "$PID" 2>/dev/null; }
stop_app() { # Name
    if alive; then
        kill -TERM "$PID"; wait "$PID" 2>/dev/null
        log "  $1 beendet"
    else
        wait "$PID" 2>/dev/null; local s=$?
        log "  ✗ $1 lief nicht mehr (Status $s) – Ausgabe:"; tail -20 "$OUT/$1.log" | tee -a "$REPORT"
        FAIL=1
    fi
    sleep 2
}
wait_for() { # Sekunden, SQL, erwarteter Wert
    local limit="$1" sql="$2" want="$3" got=""
    for _ in $(seq 1 "$limit"); do
        got=""
        [ -f "$DB" ] && got="$(sqlite3 "$DB" "$sql" 2>/dev/null || true)"
        [ "$got" = "$want" ] && return 0
        alive || return 1
        sleep 1
    done
    return 1
}
FAIL=0
check() { # Beschreibung, Befehl …
    local desc="$1"; shift
    if "$@" >> "$OUT/pruefungen.log" 2>&1; then log "  ✓ $desc"; else log "  ✗ $desc"; FAIL=1; fi
}

# --- 2. Version 2.0 ---------------------------------------------------------------------------------
log ""
log "== Version 2.0: Datenbank anlegen und Ordner einlesen"
start_app "$OLD" "v20-erststart"
wait_for 60 "SELECT count(*) FROM sqlite_master WHERE name='folders'" 1 || log "  ✗ Datenbank nicht angelegt"
sleep 3
stop_app "v20-erststart"
sqlite3 "$DB" "INSERT INTO folders(path, bookmark, name, addedAt, isExternal, enabled) VALUES('$MUSIC', NULL, 'Abnahme', strftime('%s','now'), 0, 1);"
start_app "$OLD" "v20-einlesen"
if wait_for 120 "SELECT count(*) FROM tracks" 8; then log "  ✓ 8 Titel eingelesen"; else log "  ✗ Einlesen unvollständig: $(sqlite3 "$DB" 'SELECT count(*) FROM tracks')"; FAIL=1; fi
sleep 4
stop_app "v20-einlesen"
# Nutzerdaten wie nach einiger Benutzung
sqlite3 "$DB" <<'SQL'
INSERT INTO favorite_tracks(trackUid, addedAt) SELECT uid, 1700000000 FROM tracks ORDER BY uid LIMIT 2;
INSERT INTO playlists(name, createdAt, updatedAt) VALUES('Abnahme-Playlist', 1700000000, 1700000000);
INSERT INTO playlist_entries(playlistId, trackUid, position, addedAt)
    SELECT (SELECT id FROM playlists WHERE name='Abnahme-Playlist'), uid, uid, 1700000000 FROM tracks ORDER BY uid DESC LIMIT 3;
INSERT INTO play_stats(trackUid, playCount, lastPlayedAt, firstPlayedAt, totalListenedMs) SELECT uid, 7, 1700001000, 1690000000, 28000 FROM tracks ORDER BY uid LIMIT 1 OFFSET 2;
INSERT INTO resume_points(trackUid, positionMs, updatedAt) SELECT uid, 1500, 1700002000 FROM tracks ORDER BY uid LIMIT 1 OFFSET 3;
UPDATE tracks SET rating = 80 WHERE uid = (SELECT uid FROM tracks ORDER BY uid LIMIT 1 OFFSET 4);
SQL

"${PY[@]}" - "$DB" "$OUT/stand-v20.json" <<'EOF'
import json, sqlite3, sys
db = sqlite3.connect(sys.argv[1])
q = lambda s: [list(r) for r in db.execute(s)]
json.dump({
    "user_version": db.execute("PRAGMA user_version").fetchone()[0],
    "tracks": q("SELECT uid, path, title, dateAdded, rating, durationMs, codec, bitrate, sampleRate FROM tracks ORDER BY uid"),
    "favorites": q("SELECT trackUid, addedAt FROM favorite_tracks ORDER BY trackUid"),
    "playlists": q("SELECT p.name, e.trackUid, e.position FROM playlists p JOIN playlist_entries e ON e.playlistId = p.id ORDER BY e.position"),
    "stats": q("SELECT * FROM play_stats ORDER BY trackUid"),
    "resume": q("SELECT * FROM resume_points ORDER BY trackUid"),
}, open(sys.argv[2], "w"), indent=1)
EOF
log "  Stand 2.0: $(sqlite3 "$DB" 'SELECT count(*) FROM tracks') Titel, alle mit demselben Hinzufügedatum: $(sqlite3 "$DB" 'SELECT count(DISTINCT dateAdded) FROM tracks') verschiedene Werte"

# --- 3. Version 2.1 ---------------------------------------------------------------------------------
log ""
log "== Version 2.1: erster Start mit den Daten von 2.0"
start_app "$NEW" "v21-erststart"
if wait_for 180 "SELECT count(*) FROM tracks WHERE dateAddedSource = 0" 0; then log "  ✓ Hinzufügedatum für alle Titel bestimmt"; else log "  ✗ Hinzufügedatum nicht bestimmt"; FAIL=1; fi
sleep 8
stop_app "v21-erststart"

CHECK_PY=$(cat <<'EOF'
import json, os, sqlite3, sys
mode, db_path, before_path = sys.argv[1], sys.argv[2], sys.argv[3]
db = sqlite3.connect(db_path)
before = json.load(open(before_path))
q = lambda s: [list(r) for r in db.execute(s)]
problems = []
def need(cond, msg):
    if not cond: problems.append(msg)
need(db.execute("PRAGMA user_version").fetchone()[0] == 1, "user_version ist nicht mehr 1")
need(db.execute("PRAGMA integrity_check").fetchone()[0] == "ok", "integrity_check meldet Fehler")
cols = {r[1] for r in db.execute("PRAGMA table_info(tracks)")}
need("dateAddedSource" in cols, "Spalte dateAddedSource fehlt")
need(db.execute("SELECT count(*) FROM sqlite_master WHERE name='app_meta'").fetchone()[0] == 1, "Tabelle app_meta fehlt")
old = {t[0]: t for t in before["tracks"]}
rows = q("SELECT uid, path, title, dateAdded, rating, durationMs, codec, bitrate, sampleRate, dateAddedSource FROM tracks ORDER BY uid")
now = {r[0]: r for r in rows}
need(set(old) <= set(now), "Titel aus 2.0 fehlen: %s" % sorted(set(old) - set(now)))
for uid, o in old.items():
    n = now.get(uid)
    if not n: continue
    need(n[1] == o[1] and n[2] == o[2], "Titel %d: Pfad/Titel geändert" % uid)
    need(n[4] == o[4], "Titel %d: Bewertung geändert" % uid)
    need(n[3] <= o[3], "Titel %d: Hinzufügedatum später als vorher (%d > %d)" % (uid, n[3], o[3]))
for n in rows:
    if n[1] and os.path.exists(n[1]):
        birth = int(os.stat(n[1]).st_birthtime)
        need(abs(n[3] - birth) <= 1, "%s: Hinzufügedatum %d ≠ Erstellungsdatum %d" % (os.path.basename(n[1]), n[3], birth))
        need(n[9] == 2, "%s: Quelle %d statt 2 (Erstellungsdatum)" % (os.path.basename(n[1]), n[9]))
for key, sql in [("favorites", "SELECT trackUid, addedAt FROM favorite_tracks ORDER BY trackUid"),
                 ("playlists", "SELECT p.name, e.trackUid, e.position FROM playlists p JOIN playlist_entries e ON e.playlistId = p.id ORDER BY e.position"),
                 ("stats", "SELECT * FROM play_stats ORDER BY trackUid"),
                 ("resume", "SELECT * FROM resume_points ORDER BY trackUid")]:
    need(q(sql) == before[key], "%s verändert" % key)
if mode == "same":
    prev = {t[0]: t for t in json.load(open(sys.argv[4]))["tracks"]}
    for uid, p in prev.items():
        need(uid in now and now[uid][3] == p[3], "Titel %d: Hinzufügedatum beim erneuten Start verändert" % uid)
for line in ["%-34s %s  Quelle %d  %s" % (os.path.basename(r[1] or ""), __import__("time").strftime("%d.%m.%Y %H:%M", __import__("time").localtime(r[3])), r[9], (r[6] or "?") + " " + str(r[7] or 0) + " kbit/s") for r in rows]:
    print("    " + line)
json.dump({"tracks": [r[:4] for r in rows]}, open(sys.argv[-1] if mode == "save" else os.devnull, "w"))
for p in problems: print("    ✗ " + p)
sys.exit(1 if problems else 0)
EOF
)
log "  Prüfung der Datenbank nach dem ersten Start von 2.1:"
"${PY[@]}" -c "$CHECK_PY" save "$DB" "$OUT/stand-v20.json" "$OUT/stand-v21.json" 2>&1 | tee -a "$REPORT"
[ "${PIPESTATUS[0]}" -eq 0 ] && log "  ✓ Schema ergänzt (user_version 1), alle Titel, Favoriten, Playlist, Bewertung, Statistik und Wiedergabeposition unverändert, Hinzufügedatum = Erstellungsdatum der Datei" || FAIL=1

# --- 4. Erneuter Start von 2.1 mit einer neuen Datei ------------------------------------------------
log ""
log "== Version 2.1: erneuter Start, dazu eine neue Datei (erstellt 2021)"
make_file "$MUSIC/Einzeltitel/Neu hinzugefuegt.m4a" 550 202107040900
start_app "$NEW" "v21-zweitstart"
if wait_for 120 "SELECT count(*) FROM tracks WHERE dateAddedSource <> 0" 9; then log "  ✓ neue Datei eingelesen"; else log "  ✗ neue Datei nicht eingelesen ($(sqlite3 "$DB" 'SELECT count(*) FROM tracks'))"; FAIL=1; fi
sleep 6
stop_app "v21-zweitstart"
"${PY[@]}" -c "$CHECK_PY" same "$DB" "$OUT/stand-v20.json" "$OUT/stand-v21.json" 2>&1 | tee -a "$REPORT"
[ "${PIPESTATUS[0]}" -eq 0 ] && log "  ✓ Hinzufügedaten nach dem Neustart unverändert, neue Datei mit eigenem Erstellungsdatum" || FAIL=1

# --- 5. Zurück zu 2.0 -------------------------------------------------------------------------------
log ""
log "== Version 2.0: erneuter Start mit der ergänzten Datenbank"
start_app "$OLD" "v20-rueckweg"
sleep 20
stop_app "v20-rueckweg"
check "Datenbank nicht beiseitegelegt (keine „Library-defekt“-Datei)" bash -c "! ls \"$SUPPORT\"/Library-defekt-* >/dev/null 2>&1"
"${PY[@]}" -c "$CHECK_PY" same "$DB" "$OUT/stand-v20.json" "$OUT/stand-v21.json" > "$OUT/rueckweg.txt" 2>&1 \
    && log "  ✓ 2.0 öffnet die ergänzte Datenbank; alle Daten und Hinzufügedaten erhalten" \
    || { log "  ✗ nach dem Rückweg verändert:"; tee -a "$REPORT" < "$OUT/rueckweg.txt"; FAIL=1; }

sleep 5
for f in "$HOME"/Library/Logs/DiagnosticReports/MusicLibrary*; do
    [ -e "$f" ] && cp "$f" "$OUT/" && log "  Absturzbericht: $(basename "$f")" && FAIL=1
done
log ""
if [ $FAIL -eq 0 ]; then log "ERGEBNIS: Aktualisierung 2.0 → 2.1 → 2.0 ohne Befund"; else log "ERGEBNIS: Befunde siehe oben"; fi
exit $FAIL
