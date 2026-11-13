#!/usr/bin/env bash
# Alle Prüfungen von ORBIT ohne Android-SDK (Entwicklungsumgebung ohne Google Maven):
#   1. JVM-Tests core/model und core/files   2. Kontrasttest des Designsystems
#   3. Typprüfung aller Android-Module       4. Prüfskript „Text/Symbol mit Theme-Farbe“
# Voraussetzung: Werkzeugkette unter $TOOLCHAIN (Standard /home/claude/toolchain), erzeugt mit scripts/setup.sh
# (siehe TOOLCHAIN.md). In Android Studio braucht man das nicht – dort: ./gradlew test assembleDebug lintDebug.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TC="${TOOLCHAIN:-/home/claude/toolchain}"
OUT="$(mktemp -d)"
unset JAVA_TOOL_OPTIONS || true
# Dateinamen mit Umlauten (Tests mit echten Dateien): Die JVM braucht dafür eine UTF-8-Umgebung – wie Android.
export LC_ALL=C.UTF-8 LANG=C.UTF-8
cd "$ROOT"
K="$TC/kotlinc/bin/kotlinc"; L="$TC/lib"
echo "== 1. JVM-Tests core/model"
"$TC/jvmtest.sh" --module model --src core/model/src/main/kotlin --test core/model/src/test/kotlin
"$K" -jvm-target 17 -d "$OUT/model" $(find core/model/src/main -name '*.kt') 2>&1 | grep -v '^Picked' || true
(cd "$OUT/model" && jar cf "$OUT/model.jar" .)
echo "== 1b. JVM-Tests core/files (echte Dateien in temporären Ordnern)"
"$TC/jvmtest.sh" --module files --src core/files/src/main/kotlin --test core/files/src/test/kotlin
"$ROOT/tools/typecheck/typecheck.sh" --module files --jvm --out "$OUT/files.jar" --werror -- core/files/src/main/kotlin
echo "== 2. Kontrasttest"
"$K" -jvm-target 17 -cp "$OUT/model.jar" -d "$OUT/pal" ui/designsystem/src/main/java/de/privateapp/aether/design/PaletteSpec.kt
"$K" -jvm-target 17 -cp "$OUT/model.jar:$OUT/pal:$L/junit-4.13.2.jar" -d "$OUT/paltest" ui/designsystem/src/test/java/de/privateapp/aether/design/ContrastTest.kt
java -cp "$OUT/model.jar:$OUT/pal:$OUT/paltest:$L/junit-4.13.2.jar:$L/hamcrest-core-1.3.jar:$TC/kotlinc/lib/kotlin-stdlib.jar" org.junit.runner.JUnitCore de.privateapp.aether.design.ContrastTest | tail -3
echo "== 3. Typprüfung"
TCK="$ROOT/tools/typecheck/typecheck.sh"
# Zusätzliche Platzhalter für APIs außerhalb der Framework-Stubs (siehe tools/typecheck/extra-stubs)
mkdir -p "$OUT/extra" && javac -d "$OUT/extra" $(find tools/typecheck/extra-stubs -name '*.java') && (cd "$OUT/extra" && jar cf "$OUT/extra.jar" .)
"$TCK" --module designsystem --res de.privateapp.aether.design=ui/designsystem/src/main/res --cp "$OUT/model.jar" --out "$OUT/designsystem.jar" --werror -- ui/designsystem/src/main/java
"$TCK" --module storage --no-compose --cp "$OUT/model.jar:$OUT/files.jar" --out "$OUT/storage.jar" --werror -- platform/storage/src/main/java
"$TCK" --module device --no-compose --cp "$OUT/model.jar:$OUT/extra.jar" --out "$OUT/device.jar" --werror -- platform/device/src/main/java
"$TCK" --module app --res de.privateapp.aether=app/src/main/res --res de.privateapp.aether.design=ui/designsystem/src/main/res \
  --buildconfig de.privateapp.aether --application-id de.privateapp.aether --version-code 3 --version-name 0.4.0 \
  --field 'APP_NAME=String:"ORBIT"' --cp "$OUT/model.jar:$OUT/files.jar:$OUT/designsystem.jar:$OUT/storage.jar:$OUT/device.jar:$OUT/extra.jar" --werror -- app/src/main/java
echo "== 4. Theme-Farben"
python3 -I tools/ui-check/uncolored.py
echo "Alle Prüfungen bestanden."
