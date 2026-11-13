"""Generate R.java (non-final ids, like AGP 8+ with non-transitive R classes) and BuildConfig.java.

Usage:
  python3 -I gen_r.py --out <dir> --res <namespace>=<res-dir> [--res ...]
                      [--buildconfig <namespace>] [--field NAME=TYPE:VALUE ...]
                      [--application-id ID] [--version-code N] [--version-name S]
"""
import argparse
import os
import re
import sys
import xml.etree.ElementTree as ET

FILE_TYPES = {"drawable", "mipmap", "layout", "xml", "raw", "font", "anim", "animator", "color", "menu",
              "navigation", "transition", "interpolator"}
VALUE_TAGS = {"string": "string", "color": "color", "dimen": "dimen", "bool": "bool", "integer": "integer",
              "array": "array", "string-array": "array", "integer-array": "array", "plurals": "plurals",
              "style": "style", "attr": "attr", "fraction": "fraction", "drawable": "drawable", "font": "font"}


def ident(name):
    return re.sub(r"[.\-:]", "_", name)


def collect(res_dir):
    r = {}
    styleables = {}

    def add(t, n):
        r.setdefault(t, set()).add(ident(n))

    for sub in sorted(os.listdir(res_dir)):
        p = os.path.join(res_dir, sub)
        if not os.path.isdir(p):
            continue
        base = sub.split("-")[0]
        for f in sorted(os.listdir(p)):
            fp = os.path.join(p, f)
            if f.startswith("."):
                continue
            if base == "values":
                if not f.endswith(".xml"):
                    continue
                try:
                    root = ET.parse(fp).getroot()
                except ET.ParseError as e:
                    sys.exit("XML error in %s: %s" % (fp, e))
                for el in root:
                    tag = el.tag
                    name = el.get("name")
                    if not name:
                        continue
                    if tag == "item":
                        t = el.get("type")
                        if t:
                            add(t, name)
                    elif tag in VALUE_TAGS:
                        add(VALUE_TAGS[tag], name)
                    elif tag == "declare-styleable":
                        attrs = []
                        for a in el:
                            if a.tag == "attr" and a.get("name"):
                                an = a.get("name")
                                attrs.append(an)
                                if not an.startswith("android:"):
                                    add("attr", an)
                        styleables[ident(name)] = [ident(a) for a in attrs]
                    elif tag == "public":
                        pass
                    elif tag == "eat-comment":
                        pass
            elif base in FILE_TYPES:
                name = f.split(".")[0]
                add(base, name)
                if f.endswith(".xml"):
                    try:
                        txt = open(fp, encoding="utf-8").read()
                    except UnicodeDecodeError:
                        continue
                    for m in re.finditer(r'@\+id/([A-Za-z0-9_.]+)', txt):
                        add("id", m.group(1))
    return r, styleables


def write_r(out, ns, res_dirs):
    types = {}
    styleables = {}
    for d in res_dirs:
        t, s = collect(d)
        for k, v in t.items():
            types.setdefault(k, set()).update(v)
        styleables.update(s)
    pkg_dir = os.path.join(out, ns.replace(".", "/"))
    os.makedirs(pkg_dir, exist_ok=True)
    lines = ["package %s;" % ns, "", "public final class R {", "  private R() {}"]
    nid = 0x7f010000
    for t in sorted(types):
        lines.append("  public static final class %s {" % t)
        lines.append("    private %s() {}" % t)
        for n in sorted(types[t]):
            lines.append("    public static int %s = 0x%08x;" % (n, nid))
            nid += 1
        lines.append("  }")
    if styleables:
        lines.append("  public static final class styleable {")
        lines.append("    private styleable() {}")
        for s, attrs in sorted(styleables.items()):
            lines.append("    public static int[] %s = new int[%d];" % (s, len(attrs)))
            for i, a in enumerate(attrs):
                lines.append("    public static int %s_%s = %d;" % (s, a, i))
        lines.append("  }")
    lines.append("}")
    open(os.path.join(pkg_dir, "R.java"), "w").write("\n".join(lines) + "\n")
    return sum(len(v) for v in types.values())


def jstr(s):
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'


def write_buildconfig(out, ns, app_id, vcode, vname, fields):
    pkg_dir = os.path.join(out, ns.replace(".", "/"))
    os.makedirs(pkg_dir, exist_ok=True)
    lines = ["package %s;" % ns, "", "public final class BuildConfig {",
             "  public static final boolean DEBUG = Boolean.parseBoolean(\"true\");"]
    if app_id:
        lines.append("  public static final String APPLICATION_ID = %s;" % jstr(app_id))
        lines.append("  public static final String BUILD_TYPE = \"debug\";")
        lines.append("  public static final int VERSION_CODE = %d;" % int(vcode))
        lines.append("  public static final String VERSION_NAME = %s;" % jstr(vname))
    for f in fields:
        name, _, rest = f.partition("=")
        typ, _, val = rest.partition(":")
        lines.append("  public static final %s %s = %s;" % (typ, name, val))
    lines.append("}")
    open(os.path.join(pkg_dir, "BuildConfig.java"), "w").write("\n".join(lines) + "\n")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", required=True)
    ap.add_argument("--res", action="append", default=[])
    ap.add_argument("--buildconfig", action="append", default=[])
    ap.add_argument("--field", action="append", default=[])
    ap.add_argument("--application-id")
    ap.add_argument("--version-code", default="1")
    ap.add_argument("--version-name", default="1.0")
    a = ap.parse_args()
    by_ns = {}
    for spec in a.res:
        ns, _, d = spec.partition("=")
        by_ns.setdefault(ns, []).append(d)
    for ns, dirs in by_ns.items():
        n = write_r(a.out, ns, [d for d in dirs if os.path.isdir(d)])
        print("R %s: %d resources" % (ns, n))
    for ns in a.buildconfig:
        write_buildconfig(a.out, ns, a.application_id, a.version_code, a.version_name, a.field)
        print("BuildConfig %s" % ns)


if __name__ == "__main__":
    main()
