"""Minimal JVM class-file writer for API stubs (no real code; every concrete method throws).

Enough for the Kotlin and Java compilers to *read* the classes: access flags, supertypes,
fields with ConstantValue, methods with descriptors, generic Signature attributes, Exceptions,
InnerClasses, AnnotationDefault, Deprecated and (in)visible annotations.
"""
import struct


def _mutf8(s):
    out = bytearray()
    for ch in s:
        c = ord(ch)
        if c > 0xFFFF:  # supplementary -> surrogate pair, each encoded as 3 bytes
            c -= 0x10000
            for u in (0xD800 + (c >> 10), 0xDC00 + (c & 0x3FF)):
                out += bytes([0xE0 | (u >> 12), 0x80 | ((u >> 6) & 0x3F), 0x80 | (u & 0x3F)])
        elif c == 0:
            out += b"\xC0\x80"
        elif c < 0x80:
            out.append(c)
        elif c < 0x800:
            out += bytes([0xC0 | (c >> 6), 0x80 | (c & 0x3F)])
        else:
            out += bytes([0xE0 | (c >> 12), 0x80 | ((c >> 6) & 0x3F), 0x80 | (c & 0x3F)])
    return bytes(out)


class ConstPool:
    def __init__(self):
        self.entries = [None]
        self.index = {}

    def _add(self, key, data, wide=False):
        if key in self.index:
            return self.index[key]
        idx = len(self.entries)
        self.entries.append(data)
        if wide:
            self.entries.append(None)
        self.index[key] = idx
        return idx

    def utf8(self, s):
        b = _mutf8(s)
        return self._add(("U", s), b"\x01" + struct.pack(">H", len(b)) + b)

    def cls(self, internal):
        return self._add(("C", internal), b"\x07" + struct.pack(">H", self.utf8(internal)))

    def string(self, s):
        return self._add(("S", s), b"\x08" + struct.pack(">H", self.utf8(s)))

    def integer(self, v):
        v &= 0xFFFFFFFF
        return self._add(("I", v), b"\x03" + struct.pack(">I", v))

    def float_(self, f):
        b = struct.pack(">f", f)
        return self._add(("F", b), b"\x04" + b)

    def long_(self, v):
        v &= 0xFFFFFFFFFFFFFFFF
        return self._add(("J", v), b"\x05" + struct.pack(">Q", v), wide=True)

    def double_(self, d):
        b = struct.pack(">d", d)
        return self._add(("D", b), b"\x06" + b, wide=True)

    def bytes(self):
        out = bytearray(struct.pack(">H", len(self.entries)))
        for e in self.entries[1:]:
            if e is not None:
                out += e
        return bytes(out)


ACC = dict(public=0x0001, private=0x0002, protected=0x0004, static=0x0008, final=0x0010,
           synchronized=0x0020, volatile=0x0040, transient=0x0080, native=0x0100,
           interface=0x0200, abstract=0x0400, strictfp=0x0800, annotation=0x2000, enum=0x4000)
ACC_SUPER = 0x0020
ACC_VARARGS = 0x0080
ACC_BRIDGE = 0x0040


class ElementValue:
    """Annotation element value. kind: one of B C D F I J S Z s e c @ [ ; value accordingly."""

    def __init__(self, kind, value):
        self.kind = kind
        self.value = value

    def encode(self, cp):
        k = self.kind
        if k in "BCISZ":
            return k.encode() + struct.pack(">H", cp.integer(int(self.value)))
        if k == "J":
            return b"J" + struct.pack(">H", cp.long_(int(self.value)))
        if k == "F":
            return b"F" + struct.pack(">H", cp.float_(float(self.value)))
        if k == "D":
            return b"D" + struct.pack(">H", cp.double_(float(self.value)))
        if k == "s":
            return b"s" + struct.pack(">H", cp.utf8(self.value))
        if k == "e":
            tdesc, cname = self.value
            return b"e" + struct.pack(">HH", cp.utf8(tdesc), cp.utf8(cname))
        if k == "c":
            return b"c" + struct.pack(">H", cp.utf8(self.value))
        if k == "@":
            return b"@" + self.value.encode(cp)
        if k == "[":
            out = b"[" + struct.pack(">H", len(self.value))
            for v in self.value:
                out += v.encode(cp)
            return out
        raise ValueError(k)


class AnnotationValue:
    def __init__(self, desc, elements=None):
        self.desc = desc
        self.elements = elements or []   # list[(name, ElementValue)]

    def encode(self, cp):
        out = struct.pack(">HH", cp.utf8(self.desc), len(self.elements))
        for n, v in self.elements:
            out += struct.pack(">H", cp.utf8(n)) + v.encode(cp)
        return out


def _attr(cp, name, payload):
    return struct.pack(">HI", cp.utf8(name), len(payload)) + payload


def _annotations_attrs(cp, visible, invisible):
    out = []
    if visible:
        p = struct.pack(">H", len(visible)) + b"".join(a.encode(cp) for a in visible)
        out.append(_attr(cp, "RuntimeVisibleAnnotations", p))
    if invisible:
        p = struct.pack(">H", len(invisible)) + b"".join(a.encode(cp) for a in invisible)
        out.append(_attr(cp, "RuntimeInvisibleAnnotations", p))
    return out


class FieldInfo:
    def __init__(self, access, name, desc, signature=None, const=None, visible=None, invisible=None, deprecated=False):
        self.access, self.name, self.desc = access, name, desc
        self.signature, self.const = signature, const   # const: ("I"|"J"|"F"|"D"|"S", value)
        self.visible, self.invisible = visible or [], invisible or []
        self.deprecated = deprecated


class MethodInfo:
    def __init__(self, access, name, desc, signature=None, exceptions=None, visible=None, invisible=None,
                 param_invisible=None, annotation_default=None, deprecated=False, arg_slots=0):
        self.access, self.name, self.desc = access, name, desc
        self.signature = signature
        self.exceptions = exceptions or []
        self.visible, self.invisible = visible or [], invisible or []
        self.param_invisible = param_invisible          # list[list[AnnotationValue]] or None
        self.annotation_default = annotation_default    # ElementValue or None
        self.deprecated = deprecated
        self.arg_slots = arg_slots


class ClassFile:
    def __init__(self, access, name, super_, interfaces, signature=None):
        self.access, self.name, self.super_, self.interfaces = access, name, super_, interfaces
        self.signature = signature
        self.fields = []
        self.methods = []
        self.inner = []          # list[(inner, outer, simple, flags)]
        self.visible, self.invisible = [], []
        self.deprecated = False

    def to_bytes(self):
        cp = ConstPool()
        body = bytearray()
        body += struct.pack(">HHH", self.access, cp.cls(self.name), cp.cls(self.super_) if self.super_ else 0)
        body += struct.pack(">H", len(self.interfaces))
        for i in self.interfaces:
            body += struct.pack(">H", cp.cls(i))
        body += struct.pack(">H", len(self.fields))
        for f in self.fields:
            attrs = []
            if f.const is not None:
                k, v = f.const
                idx = {"I": cp.integer, "J": cp.long_, "F": cp.float_, "D": cp.double_, "S": cp.string}[k](v)
                attrs.append(_attr(cp, "ConstantValue", struct.pack(">H", idx)))
            if f.signature:
                attrs.append(_attr(cp, "Signature", struct.pack(">H", cp.utf8(f.signature))))
            if f.deprecated:
                attrs.append(_attr(cp, "Deprecated", b""))
            attrs += _annotations_attrs(cp, f.visible, f.invisible)
            body += struct.pack(">HHHH", f.access, cp.utf8(f.name), cp.utf8(f.desc), len(attrs))
            body += b"".join(attrs)
        body += struct.pack(">H", len(self.methods))
        for m in self.methods:
            attrs = []
            if not (m.access & (ACC["abstract"] | ACC["native"])):
                code = b"\x01\xbf"  # aconst_null; athrow
                payload = struct.pack(">HHI", 1, max(m.arg_slots, 1), len(code)) + code + struct.pack(">HH", 0, 0)
                attrs.append(_attr(cp, "Code", payload))
            if m.exceptions:
                payload = struct.pack(">H", len(m.exceptions)) + b"".join(struct.pack(">H", cp.cls(e)) for e in m.exceptions)
                attrs.append(_attr(cp, "Exceptions", payload))
            if m.signature:
                attrs.append(_attr(cp, "Signature", struct.pack(">H", cp.utf8(m.signature))))
            if m.deprecated:
                attrs.append(_attr(cp, "Deprecated", b""))
            attrs += _annotations_attrs(cp, m.visible, m.invisible)
            if m.param_invisible and any(m.param_invisible):
                payload = bytes([len(m.param_invisible)])
                for anns in m.param_invisible:
                    payload += struct.pack(">H", len(anns)) + b"".join(a.encode(cp) for a in anns)
                attrs.append(_attr(cp, "RuntimeInvisibleParameterAnnotations", payload))
            if m.annotation_default is not None:
                attrs.append(_attr(cp, "AnnotationDefault", m.annotation_default.encode(cp)))
            body += struct.pack(">HHHH", m.access, cp.utf8(m.name), cp.utf8(m.desc), len(attrs))
            body += b"".join(attrs)
        attrs = []
        if self.signature:
            attrs.append(_attr(cp, "Signature", struct.pack(">H", cp.utf8(self.signature))))
        if self.inner:
            payload = struct.pack(">H", len(self.inner))
            for inner, outer, simple, flags in self.inner:
                payload += struct.pack(">HHHH", cp.cls(inner), cp.cls(outer) if outer else 0,
                                       cp.utf8(simple) if simple else 0, flags)
            attrs.append(_attr(cp, "InnerClasses", payload))
        if self.deprecated:
            attrs.append(_attr(cp, "Deprecated", b""))
        attrs += _annotations_attrs(cp, self.visible, self.invisible)
        body += struct.pack(">H", len(attrs)) + b"".join(attrs)
        return b"\xCA\xFE\xBA\xBE" + struct.pack(">HH", 0, 61) + cp.bytes() + bytes(body)


def read_class_header(data):
    """Return (access_flags, this_name, super_name, interfaces) of a class file (also .sig of ct.sym)."""
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
        else:
            raise ValueError("bad constant pool tag %d" % tag)
        i += 1
    access, this_i, super_i, n_if = struct.unpack_from(">HHHH", data, off)
    off += 8
    ifs = []
    for _ in range(n_if):
        ifs.append(utf[classes[struct.unpack_from(">H", data, off)[0]]])
        off += 2
    return access, utf[classes[this_i]], (utf[classes[super_i]] if super_i else None), ifs
