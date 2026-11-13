"""Compare the public API in a Metalava signature file with what a stub jar provides.

Reports classes and members that are in the released API but missing from the stubs (i.e. code using them
would be rejected by the typecheck although the real library accepts it).
Usage: python3 -I api_coverage.py <api.txt> <stub.jar> [<more.jar> ...]
"""
import os
import re
import struct
import sys
import zipfile

sys.path.insert(0, os.path.dirname(__file__))
from sigparse import parse_file  # noqa: E402


def members_of(data):
    off = 8
    count = struct.unpack_from(">H", data, off)[0]
    off += 2
    utf = {}
    classes = {}
    i = 1
    while i < count:
        tag = data[off]
        if tag == 1:
            ln = struct.unpack_from(">H", data, off + 1)[0]
            utf[i] = data[off + 3: off + 3 + ln].decode("utf-8", "replace")
            off += 3 + ln
        elif tag in (3, 4):
            off += 5
        elif tag in (5, 6):
            off += 9
            i += 1
        elif tag == 7:
            classes[i] = struct.unpack_from(">H", data, off + 1)[0]
            off += 3
        elif tag in (8, 16, 19, 20):
            off += 3
        elif tag in (9, 10, 11, 12, 17, 18):
            off += 5
        elif tag == 15:
            off += 4
        i += 1
    access, this_i, super_i, n_if = struct.unpack_from(">HHHH", data, off)
    off += 8 + 2 * n_if
    names = set()
    for kind in ("field", "method"):
        n = struct.unpack_from(">H", data, off)[0]
        off += 2
        for _ in range(n):
            acc, ni, di, ac = struct.unpack_from(">HHHH", data, off)
            off += 8
            if acc & 0x0005:  # public or protected
                names.add(utf[ni])
            for _ in range(ac):
                alen = struct.unpack_from(">I", data, off + 2)[0]
                off += 6 + alen
    return utf[classes[this_i]], names


def norm(name):
    name = name.split("$default")[0]
    return re.sub(r"-[A-Za-z0-9_]{7}$", "", name.split("-")[0] if "-" in name else name)


def main(api, jars):
    have = {}
    for j in jars:
        with zipfile.ZipFile(j) as z:
            for n in z.namelist():
                if n.endswith(".class"):
                    try:
                        cn, names = members_of(z.read(n))
                    except Exception:
                        continue
                    have.setdefault(cn, set()).update(norm(x) for x in names)
    fmt, classes = parse_file(api)
    miss_cls, miss_mem, total_mem = [], [], 0
    for c in classes:
        internal = c.package.replace(".", "/") + "/" + c.name.replace(".", "$")
        if internal not in have:
            miss_cls.append(c.fqname)
            continue
        hv = have[internal]
        for m in c.members:
            if m.kind == "property":
                continue
            if m.kind == "ctor":
                nm = "<init>"
            else:
                nm = norm(m.name)
            if m.kind == "enum_constant" or m.kind == "field":
                nm = m.name
            total_mem += 1
            if nm not in hv and not (m.kind == "method" and (m.name.startswith("get") or m.name.startswith("is"))
                                     and m.ann("BytecodeOnly")):
                miss_mem.append("%s#%s" % (c.fqname, m.name))
    print("%s: %d classes, %d missing; %d members, %d missing" % (os.path.basename(api), len(classes), len(miss_cls),
                                                               total_mem, len(miss_mem)))
    for x in miss_cls[:200]:
        print("  missing class  " + x)
    for x in miss_mem[:400]:
        print("  missing member " + x)


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2:])
