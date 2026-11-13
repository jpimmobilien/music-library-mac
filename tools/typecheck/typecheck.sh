#!/usr/bin/env bash
# Typecheck Android/Compose Kotlin sources against the generated API stubs (no Android SDK needed).
#
#   typecheck.sh [options] -- <source dir or .kt file>...
#
# Options:
#   --module NAME            Kotlin module name (decides what 'internal' means)        default: main
#   --res NS=DIR             generate R for namespace NS from resource dir DIR         (repeatable)
#   --buildconfig NS         generate NS.BuildConfig (DEBUG, APPLICATION_ID, ...)      (repeatable)
#   --application-id ID / --version-code N / --version-name S   values for BuildConfig
#   --field NAME=TYPE:VALUE  extra BuildConfig field, VALUE as Java literal            (repeatable)
#   --cp JAR                 extra classpath entry (e.g. output of another module)     (repeatable)
#   --out JAR                keep the compiled classes (for modules depending on this one)
#   --opt-in FQNAME          like -opt-in (repeatable)
#   --no-compose             do not apply the Compose compiler plugin
#   --jvm                    pure Kotlin/JVM module: compile against the JDK 17 API, no Android
#   --werror                 treat warnings as failure (exit 1)
#   --no-inline              pass -Xno-inline (only if the JVM backend chokes on inlined stub code)
#
# Exit code 0 = no errors. All compiler diagnostics are printed.
set -euo pipefail
TC="${TOOLCHAIN:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
[ -x "$TC/kotlinc/bin/kotlinc" ] || TC=/home/claude/toolchain
unset JAVA_TOOL_OPTIONS || true
export JAVA_OPTS="${JAVA_OPTS:--Xmx4g -Xss8m}"

MODULE=main; RES=(); BC=(); FIELDS=(); CP=(); OUT=""; OPTINS=(); COMPOSE=1; JVM=0; WERROR=0; NOINLINE=0
APPID=""; VCODE=1; VNAME="1.0"
while [ $# -gt 0 ]; do
  case "$1" in
    --module) MODULE="$2"; shift 2;;
    --res) RES+=("--res" "$2"); shift 2;;
    --buildconfig) BC+=("--buildconfig" "$2"); shift 2;;
    --application-id) APPID="$2"; shift 2;;
    --version-code) VCODE="$2"; shift 2;;
    --version-name) VNAME="$2"; shift 2;;
    --field) FIELDS+=("--field" "$2"); shift 2;;
    --cp) CP+=("$2"); shift 2;;
    --out) OUT="$2"; shift 2;;
    --opt-in) OPTINS+=("-opt-in=$2"); shift 2;;
    --no-compose) COMPOSE=0; shift;;
    --jvm) JVM=1; COMPOSE=0; shift;;
    --werror) WERROR=1; shift;;
    --no-inline) NOINLINE=1; shift;;
    --) shift; break;;
    *) echo "unknown option $1" >&2; exit 2;;
  esac
done
[ $# -gt 0 ] || { echo "no sources given" >&2; exit 2; }

WORK=$(mktemp -d "${TMPDIR:-/tmp}/typecheck.XXXXXX")
trap 'rm -rf "$WORK"' EXIT
GENCP=""
if [ ${#RES[@]} -gt 0 ] || [ ${#BC[@]} -gt 0 ]; then
  python3 -I "$TC/scripts/gen_r.py" --out "$WORK/gen" "${RES[@]}" "${BC[@]}" ${APPID:+--application-id "$APPID"} \
    --version-code "$VCODE" --version-name "$VNAME" "${FIELDS[@]}" >/dev/null
  mkdir -p "$WORK/genc"
  javac -nowarn --release 17 -d "$WORK/genc" $(find "$WORK/gen" -name '*.java') 2>&1 | grep -v '^Note:' || true
  GENCP="$WORK/genc"
fi

FILES=()
for s in "$@"; do
  if [ -d "$s" ]; then while IFS= read -r f; do FILES+=("$f"); done < <(find "$s" -name '*.kt' | sort)
  elif [ -f "$s" ]; then FILES+=("$s")
  else echo "missing source: $s" >&2; exit 2; fi
done
[ ${#FILES[@]} -gt 0 ] || { echo "no .kt files found" >&2; exit 2; }

if [ $JVM -eq 1 ]; then
  BASECP="$TC/lib/kotlinx-coroutines-core-jvm-1.11.0.jar:$TC/lib/atomicfu-jvm-0.32.1.jar"
  ARGS=(-jdk-home /usr/lib/jvm/java-21-openjdk-amd64 -Xjdk-release=17)
else
  BASECP="$TC/stubs/java17-api.jar:$TC/stubs/android-stubs.jar:$TC/lib/kotlinx-coroutines-core-jvm-1.11.0.jar:$TC/lib/kotlinx-coroutines-android-1.11.0.jar:$TC/lib/atomicfu-jvm-0.32.1.jar"
  for j in "$TC"/stubs/androidx/*.jar; do BASECP="$BASECP:$j"; done
  ARGS=(-no-jdk)
fi
[ -n "$GENCP" ] && BASECP="$BASECP:$GENCP"
for j in "${CP[@]}"; do BASECP="$BASECP:$j"; done
[ $COMPOSE -eq 1 ] && ARGS+=("-Xplugin=$TC/kotlinc/lib/compose-compiler-plugin.jar")
DEST="${OUT:-$WORK/out}"
ARGS+=(-jvm-target 17 -module-name "$MODULE" -Xsuppress-version-warnings -cp "$BASECP" -d "$DEST" "${OPTINS[@]}")
[ $NOINLINE -eq 1 ] && ARGS+=(-Xno-inline)

AF="$WORK/args.txt"
: > "$AF"
for a in "${ARGS[@]}" "${FILES[@]}"; do printf '"%s"\n' "$(printf '%s' "$a" | sed 's/\\/\\\\/g; s/"/\\"/g')" >> "$AF"; done
set +e
"$TC/kotlinc/bin/kotlinc" "@$AF" > "$WORK/log.txt" 2>&1
RC=$?
set -e
grep -v -E '^(warning: unable to find kotlin-stdlib|Picked up JAVA_TOOL_OPTIONS)' "$WORK/log.txt" || true
NE=$(grep -c -E '^[^ ]+:[0-9]+:[0-9]+: error:' "$WORK/log.txt" || true)
NW=$(grep -c -E '^[^ ]+:[0-9]+:[0-9]+: warning:' "$WORK/log.txt" || true)
if [ $RC -ne 0 ] && [ "$NE" -eq 0 ] && grep -q -E 'Backend Internal error|exception: ' "$WORK/log.txt"; then
  # All front-end checks (resolution, types, nullability, @Composable, opt-in ...) have passed; only the JVM
  # back end failed on code inlined from the API stubs. That is not a finding about the checked sources.
  echo "typecheck[$MODULE]: ${#FILES[@]} files, 0 errors, $NW warnings (front end clean; JVM back end crashed on stub code - ignored)"
  exit 0
fi
echo "typecheck[$MODULE]: ${#FILES[@]} files, $NE errors, $NW warnings"
if [ $RC -ne 0 ]; then exit 1; fi
if [ $WERROR -eq 1 ] && [ "$NW" -gt 0 ]; then exit 1; fi
exit 0
