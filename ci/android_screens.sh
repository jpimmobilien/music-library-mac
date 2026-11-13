#!/usr/bin/env bash
# Installiert die APK auf dem laufenden Emulator, startet ORBIT und nimmt Bildschirmfotos auf.
# Aufruf: ci/android_screens.sh <apk> <ausgabeordner>
# Bildschirme werden über die Startparameter des Prüfmodus geöffnet (MainActivity: nur mit "orbit.snapshot"),
# Hell/Dunkel über den Nachtmodus von Android, das Tablet über "wm size/density".
set -u
APK="$1"; OUT="$2"
mkdir -p "$OUT"
PKG=de.privateapp.aether
log() { echo "[$(date +%H:%M:%S)] $*" | tee -a "$OUT/ablauf.txt"; }

adb wait-for-device
adb shell getprop ro.build.version.release | sed 's/^/Android /' | tee "$OUT/geraet.txt"
adb shell getprop ro.product.model | tee -a "$OUT/geraet.txt"
adb shell wm size | tee -a "$OUT/geraet.txt"
log "Installation"
adb install -r -g "$APK" 2>&1 | tee "$OUT/installation.txt"
adb shell dumpsys package "$PKG" | grep -E "versionName|versionCode|targetSdk" | tee -a "$OUT/installation.txt"
# Animationen des Systems an lassen (ORBIT-Übergänge sollen sichtbar sein); Statusleiste ruhig
adb shell settings put global window_animation_scale 1 >/dev/null 2>&1
adb shell settings put global transition_animation_scale 1 >/dev/null 2>&1
adb shell settings put global animator_duration_scale 1 >/dev/null 2>&1

shot() { # name, screen, [extra args]
  local name="$1" screen="$2"; shift 2
  adb shell am force-stop "$PKG"
  adb shell am start -W -n "$PKG/.MainActivity" --es orbit.snapshot "$screen" "$@" >/dev/null 2>&1
  sleep 6
  adb exec-out screencap -p > "$OUT/$name.png"
  log "Foto $name ($screen) $(stat -c %s "$OUT/$name.png") Bytes"
}

start_time() {
  adb shell am force-stop "$PKG"
  adb shell am start -W -n "$PKG/.MainActivity" 2>&1 | grep -E "TotalTime|WaitTime|Status" | tee -a "$OUT/startzeit.txt"
}

log "Kaltstartzeiten (3 Läufe)"
for i in 1 2 3; do start_time; sleep 3; done

SCREENS="home device storage files motion settings"
for mode in no yes; do
  adb shell cmd uimode night "$mode" >/dev/null 2>&1
  label=$([ "$mode" = yes ] && echo dunkel || echo hell)
  for s in $SCREENS; do shot "telefon-$label-$s" "$s"; done
done

log "Alle Themes (Übersicht) – Darstellung nur für diese Sitzung"
adb shell cmd uimode night no >/dev/null 2>&1
for t in GLASS_LIGHT GLASS_DARK MINIMAL_LIGHT MINIMAL_DARK DEEP_DARK; do
  shot "theme-$t-home" home --es orbit.theme "$t"
done

log "Effektprofile"
for e in MINIMAL BALANCED IMMERSIVE; do
  shot "effekte-$e-home" home --es orbit.theme GLASS_DARK --es orbit.effects "$e"
done

log "Übersicht gescrollt und ORBIT Core aufgeklappt"
shot "telefon-hell-home-oben" home --es orbit.theme GLASS_LIGHT
adb shell input swipe 540 1700 540 900 400
sleep 2
adb exec-out screencap -p > "$OUT/telefon-hell-home-gescrollt.png"
log "Foto telefon-hell-home-gescrollt"

log "Bewegung gescrollt (Sensor-Globus) – gewischt wird am linken Rand, damit der Globus sich nicht dreht"
shot "telefon-dunkel-bewegung-oben" motion --es orbit.theme GLASS_DARK
for i in 1 2 3; do
  adb shell input swipe 60 1900 60 700 500
  sleep 2
  adb exec-out screencap -p > "$OUT/telefon-dunkel-bewegung-gescrollt-$i.png"
  log "Foto telefon-dunkel-bewegung-gescrollt-$i"
done

log "ORBIT Core: Zeile „Arbeitsspeicher“ aufgeklappt (Antippen nach Bildschirmposition)"
shot "telefon-dunkel-home-orbit" home --es orbit.theme GLASS_DARK
adb shell uiautomator dump /sdcard/ui.xml >/dev/null 2>&1 && adb pull /sdcard/ui.xml "$OUT/ui-home.xml" >/dev/null 2>&1
B=$(python3 - "$OUT/ui-home.xml" <<'PY'
import re,sys
try:
    x=open(sys.argv[1],encoding='utf-8').read()
except Exception:
    sys.exit(0)
for m in re.finditer(r'<node [^>]*>', x):
    n=m.group(0)
    if re.search(r'text="Arbeitsspeicher', n):
        b=re.search(r'bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"', n)
        if b:
            x1,y1,x2,y2=map(int,b.groups()); print((x1+x2)//2,(y1+y2)//2); break
PY
)
if [ -n "$B" ]; then
  adb shell input tap $B
  sleep 3
  adb exec-out screencap -p > "$OUT/telefon-dunkel-home-orbit-aufgeklappt.png"
  log "Foto telefon-dunkel-home-orbit-aufgeklappt (Tipp bei $B)"
else
  log "Zeile „Arbeitsspeicher“ nicht gefunden – kein Foto aufgeklappt"
fi

log "Tablet-Größe"
adb shell wm size 1600x2560
adb shell wm density 320
adb shell cmd uimode night no >/dev/null 2>&1
for s in home device; do shot "tablet-hell-$s" "$s"; done
adb shell cmd uimode night yes >/dev/null 2>&1
for s in home device; do shot "tablet-dunkel-$s" "$s"; done
adb shell wm size reset
adb shell wm density reset

log "Leistung: gfxinfo nach Startseite"
adb shell am force-stop "$PKG"
adb shell am start -W -n "$PKG/.MainActivity" >/dev/null 2>&1
sleep 8
adb shell dumpsys gfxinfo "$PKG" | sed -n '1,40p' > "$OUT/gfxinfo.txt"
adb shell dumpsys meminfo "$PKG" | sed -n '1,40p' > "$OUT/meminfo.txt"
log "Absturzprüfung"
adb logcat -d -b crash > "$OUT/abstuerze.txt" 2>&1
adb logcat -d | grep -iE "orbit|aether|AndroidRuntime" | tail -400 > "$OUT/logcat.txt"
if [ -s "$OUT/abstuerze.txt" ] && grep -q "$PKG" "$OUT/abstuerze.txt"; then log "ABSTURZ gefunden"; exit 1; fi
log "fertig"
