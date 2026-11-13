#!/usr/bin/env bash
# Rebuilds the whole offline toolchain from official sources (needs: JDK 21 with ct.sym, python3, git,
# curl; network access to github.com only). Takes roughly 1–1.5 hours, mostly for the AndroidX stubs.
#
#   scripts/setup.sh <toolchain-dir> <vendor-dir>
set -euo pipefail
TC=$(mkdir -p "$1" && cd "$1" && pwd)
V=$(mkdir -p "$2" && cd "$2" && pwd)
S=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
unset JAVA_TOOL_OPTIONS || true
mkdir -p "$TC/lib" "$TC/stubs" "$TC/build" "$TC/dl"
[ "$S" = "$TC/scripts" ] || { rm -rf "$TC/scripts"; cp -r "$S" "$TC/scripts"; }
cp "$S/../typecheck.sh" "$S/../jvmtest.sh" "$TC/" 2>/dev/null || true
K="$TC/kotlinc/bin/kotlinc"

# 1. Kotlin compiler (includes the Compose compiler plugin)
if [ ! -x "$K" ]; then
  curl -sSL -o "$TC/dl/kotlin-compiler-2.4.21.zip" https://github.com/JetBrains/kotlin/releases/download/v2.4.21/kotlin-compiler-2.4.21.zip
  (cd "$TC" && unzip -q -o dl/kotlin-compiler-2.4.21.zip)
fi
clone() { [ -d "$V/$2" ] || git clone -q --depth 1 --branch "$3" "$1" "$V/$2"; }

# 2. JUnit 4.13.2 + hamcrest-core 1.3
clone https://github.com/hamcrest/JavaHamcrest hamcrest hamcrest-java-1.3
clone https://github.com/junit-team/junit4 junit4 r4.13.2
B="$TC/build/hamcrest"; rm -rf "$B"; mkdir -p "$B/core" "$B/gen" "$B/gensrc"
cp -r "$V/hamcrest/hamcrest-core/src/main/java" "$B/src"
sed -i 's/return allOf(Arrays.asList(matchers));/return allOf(Arrays.<Matcher<? super T>>asList(matchers));/; s/return anyOf(Arrays.asList(matchers));/return anyOf(Arrays.<Matcher<? super T>>asList(matchers));/' "$B/src/org/hamcrest/core/AllOf.java" "$B/src/org/hamcrest/core/AnyOf.java"
javac -nowarn --release 8 -d "$B/core" $(find "$B/src" -name '*.java')
javac -nowarn --release 8 -cp "$B/core" -d "$B/gen" $(find "$V/hamcrest/hamcrest-generator/src/main/java" -name '*.java' | grep -v -E 'QDox|XmlConfigurator') "$S/junit/GenCoreMatchers.java"
java -cp "$B/core:$B/gen" GenCoreMatchers "$B/gensrc"
javac -nowarn --release 8 -cp "$B/core" -d "$B/core" "$B/gensrc/org/hamcrest/CoreMatchers.java"
cp "$V/hamcrest/LICENSE.txt" "$B/core/LICENSE-hamcrest.txt"; rm -f "$TC/lib/hamcrest-core-1.3.jar"
(cd "$B/core" && jar cf "$TC/lib/hamcrest-core-1.3.jar" .)
B="$TC/build/junit"; rm -rf "$B"; mkdir -p "$B/classes"
javac -nowarn --release 8 -cp "$TC/lib/hamcrest-core-1.3.jar" -d "$B/classes" $(find "$V/junit4/src/main/java" -name '*.java')
cp "$V/junit4/LICENSE-junit.txt" "$B/classes/"; rm -f "$TC/lib/junit-4.13.2.jar"
(cd "$B/classes" && jar cf "$TC/lib/junit-4.13.2.jar" .)

# 3. Java 17 API from ct.sym
python3 -I "$S/jdkapi.py" "$(dirname "$(dirname "$(readlink -f "$(which javac)")")")/lib/ct.sym" "$TC/stubs/java17-api.jar" "$TC/stubs/java17-index.json"

# 4. Android framework API 36.1 (+ Location, MediaProvider, PDF)
sparse() { # url dir branch path...
  local url=$1 dir=$2 br=$3; shift 3
  if [ ! -d "$V/$dir" ]; then git clone -q --filter=blob:none --sparse --depth 1 --branch "$br" "$url" "$V/$dir"; fi
  git -C "$V/$dir" sparse-checkout set --no-cone "$@"
}
sparse https://github.com/aosp-mirror/platform_frameworks_base fwb android16-qpr1-release /core/api/ /location/api/
sparse https://github.com/aosp-mirror/platform_packages_providers_mediaprovider mediaprovider android16-qpr1-release /apex/framework/api/ /pdf/framework/api/ /pdf/framework-v/api/
python3 -I "$S/sig2jar.py" --out "$TC/stubs/android-stubs.jar" --index "$TC/stubs/android-index.json" \
  --cp-index "$TC/stubs/java17-index.json" --nullness android --placeholders "$TC/stubs/android-placeholders.txt" \
  "$V/fwb/core/api/current.txt" "$V/fwb/location/api/current.txt" "$V/mediaprovider/apex/framework/api/current.txt" \
  "$V/mediaprovider/pdf/framework/api/current.txt" "$V/mediaprovider/pdf/framework-v/api/current.txt"

# 5. kotlinx-coroutines 1.11.0 (+ atomicfu 0.32.1)
clone https://github.com/Kotlin/kotlinx-atomicfu atomicfu 0.32.1
clone https://github.com/Kotlin/kotlinx.coroutines coroutines 1.11.0
mpp() { # out module optins -- fragments...  (fragment spec: name=dir,dir)
  local out=$1 mod=$2 cp=$3; shift 3
  local frags=() refines=() srcs="" files=()
  local prev=""
  for spec in "$@"; do
    local name=${spec%%=*} dirs=${spec#*=}
    frags+=("$name"); [ -n "$prev" ] && refines+=("-Xfragment-refines=$name:$prev"); prev=$name
    for d in ${dirs//,/ }; do while IFS= read -r f; do files+=("$f"); srcs="$srcs,$name:$f"; done < <(find "$d" -name '*.kt' | sort); done
  done
  local fr; fr=$(IFS=,; echo "${frags[*]}")
  "$K" -Xmulti-platform -Xexpect-actual-classes -Xdont-warn-on-error-suppression "-Xfragments=$fr" "${refines[@]}" \
    "-Xfragment-sources=${srcs#,}" -jvm-target 1.8 -nowarn -Xsuppress-version-warnings -module-name "$mod" \
    $MPP_OPTS -cp "$cp" -d "$out" "${files[@]}"
}
A="$V/atomicfu/atomicfu/src"
MPP_OPTS="-opt-in=kotlinx.atomicfu.locks.ExperimentalThreadBlockingApi" \
  mpp "$TC/lib/atomicfu-jvm-0.32.1.jar" atomicfu "" common="$A/commonMain/kotlin" concurrent="$A/concurrentMain" jvm="$A/jvmMain"
CS="$TC/build/coroutines"; rm -rf "$CS"; mkdir -p "$CS/cstub/classes" "$CS/vft"
mkdir -p "$CS/cstub/src/android/annotation" "$CS/cstub/src/org/codehaus/mojo/animal_sniffer" "$CS/vft/androidx/annotation"
echo 'package android.annotation; import java.lang.annotation.*; @Retention(RetentionPolicy.CLASS) public @interface SuppressLint { String[] value(); }' > "$CS/cstub/src/android/annotation/SuppressLint.java"
echo 'package org.codehaus.mojo.animal_sniffer; import java.lang.annotation.*; @Retention(RetentionPolicy.CLASS) public @interface IgnoreJRERequirement {}' > "$CS/cstub/src/org/codehaus/mojo/animal_sniffer/IgnoreJRERequirement.java"
echo 'package androidx.annotation; @java.lang.annotation.Retention(java.lang.annotation.RetentionPolicy.CLASS) public @interface VisibleForTesting { int otherwise() default 2; }' > "$CS/vft/androidx/annotation/VisibleForTesting.java"
javac -nowarn -d "$CS/cstub/classes" $(find "$CS/cstub/src" -name '*.java')
javac -nowarn -d "$CS/vft" "$CS/vft/androidx/annotation/VisibleForTesting.java"
CO="-opt-in=kotlin.ExperimentalMultiplatform -opt-in=kotlin.experimental.ExperimentalTypeInference -opt-in=kotlinx.coroutines.DelicateCoroutinesApi -opt-in=kotlinx.coroutines.ExperimentalCoroutinesApi -opt-in=kotlinx.coroutines.ObsoleteCoroutinesApi -opt-in=kotlinx.coroutines.InternalCoroutinesApi -opt-in=kotlinx.coroutines.FlowPreview"
R="$V/coroutines/kotlinx-coroutines-core"
MPP_OPTS="$CO -Xno-param-assertions -Xno-call-assertions -Xno-receiver-assertions" \
  mpp "$CS/classes" kotlinx-coroutines-core "$TC/lib/atomicfu-jvm-0.32.1.jar:$CS/cstub/classes" common="$R/common/src" concurrent="$R/concurrent/src" jvm="$R/jvm/src"
cp -r "$R/jvm/resources/META-INF" "$CS/classes/"; rm -f "$TC/lib/kotlinx-coroutines-core-jvm-1.11.0.jar"
(cd "$CS/classes" && jar cf "$TC/lib/kotlinx-coroutines-core-jvm-1.11.0.jar" .)
R="$V/coroutines/kotlinx-coroutines-test"
MPP_OPTS="$CO -Xfriend-paths=$TC/lib/kotlinx-coroutines-core-jvm-1.11.0.jar" \
  mpp "$CS/tclasses" kotlinx-coroutines-test "$TC/lib/atomicfu-jvm-0.32.1.jar:$TC/lib/kotlinx-coroutines-core-jvm-1.11.0.jar:$CS/cstub/classes" common="$R/common/src" jvm="$R/jvm/src"
cp -r "$R/jvm/resources/"* "$CS/tclasses/" 2>/dev/null || true; rm -f "$TC/lib/kotlinx-coroutines-test-jvm-1.11.0.jar"
(cd "$CS/tclasses" && jar cf "$TC/lib/kotlinx-coroutines-test-jvm-1.11.0.jar" .)
R="$V/coroutines/ui/kotlinx-coroutines-android"
"$K" -no-jdk -jvm-target 1.8 -nowarn -module-name kotlinx-coroutines-android -opt-in=kotlinx.coroutines.InternalCoroutinesApi \
  -opt-in=kotlinx.coroutines.ExperimentalCoroutinesApi -cp "$TC/stubs/java17-api.jar:$TC/stubs/android-stubs.jar:$TC/lib/kotlinx-coroutines-core-jvm-1.11.0.jar:$TC/lib/atomicfu-jvm-0.32.1.jar:$CS/vft" \
  -d "$CS/aclasses" $(find "$R/src" -name '*.kt')
cp -r "$R/resources/"* "$CS/aclasses/" 2>/dev/null || true; rm -f "$TC/lib/kotlinx-coroutines-android-1.11.0.jar"
(cd "$CS/aclasses" && jar cf "$TC/lib/kotlinx-coroutines-android-1.11.0.jar" .)

# 6. KStub and the AndroidX stubs
"$K" -nowarn -cp "$TC/kotlinc/lib/kotlin-compiler.jar" "$S/kstub/KStub.kt" -d "$TC/build/kstub.jar" \
  -opt-in=org.jetbrains.kotlin.config.CompilerConfiguration.Internals -opt-in=org.jetbrains.kotlin.CoreEnvironmentDeprecation \
  -opt-in=org.jetbrains.kotlin.K1Deprecation -opt-in=org.jetbrains.kotlin.compiler.plugin.ExperimentalCompilerApi
if [ ! -d "$V/androidx" ]; then
  git clone -q --filter=blob:none --sparse --depth 1 https://github.com/androidx/androidx "$V/androidx"
fi
git -C "$V/androidx" fetch -q --filter=blob:none --shallow-since=2025-01-01 origin androidx-main
python3 -I "$S/build_androidx.py" "$V/androidx" "$TC"
echo "toolchain ready in $TC"
