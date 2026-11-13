"""API coverage of every built AndroidX stub jar against the official (frozen) API file."""
import os, re, subprocess, sys
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import build_androidx as B
git, tc = sys.argv[1], sys.argv[2]
ctx = B.Ctx(git, tc)
for lib_id, path, commit, kind, compose, api in B.LIBS:
    tree = ctx.tree(commit)
    apif = os.path.join(tree, path, api) if api else B.frozen_api(ctx, tree, path, commit)
    pub = os.path.join(os.path.dirname(apif), os.path.basename(apif).replace("restricted_", ""))
    jars = [os.path.join(ctx.out, lib_id + s + ".jar") for s in ("", "-java") if os.path.exists(os.path.join(ctx.out, lib_id + s + ".jar"))]
    r = subprocess.run([sys.executable, "-I", os.path.join(HERE, "api_coverage.py"), pub] + jars, stdout=subprocess.PIPE, text=True)
    lines = r.stdout.splitlines()
    real = []
    for l in lines[1:]:
        m = re.match(r"\s+missing member (.+)#(.+)$", l)
        if m:
            cls, mem = m.group(1), m.group(2)
            if cls.rsplit(".", 1)[-1] == mem or "$" in mem or mem in ("addFirst", "addLast", "removeFirst", "removeLast", "getFirst", "getLast", "reversed"):
                continue  # ctor naming / JDK 21 SequencedCollection / bytecode-only bridges
        if "serializ" in l.lower():
            continue
        real.append(l.strip())
    print("%-32s %-22s %s; relevant gaps: %d" % (lib_id, os.path.basename(pub), lines[0].split(": ", 1)[1] if lines else "?", len(real)))
    for l in real[:12]:
        print("      " + l)
