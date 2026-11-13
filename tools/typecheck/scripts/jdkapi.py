"""Extract the Java SE 17 API (selected modules) from the JDK's ct.sym into a plain jar.

Android's java.* surface is close to a subset of Java 17; using these signature classes with
`kotlinc -no-jdk` keeps desktop-only modules (AWT, Swing, java.net.http ...) out of reach.
Usage: python3 -I jdkapi.py <ct.sym> <out.jar> <out-index.json>
"""
import json
import sys
import zipfile

sys.path.insert(0, __import__("os").path.dirname(__file__))
from classgen import read_class_header  # noqa: E402

MODULES = ["java.base", "java.logging", "java.prefs", "java.sql", "java.xml"]
RELEASE = "H"  # 17 (8=8, 9=9, A=10, B=11, ... H=17)
# Packages of java.base that are not part of Android's public API.
EXCLUDE_PREFIXES = ("java/lang/foreign/", "jdk/", "sun/", "com/sun/", "java/lang/runtime/",
                    "javax/security/cert/")


def main(ctsym, out_jar, out_index):
    zin = zipfile.ZipFile(ctsym)
    chosen = {}
    for name in zin.namelist():
        if not name.endswith(".sig"):
            continue
        rel, _, rest = name.partition("/")
        if RELEASE not in rel:
            continue
        mod, _, path = rest.partition("/")
        if mod not in MODULES or path.endswith("module-info.sig"):
            continue
        if path.startswith(EXCLUDE_PREFIXES):
            continue
        chosen[path[:-4]] = name
    index = {}
    with zipfile.ZipFile(out_jar, "w", zipfile.ZIP_DEFLATED) as zout:
        for internal, entry in sorted(chosen.items()):
            data = zin.read(entry)
            acc, this, sup, ifs = read_class_header(data)
            index[internal] = [acc, sup, ifs]
            zout.writestr(internal + ".class", data)
    json.dump(index, open(out_index, "w"))
    print("jdk api classes:", len(index))


if __name__ == "__main__":
    main(*sys.argv[1:])
