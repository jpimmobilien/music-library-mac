#!/usr/bin/env bash
# Compile a pure Kotlin/JVM module and run its JUnit 4 tests (no Gradle needed).
#
#   jvmtest.sh [--module NAME] [--cp JAR]... [--out DIR] --src DIR... [--test DIR...]
#
# Main sources are compiled against the Java 17 API (like jvmTarget 17), kotlinx-coroutines 1.11.0 is on the
# classpath. Tests additionally see JUnit 4.13.2, hamcrest-core 1.3, kotlin-test(-junit) and
# kotlinx-coroutines-test 1.11.0. Every class with @Test methods is run. Exit code 0 = compiled and all green.
set -euo pipefail
TC="${TOOLCHAIN:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
[ -x "$TC/kotlinc/bin/kotlinc" ] || TC=/home/claude/toolchain
unset JAVA_TOOL_OPTIONS || true
export JAVA_OPTS="${JAVA_OPTS:--Xmx3g}"
MODULE=main; CP=(); SRC=(); TEST=(); OUT=""
mode=""
while [ $# -gt 0 ]; do
  case "$1" in
    --module) MODULE="$2"; shift 2;;
    --cp) CP+=("$2"); shift 2;;
    --out) OUT="$2"; shift 2;;
    --src) mode=src; shift;;
    --test) mode=test; shift;;
    *) if [ "$mode" = src ]; then SRC+=("$1"); elif [ "$mode" = test ]; then TEST+=("$1"); else echo "unexpected $1" >&2; exit 2; fi; shift;;
  esac
done
WORK=$(mktemp -d "${TMPDIR:-/tmp}/jvmtest.XXXXXX")
trap 'rm -rf "$WORK"' EXIT
L="$TC/lib"; K="$TC/kotlinc/lib"
LIBCP="$L/kotlinx-coroutines-core-jvm-1.11.0.jar:$L/atomicfu-jvm-0.32.1.jar"
for j in "${CP[@]}"; do LIBCP="$LIBCP:$j"; done
files() { for d in "$@"; do find "$d" -name '*.kt' | sort; done; }
MAIN_OUT="${OUT:-$WORK/main}"
mapfile -t MF < <(files "${SRC[@]}")
set +e
"$TC/kotlinc/bin/kotlinc" -jvm-target 17 -Xjdk-release=17 -module-name "$MODULE" -Xsuppress-version-warnings \
  -cp "$LIBCP" -d "$MAIN_OUT" "${MF[@]}" > "$WORK/main.log" 2>&1
RC=$?
set -e
grep -v '^warning: unable to find' "$WORK/main.log" || true
[ $RC -eq 0 ] || { echo "main compilation of $MODULE failed"; exit 1; }
echo "compiled $MODULE: ${#MF[@]} files"
[ ${#TEST[@]} -gt 0 ] || exit 0
TESTCP="$MAIN_OUT:$LIBCP:$L/junit-4.13.2.jar:$L/hamcrest-core-1.3.jar:$K/kotlin-test.jar:$K/kotlin-test-junit.jar:$L/kotlinx-coroutines-test-jvm-1.11.0.jar"
mapfile -t TF < <(files "${TEST[@]}")
set +e
"$TC/kotlinc/bin/kotlinc" -jvm-target 17 -Xjdk-release=17 -module-name "$MODULE" -Xfriend-paths="$MAIN_OUT" \
  -Xsuppress-version-warnings -cp "$TESTCP" -d "$WORK/test" "${TF[@]}" > "$WORK/test.log" 2>&1
RC=$?
set -e
grep -v '^warning: unable to find' "$WORK/test.log" || true
[ $RC -eq 0 ] || { echo "test compilation of $MODULE failed"; exit 1; }
mkdir -p "$WORK/runner"
javac -nowarn -cp "$L/junit-4.13.2.jar" -d "$WORK/runner" "$TC/scripts/junit/RunAll.java"
java -cp "$WORK/runner:$WORK/test:$TESTCP:$K/kotlin-stdlib.jar:$K/kotlin-reflect.jar" RunAll "$WORK/test"
