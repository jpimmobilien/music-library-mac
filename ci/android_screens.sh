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
