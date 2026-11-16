"""KI-Hörspiel – Geschichten mit einem lokalen Sprachmodell schreiben.

Ablauf (auch für lange Produktionen): 1. Konzept mit Figuren und Kapitel-/Szenenplan (JSON) → 2. jede Szene
einzeln als Drehbuch im Zeilenformat (siehe hs_text) mit Zusammenfassung der bisherigen Handlung → 3. Prüfung
(Länge, Wiederholungen, unbekannte Sprecher) mit gezielter Nachbesserung. Eine Szene neu zu schreiben ändert
die anderen nicht.

Sprachmodell-Anbindungen:
- MLXChat: mlx-lm im selben Prozess (die App auf dem Mac)
- OpenAIChat: lokaler OpenAI-kompatibler Server auf 127.0.0.1 (nur Prüfstände, z. B. llama.cpp unter Linux)
"""

import json
import re
import time

from hs_text import parse_script, repetition_ratio, spoken_words

WORDS_PER_MINUTE = 140   # Hörspiel-Sprechtempo inkl. kurzer Pausen
SPEECH_SHARE = 0.85      # Rest: Musik, Geräusche, Übergänge


class ChatError(RuntimeError):
    pass


def _strip_thinking(text):
    text = re.sub(r"<think>.*?</think>", "", text or "", flags=re.S)
    text = re.sub(r"<\|channel\|>analysis.*?<\|channel\|>final<\|message\|>", "", text, flags=re.S)
    return text.strip()


class MLXChat:
    """Sprachmodell mit mlx-lm (Apple Silicon)."""

    def __init__(self, model_path, log=print):
        from mlx_lm import load
        t0 = time.time()
        self.model, self.tokenizer = load(model_path)
        self.name = model_path
        self.load_seconds = round(time.time() - t0, 1)
        self.log = log
        self.stats = {"prompt_tokens": 0, "completion_tokens": 0, "seconds": 0.0}

    def chat(self, messages, max_tokens=2048, temperature=0.8, top_p=0.95, repetition_penalty=1.05):
        from mlx_lm import generate
        from mlx_lm.sample_utils import make_logits_processors, make_sampler
        kwargs = {}
        try:
            prompt = self.tokenizer.apply_chat_template(messages, add_generation_prompt=True, tokenize=False,
                                                        enable_thinking=False)
        except TypeError:
            prompt = self.tokenizer.apply_chat_template(messages, add_generation_prompt=True, tokenize=False)
        t0 = time.time()
        out = generate(self.model, self.tokenizer, prompt=prompt, max_tokens=max_tokens,
                       sampler=make_sampler(temp=temperature, top_p=top_p),
                       logits_processors=make_logits_processors(repetition_penalty=repetition_penalty), **kwargs)
        self.stats["seconds"] += time.time() - t0
        self.stats["prompt_tokens"] += len(self.tokenizer.encode(prompt))
        self.stats["completion_tokens"] += len(self.tokenizer.encode(out))
        return _strip_thinking(out)


class OpenAIChat:
    """Lokaler OpenAI-kompatibler Server (nur 127.0.0.1)."""

    def __init__(self, base_url="http://127.0.0.1:8080", name="local", log=print):
        if not re.match(r"^http://(127\.0\.0\.1|localhost)(:\d+)?", base_url):
            raise ValueError("Nur lokale Server sind erlaubt")
        self.base = base_url.rstrip("/")
        self.name = name
        self.log = log
        self.load_seconds = 0.0
        self.stats = {"prompt_tokens": 0, "completion_tokens": 0, "seconds": 0.0}

    def chat(self, messages, max_tokens=2048, temperature=0.8, top_p=0.95, repetition_penalty=1.05):
        import urllib.request
        body = {"messages": messages, "max_tokens": max_tokens, "temperature": temperature, "top_p": top_p,
                "repeat_penalty": repetition_penalty, "chat_template_kwargs": {"enable_thinking": False}}
        req = urllib.request.Request(self.base + "/v1/chat/completions", data=json.dumps(body).encode(),
                                     headers={"Content-Type": "application/json"})
        t0 = time.time()
        with urllib.request.urlopen(req, timeout=3600) as r:
            data = json.loads(r.read())
        self.stats["seconds"] += time.time() - t0
        usage = data.get("usage") or {}
        self.stats["prompt_tokens"] += usage.get("prompt_tokens", 0)
        self.stats["completion_tokens"] += usage.get("completion_tokens", 0)
        msg = data["choices"][0]["message"]
        return _strip_thinking(msg.get("content") or "")


# MARK: JSON aus Modellantworten

def extract_json(text):
    """Erstes JSON-Objekt aus einer Modellantwort lesen (Codeblöcke, typografische Anführungszeichen, Kommas)."""
    t = re.sub(r"```(?:json)?", "", text or "")
    start = t.find("{")
    if start < 0:
        raise ValueError("Kein JSON-Objekt in der Antwort")
    depth, end, in_str, esc = 0, None, False, False
    for i in range(start, len(t)):
        c = t[i]
        if in_str:
            if esc:
                esc = False
            elif c == "\\":
                esc = True
            elif c == '"':
                in_str = False
            continue
        if c == '"':
            in_str = True
        elif c == "{":
            depth += 1
        elif c == "}":
            depth -= 1
            if depth == 0:
                end = i + 1
                break
    raw = t[start:end] if end else t[start:]
    for candidate in (raw, re.sub(r",\s*([}\]])", r"\1", raw)):
        try:
            return json.loads(candidate)
        except json.JSONDecodeError:
            continue
    raise ValueError("JSON unvollständig oder fehlerhaft")


# MARK: Eingaben

SYSTEM = (
    "Du bist eine erfahrene deutsche Hörspielautorin. Du schreibst eigenständige, neue Geschichten mit eigenen "
    "Figuren, eigenen Namen, eigenen Orten und eigenen Dialogen. Du übernimmst niemals Figuren, Namen, Handlungen "
    "oder Texte aus bestehenden Hörspielreihen, Büchern oder Filmen (zum Beispiel nicht TKKG, Die drei ???, "
    "Fünf Freunde, Benjamin Blümchen). Wenn der Nutzer eine Reihe als Vorbild nennt, übernimmst du nur allgemeine "
    "Eigenschaften: Epoche, Atmosphäre, Genre, Erzähltempo, Art der Figurenkonstellation, Dialogstil. "
    "Du schreibst natürliches, lebendiges Deutsch mit korrekter Rechtschreibung."
)

ROOM_WORDS = "draußen, wald, zimmer, küche, büro, auto, keller, treppenhaus, halle, bahnhofshalle, kirche, telefon"


def concept_prompt(prompt, minutes, mode, chapters, scenes_per_chapter, user_characters=None, style=None):
    hint = ""
    if user_characters:
        hint += "\nVorgaben des Nutzers zu Figuren (unbedingt übernehmen):\n" + "\n".join(f"- {c}" for c in user_characters)
    if style:
        hint += f"\nStilvorgaben aus einer analysierten Referenz (nur allgemeine Merkmale): {style}"
    roles = ("einen Erzähler und 4 bis 7 Sprechrollen" if mode == "hoerspiel"
             else "einen Erzähler; Figuren sprechen nur in wörtlicher Rede, die der Erzähler vorliest")
    return f"""Entwickle das Konzept für ein {'Hörspiel' if mode == 'hoerspiel' else 'Hörbuch'} von etwa {minutes} Minuten.

Idee des Nutzers:
{prompt}
{hint}

Anforderungen:
- {roles}
- {chapters} Kapitel mit je {scenes_per_chapter} Szenen; eine zusammenhängende Handlung mit Spannungsbogen,
  Verdächtigen bzw. Hindernissen, Wendung und Auflösung.
- Für jede Figur eine kurze Beschreibung und eine Stimmbeschreibung (deutsch) sowie dieselbe Stimmbeschreibung
  auf Englisch für ein Stimmmodell ("voice_en": Alter, Geschlecht, Tonhöhe, Klangfarbe, Tempo, Wirkung).
- Kennung ("id") jeder Figur: ein Wort in GROSSBUCHSTABEN, z. B. "LENA". Der Erzähler hat die Kennung "ERZÄHLER".
- Für jede Szene: Ort, Raumklang (eines von: {ROOM_WORDS}), beteiligte Figuren, Inhalt in 2–3 Sätzen und eine
  englische Beschreibung der Hintergrundgeräusche ("atmo_en").

Antworte NUR mit JSON in genau dieser Form:
{{"titel": "", "untertitel": "", "logline": "", "epoche_ort": "", "ton": "",
 "figuren": [{{"id": "ERZÄHLER", "name": "Erzähler", "rolle": "Erzähler", "alter": 45, "geschlecht": "m",
   "beschreibung": "", "stimme": "", "voice_en": ""}}],
 "kapitel": [{{"nr": 1, "titel": "", "szenen": [{{"nr": 1, "titel": "", "ort": "", "raum": "draußen",
   "figuren": ["ERZÄHLER"], "inhalt": "", "atmo_en": ""}}]}}],
 "aufloesung": ""}}"""


FORMAT_RULES = """Format – jede Zeile genau eine der folgenden Formen, sonst nichts:
ERZÄHLER: kurzer erzählender Text (Gegenwart oder Präteritum, bildhaft, knapp)
KENNUNG: gesprochener Dialog der Figur
KENNUNG (Gefühl): Dialog mit Regieanweisung zum Tonfall, z. B. (flüsternd), (aufgeregt), (ängstlich), (wütend)
[ATMO: deutsche Beschreibung | english sound description]   – Hintergrundgeräusch der Szene, einmal am Anfang
[GERÄUSCH: deutsche Beschreibung | english sound effect]      – einzelnes Geräusch an der passenden Stelle
[MUSIK: Spannung | english music description]                 – nur für Übergänge oder Höhepunkte
[PAUSE: 1.5]                                                   – kurze Stille in Sekunden

Beispiel:
[ATMO: Wind über einem leeren Bahnsteig | wind over an empty railway platform, distant crows]
ERZÄHLER: Der alte Bahnhof lag still in der Mittagshitze.
JONAS (flüsternd): Da hinten. Siehst du das Licht im Stellwerk?
MIRA: Das ist doch seit Jahren verlassen.
[GERÄUSCH: Eine schwere Tür quietscht | heavy metal door creaking open]
JONAS: Jetzt nicht mehr."""


def scene_prompt(concept, chapter, scene, story_so_far, previous_tail, target_words, is_first, is_last):
    figs = "\n".join(f"- {f['id']}: {f.get('name', '')}, {f.get('rolle', '')}, {f.get('beschreibung', '')}"
                     for f in concept.get("figuren", []))
    intro = "Beginne mit [MUSIK: Titelmusik | ...] und einer kurzen Einleitung des Erzählers.\n" if is_first else ""
    outro = ("Dies ist die letzte Szene: Löse den Fall vollständig auf und ende mit einem kurzen Schlusswort des "
             "Erzählers und [MUSIK: Abspann | ...].\n" if is_last else "")
    return f"""Hörspiel „{concept.get('titel', '')}“ – {concept.get('logline', '')}
Epoche und Ort: {concept.get('epoche_ort', '')}. Ton: {concept.get('ton', '')}.

Figuren (Kennung: Beschreibung):
{figs}

Bisherige Handlung:
{story_so_far or '(Dies ist der Anfang.)'}

{('Letzte Zeilen der vorigen Szene:' + chr(10) + previous_tail) if previous_tail else ''}

Schreibe jetzt Kapitel {chapter.get('nr')} „{chapter.get('titel', '')}“, Szene {scene.get('nr')} „{scene.get('titel', '')}“.
Ort: {scene.get('ort', '')}. Beteiligte: {', '.join(scene.get('figuren', []))}.
Inhalt: {scene.get('inhalt', '')}

Länge: etwa {target_words} gesprochene Wörter. Überwiegend Dialog (mindestens zwei Drittel), der Erzähler nur
für kurze Übergänge. Lebendige, natürliche Sprache, jede Figur mit eigener Art zu sprechen. Keine Wiederholungen,
keine Zusammenfassungen am Ende. Verwende nur die Kennungen aus der Figurenliste.
{intro}{outro}
{FORMAT_RULES}

Schreibe nur das Drehbuch der Szene."""


# MARK: Ablauf

_FEMALE_END = ("A", "E", "I", "Y", "IN", "INE", "ETTE")


def added_figure(name):
    """Vom Modell spontan eingeführte Nebenfigur – mit allgemeiner Stimme, als „ergänzt“ markiert."""
    female = name.upper().endswith(_FEMALE_END) and not name.upper().endswith(("UWE", "OVE"))
    return {"id": name, "name": name.title(), "rolle": "Nebenfigur", "alter": 40, "geschlecht": "w" if female else "m",
            "beschreibung": "vom Sprachmodell während des Schreibens ergänzt", "stimme": "",
            "voice_en": ("An adult German woman, natural mid-range voice, clear diction" if female else
                         "An adult German man, natural mid-range voice, clear diction"), "ergaenzt": True}


def plan_size(minutes):
    """Kapitel und Szenen für eine Ziel-Länge."""
    scenes_total = max(3, round(minutes / 1.7))
    chapters = max(1, round(minutes / 12))
    per_chapter = max(3, round(scenes_total / chapters))
    return chapters, per_chapter


class StoryWriter:
    def __init__(self, llm, log=print):
        self.llm = llm
        self.log = log

    def _ask(self, messages, **kw):
        return self.llm.chat(messages, **kw)

    def concept(self, prompt, minutes=10, mode="hoerspiel", user_characters=None, style=None):
        chapters, per_chapter = plan_size(minutes)
        msgs = [{"role": "system", "content": SYSTEM},
                {"role": "user", "content": concept_prompt(prompt, minutes, mode, chapters, per_chapter,
                                                           user_characters, style)}]
        last_error = None
        for attempt in range(3):
            raw = self._ask(msgs, max_tokens=4096, temperature=0.7 if attempt == 0 else 0.4)
            try:
                c = extract_json(raw)
                self._check_concept(c)
                c["_minutes"] = minutes
                c["_mode"] = mode
                return c
            except (ValueError, KeyError, TypeError) as e:
                last_error = e
                self.log(f"[Geschichte] Konzept unbrauchbar ({e}) – neuer Versuch")
                msgs = msgs[:2] + [{"role": "assistant", "content": raw[:6000]},
                                   {"role": "user", "content": f"Das war kein gültiges JSON in der verlangten Form "
                                                               f"({e}). Gib NUR das vollständige JSON aus."}]
        raise ChatError(f"Kein brauchbares Konzept: {last_error}")

    @staticmethod
    def _check_concept(c):
        if not c.get("figuren") or not c.get("kapitel"):
            raise ValueError("Figuren oder Kapitel fehlen")
        ids = set()
        for f in c["figuren"]:
            f["id"] = re.sub(r"[^A-ZÄÖÜ0-9]", "", str(f.get("id") or f.get("name", "")).upper()) or "FIGUR"
            ids.add(f["id"])
        if "ERZÄHLER" not in ids:
            c["figuren"].insert(0, {"id": "ERZÄHLER", "name": "Erzähler", "rolle": "Erzähler", "alter": 45,
                                    "geschlecht": "m", "beschreibung": "", "stimme": "ruhige, warme Erzählerstimme",
                                    "voice_en": "A calm, warm, clear male narrator voice in his forties, measured pace"})
        for k in c["kapitel"]:
            if not k.get("szenen"):
                raise ValueError(f"Kapitel {k.get('nr')} ohne Szenen")

    def scene_list(self, concept):
        return [(k, s) for k in concept["kapitel"] for s in k["szenen"]]

    def write_scene(self, concept, index, summaries, previous_tail, target_words):
        scenes = self.scene_list(concept)
        chapter, scene = scenes[index]
        ids = [f["id"] for f in concept["figuren"]]
        msgs = [{"role": "system", "content": SYSTEM},
                {"role": "user", "content": scene_prompt(concept, chapter, scene, "\n".join(summaries), previous_tail,
                                                         target_words, index == 0, index == len(scenes) - 1)}]
        best = None
        for attempt in range(3):
            text = self._ask(msgs, max_tokens=min(4096, int(target_words * 3.2) + 400),
                             temperature=0.85 if attempt == 0 else 0.75, repetition_penalty=1.08)
            items = parse_script(text, ids)
            rep = repetition_ratio(" ".join(i["text"] for i in items if i["type"] == "line"))
            if rep >= 0.2:
                self.log(f"[Geschichte] Szene {index + 1}: Wiederholungen ({rep}) – neuer Versuch")
                if best is None:
                    best = (text, items, rep, attempt + 1, 0)
                continue
            # zu kurz: fortsetzen statt neu schreiben (erhält, was schon gut ist)
            continued = 0
            while spoken_words(items) < 0.8 * target_words and continued < 3:
                continued += 1
                words = spoken_words(items)
                self.log(f"[Geschichte] Szene {index + 1}: {words} von {target_words} Wörtern – wird fortgesetzt")
                more = self._ask(msgs + [{"role": "assistant", "content": text},
                                         {"role": "user", "content": f"Setze die Szene im selben Format fort (noch "
                                          f"etwa {target_words - words} Wörter), ohne etwas zu wiederholen. Nur neue Zeilen."}],
                                 max_tokens=min(3000, int((target_words - words) * 3.2) + 300), temperature=0.8)
                text2 = text.rstrip() + "\n" + more.strip()
                items2 = parse_script(text2, ids)
                rep2 = repetition_ratio(" ".join(i["text"] for i in items2 if i["type"] == "line"))
                if rep2 >= 0.2 or spoken_words(items2) <= words:
                    break
                text, items, rep = text2, items2, rep2
            best = (text, items, rep, attempt + 1, continued)
            break
        text, items, rep, attempts, continued = best
        unknown = sorted({i["speaker"] for i in items if i["type"] == "line" and i["speaker"] not in ids})
        score = {"words": spoken_words(items), "repetition": rep, "unknown_speakers": unknown,
                 "attempts": attempts, "continued": continued}
        return {"chapter": chapter.get("nr"), "scene": scene.get("nr"), "title": scene.get("titel", ""),
                "room": scene.get("raum", ""), "atmo_en": scene.get("atmo_en", ""), "text": text, "items": items,
                **score}

    def summarize(self, scene_text):
        msgs = [{"role": "system", "content": "Du fasst Hörspielszenen sachlich zusammen."},
                {"role": "user", "content": "Fasse diese Szene in zwei Sätzen zusammen (Wer, was, welche neue "
                                            "Information oder Spur):\n\n" + scene_text[:6000]}]
        return self._ask(msgs, max_tokens=200, temperature=0.3).strip().replace("\n", " ")

    def write(self, prompt, minutes=10, mode="hoerspiel", user_characters=None, style=None, progress=None):
        t0 = time.time()
        concept = self.concept(prompt, minutes, mode, user_characters, style)
        scenes = self.scene_list(concept)
        target_total = int(minutes * WORDS_PER_MINUTE * SPEECH_SHARE)
        per_scene = max(80, target_total // len(scenes))
        self.log(f"[Geschichte] Konzept „{concept.get('titel')}“: {len(concept['figuren'])} Figuren, "
                 f"{len(scenes)} Szenen, je ca. {per_scene} Wörter ({round(time.time() - t0)} s)")
        out, summaries, tail = [], [], ""
        for idx in range(len(scenes)):
            if progress:
                progress(idx / len(scenes), f"Szene {idx + 1} von {len(scenes)}")
            ts = time.time()
            sc = self.write_scene(concept, idx, summaries, tail, per_scene)
            for name in sc["unknown_speakers"]:
                concept["figuren"].append(added_figure(name))
                self.log(f"[Geschichte] Neue Nebenfigur vom Modell: {name} (Stimme wird allgemein angelegt)")
            sc["seconds"] = round(time.time() - ts, 1)
            summary = self.summarize(sc["text"])
            sc["summary"] = summary
            summaries.append(f"Szene {idx + 1}: {summary}")
            lines = [ln for ln in sc["text"].splitlines() if ln.strip()]
            tail = "\n".join(lines[-6:])
            out.append(sc)
            self.log(f"[Geschichte] Szene {idx + 1}/{len(scenes)} „{sc['title']}“: {sc['words']} Wörter, "
                     f"Wiederholungen {sc['repetition']}, {sc['seconds']} s")
        words = sum(s["words"] for s in out)
        return {"concept": concept, "scenes": out, "words": words,
                "estimated_minutes": round(words / (WORDS_PER_MINUTE * SPEECH_SHARE), 1),
                "seconds": round(time.time() - t0, 1), "llm": getattr(self.llm, "name", "?"),
                "llm_stats": dict(self.llm.stats)}


def script_text(story):
    """Vollständiges Drehbuch als lesbarer Text."""
    c = story["concept"]
    parts = [f"# {c.get('titel', '')}", c.get("untertitel", ""), "", c.get("logline", ""), "",
             "## Figuren"] + [f"- {f['id']} – {f.get('name', '')}: {f.get('beschreibung', '')} "
                              f"(Stimme: {f.get('stimme', '')})" for f in c.get("figuren", [])]
    for s in story["scenes"]:
        parts += ["", f"## Kapitel {s['chapter']}, Szene {s['scene']}: {s['title']}", "", s["text"].strip()]
    return "\n".join(parts) + "\n"
