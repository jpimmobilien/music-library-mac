"""Turn Metalava signature files describing *Java* APIs into a stub jar of class files.

Usage:
  python3 -I sig2jar.py --out android-stubs.jar --index android-index.json \
      --cp-index java17-index.json [--cp-index other.json ...] \
      [--nullness android|androidx] [--placeholders placeholders.txt] api1.txt api2.txt ...

Every concrete method body is `aconst_null; athrow` - the jar is only meant to be compiled against.
"""
import argparse
import json
import os
import re
import sys
import zipfile

sys.path.insert(0, os.path.dirname(__file__))
from sigparse import parse_file, TypeRef, tokenize  # noqa: E402
from classgen import (ClassFile, FieldInfo, MethodInfo, AnnotationValue, ElementValue, ACC,  # noqa: E402
                      ACC_SUPER, ACC_VARARGS)

PRIM = {"boolean": "Z", "byte": "B", "char": "C", "short": "S", "int": "I", "long": "J",
        "float": "F", "double": "D", "void": "V"}


class World:
    """All known classes: dotted name -> info."""

    def __init__(self):
        self.dotted = {}      # dotted -> internal
        self.kind = {}        # internal -> "class"|"interface"|"enum"|"@interface"
        self.flags = {}       # internal -> inner-class flags (for nested)
        self.decl = {}        # internal -> ClassDecl (model classes only)
        self.placeholders = {}  # internal -> kind

    def add_index(self, index):
        for internal, (acc, sup, ifs) in index.items():
            dotted = internal.replace("/", ".").replace("$", ".")
            self.dotted.setdefault(dotted, internal)
            if internal not in self.kind:
                self.kind[internal] = ("@interface" if acc & 0x2000 else "interface" if acc & 0x0200
                                       else "enum" if acc & 0x4000 else "class")
                fl = acc & (0x0001 | 0x0010 | 0x0200 | 0x0400 | 0x2000 | 0x4000)
                if acc & 0x0200:
                    fl |= 0x0008
                self.flags[internal] = fl | 0x0008  # nested JDK/library classes referenced as static


def internal_of(c):
    return c.package.replace(".", "/") + "/" + c.name.replace(".", "$")


class Emitter:
    def __init__(self, world, nullness):
        self.w = world
        self.null_desc = ({"android": ("Landroid/annotation/Nullable;", "Landroid/annotation/NonNull;"),
                           "androidx": ("Landroidx/annotation/Nullable;", "Landroidx/annotation/NonNull;")}[nullness])
        self.referenced = set()

    # ------------------------------------------------------------ resolution
    def resolve(self, name, ctx, as_interface=False):
        w = self.w
        if name in w.dotted:
            return w.dotted[name]
        if "java.lang." + name in w.dotted:
            return w.dotted["java.lang." + name]
        if ctx is not None:
            # relative to the current class / its outers / its package
            parts = ctx.name.split(".")
            for i in range(len(parts), -1, -1):
                cand = ".".join([ctx.package] + parts[:i] + [name])
                if cand in w.dotted:
                    return w.dotted[cand]
        if name in ("Object", "String"):
            return "java/lang/" + name
        # unknown -> placeholder
        segs = name.split(".")
        k = 0
        while k < len(segs) - 1 and not segs[k][:1].isupper():
            k += 1
        internal = "/".join(segs[:k]) + ("/" if k else "") + "$".join(segs[k:])
        for j in range(k + 1, len(segs) + 1):
            part = "/".join(segs[:k]) + ("/" if k else "") + "$".join(segs[k:j])
            dotted = ".".join(segs[:j])
            if dotted not in w.dotted:
                w.dotted[dotted] = part
                w.placeholders[part] = "class"
                w.kind[part] = "class"
                w.flags[part] = 0x0001 | 0x0008
        if as_interface and internal in w.placeholders:
            w.placeholders[internal] = "interface"
            w.kind[internal] = "interface"
            w.flags[internal] = 0x0001 | 0x0008 | 0x0200 | 0x0400
        return internal

    def is_interface(self, internal):
        return self.w.kind.get(internal) in ("interface", "@interface")

    # ------------------------------------------------------------ types
    def erasure(self, tr, tvars, ctx):
        if tr.wildcard:
            return "Ljava/lang/Object;"
        base = tr.name
        if base in PRIM and tr.dims == 0:
            return PRIM[base]
        if base in PRIM:
            d = PRIM[base]
        elif base in tvars:
            bounds = tvars[base]
            if bounds:
                b = TypeRef(bounds[0].name)
                b.args = bounds[0].args
                d = self.erasure(b, {k: v for k, v in tvars.items() if k != base}, ctx)
            else:
                d = "Ljava/lang/Object;"
        else:
            internal = self.resolve(base, ctx)
            self.referenced.add(internal)
            d = "L" + internal + ";"
        return "[" * tr.dims + d

    def gsig(self, tr, tvars, ctx):
        if tr.wildcard == "?":
            return "*"
        if tr.wildcard == "extends":
            return "+" + self.gsig(tr.bound, tvars, ctx)
        if tr.wildcard == "super":
            return "-" + self.gsig(tr.bound, tvars, ctx)
        base = tr.name
        if base in PRIM:
            return "[" * tr.dims + PRIM[base]
        if base in tvars:
            return "[" * tr.dims + "T" + base + ";"
        if tr.outer is not None:
            o = self.gsig_noarray(tr.outer, tvars, ctx)[:-1]
            outer_internal = self.resolve(tr.outer.name, ctx)
            internal = self.resolve(tr.outer.name + "." + base, ctx)
            if internal.startswith(outer_internal + "$"):
                simple = internal[len(outer_internal) + 1:]
            else:
                simple = base
            self.referenced.add(internal)
            s = o + "." + simple
        else:
            internal = self.resolve(base, ctx)
            self.referenced.add(internal)
            s = "L" + internal
        if tr.args:
            s += "<" + "".join(self.gsig(a, tvars, ctx) for a in tr.args) + ">"
        return "[" * tr.dims + s + ";"

    def gsig_noarray(self, tr, tvars, ctx):
        d = tr.dims
        tr.dims = 0
        try:
            return self.gsig(tr, tvars, ctx)
        finally:
            tr.dims = d

    @staticmethod
    def needs_sig(tr, tvars):
        if tr.wildcard:
            return True
        if tr.args or tr.name in tvars or tr.outer is not None:
            return True
        return False

    def tparams_sig(self, tps, tvars, ctx):
        if not tps:
            return ""
        s = "<"
        for tp in tps:
            s += tp.name
            if not tp.bounds:
                s += ":Ljava/lang/Object;"
            for i, b in enumerate(tp.bounds):
                bs = self.gsig(b, tvars, ctx)
                if i == 0 and b.name not in tvars and b.dims == 0 and self.is_interface(self.resolve(b.name, ctx)):
                    s += "::" + bs
                else:
                    s += ":" + bs
        return s + ">"

    # ------------------------------------------------------------ annotations
    def null_ann(self, tr):
        if tr is None or tr.name in PRIM and tr.dims == 0:
            return []
        if tr.nullable is True:
            return [AnnotationValue(self.null_desc[0])]
        if tr.nullable is False:
            return [AnnotationValue(self.null_desc[1])]
        return []

    def element_value(self, toks, expected, tvars, ctx):
        """Parse an annotation element value from tokens given expected TypeRef."""
        text = "".join(t.text for t in toks)
        if expected.dims > 0:
            inner = TypeRef(expected.name)
            inner.args = expected.args
            vals = []
            if text.startswith("{"):
                body = toks[1:-1]
                cur = []
                depth = 0
                for t in body:
                    if t.text == "," and depth == 0:
                        if cur:
                            vals.append(self.element_value(cur, inner, tvars, ctx))
                        cur = []
                        continue
                    if t.text in "({":
                        depth += 1
                    if t.text in ")}":
                        depth -= 1
                    cur.append(t)
                if cur:
                    vals.append(self.element_value(cur, inner, tvars, ctx))
            else:
                vals.append(self.element_value(toks, inner, tvars, ctx))
            return ElementValue("[", vals)
        n = expected.name
        if n in PRIM:
            k = PRIM[n]
            v = const_value(toks, n)
            if v is None:
                return None
            return ElementValue(k, v)
        if n in ("String", "java.lang.String"):
            return ElementValue("s", const_value(toks, "String"))
        if n in ("Class", "java.lang.Class"):
            cname = text[:-len(".class")] if text.endswith(".class") else text
            return ElementValue("c", self.erasure(TypeRef(cname), tvars, ctx))
        internal = self.resolve(n, ctx)
        if self.w.kind.get(internal) == "enum" or "." in text:
            cname = text.rsplit(".", 1)[-1]
            return ElementValue("e", ("L" + internal + ";", cname))
        return None

    def meta_annotations(self, c):
        vis = []
        for a in c.annotations:
            s = a.simple()
            if s == "Retention" and a.args:
                val = "".join(t.text for t in a.args).rsplit(".", 1)[-1]
                vis.append(AnnotationValue("Ljava/lang/annotation/Retention;", [
                    ("value", ElementValue("e", ("Ljava/lang/annotation/RetentionPolicy;", val)))]))
            elif s == "Target" and a.args:
                raw = "".join(t.text for t in a.args).strip("{}")
                vals = [ElementValue("e", ("Ljava/lang/annotation/ElementType;", x.rsplit(".", 1)[-1]))
                        for x in raw.split(",") if x]
                vis.append(AnnotationValue("Ljava/lang/annotation/Target;", [("value", ElementValue("[", vals))]))
            elif s == "Repeatable" and a.args:
                cn = "".join(t.text for t in a.args)
                cn = cn[:-6] if cn.endswith(".class") else cn
                vis.append(AnnotationValue("Ljava/lang/annotation/Repeatable;", [
                    ("value", ElementValue("c", "L" + self.resolve(cn, c) + ";"))]))
            elif s == "FunctionalInterface":
                vis.append(AnnotationValue("Ljava/lang/FunctionalInterface;"))
        return vis

    # ------------------------------------------------------------ classes
    def emit(self, c):
        internal = internal_of(c)
        self.referenced = set()
        outer_decl = None
        if "." in c.name:
            outer_internal = internal.rsplit("$", 1)[0]
            outer_decl = self.w.decl.get(outer_internal)
        tvars = {}
        # type variables of enclosing classes are visible in non-static inner classes
        chain = []
        o = outer_decl
        cur_static = "static" in c.modifiers or c.kind != "class"
        while o is not None and not cur_static:
            chain.append(o)
            cur_static = "static" in o.modifiers or o.kind != "class"
            oi = internal_of(o)
            o = self.w.decl.get(oi.rsplit("$", 1)[0]) if "$" in oi else None
        for o in reversed(chain):
            for tp in o.type_params:
                tvars[tp.name] = tp.bounds
        for tp in c.type_params:
            tvars[tp.name] = tp.bounds

        mods = c.modifiers
        acc = 0
        if "public" in mods or "protected" in mods:
            acc |= ACC["public"]
        if c.kind == "interface":
            acc |= ACC["interface"] | ACC["abstract"]
        elif c.kind == "@interface":
            acc |= ACC["interface"] | ACC["abstract"] | ACC["annotation"]
        else:
            acc |= ACC_SUPER
            if "abstract" in mods:
                acc |= ACC["abstract"]
            if "final" in mods:
                acc |= ACC["final"]
            if c.kind == "enum":
                acc |= ACC["enum"] | ACC["final"]

        # supertypes
        super_internal = "java/lang/Object"
        super_tr = None
        if c.kind == "enum":
            super_internal = "java/lang/Enum"
            super_tr = TypeRef("java.lang.Enum")
            super_tr.args = [TypeRef(c.package + "." + c.name)]
        elif c.kind == "class" and c.extends is not None:
            super_internal = self.resolve(c.extends.name, c)
            super_tr = c.extends
        ifaces = []
        iface_trs = list(c.implements)
        if c.kind == "@interface":
            iface_trs = [TypeRef("java.lang.annotation.Annotation")] + [t for t in iface_trs if t.name not in (
                "java.lang.annotation.Annotation", "Annotation")]
        for t in iface_trs:
            ii = self.resolve(t.name, c, as_interface=True)
            if ii not in ifaces:
                ifaces.append(ii)
        csig = None
        need = bool(c.type_params) or (super_tr is not None and self.needs_sig(super_tr, tvars)) or \
            any(self.needs_sig(t, tvars) for t in iface_trs)
        if need:
            csig = self.tparams_sig(c.type_params, tvars, c)
            csig += self.gsig(super_tr, tvars, c) if super_tr is not None else "Ljava/lang/Object;"
            csig += "".join(self.gsig(t, tvars, c) for t in iface_trs)
        self.referenced.add(super_internal)
        self.referenced.update(ifaces)
        cf = ClassFile(acc, internal, super_internal, ifaces, csig)
        cf.visible = self.meta_annotations(c)
        if c.ann("Deprecated"):
            cf.deprecated = True
            cf.visible.append(AnnotationValue("Ljava/lang/Deprecated;"))

        non_static_inner = outer_decl is not None and c.kind == "class" and "static" not in mods
        declared = set()
        for m in c.members:
            if m.kind in ("property",):
                continue
            if m.ann("BytecodeOnly") is not None and False:
                pass
            mtvars = dict(tvars)
            for tp in m.type_params:
                mtvars[tp.name] = tp.bounds
            macc = 0
            for k in ("public", "protected", "private", "static", "final", "synchronized", "native",
                      "transient", "volatile", "strictfp"):
                if k in m.modifiers:
                    macc |= ACC[k]
            deprecated = m.ann("Deprecated") is not None
            vis = [AnnotationValue("Ljava/lang/Deprecated;")] if deprecated else []
            if m.kind in ("field", "enum_constant"):
                if m.kind == "enum_constant":
                    macc |= ACC["public"] | ACC["static"] | ACC["final"] | ACC["enum"]
                desc = self.erasure(m.ret, mtvars, c)
                fsig = self.gsig(m.ret, mtvars, c) if self.needs_sig(m.ret, mtvars) else None
                const = None
                if m.value and "static" in m.modifiers and "final" in m.modifiers:
                    const = field_const(m.value, m.ret)
                cf.fields.append(FieldInfo(macc, m.name, desc, fsig, const, vis,
                                           self.null_ann(m.ret) if m.kind == "field" else [], deprecated))
                continue
            # methods & ctors
            params = list(m.params)
            if m.kind == "ctor":
                name = "<init>"
                ret = TypeRef("void")
                macc &= ~(ACC["static"] | ACC["final"])
            else:
                name = m.name
                ret = m.ret
                if c.kind in ("interface", "@interface"):
                    if "static" not in m.modifiers and "default" not in m.modifiers and "private" not in m.modifiers:
                        macc |= ACC["abstract"]
                    if "private" not in m.modifiers:
                        macc |= ACC["public"]
                elif "abstract" in m.modifiers:
                    macc |= ACC["abstract"]
            if params and params[-1].vararg:
                macc |= ACC_VARARGS
            pdesc = "".join(self.erasure(p.type, mtvars, c) for p in params)
            if m.kind == "ctor" and non_static_inner:
                outer_i = internal.rsplit("$", 1)[0]
                pdesc = "L" + outer_i + ";" + pdesc
            if m.kind == "ctor" and c.kind == "enum":
                continue  # enum constructors are private in reality
            desc = "(" + pdesc + ")" + self.erasure(ret, mtvars, c)
            key = (name, desc)
            if key in declared:
                continue
            declared.add(key)
            msig = None
            if m.type_params or self.needs_sig(ret, mtvars) or any(self.needs_sig(p.type, mtvars) for p in params) \
                    or any(self.needs_sig(t, mtvars) for t in m.throws):
                if not (m.kind == "ctor" and non_static_inner):
                    msig = self.tparams_sig(m.type_params, mtvars, c) + "(" + \
                        "".join(self.gsig(p.type, mtvars, c) for p in params) + ")" + self.gsig(ret, mtvars, c)
                    if any(self.needs_sig(t, mtvars) for t in m.throws):
                        msig += "".join("^" + self.gsig(t, mtvars, c) for t in m.throws)
            exc = [self.resolve(t.name, c) for t in m.throws if t.name not in mtvars]
            slots = 0 if (macc & ACC["static"]) else 1
            for p in params:
                slots += 2 if (p.type.dims == 0 and p.type.name in ("long", "double")) else 1
            if m.kind == "ctor" and non_static_inner:
                slots += 1
            pann = [self.null_ann(p.type) for p in params]
            if m.kind == "ctor" and non_static_inner:
                pann = [[]] + pann
            ad = None
            if c.kind == "@interface" and m.default is not None:
                try:
                    ad = self.element_value(m.default, ret, mtvars, c)
                except Exception:
                    ad = None
            cf.methods.append(MethodInfo(macc, name, desc, msig, exc, vis,
                                         self.null_ann(ret) if m.kind == "method" else [], pann, ad,
                                         deprecated, slots))
        if c.kind == "enum":
            self_desc = "L" + internal + ";"
            if ("values", "()[" + self_desc) not in declared:
                cf.methods.append(MethodInfo(ACC["public"] | ACC["static"], "values", "()[" + self_desc,
                                             arg_slots=0))
            if ("valueOf", "(Ljava/lang/String;)" + self_desc) not in declared:
                cf.methods.append(MethodInfo(ACC["public"] | ACC["static"], "valueOf",
                                             "(Ljava/lang/String;)" + self_desc, arg_slots=1))
        # a class without any declared constructor gets none (like metalava: non-instantiable)
        self.add_inner_classes(cf, internal)
        return cf

    def add_inner_classes(self, cf, internal):
        names = set(n for n in self.referenced if "$" in n)
        if "$" in internal:
            names.add(internal)
        for n in list(self.w.decl.keys()):
            if n.startswith(internal + "$") and "$" not in n[len(internal) + 1:]:
                names.add(n)
        # include outer chains
        allnames = set()
        for n in names:
            while "$" in n:
                allnames.add(n)
                n = n.rsplit("$", 1)[0]
        entries = []
        for n in sorted(allnames, key=lambda s: s.count("$")):
            outer, simple = n.rsplit("$", 1)
            fl = self.w.flags.get(n, 0x0001 | 0x0008)
            entries.append((n, outer, simple, fl))
        cf.inner = entries

    def placeholder(self, internal, kind):
        acc = ACC["public"] | (ACC["interface"] | ACC["abstract"] if kind == "interface" else ACC_SUPER)
        cf = ClassFile(acc, internal, "java/lang/Object", [])
        self.referenced = set()
        if kind != "interface":
            cf.methods.append(MethodInfo(ACC["public"], "<init>", "()V", arg_slots=1))
        self.add_inner_classes(cf, internal)
        return cf


def class_inner_flags(c):
    fl = 0
    for k in ("public", "protected", "private", "static", "final", "abstract"):
        if k in c.modifiers:
            fl |= ACC[k]
    if c.kind == "interface":
        fl |= ACC["interface"] | ACC["abstract"] | ACC["static"]
    elif c.kind == "@interface":
        fl |= ACC["interface"] | ACC["abstract"] | ACC["annotation"] | ACC["static"]
    elif c.kind == "enum":
        fl |= ACC["enum"] | ACC["static"] | ACC["final"]
    return fl


_ESC = {"n": "\n", "t": "\t", "r": "\r", "b": "\b", "f": "\f", "0": "\0", "\\": "\\", "'": "'", '"': '"', "s": " "}


def unescape_java(s):
    out = []
    i = 0
    while i < len(s):
        ch = s[i]
        if ch == "\\" and i + 1 < len(s):
            n = s[i + 1]
            if n == "u":
                j = i + 2
                while j < len(s) and s[j] == "u":
                    j += 1
                out.append(chr(int(s[j:j + 4], 16)))
                i = j + 4
                continue
            if n in "01234567":
                j = i + 1
                k = j
                while k < len(s) and k < j + 3 and s[k] in "01234567":
                    k += 1
                out.append(chr(int(s[j:k], 8)))
                i = k
                continue
            out.append(_ESC.get(n, n))
            i += 2
            continue
        out.append(ch)
        i += 1
    s2 = "".join(out)
    # join surrogate pairs
    return s2.encode("utf-16", "surrogatepass").decode("utf-16")


def const_value(toks, tname):
    text = "".join(t.text for t in toks).strip()
    if tname in ("String", "java.lang.String"):
        if text.startswith('"'):
            return unescape_java(text[1:-1])
        return None
    if tname == "boolean":
        return 1 if text == "true" else 0
    if tname == "char":
        if text.startswith("'"):
            return ord(unescape_java(text[1:-1]))
        return int(text, 0)
    t = text.replace("_", "")
    m = re.fullmatch(r"\((-?[\d.]+)[fFdD]?/0\.0[fFdD]?\)", t)
    if m:
        a = float(m.group(1))
        return float("nan") if a == 0 else (float("inf") if a > 0 else float("-inf"))
    if tname in ("float", "double"):
        return float(t.rstrip("fFdD"))
    t = t.rstrip("lL")
    neg = t.startswith("-")
    if neg:
        t = t[1:]
    v = int(t, 16) if t.lower().startswith("0x") else int(t, 8) if (len(t) > 1 and t.startswith("0")) else int(t)
    return -v if neg else v


def field_const(tokens, tr):
    if tr.dims:
        return None
    n = tr.name
    try:
        if n in ("int", "short", "byte", "char", "boolean"):
            return ("I", const_value(tokens, n))
        if n == "long":
            return ("J", const_value(tokens, n))
        if n == "float":
            return ("F", const_value(tokens, n))
        if n == "double":
            return ("D", const_value(tokens, n))
        if n in ("String", "java.lang.String"):
            v = const_value(tokens, n)
            return ("S", v) if v is not None else None
    except (ValueError, IndexError):
        return None
    return None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", required=True)
    ap.add_argument("--index", required=True)
    ap.add_argument("--cp-index", action="append", default=[])
    ap.add_argument("--nullness", default="android")
    ap.add_argument("--placeholders")
    ap.add_argument("--only-classes", help="file with dotted class names to emit (others are only used for resolution)")
    ap.add_argument("files", nargs="+")
    a = ap.parse_args()

    w = World()
    for ix in a.cp_index:
        w.add_index(json.load(open(ix)))
    classes = []
    for f in a.files:
        fmt, cs = parse_file(f)
        classes += cs
    only = None
    if a.only_classes:
        only = set(x.strip() for x in open(a.only_classes) if x.strip())
    emitted = []
    for c in classes:
        internal = internal_of(c)
        if internal in w.decl:
            # same class declared in several files (should not happen) -> merge members
            w.decl[internal].members += c.members
            continue
        w.decl[internal] = c
        w.dotted[c.fqname] = internal
        w.kind[internal] = c.kind
        w.flags[internal] = class_inner_flags(c)
        if only is None or c.fqname in only:
            emitted.append(c)
    em = Emitter(w, a.nullness)
    out_index = {}
    with zipfile.ZipFile(a.out, "w", zipfile.ZIP_DEFLATED) as z:
        for c in emitted:
            cf = em.emit(c)
            z.writestr(cf.name + ".class", cf.to_bytes())
            out_index[cf.name] = [cf.access, cf.super_, cf.interfaces]
        for internal, kind in sorted(w.placeholders.items()):
            cf = em.placeholder(internal, kind)
            z.writestr(internal + ".class", cf.to_bytes())
            out_index[internal] = [cf.access, cf.super_, cf.interfaces]
    json.dump(out_index, open(a.index, "w"))
    if a.placeholders:
        with open(a.placeholders, "w") as f:
            for k, v in sorted(w.placeholders.items()):
                f.write("%s %s\n" % (v, k))
    print("classes: %d, placeholders: %d -> %s" % (len(emitted), len(w.placeholders), a.out))


if __name__ == "__main__":
    main()
