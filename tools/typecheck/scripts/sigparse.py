"""Parser for Metalava API signature files (formats 2.0, 3.0, 4.0, 5.0).

Produces a simple model (packages -> classes -> members) that the emitters use.
Only the information needed for compile-time checking is kept: kinds, modifiers,
type parameters, supertypes, member signatures, nullability, constant values,
annotation-element defaults and a few meta annotations (@Retention/@Target/@Deprecated).
"""
import re

# ---------------------------------------------------------------- tokenizer
_TOKEN_RE = re.compile(r'''
    (?P<ws>\s+)
  | (?P<comment>//[^\n]*)
  | (?P<str>"(?:\\.|[^"\\])*")
  | (?P<chr>'(?:\\.|[^'\\])+')
  | (?P<num>-?(?:0[xX][0-9a-fA-F_]+[lL]?|\d[\d_]*(?:\.\d*)?(?:[eE][-+]?\d+)?[fFdDlL]?|\.\d+(?:[eE][-+]?\d+)?[fFdD]?))
  | (?P<ellipsis>\.\.\.)
  | (?P<ident>[A-Za-z_$][A-Za-z0-9_$]*(?:\.[A-Za-z_$][A-Za-z0-9_$\-]*)*(?:-+[A-Za-z0-9_$]+)*)
  | (?P<punct>[<>,()\[\]?!@=;{}:&|*/+\-.~^%])
''', re.VERBOSE)


class Tok:
    __slots__ = ("kind", "text")

    def __init__(self, kind, text):
        self.kind = kind
        self.text = text

    def __repr__(self):
        return "%s:%s" % (self.kind, self.text)


def tokenize(s):
    out = []
    pos = 0
    n = len(s)
    while pos < n:
        m = _TOKEN_RE.match(s, pos)
        if not m:
            raise SyntaxError("cannot tokenize at %r" % s[pos:pos + 40])
        pos = m.end()
        k = m.lastgroup
        if k in ("ws", "comment"):
            continue
        out.append(Tok(k, m.group(k)))
    return out


# ---------------------------------------------------------------- model
class TypeRef:
    """A (possibly generic, possibly array) type as written in the signature file."""
    __slots__ = ("name", "args", "dims", "nullable", "wildcard", "bound", "annotations", "outer", "vararg")

    def __init__(self, name):
        self.name = name          # dotted name as written ("String", "java.util.List", "T", "int")
        self.args = []            # list[TypeRef]
        self.dims = 0             # array dimensions
        self.nullable = None      # True (?), False (non-null), None (platform/unknown)
        self.wildcard = None      # None | "?" | "extends" | "super"
        self.bound = None         # TypeRef for wildcard bound
        self.annotations = []     # list[str] (annotation names, type-use)
        self.outer = None         # TypeRef of the outer class for "Outer<A>.Inner<B>"
        self.vararg = False

    def __repr__(self):
        if self.wildcard:
            return "?" if self.wildcard == "?" else "? %s %r" % (self.wildcard, self.bound)
        s = self.name
        if self.args:
            s += "<" + ",".join(repr(a) for a in self.args) + ">"
        s += "[]" * self.dims
        if self.nullable:
            s += "?"
        return s


class Annotation:
    __slots__ = ("name", "args")

    def __init__(self, name, args):
        self.name = name          # as written
        self.args = args          # raw token list (inside parentheses) or None

    def simple(self):
        return self.name.rsplit(".", 1)[-1]


class TypeParam:
    __slots__ = ("name", "bounds", "reified")

    def __init__(self, name, bounds):
        self.name = name
        self.bounds = bounds      # list[TypeRef]
        self.reified = False


class Param:
    __slots__ = ("type", "name", "annotations", "optional", "vararg", "default")

    def __init__(self):
        self.type = None
        self.name = None
        self.annotations = []
        self.optional = False
        self.vararg = False
        self.default = None


class Member:
    __slots__ = ("kind", "name", "modifiers", "annotations", "type_params", "ret", "params",
                 "throws", "value", "default", "line", "owner")

    def __init__(self, kind):
        self.kind = kind          # ctor | method | field | enum_constant | property
        self.name = None
        self.modifiers = set()
        self.annotations = []
        self.type_params = []
        self.ret = None           # TypeRef (method return / field type / property type)
        self.params = []
        self.throws = []
        self.value = None         # raw constant tokens for fields
        self.default = None       # raw default tokens for annotation methods
        self.line = ""
        self.owner = None

    def ann(self, simple):
        for a in self.annotations:
            if a.simple() == simple:
                return a
        return None


class ClassDecl:
    __slots__ = ("package", "name", "kind", "modifiers", "annotations", "type_params", "extends",
                 "implements", "members", "line", "source")

    def __init__(self):
        self.package = None
        self.name = None          # "Outer.Inner" (relative to package)
        self.kind = None          # class | interface | enum | @interface | value class (kind "class" + modifier "value")
        self.modifiers = set()
        self.annotations = []
        self.type_params = []
        self.extends = None       # TypeRef or list for interfaces
        self.implements = []      # list[TypeRef]
        self.members = []
        self.line = ""
        self.source = None

    @property
    def fqname(self):
        return self.package + "." + self.name if self.package else self.name

    def ann(self, simple):
        for a in self.annotations:
            if a.simple() == simple:
                return a
        return None


MODIFIERS = {"public", "protected", "private", "static", "final", "abstract", "default", "native",
             "synchronized", "transient", "volatile", "strictfp", "sealed", "open", "data", "inline",
             "operator", "infix", "suspend", "value", "fun", "const", "lateinit", "tailrec", "external",
             "reified", "vararg", "deprecated", "expect", "actual", "inner", "companion", "noinline",
             "crossinline", "override", "internal", "exhaustive"}


# ---------------------------------------------------------------- parser
class Parser:
    def __init__(self, toks, fmt, line):
        self.t = toks
        self.i = 0
        self.fmt = fmt
        self.line = line
        self.kotlin_nulls = fmt >= 3.0

    def peek(self, k=0):
        j = self.i + k
        return self.t[j] if j < len(self.t) else None

    def next(self):
        tok = self.t[self.i]
        self.i += 1
        return tok

    def at(self, text):
        p = self.peek()
        return p is not None and p.text == text

    def expect(self, text):
        tok = self.next()
        if tok.text != text:
            raise SyntaxError("expected %r got %r in %s" % (text, tok.text, self.line))
        return tok

    def skip_balanced(self, open_, close):
        """Consume a balanced group starting at current 'open_' token and return inner tokens."""
        self.expect(open_)
        depth = 1
        inner = []
        while True:
            tok = self.next()
            if tok.text == open_:
                depth += 1
            elif tok.text == close:
                depth -= 1
                if depth == 0:
                    return inner
            inner.append(tok)

    def annotations(self):
        anns = []
        while self.at("@") and self.peek(1) is not None and self.peek(1).kind == "ident" and self.peek(1).text != "interface":
            self.next()
            name = self.next().text
            args = None
            if self.at("("):
                args = self.skip_balanced("(", ")")
            anns.append(Annotation(name, args))
        return anns

    def modifiers(self):
        mods = set()
        while True:
            p = self.peek()
            if p is None or p.kind != "ident" or p.text not in MODIFIERS:
                return mods
            # "value class", "fun interface", "annotation class" are handled by caller
            if p.text == "value" and self.peek(1) is not None and self.peek(1).text == "class":
                return mods
            if p.text == "fun" and self.peek(1) is not None and self.peek(1).text == "interface":
                return mods
            mods.add(self.next().text)

    def type_params(self):
        tps = []
        if not self.at("<"):
            return tps
        self.next()
        while True:
            self.annotations()
            reified = False
            if self.at("reified"):
                self.next()
                reified = True
            name = self.next().text
            bounds = []
            if self.at("extends"):
                self.next()
                bounds.append(self.type())
                while self.at("&"):
                    self.next()
                    bounds.append(self.type())
            tp = TypeParam(name, bounds)
            tp.reified = reified
            tps.append(tp)
            if self.at(","):
                self.next()
                continue
            self.expect(">")
            return tps

    def type(self):
        anns = [a.name for a in self.annotations()]
        if self.at("?"):
            self.next()
            tr = TypeRef("?")
            tr.wildcard = "?"
            if self.at("extends") or self.at("super"):
                tr.wildcard = self.next().text
                tr.bound = self.type()
            return tr
        name_tok = self.next()
        if name_tok.kind != "ident":
            raise SyntaxError("type expected, got %r in %s" % (name_tok.text, self.line))
        tr = TypeRef(name_tok.text)
        tr.annotations = anns
        if self.at("<"):
            self.next()
            while True:
                tr.args.append(self.type())
                if self.at(","):
                    self.next()
                    continue
                self.expect(">")
                break
        # Outer<A>.Inner<B>
        while self.at(".") and self.peek(1) is not None and self.peek(1).kind == "ident":
            self.next()
            inner = TypeRef(self.next().text)
            inner.outer = tr
            if self.at("<"):
                self.next()
                while True:
                    inner.args.append(self.type())
                    if self.at(","):
                        self.next()
                        continue
                    self.expect(">")
                    break
            tr = inner
        if self.kotlin_nulls:
            tr.nullable = False
        for a in anns:
            s = a.rsplit(".", 1)[-1]
            if s in ("Nullable", "RecentlyNullable"):
                tr.nullable = True
            elif s in ("NonNull", "RecentlyNonNull"):
                tr.nullable = False
        self._suffix(tr)
        while self.at("[") and self.peek(1) is not None and self.peek(1).text == "]":
            self.next()
            self.next()
            tr.dims += 1
            self._suffix(tr)
        if self.at("..."):
            self.next()
            tr.dims += 1
            tr.vararg = True
            self._suffix(tr)
        return tr

    def _suffix(self, tr):
        if self.at("?"):
            self.next()
            tr.nullable = True
        elif self.at("!"):
            self.next()
            tr.nullable = None

    def params(self):
        ps = []
        self.expect("(")
        if self.at(")"):
            self.next()
            return ps
        while True:
            p = Param()
            p.annotations = self.annotations()
            if self.at("optional"):
                self.next()
                p.optional = True
            # Kotlin modifiers on params (vararg, noinline, crossinline)
            while self.peek() is not None and self.peek().text in ("vararg", "noinline", "crossinline") and \
                    self.peek(1) is not None and self.peek(1).kind == "ident":
                if self.next().text == "vararg":
                    p.vararg = True
            p.annotations += self.annotations()
            p.type = self.type()
            if p.type.vararg:
                p.vararg = True
            for a in p.annotations:
                s = a.simple()
                if s in ("Nullable", "RecentlyNullable"):
                    p.type.nullable = True
                elif s in ("NonNull", "RecentlyNonNull"):
                    p.type.nullable = False
            if self.peek() is not None and self.peek().kind == "ident":
                p.name = self.next().text
            if self.at("="):
                self.next()
                d = []
                depth = 0
                while not (depth == 0 and (self.at(",") or self.at(")"))):
                    tok = self.next()
                    if tok.text in "([{":
                        depth += 1
                    elif tok.text in ")]}":
                        depth -= 1
                    d.append(tok)
                p.default = d
                p.optional = True
            ps.append(p)
            if self.at(","):
                self.next()
                continue
            self.expect(")")
            return ps


def _member(kind, toks, fmt, line):
    p = Parser(toks, fmt, line)
    m = Member(kind)
    m.line = line
    m.annotations = p.annotations()
    m.modifiers = p.modifiers()
    m.annotations += p.annotations()
    m.modifiers |= p.modifiers()
    if kind in ("ctor",):
        m.type_params = p.type_params()
        m.name = p.next().text
        m.params = p.params()
    elif kind == "method":
        m.type_params = p.type_params()
        m.ret = p.type()
        _apply_decl_nullness(m.ret, m.annotations)
        m.name = p.next().text
        m.params = p.params()
    else:  # field, enum_constant, property
        m.ret = p.type()
        _apply_decl_nullness(m.ret, m.annotations)
        m.name = p.next().text
    if p.at("throws"):
        p.next()
        m.throws.append(p.type())
        while p.at(","):
            p.next()
            m.throws.append(p.type())
    if p.at("default"):
        p.next()
        rest = []
        while not p.at(";"):
            rest.append(p.next())
        m.default = rest
    if p.at("="):
        p.next()
        rest = []
        while not p.at(";"):
            rest.append(p.next())
        m.value = rest
    if not p.at(";"):
        raise SyntaxError("trailing tokens %r in %s" % (p.t[p.i:], line))
    return m


def _apply_decl_nullness(tr, anns):
    for a in anns:
        s = a.simple()
        if s in ("Nullable", "RecentlyNullable"):
            tr.nullable = True
        elif s in ("NonNull", "RecentlyNonNull"):
            tr.nullable = False


def _class_header(toks, fmt, line):
    p = Parser(toks, fmt, line)
    c = ClassDecl()
    c.line = line
    c.annotations = p.annotations()
    c.modifiers = p.modifiers()
    c.annotations += p.annotations()
    c.modifiers |= p.modifiers()
    kw = p.next().text
    while kw not in ("value", "fun", "@", "annotation", "class", "interface", "enum", "record", "object") and \
            re.match(r"^[a-z]+$", kw) and p.peek() is not None:
        c.modifiers.add(kw)
        kw = p.next().text
    if kw == "value":
        p.expect("class")
        c.kind = "class"
        c.modifiers.add("value")
    elif kw == "fun":
        p.expect("interface")
        c.kind = "interface"
        c.modifiers.add("fun")
    elif kw == "@":
        p.expect("interface")
        c.kind = "@interface"
    elif kw == "annotation":
        p.expect("class")
        c.kind = "@interface"
    elif kw in ("class", "interface", "enum", "record", "object"):
        c.kind = {"object": "class", "record": "class"}.get(kw, kw)
    else:
        raise SyntaxError("class keyword expected, got %r in %s" % (kw, line))
    c.name = p.next().text
    c.type_params = p.type_params()
    while not p.at("{"):
        kw = p.next().text
        if kw == "extends":
            if c.kind in ("interface", "@interface"):
                c.implements.append(p.type())
                while p.at(",") or (p.peek() is not None and p.peek().kind == "ident" and p.peek().text not in ("extends", "implements")) or p.at("@"):
                    if p.at(","):
                        p.next()
                    c.implements.append(p.type())
            else:
                c.extends = p.type()
        elif kw == "implements":
            c.implements.append(p.type())
            while p.at(",") or (p.peek() is not None and p.peek().kind == "ident" and p.peek().text not in ("extends", "implements")) or p.at("@"):
                if p.at(","):
                    p.next()
                c.implements.append(p.type())
        else:
            raise SyntaxError("unexpected %r in class header %s" % (kw, line))
    return c


def parse_file(path, source_tag=None):
    """Returns (format, list[ClassDecl])."""
    text = open(path, encoding="utf-8").read()
    lines = text.split("\n")
    m = re.match(r"// Signature format: (\d+\.\d+)", lines[0])
    if not m:
        raise SyntaxError("no signature header in " + path)
    fmt = float(m.group(1))
    classes = []
    pkg = None
    cur = None
    for raw in lines[1:]:
        line = raw.strip()
        if not line or line.startswith("//"):
            continue
        if line.startswith("package ") and line.endswith("{"):
            pkg = re.sub(r"@\S+\s+", "", line[len("package "):-1]).strip()
            continue
        if line == "}":
            if cur is not None:
                cur = None
            else:
                pkg = None
            continue
        toks = tokenize(line)
        head = toks[0].text
        if cur is None and re.search(r"\btypealias\b", line):
            continue
        if cur is None:
            if not line.endswith("{"):
                raise SyntaxError("class header expected: " + line)
            cur = _class_header(toks[:-1] + [Tok("punct", "{")], fmt, line)
            cur.package = pkg
            cur.source = source_tag or path
            classes.append(cur)
            continue
        if head in ("ctor", "method", "field", "enum_constant", "property"):
            try:
                mem = _member(head, toks[1:], fmt, line)
            except SyntaxError:
                if head != "property":
                    raise
                mem = Member("property")  # Kotlin-only detail (e.g. generic extension property) - not needed
                mem.line = line
                mem.name = toks[-2].text if len(toks) > 1 else "?"
            mem.owner = cur
            cur.members.append(mem)
        else:
            raise SyntaxError("unknown member line: " + line)
    return fmt, classes
