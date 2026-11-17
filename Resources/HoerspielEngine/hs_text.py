"""KI-Hörspiel – Textwerkzeuge: deutsche Zahlen ausschreiben, Sprechtext säubern, Drehbuch lesen.

Sprachmodelle lesen Ziffern oft falsch („1984“ als „eins neun acht vier“). Darum schreibt die Produktion Zahlen,
Uhrzeiten, Jahreszahlen und Ordnungszahlen vor der Sprachausgabe in Worten aus. Das Drehbuch ist ein einfaches
Zeilenformat, das auch kleine Sprachmodelle zuverlässig einhalten:

    ERZÄHLER: Es war ein heißer Sommer …
    LENA (flüsternd): Hast du das gehört?
    [GERÄUSCH: Tür knarrt | creaking wooden door]
    [ATMO: Regen und Wind | steady rain and wind]
    [MUSIK: Spannung | tense analog synth pulse]
    [PAUSE: 2]

Nur Standardbibliothek – läuft in jeder Python-Umgebung.
"""

import re
import unicodedata

_ONES = ["null", "eins", "zwei", "drei", "vier", "fünf", "sechs", "sieben", "acht", "neun", "zehn", "elf", "zwölf",
         "dreizehn", "vierzehn", "fünfzehn", "sechzehn", "siebzehn", "achtzehn", "neunzehn"]
_TENS = ["", "", "zwanzig", "dreißig", "vierzig", "fünfzig", "sechzig", "siebzig", "achtzig", "neunzig"]
_ORD_IRREGULAR = {1: "erste", 3: "dritte", 7: "siebte", 8: "achte"}


def _below_hundred(n):
    if n < 20:
        return _ONES[n]
    tens, ones = divmod(n, 10)
    if ones == 0:
        return _TENS[tens]
    unit = "ein" if ones == 1 else _ONES[ones]
    return f"{unit}und{_TENS[tens]}"


def _below_thousand(n):
    hundreds, rest = divmod(n, 100)
    out = ""
    if hundreds:
        out = ("ein" if hundreds == 1 else _ONES[hundreds]) + "hundert"
    if rest:
        out += _below_hundred(rest)
    return out or "null"


def cardinal(n):
    """Ganze Zahl in deutschen Worten (bis unter eine Billion)."""
    if n < 0:
        return "minus " + cardinal(-n)
    if n < 1000:
        return _below_thousand(n)
    parts = []
    for value, sing, plur in ((10**9, "eine Milliarde", "Milliarden"), (10**6, "eine Million", "Millionen")):
        if n >= value:
            q, n = divmod(n, value)
            parts.append(sing if q == 1 else f"{_below_thousand(q)} {plur}")
    if n >= 1000:
        q, n = divmod(n, 1000)
        parts.append(("ein" if q == 1 else _below_thousand(q)) + "tausend")
    if n:
        parts.append(_below_thousand(n))
    return " ".join(parts).replace("tausend ", "tausend")


def year(n):
    """Jahreszahl wie gesprochen: 1984 → neunzehnhundertvierundachtzig, 2007 → zweitausendsieben."""
    if 1100 <= n <= 1999:
        hi, lo = divmod(n, 100)
        return _below_hundred(hi) + "hundert" + (_below_hundred(lo) if lo else "")
    return cardinal(n)


def ordinal_stem(n):
    """Ordnungszahl ohne Endung: 3 → dritte, 14 → vierzehnte, 20 → zwanzigste."""
    if n in _ORD_IRREGULAR:
        return _ORD_IRREGULAR[n]
    if n < 20:
        return _ONES[n] + "te"
    return cardinal(n) + "ste"


_MONTH_NAMES = ["Januar", "Februar", "März", "April", "Mai", "Juni", "Juli", "August", "September", "Oktober",
                "November", "Dezember"]
_MONTHS = ("Januar|Februar|März|April|Mai|Juni|Juli|August|September|Oktober|November|Dezember|Jänner")
_ABBREV = {
    "z. B.": "zum Beispiel", "z.B.": "zum Beispiel", "d. h.": "das heißt", "d.h.": "das heißt",
    "u. a.": "unter anderem", "usw.": "und so weiter", "bzw.": "beziehungsweise", "ca.": "circa",
    "Nr.": "Nummer", "Dr.": "Doktor", "Hr.": "Herr", "Fr.": "Frau", "St.": "Sankt", "Str.": "Straße",
    "km/h": "Kilometer pro Stunde", "km": "Kilometer", "kg": "Kilogramm", "€": "Euro", "DM": "D-Mark",
    "%": " Prozent",
}


_ORDINAL_CONTEXT = {"der", "die", "das", "den", "dem", "des", "am", "im", "zum", "zur", "vom", "beim", "ein", "eine",
                    "einen", "einem", "einer", "sein", "seine", "seinem", "seinen", "ihr", "ihre", "ihrem", "ihren",
                    "unser", "unsere", "unserem", "jeder", "jede", "jedem", "bis", "ab", "seit", "dieser", "diese",
                    "diesem", "diesen"}


def _ordinal_case(prev_word):
    # nach Präposition/Artikel im Dativ/Akkusativ: „am vierzehnten“, sonst „der vierzehnte“
    return "n" if prev_word.lower() in {"am", "im", "zum", "vom", "beim", "dem", "den", "des", "einem", "einen",
                                         "ihrem", "seinem", "unserem", "diesem", "bis", "ab", "seit"} else ""


def normalize_numbers(text):
    """Ziffern in gesprochene Wörter umwandeln (Uhrzeiten, Datumsangaben, Jahre, Ordnungs- und Grundzahlen)."""
    # Uhrzeit 22:15 / 22.15 Uhr
    def _time(m):
        h, mi = int(m.group(1)), int(m.group(2))
        words = f"{cardinal(h) if h != 1 else 'ein'} Uhr"
        return words + (f" {cardinal(mi)}" if mi else "")
    text = re.sub(r"\b(\d{1,2})[:.](\d{2})\s*Uhr\b", _time, text)
    text = re.sub(r"\b(\d{1,2}):(\d{2})\b", _time, text)
    text = re.sub(r"\b(\d{1,2})\s*Uhr\b", lambda m: f"{'ein' if int(m.group(1)) == 1 else cardinal(int(m.group(1)))} Uhr", text)

    # Geldbeträge 3,50 Euro / 3,50 D-Mark → drei Euro fünfzig
    def _money(m):
        units = {"D-Mark": "Mark", "Mark": "Mark", "Euro": "Euro", "Pfennig": "Pfennig"}
        whole, cents, unit = int(m.group(1)), int(m.group(2)), units.get(m.group(3), m.group(3))
        return f"{cardinal(whole) if whole != 1 else 'ein'} {unit}" + (f" {cardinal(cents)}" if cents else "")
    text = re.sub(r"\b(\d+),(\d{2})\s*(D-Mark|Mark|Euro)\b", _money, text)

    # Datum 14.07.1984 → vierzehnten Juli neunzehnhundertvierundachtzig
    def _numdate(m):
        d, mo, y = int(m.group(1)), int(m.group(2)), m.group(3)
        out = f"{ordinal_stem(d)}n " + (_MONTH_NAMES[mo - 1] if 1 <= mo <= 12 else f"{ordinal_stem(mo)}n")
        if y:
            out += " " + year(int(y))
        return out
    text = re.sub(r"\b(\d{1,2})\.(\d{1,2})\.(\d{4})?(?!\d)", _numdate, text)

    # Ordnungszahl vor Monatsnamen oder allgemein „3. Kapitel“
    def _ordinal(m):
        prev, n, after = m.group(1) or "", int(m.group(2)), m.group(3)
        is_month = re.fullmatch(_MONTHS, after) is not None
        if not is_month and prev.strip().lower() not in _ORDINAL_CONTEXT:
            # „Er war 14. Sie …“ – Satzende, keine Ordnungszahl
            return f"{prev}{cardinal(n)}. {after}"
        ending = _ordinal_case(prev.strip())
        return f"{prev}{ordinal_stem(n)}{ending} {after}"
    text = re.sub(rf"(\b\w+\s)?\b(\d{{1,3}})\.\s+({_MONTHS}|[A-ZÄÖÜ][a-zäöüß]+)", _ordinal, text)

    # Jahreszahlen (vierstellig, 1100–2099) – als Jahr gesprochen
    text = re.sub(r"\b(1[1-9]\d\d|20\d\d)\b", lambda m: year(int(m.group(1))), text)
    # Dezimalzahlen 3,5
    text = re.sub(r"\b(\d+),(\d+)\b",
                  lambda m: f"{cardinal(int(m.group(1)))} Komma {' '.join(_ONES[int(c)] for c in m.group(2))}", text)
    # Tausenderpunkte 10.000
    text = re.sub(r"\b(\d{1,3}(?:\.\d{3})+)\b", lambda m: cardinal(int(m.group(1).replace(".", ""))), text)
    # übrige Zahlen
    text = re.sub(r"\b\d+\b", lambda m: cardinal(int(m.group(0))), text)
    return text


def normalize_for_speech(text):
    """Sprechtext vorbereiten: Abkürzungen, Zahlen, typografische Zeichen."""
    text = unicodedata.normalize("NFC", text or "")
    text = re.sub(r"(\w)str\.", r"\1straße", text)
    for k, v in sorted(_ABBREV.items(), key=lambda kv: -len(kv[0])):
        text = text.replace(k, v)
    text = normalize_numbers(text)
    text = text.replace("…", "...")
    text = re.sub(r"\s*[–—]\s*", ", ", text)
    text = re.sub(r"[*_#<>{}\[\]]", "", text)
    text = re.sub(r"\s+", " ", text).strip()
    return text


# MARK: Drehbuch

# Platzhalter aus der Formatbeschreibung, die kleine Modelle wörtlich übernehmen („KENNUNG: …“) – keine Figur
# (gefunden in der App-Abnahme am 17.11.2026 mit Qwen3.5 4B: eine Figur „KENNUNG“ sprach eine ganze Szene)
PLACEHOLDER_SPEAKERS = {"KENNUNG", "FIGUR", "ROLLE", "NAME", "SPRECHER", "SPRECHERIN", "PERSON", "CHARACTER", "SPEAKER"}

CUE_TYPES = {"GERÄUSCH": "sfx", "GERAEUSCH": "sfx", "SFX": "sfx", "ATMO": "atmo", "ATMOSPHÄRE": "atmo",
             "MUSIK": "music", "MUSIC": "music", "PAUSE": "pause", "SZENE": "scene"}
_CUE = re.compile(r"^\s*\[\s*([A-ZÄÖÜa-zäöü]+)\s*:?\s*([^\]]*)\]\s*$")
_LINE = re.compile(r"^\s*\**([A-ZÄÖÜ][A-Za-zÄÖÜäöüß0-9 ._'\-]{0,40}?)\**\s*(?:\(([^)]{1,60})\))?\s*:\s*(.+?)\s*$")


def speaker_key(name):
    """Vergleichsschlüssel für Sprecher: „Frau Meyer“, „FRAU_MEYER“ und „FRAUMEYER“ sind dieselbe Figur."""
    return re.sub(r"[^A-ZÄÖÜ0-9]", "", (name or "").upper().replace("ß", "SS"))


def parse_script(text, known_speakers=None, aliases=None):
    """Drehbuchtext in Elemente zerlegen.

    Liefert eine Liste von Dicts: {"type": "line", "speaker", "emotion", "text"} bzw.
    {"type": "sfx"|"atmo"|"music"|"pause", "de", "en", "seconds"}. known_speakers: Kennungen; aliases: weitere
    Schreibweisen → Kennung (z. B. Namen). Schreibweisen wie „FRAU MEYER“/„FRAU_MEYER“ werden der Kennung „FRAUMEYER“
    zugeordnet. Zeilen ohne Rolle gehen an den Erzähler (kleine Modelle vergessen das Präfix gelegentlich)."""
    items = []
    known = {speaker_key(s): s for s in (known_speakers or [])}
    for k, v in (aliases or {}).items():
        known.setdefault(speaker_key(k), v)
    for raw in (text or "").splitlines():
        line = raw.strip()
        if not line or line.startswith(("```", "---", "#")):
            continue
        m = _CUE.match(line)
        if m:
            kind = CUE_TYPES.get(m.group(1).upper())
            if kind is None:
                continue
            body = m.group(2).strip()
            de, _, en = body.partition("|")
            item = {"type": kind, "de": de.strip(), "en": en.strip() or de.strip()}
            if kind == "pause":
                try:
                    item["seconds"] = max(0.3, min(6.0, float(re.findall(r"[\d.]+", body)[0])))
                except (IndexError, ValueError):
                    item["seconds"] = 1.5
            items.append(item)
            continue
        m = _LINE.match(line)
        if m:
            raw_name = m.group(1).strip().strip("*")
            key = speaker_key(raw_name)
            cue = CUE_TYPES.get(key) or CUE_TYPES.get(raw_name.strip().upper())
            if cue and cue != "scene" and key not in known:
                # „MUSIK: Spannung | tension“ ohne eckige Klammern (kleine Modelle) – ein Hinweis, keine Figur
                # (gefunden in der App-Abnahme am 17.11.2026: eine Figur „MUSIK“ sprach die Musikbeschreibung)
                body = ((m.group(2) + ": ") if m.group(2) else "") + m.group(3)
                de, _, en = body.partition("|")
                item = {"type": cue, "de": de.strip(), "en": en.strip() or de.strip()}
                if cue == "pause":
                    try:
                        item["seconds"] = max(0.3, min(6.0, float(re.findall(r"[\d.]+", body)[0])))
                    except (IndexError, ValueError):
                        item["seconds"] = 1.5
                items.append(item)
                continue
            is_role = key in known or raw_name.replace("_", " ").replace("-", " ").isupper() or known_speakers is None
            if is_role and key:
                if key in PLACEHOLDER_SPEAKERS and key not in known:
                    items.append({"type": "line", "speaker": "ERZÄHLER", "emotion": (m.group(2) or "").strip(),
                                  "text": m.group(3).strip().strip('"„“'), "placeholder": True})
                    continue
                speaker = known.get(key, key)
                items.append({"type": "line", "speaker": speaker, "emotion": (m.group(2) or "").strip(),
                              "text": m.group(3).strip().strip('"„“')})
                continue
        if re.search(r"[A-Za-zÄÖÜäöüß]{3}", line):
            items.append({"type": "line", "speaker": "ERZÄHLER", "emotion": "", "text": line.strip('"„“')})
    return items


def spoken_words(items):
    return sum(len(i["text"].split()) for i in items if i["type"] == "line")


def repetition_ratio(text, n=4):
    """Anteil wiederholter Wort-n-Gramme – hoch = das Modell dreht sich im Kreis."""
    words = re.findall(r"\w+", (text or "").lower())
    grams = [tuple(words[i:i + n]) for i in range(max(0, len(words) - n + 1))]
    if not grams:
        return 0.0
    return round(1 - len(set(grams)) / len(grams), 3)


def sentences(text):
    """Sprechtext in Sätze teilen (für die Sprachausgabe in handlichen Stücken)."""
    parts = re.split(r"(?<=[.!?…])\s+(?=[A-ZÄÖÜ„\"'])", text.strip())
    return [p.strip() for p in parts if p.strip()]


def chunk_text(text, max_chars=220):
    """Lange Absätze an Satzgrenzen in Stücke ≤ max_chars teilen."""
    out, cur = [], ""
    for s in sentences(text):
        if cur and len(cur) + 1 + len(s) > max_chars:
            out.append(cur)
            cur = s
        else:
            cur = f"{cur} {s}".strip()
    if cur:
        out.append(cur)
    return out
