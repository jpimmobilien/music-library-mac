"""Build compile-only stub jars for the AndroidX libraries used by the project.

For every library the sources are taken from the androidx-main commit at which the library's API
was frozen for the release used by the project (the commit that added api/<version>.txt), so the
public API matches the released version. Kotlin sources are stubbed with KStub (bodies removed,
private/internal declarations removed) and compiled with kotlinc (+ Compose plugin where needed),
Java-only APIs are generated from the signature file (sig2jar). Declarations that cannot be
compiled because a dependency is not available are removed one by one and logged (drops.log).

Usage: python3 -I build_androidx.py <androidx-git-dir> <toolchain-dir> [lib ...]
"""
import json
import os
import re
import shutil
import subprocess
import sys
import zipfile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from classgen import read_class_header  # noqa: E402

COMPOSE = "c136b3fcbd"      # Compose 1.12.0-beta01 (API of 1.12.x)
M3 = "8bf4107d24"           # Material3 1.4.0-beta03
ACTIVITY = "2b1eab2866"     # Activity 1.13.0-rc01
LIFECYCLE = "794ea79a0f"    # Lifecycle 2.11.0-rc01
CORE = "a8df5839f0"         # Core 1.19.0-rc01
DATASTORE = "fa38a261cd"    # DataStore 1.3.0-rc01
ANNOTATION = "3614450a97"   # Annotation 1.10.0-rc01
ANN_EXP = "4924cd1954"      # Annotation-experimental 1.6.0-rc01
COLLECTION = "18f542120b"   # Collection 1.6.0-rc01
SAVEDSTATE = "d6c8a38b61"   # SavedState 1.5.0-rc01
NAVEVENT = "fac679b256"     # NavigationEvent 1.1.0-rc01
DOCFILE = "e3610d66a5"      # DocumentFile 1.1.0-rc01
HEAD = "HEAD"

# (id, path, commit, kind, compose, api file (for java kinds))
LIBS = [
    ("annotation", "annotation/annotation", ANNOTATION, "kmp", False, None),
    ("runtime-annotation", "compose/runtime/runtime-annotation", COMPOSE, "kmp", False, None),
    ("annotation-experimental", "annotation/annotation-experimental", ANN_EXP, "android", False, None),
    ("collection", "collection/collection", COLLECTION, "kmp", False, None),
    ("lifecycle-common", "lifecycle/lifecycle-common", LIFECYCLE, "kmp", False, None),
    ("arch-core-common", "arch/core/core-common", HEAD, "java", False, "api/2.2.0-beta01.txt"),
    ("lifecycle-runtime", "lifecycle/lifecycle-runtime", LIFECYCLE, "kmp", False, None),
    ("versionedparcelable", "versionedparcelable/versionedparcelable", HEAD, "java", False, "api/1.2.0-rc01.txt"),
    ("core-viewtree", "core/core-viewtree", HEAD, "android", False, None),
    ("core", "core/core", CORE, "mixed", False, "api/1.19.0-rc01.txt"),
    ("lifecycle-viewmodel", "lifecycle/lifecycle-viewmodel", LIFECYCLE, "kmp", False, None),
    ("lifecycle-livedata-core", "lifecycle/lifecycle-livedata-core", LIFECYCLE, "android", False, None),
    ("savedstate", "savedstate/savedstate", SAVEDSTATE, "kmp", False, None),
    ("lifecycle-viewmodel-savedstate", "lifecycle/lifecycle-viewmodel-savedstate", LIFECYCLE, "kmp", False, None),
    ("lifecycle-process", "lifecycle/lifecycle-process", LIFECYCLE, "android", False, None),
    ("navigationevent", "navigationevent/navigationevent", NAVEVENT, "kmp", False, None),
    ("runtime", "compose/runtime/runtime", COMPOSE, "kmp", True, None),
    ("runtime-retain", "compose/runtime/runtime-retain", COMPOSE, "kmp", True, None),
    ("lifecycle-runtime-compose", "lifecycle/lifecycle-runtime-compose", LIFECYCLE, "kmp", True, None),
    ("savedstate-compose", "savedstate/savedstate-compose", SAVEDSTATE, "kmp", True, None),
    ("runtime-saveable", "compose/runtime/runtime-saveable", COMPOSE, "kmp", True, None),
    ("ui-util", "compose/ui/ui-util", COMPOSE, "kmp", True, None),
    ("ui-geometry", "compose/ui/ui-geometry", COMPOSE, "kmp", True, None),
    ("ui-unit", "compose/ui/ui-unit", COMPOSE, "kmp", True, None),
    ("ui-graphics", "compose/ui/ui-graphics", COMPOSE, "kmp", True, None),
    ("ui-text", "compose/ui/ui-text", COMPOSE, "kmp", True, None),
    ("ui", "compose/ui/ui", COMPOSE, "kmp", True, None),
    ("navigationevent-compose", "navigationevent/navigationevent-compose", NAVEVENT, "kmp", True, None),
    ("lifecycle-viewmodel-compose", "lifecycle/lifecycle-viewmodel-compose", LIFECYCLE, "kmp", True, None),
    ("ui-tooling-preview", "compose/ui/ui-tooling-preview", COMPOSE, "kmp", True, None),
    ("animation-core", "compose/animation/animation-core", COMPOSE, "kmp", True, None),
    ("animation", "compose/animation/animation", COMPOSE, "kmp", True, None),
    ("foundation-layout", "compose/foundation/foundation-layout", COMPOSE, "kmp", True, None),
    ("graphics-shapes", "graphics/graphics-shapes", HEAD, "kmp", False, None),
    ("foundation", "compose/foundation/foundation", COMPOSE, "kmp", True, None),
    ("material-ripple", "compose/material/material-ripple", COMPOSE, "kmp", True, None),
    ("activity", "activity/activity", ACTIVITY, "android", False, None),
    ("activity-compose", "activity/activity-compose", ACTIVITY, "android", True, None),
    ("material3", "compose/material3/material3", M3, "kmp", True, None),
    ("datastore-core", "datastore/datastore-core", DATASTORE, "kmp", False, None),
    ("datastore-preferences-core", "datastore/datastore-preferences-core", DATASTORE, "kmp", False, None),
    ("datastore", "datastore/datastore", DATASTORE, "kmp", False, None),
    ("datastore-preferences", "datastore/datastore-preferences", DATASTORE, "kmp", False, None),
    ("documentfile", "documentfile/documentfile", DOCFILE, "java", False, "api/1.1.0-rc01.txt"),
]


def run(cmd, **kw):
    return subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, **kw)


class Ctx:
    def __init__(self, git, tc):
        self.git = git
        self.tc = tc
        self.work = os.path.join(tc, "build", "ax")
        self.out = os.path.join(tc, "stubs", "androidx")
        os.makedirs(self.work, exist_ok=True)
        os.makedirs(self.out, exist_ok=True)
        self.kotlinc = os.path.join(tc, "kotlinc", "bin", "kotlinc")
        self.lib = os.path.join(tc, "kotlinc", "lib")
        self.base_cp = [os.path.join(tc, "stubs", "java17-api.jar"), os.path.join(tc, "stubs", "android-stubs.jar"),
                        os.path.join(tc, "lib", "kotlinx-coroutines-core-jvm-1.11.0.jar"),
                        os.path.join(tc, "lib", "kotlinx-coroutines-android-1.11.0.jar"),
                        os.path.join(tc, "lib", "atomicfu-jvm-0.32.1.jar")]
        self.optins = set()
        state = os.path.join(self.out, "optins.txt")
        if os.path.exists(state):
            self.optins = set(x.strip() for x in open(state) if x.strip())
        self.env = dict(os.environ)
        self.env.pop("JAVA_TOOL_OPTIONS", None)
        self.env["JAVA_OPTS"] = "-Xmx5g -Xss8m"

    def built_jars(self, upto):
        jars = []
        for lib in LIBS:
            if lib[0] == upto:
                break
            for suffix in ("", "-java"):
                j = os.path.join(self.out, lib[0] + suffix + ".jar")
                if os.path.exists(j):
                    jars.append(j)
        return jars

    # ------------------------------------------------------------ sources
    def tree(self, commit):
        d = os.path.join(self.git, "..", "ax-src", commit)
        return os.path.abspath(d)

    def checkout(self, commit, paths):
        d = self.tree(commit)
        if not os.path.exists(d):
            r = run(["git", "-C", self.git, "worktree", "add", "--no-checkout", "--detach", d, commit])
            if r.returncode:
                raise SystemExit(r.stdout)
            run(["git", "-C", d, "sparse-checkout", "init", "--no-cone"])
        pats_file = os.path.join(d, ".git-sparse-wanted")
        want = set()
        if os.path.exists(pats_file):
            want = set(open(pats_file).read().split())
        new = set()
        for p in paths:
            for sub in ("src/commonMain/", "src/jvmAndAndroidMain/", "src/jvmMain/", "src/androidMain/", "src/main/",
                        "api/", "build.gradle"):
                new.add("/" + p + "/" + sub)
        if not new <= want:
            want |= new
            open(pats_file, "w").write("\n".join(sorted(want)))
            r = run(["git", "-C", d, "sparse-checkout", "set", "--no-cone"] + sorted(want))
            if r.returncode:
                raise SystemExit(r.stdout)
            r = run(["git", "-C", d, "checkout", "--detach", commit])
            if r.returncode:
                raise SystemExit(r.stdout)
        return d


def chain_for(src_dir, build_gradle, kind):
    """Source sets on the path from the Android (or JVM) platform to commonMain, root first."""
    if kind in ("android", "mixed"):
        return [("main", "main")]
    gradle = open(build_gradle).read() if os.path.exists(build_gradle) else ""
    has = lambda n: os.path.isdir(os.path.join(src_dir, n))  # noqa: E731
    android_target = bool(re.search(r"androidLibrary\s*\{|android\(\)|androidTarget", gradle))
    chain = [("common", "commonMain")]
    if has("jvmAndAndroidMain"):
        chain.append(("jvmAndAndroid", "jvmAndAndroidMain"))
    if android_target:
        if has("jvmMain") and re.search(r"androidMain\s*\{[^}]*dependsOn\(jvmMain\)|androidMain\.dependsOn\(jvmMain\)", gradle, re.S):
            chain.append(("jvm", "jvmMain"))
        if has("androidMain"):
            chain.append(("android", "androidMain"))
    else:
        if has("jvmMain"):
            chain.append(("jvm", "jvmMain"))
    return chain


def kotlin_files(root):
    out = []
    for dp, dn, fn in os.walk(root):
        for f in fn:
            if f.endswith(".kt"):
                out.append(os.path.join(dp, f))
    return sorted(out)


def jar_index(jar):
    idx = {}
    with zipfile.ZipFile(jar) as z:
        for n in z.namelist():
            if n.endswith(".class") and not n.startswith("META-INF"):
                try:
                    acc, this, sup, ifs = read_class_header(z.read(n))
                except Exception:
                    continue
                idx[this] = [acc, sup, ifs]
    return idx


ERR_RE = re.compile(r"^([^:\s][^:]*\.kt):(\d+):(\d+): error: (.*)$")


def build_kotlin(ctx, lib_id, src_root, chain, compose, cp, extra_files_frag=None):
    work = os.path.join(ctx.work, lib_id)
    sdir = os.path.join(work, "s")
    shutil.rmtree(work, ignore_errors=True)
    os.makedirs(sdir)
    listing = []
    for frag, sub in chain:
        base = os.path.join(src_root, sub)
        for root_kind in ("kotlin", "java"):
            rr = os.path.join(base, root_kind)
            if not os.path.isdir(rr):
                continue
            for f in kotlin_files(rr):
                listing.append("%s\t%s\t%s" % (frag, os.path.relpath(f, rr), f))
    if not listing:
        return None, 0
    lf = os.path.join(work, "list.txt")
    open(lf, "w").write("\n".join(listing) + "\n")
    kcp = ":".join(os.path.join(ctx.lib, j) for j in ("kotlin-compiler.jar", "kotlin-stdlib.jar", "kotlin-reflect.jar",
                                                     "kotlinx-coroutines-core-jvm.jar", "annotations-13.0.jar",
                                                     "kotlin-script-runtime.jar"))
    kcp += ":" + os.path.join(ctx.tc, "build", "kstub.jar")
    r = run(["java", "-Xmx3g", "-cp", kcp, "KStubKt", "stub", lf, sdir], env=ctx.env)
    if r.returncode:
        raise SystemExit("KStub failed for %s:\n%s" % (lib_id, r.stdout[-4000:]))
    for line in r.stdout.splitlines():
        if line.startswith("OPTIN "):
            ctx.optins.add(line[6:].strip())
    open(os.path.join(ctx.out, "optins.txt"), "w").write("\n".join(sorted(ctx.optins)) + "\n")
    frags = [f for f, _ in chain]
    jar = os.path.join(ctx.out, lib_id + ".jar")
    droplog = os.path.join(work, "drops.log")
    open(droplog, "w").close()
    for it in range(40):
        files = []
        fragsrc = []
        for frag in frags:
            fd = os.path.join(sdir, frag)
            for f in kotlin_files(fd):
                files.append(f)
                fragsrc.append("%s:%s" % (frag, f))
        args = ["-no-jdk", "-nowarn", "-Xsuppress-version-warnings", "-jvm-target", "17",
                "-module-name", "stub-" + lib_id, "-Xexplicit-api=disable", "-Xdont-warn-on-error-suppression",
                "-Xexpect-actual-classes", "-Xskip-prerelease-check", "-Xallow-kotlin-package",
                "-cp", ":".join(ctx.base_cp + cp)]
        for o in sorted(ctx.optins | {"kotlin.RequiresOptIn", "kotlin.ExperimentalStdlibApi",
                                      "kotlin.contracts.ExperimentalContracts", "kotlin.ExperimentalMultiplatform",
                                      "kotlinx.coroutines.ExperimentalCoroutinesApi",
                                      "kotlinx.coroutines.InternalCoroutinesApi", "kotlinx.coroutines.FlowPreview",
                                      "kotlinx.coroutines.DelicateCoroutinesApi", "kotlin.experimental.ExperimentalTypeInference",
                                      "kotlin.ExperimentalSubclassOptIn", "kotlin.uuid.ExperimentalUuidApi",
                                      "kotlin.time.ExperimentalTime", "kotlin.concurrent.atomics.ExperimentalAtomicApi"}):
            args.append("-opt-in=" + o)
        if len(frags) > 1:
            args += ["-Xmulti-platform", "-Xfragments=" + ",".join(frags)]
            for a, b in zip(frags[1:], frags[:-1]):
                args.append("-Xfragment-refines=%s:%s" % (a, b))
            args.append("-Xfragment-sources=" + ",".join(fragsrc))
        if compose:
            args.append("-Xplugin=" + os.path.join(ctx.lib, "compose-compiler-plugin.jar"))
        args += ["-d", jar] + files
        af = os.path.join(work, "args.txt")
        with open(af, "w") as fh:
            for a in args:
                fh.write('"' + a.replace("\\", "\\\\").replace('"', '\\"') + '"\n')
        r = run([ctx.kotlinc, "@" + af], env=ctx.env, cwd=work)
        errs = {}
        other = []
        for line in r.stdout.splitlines():
            m = ERR_RE.match(line)
            if m:
                errs.setdefault(os.path.normpath(os.path.join(work, m.group(1))), set()).add("%s:%s" % (m.group(2), m.group(3)))
            elif "error:" in line:
                other.append(line)
        if r.returncode == 0:
            break
        if not errs:
            m = re.search(r"File being compiled: (\S+\.kt)", r.stdout)
            if m:
                bad = os.path.normpath(os.path.join(work, m.group(1)))
                crashes = getattr(ctx, "crashes", {})
                ctx.crashes = crashes
                crashes[bad] = crashes.get(bad, 0) + 1
                if crashes[bad] > 3:
                    raise SystemExit("backend keeps crashing on %s" % bad)
                rr = run(["java", "-Xmx2g", "-cp", kcp, "KStubKt", "dropuntyped", bad, droplog], env=ctx.env)
                print("  [%s] iteration %d: backend crash in %s (%s)" % (lib_id, it, os.path.basename(bad), rr.stdout.strip()), flush=True)
                if rr.returncode == 0 and not rr.stdout.strip().endswith(" 0"):
                    continue
                raise SystemExit("backend crash in %s, nothing left to remove:\n%s" % (bad, r.stdout[:3000]))
            raise SystemExit("compile failed for %s without locatable errors:\n%s" % (lib_id, r.stdout[:3000]))
        with open(os.path.join(work, "errors-%02d.txt" % it), "w") as fh:
            fh.write(r.stdout)
        spec = os.path.join(work, "drop-spec.txt")
        with open(spec, "w") as fh:
            for f, lines in errs.items():
                fh.write("%s\t%s\n" % (f, ",".join(sorted(lines))))
        rr = run(["java", "-Xmx2g", "-cp", kcp, "KStubKt", "dropbatch", spec, droplog], env=ctx.env)
        if rr.returncode:
            raise SystemExit(rr.stdout)
        # guard against no progress: files whose errors could not be attributed get removed
        n_err = sum(len(v) for v in errs.values())
        print("  [%s] iteration %d: %d error lines in %d files" % (lib_id, it, n_err, len(errs)), flush=True)
    else:
        raise SystemExit("too many iterations for " + lib_id)
    drops = sum(1 for _ in open(droplog))
    return jar, drops


def build_java(ctx, lib_id, api_file, cp_jars, only=None):
    tc = ctx.tc
    idx_files = [os.path.join(tc, "stubs", "java17-index.json"), os.path.join(tc, "stubs", "android-index.json")]
    work = os.path.join(ctx.work, lib_id)
    os.makedirs(work, exist_ok=True)
    for j in cp_jars:
        ix = os.path.join(work, os.path.basename(j) + ".idx.json")
        json.dump(jar_index(j), open(ix, "w"))
        idx_files.append(ix)
    out = os.path.join(ctx.out, lib_id + ("-java" if only else "") + ".jar")
    cmd = [sys.executable, "-I", os.path.join(HERE, "sig2jar.py"), "--out", out,
           "--index", os.path.join(work, "index.json"), "--nullness", "androidx",
           "--placeholders", os.path.join(work, "placeholders.txt")]
    for ix in idx_files:
        cmd += ["--cp-index", ix]
    if only:
        of = os.path.join(work, "only.txt")
        open(of, "w").write("\n".join(sorted(only)) + "\n")
        cmd += ["--only-classes", of]
    cmd.append(api_file)
    r = run(cmd)
    if r.returncode:
        raise SystemExit(r.stdout)
    print("  " + r.stdout.strip())
    return out


def java_classes_of(api_file, roots):
    """Classes in the signature file whose top-level class is declared in a .java source."""
    sys.path.insert(0, HERE)
    from sigparse import parse_file
    fmt, classes = parse_file(api_file)
    only = set()
    for c in classes:
        top = c.name.split(".")[0]
        for r in roots:
            p = os.path.join(r, c.package.replace(".", "/"), top + ".java")
            if os.path.exists(p):
                only.add(c.fqname)
                break
    return only


def java_roots(src, chain):
    roots = []
    for _, sub in chain:
        for k in ("java", "kotlin"):
            d = os.path.join(src, sub, k)
            if os.path.isdir(d):
                for dp, dn, fn in os.walk(d):
                    if any(f.endswith(".java") for f in fn):
                        roots.append(d)
                        break
    return roots


def frozen_api(ctx, tree, path, commit):
    """The api/<version>.txt file that was added by the freeze commit (current.txt for HEAD)."""
    if commit == HEAD:
        rc = os.path.join(tree, path, "api", "restricted_current.txt")
        return rc if os.path.exists(rc) else os.path.join(tree, path, "api", "current.txt")
    r = run(["git", "-C", ctx.git, "diff-tree", "--no-commit-id", "--name-only", "--diff-filter=A", "-r", commit,
             "--", path + "/api/"])
    for line in r.stdout.split():
        b = os.path.basename(line)
        if re.match(r"^\d+\.\d+\.\d+(-[a-z]+\d+)?\.txt$", b):
            restricted = os.path.join(tree, os.path.dirname(line), "restricted_" + b)
            return restricted if os.path.exists(restricted) else os.path.join(tree, line)
    return os.path.join(tree, path, "api", "current.txt")


def main():
    git, tc = sys.argv[1], sys.argv[2]
    wanted = sys.argv[3:]
    ctx = Ctx(git, tc)
    summary = json.load(open(os.path.join(ctx.out, "summary.json"))) if os.path.exists(os.path.join(ctx.out, "summary.json")) else {}
    for lib_id, path, commit, kind, compose, api in LIBS:
        if wanted and lib_id not in wanted:
            continue
        print("== %s (%s @ %s)" % (lib_id, path, commit), flush=True)
        tree = ctx.checkout(commit, [path])
        src = os.path.join(tree, path, "src")
        cp = ctx.built_jars(lib_id)
        if kind == "java":
            apif = os.path.join(tree, path, api)
            rapi = os.path.join(os.path.dirname(apif), "restricted_" + os.path.basename(apif))
            build_java(ctx, lib_id, rapi if os.path.exists(rapi) else apif, cp)
            summary[lib_id] = {"commit": commit, "kind": kind, "api": api}
            continue
        chain = chain_for(src, os.path.join(tree, path, "build.gradle"), kind)
        roots = java_roots(src, chain)
        if roots:
            apif = frozen_api(ctx, tree, path, commit)
            only = java_classes_of(apif, roots)
            print("  java classes from %s: %d" % (os.path.basename(apif), len(only)))
            if only:
                jj = build_java(ctx, lib_id, apif, cp, only=only)
                cp = cp + [jj]
        jar, drops = build_kotlin(ctx, lib_id, src, chain, compose, cp)
        summary[lib_id] = {"commit": commit, "kind": kind, "chain": [c for _, c in chain], "drops": drops}
        print("  -> %s (%d declarations dropped)" % (jar, drops), flush=True)
        json.dump(summary, open(os.path.join(ctx.out, "summary.json"), "w"), indent=1)


if __name__ == "__main__":
    main()
