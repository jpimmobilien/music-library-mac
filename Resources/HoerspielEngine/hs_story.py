"""KI-Hörspiel – Geschichten mit einem lokalen Sprachmodell schreiben.

Ablauf (auch für lange Produktionen): 1. Konzept mit Figuren und Kapitel-/Szenenplan (JSON) → 2. jede Szene
einzeln als Drehbuch im Zeilenformat (siehe hs_text) mit Zusammenfassung und Stand der bisherigen Handlung und den
geplanten Spuren der Szene → 3. Prüfung (Länge, Wiederholungen, unbekannte Sprecher) mit gezielter Nachbesserung →
4. Lektorat der ganzen Geschichte (Widersprüche, ungeklärte Rätsel) und gezielte Überarbeitung betroffener Szenen.
Eine Szene neu zu schreiben ändert die anderen nicht.

Sprachmodell-Anbindungen:
- MLXChat: mlx-lm im selben Prozess (die App auf dem Mac)
- OpenAIChat: lokaler OpenAI-kompatibler Server auf 127.0.0.1 (nur Prüfstände, z. B. llama.cpp unter Linux)
"""

import json
import math
import re
import time

from hs_text import parse_script, repetition_ratio, speaker_key, spoken_words

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

LANGUAGES = {"de": "Deutsch", "en": "Englisch", "fr": "Französisch", "es": "Spanisch", "it": "Italienisch"}


def language_rule(language):
    """Anweisung zur Ausgabesprache (leer für Deutsch). Kennungen, Tags und JSON-Schlüssel bleiben wie vorgegeben."""
    if not language or language == "de":
        return ""
    name = LANGUAGES.get(language, language)
    return (f"\nSPRACHE: Schreibe alle Titel, Beschreibungen, Erzähltexte und Dialoge auf {name} (natürlich, wie von "
            f"Muttersprachlern). Kennungen in GROSSBUCHSTABEN, die Kennung ERZÄHLER, die Tags [ATMO], [GERÄUSCH], "
            f"[MUSIK], [PAUSE] und die JSON-Schlüssel bleiben genau wie vorgegeben.\n")


ROOM_WORDS = "draußen, wald, zimmer, küche, büro, auto, keller, treppenhaus, halle, bahnhofshalle, kirche, telefon"


def concept_prompt(prompt, minutes, mode, chapters, scenes_per_chapter, user_characters=None, style=None, language="de"):
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
{hint}{language_rule(language)}

Anforderungen:
- {roles}
- {chapters} Kapitel mit je {scenes_per_chapter} Szenen; eine zusammenhängende Handlung mit Spannungsbogen,
  Verdächtigen bzw. Hindernissen, Wendung und Auflösung.
- Für jede Figur eine kurze Beschreibung und eine Stimmbeschreibung (deutsch) sowie dieselbe Stimmbeschreibung
  auf Englisch für ein Stimmmodell ("voice_en": Alter, Geschlecht, Tonhöhe, Klangfarbe, Tempo, Wirkung).
- Kennung ("id") jeder Figur: ein Wort in GROSSBUCHSTABEN, z. B. "LENA". Der Erzähler hat die Kennung "ERZÄHLER".
- Für jede Szene: Ort, Raumklang (eines von: {ROOM_WORDS}), beteiligte Figuren, Inhalt in 2–3 Sätzen und eine
  englische Beschreibung der Hintergrundgeräusche ("atmo_en").
- "spuren": die Hinweise, Gegenstände und falschen Fährten, die die Auflösung tragen – je mit der Szene
  ("szene": laufende Nummer ab 1 über alle Kapitel), in der sie zum ersten Mal vorkommen.
- "aufloesung": erklärt JEDES rätselhafte Element der Handlung schlüssig (wer, was, warum, wie) – nichts bleibt
  ungeklärt, nichts widerspricht den Spuren.

Antworte NUR mit JSON in genau dieser Form:
{{"titel": "", "untertitel": "", "logline": "", "epoche_ort": "", "ton": "",
 "figuren": [{{"id": "ERZÄHLER", "name": "Erzähler", "rolle": "Erzähler", "alter": 45, "geschlecht": "m",
   "beschreibung": "", "stimme": "", "voice_en": ""}}],
 "kapitel": [{{"nr": 1, "titel": "", "szenen": [{{"nr": 1, "titel": "", "ort": "", "raum": "draußen",
   "figuren": ["ERZÄHLER"], "inhalt": "", "atmo_en": ""}}]}}],
 "spuren": [{{"spur": "", "szene": 1, "bedeutung": ""}}],
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


PROSE_RULES = """Format – Hörbuch: Jede Zeile beginnt mit „ERZÄHLER:“ und enthält einen Absatz Erzähltext.
Wörtliche Rede steht in Anführungszeichen innerhalb der Erzählung („…“, sagte Mira). Keine Geräusch- oder
Musikhinweise. Für einen deutlichen Einschnitt darf eine Zeile [PAUSE: 1.5] stehen.

Beispiel:
ERZÄHLER: Der alte Bahnhof lag still in der Mittagshitze. Jonas blieb stehen und deutete auf das Stellwerk.
ERZÄHLER: „Siehst du das Licht?“, flüsterte er. Mira schüttelte den Kopf. „Das ist seit Jahren verlassen.“"""

NARRATION_STYLES = {
    "klassisch": "klassisch und ruhig erzählt, klare Sätze",
    "spannend": "spannend, mit kurzen Sätzen an den Höhepunkten",
    "humorvoll": "humorvoll und augenzwinkernd",
    "märchenhaft": "märchenhaft und bildreich",
    "sachlich": "sachlich und knapp",
}


def _clues_for(concept, number):
    """Spuren, die laut Konzept in dieser Szene zum ersten Mal vorkommen (leer, wenn keine)."""
    if not number:
        return ""
    clues = []
    for c in concept.get("spuren") or []:
        try:
            if int(c.get("szene", 0)) == number and c.get("spur"):
                clues.append(f"- {c['spur']}" + (f" (Bedeutung, nicht verraten: {c['bedeutung']})" if c.get("bedeutung") else ""))
        except (TypeError, ValueError, AttributeError):
            continue
    return ("In dieser Szene einführen:\n" + "\n".join(clues) + "\n") if clues else ""


def scene_prompt(concept, chapter, scene, story_so_far, previous_tail, target_words, is_first, is_last, scene_number=0):
    mode = concept.get("_mode", "hoerspiel")
    figs = "\n".join(f"- {f['id']}: {f.get('name', '')}, {f.get('rolle', '')}, {f.get('beschreibung', '')}"
                     for f in concept.get("figuren", []))
    head = f"""{'Hörbuch' if mode == 'hoerbuch' else 'Hörspiel'} „{concept.get('titel', '')}“ – {concept.get('logline', '')}
Epoche und Ort: {concept.get('epoche_ort', '')}. Ton: {concept.get('ton', '')}.

Figuren (Kennung: Beschreibung):
{figs}

Geplante Auflösung (nur zur Orientierung – nicht vorwegnehmen): {concept.get('aufloesung', '') or 'offen'}
{_clues_for(concept, scene_number)}
Bisherige Handlung (mit Stand am Ende jeder Szene – daran anknüpfen, nichts widersprechen):
{story_so_far or '(Dies ist der Anfang.)'}

{('Letzte Zeilen der vorigen Szene:' + chr(10) + previous_tail) if previous_tail else ''}

Schreibe jetzt Kapitel {chapter.get('nr')} „{chapter.get('titel', '')}“, Szene {scene.get('nr')} „{scene.get('titel', '')}“.
Ort: {scene.get('ort', '')}. Beteiligte: {', '.join(scene.get('figuren', []))}.
Inhalt: {scene.get('inhalt', '')}
"""
    if mode == "hoerbuch":
        style = NARRATION_STYLES.get(concept.get("_style", ""), concept.get("_style") or "lebendig erzählt")
        ending = ("Dies ist der letzte Abschnitt: Führe die Handlung zu einem runden Ende.\n" if is_last else "")
        return head + f"""
Länge: etwa {target_words} Wörter. Erzählstil: {style}. Natürliche Dialoge in wörtlicher Rede, jede Figur mit eigener
Art zu sprechen. Keine Wiederholungen, keine Zusammenfassung am Ende.
{ending}
{PROSE_RULES}

{language_rule(concept.get("_language"))}
Schreibe nur den Text dieses Abschnitts."""
    intro = "Beginne mit [MUSIK: Titelmusik | ...] und einer kurzen Einleitung des Erzählers.\n" if is_first else ""
    outro = ("Dies ist die letzte Szene: Löse den Fall vollständig auf und ende mit einem kurzen Schlusswort des "
             "Erzählers und [MUSIK: Abspann | ...].\n" if is_last else "")
    return head + f"""
Länge: etwa {target_words} gesprochene Wörter. Überwiegend Dialog (mindestens zwei Drittel), der Erzähler nur
für kurze Übergänge. Lebendige, natürliche Sprache, jede Figur mit eigener Art zu sprechen. Keine Wiederholungen,
keine Zusammenfassungen am Ende. Verwende nur die Kennungen aus der Figurenliste.
{intro}{outro}
{FORMAT_RULES}

{language_rule(concept.get("_language"))}
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
    def rnd(x):  # kaufmännisch runden wie Swift (.rounded()), nicht wie Pythons round()
        return int(math.floor(x + 0.5))
    scenes_total = max(3, rnd(minutes / 1.7))
    chapters = max(1, rnd(minutes / 12))
    per_chapter = max(3, rnd(scenes_total / chapters))
    return chapters, per_chapter


class StoryWriter:
    def __init__(self, llm, log=print):
        self.llm = llm
        self.log = log

    def _ask(self, messages, **kw):
        return self.llm.chat(messages, **kw)

    def concept(self, prompt, minutes=10, mode="hoerspiel", user_characters=None, style=None, narration=None, language="de"):
        chapters, per_chapter = plan_size(minutes)
        msgs = [{"role": "system", "content": SYSTEM},
                {"role": "user", "content": concept_prompt(prompt, minutes, mode, chapters, per_chapter,
                                                           user_characters, style, language)}]
        last_error = None
        for attempt in range(3):
            raw = self._ask(msgs, max_tokens=4096, temperature=0.7 if attempt == 0 else 0.4)
            try:
                c = extract_json(raw)
                self._check_concept(c)
                c["_minutes"] = minutes
                c["_mode"] = mode
                c["_language"] = language or "de"
                if narration:
                    c["_style"] = narration
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
            f["id"] = speaker_key(str(f.get("id") or f.get("name", ""))) or "FIGUR"
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
        aliases = {f.get("name", ""): f["id"] for f in concept["figuren"] if f.get("name")}
        msgs = [{"role": "system", "content": SYSTEM},
                {"role": "user", "content": scene_prompt(concept, chapter, scene, "\n".join(summaries), previous_tail,
                                                         target_words, index == 0, index == len(scenes) - 1,
                                                         index + 1)}]
        best = None
        for attempt in range(3):
            text = self._ask(msgs, max_tokens=min(4096, int(target_words * 3.2) + 400),
                             temperature=0.85 if attempt == 0 else 0.75, repetition_penalty=1.08)
            items = parse_script(text, ids, aliases)
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
                items2 = parse_script(text2, ids, aliases)
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

    def rewrite_line(self, concept, scene_text, speaker, line, hint=""):
        """Eine einzelne Replik neu formulieren – Rest der Szene bleibt unverändert."""
        fig = next((f for f in concept.get("figuren", []) if f.get("id") == speaker), {})
        msgs = [{"role": "system", "content": SYSTEM},
                {"role": "user", "content": f"""Hörspiel „{concept.get('titel', '')}“. Figur {speaker}: {fig.get('beschreibung', '')}

Szene:
{scene_text[:6000]}

Formuliere nur diese eine Replik von {speaker} neu{(' – ' + hint) if hint else ''}:
„{line}“

Sie muss an derselben Stelle in die Szene passen, denselben Inhalt transportieren, natürlich klingen und in
derselben Sprache wie die Szene stehen.
Antworte nur mit dem neuen Satz, ohne Kennung und ohne Anführungszeichen."""}]
        out = self._ask(msgs, max_tokens=300, temperature=0.8).strip()
        out = re.sub(r"^[A-ZÄÖÜ]{2,}\s*(\([^)]*\))?\s*:\s*", "", out).strip().strip('"„“')
        return out.splitlines()[0].strip() if out else line

    def review(self, concept, scenes):
        """Lektorat der ganzen Geschichte: echte Widersprüche und Logiklücken finden (Gegenstände, Orte, Wissen der
        Figuren, Namen, Verwandtschaft, ungeklärte Rätsel, Auflösung passt nicht zu den Spuren).
        scenes: [{"title", "text"}]. Ergebnis: [{"szene": Nummer ab 1, "problem": "", "korrektur": ""}]."""
        body = "\n\n".join(f"### Szene {i + 1}: {sc.get('title', '')}\n{sc.get('text', '')}" for i, sc in enumerate(scenes))
        figs = "\n".join(f"- {f['id']}: {f.get('name', '')}, {f.get('rolle', '')}, {f.get('beschreibung', '')}"
                         for f in concept.get("figuren", []))
        msgs = [{"role": "system", "content": "Du bist eine erfahrene Hörspiel-Lektorin. Du prüfst Logik und "
                                              "Kontinuität, nicht den Stil."},
                {"role": "user", "content": f"""Hörspiel „{concept.get('titel', '')}“. Figuren:
{figs}

Geplante Auflösung: {concept.get('aufloesung', '')}

Drehbuch:
{body[:60000]}

Finde echte Widersprüche und Logikfehler: Gegenstände, die ohne Erklärung den Ort oder Besitzer wechseln; Figuren,
die etwas wissen, was sie nicht wissen können; falsche Namen, Rollen oder Verwandtschaften; Rätsel oder Spuren, die
am Ende nicht aufgelöst werden; eine Auflösung, die den Spuren widerspricht oder nicht überzeugt; Anrede (du/Sie),
die ohne Grund wechselt. Keine Stilkritik, keine Geschmacksfragen. Höchstens 5 Punkte, die wichtigsten zuerst.

Antworte NUR mit JSON (Beschreibungen auf Deutsch): {{"probleme": [{{"szene": 1, "problem": "", "korrektur": ""}}]}}
Wenn alles schlüssig ist: {{"probleme": []}}"""}]
        try:
            data = extract_json(self._ask(msgs, max_tokens=1500, temperature=0.2))
        except (ValueError, ChatError) as e:
            self.log(f"[Geschichte] Lektorat ohne Ergebnis ({e})")
            return []
        out = []
        for p in data.get("probleme") or []:
            try:
                n = int(p.get("szene", 0))
            except (TypeError, ValueError):
                continue
            if 1 <= n <= len(scenes) and (p.get("problem") or "").strip():
                out.append({"szene": n, "problem": p["problem"].strip(), "korrektur": (p.get("korrektur") or "").strip()})
        return out[:5]

    def revise_scene(self, concept, index, scene_text, problems, target_words):
        """Eine Szene gezielt korrigieren: alles bleibt, nur die genannten Probleme werden behoben. Gibt die neue
        Szene zurück oder None, wenn die Überarbeitung schlechter ist (zu kurz, Wiederholungen, fremde Sprecher)."""
        ids = [f["id"] for f in concept["figuren"]]
        aliases = {f.get("name", ""): f["id"] for f in concept["figuren"] if f.get("name")}
        fixes = "\n".join(f"- {p['problem']}" + (f" → {p['korrektur']}" if p.get("korrektur") else "") for p in problems)
        rules = PROSE_RULES if concept.get("_mode") == "hoerbuch" else FORMAT_RULES
        msgs = [{"role": "system", "content": SYSTEM},
                {"role": "user", "content": f"""Hörspiel „{concept.get('titel', '')}“, Szene {index + 1}.
Geplante Auflösung: {concept.get('aufloesung', '')}

Bisherige Fassung der Szene:
{scene_text[:8000]}

Überarbeite die Szene so, dass diese Probleme behoben sind:
{fixes}

Alles andere bleibt so nah wie möglich am Original (Ablauf, Länge, Figuren, Geräusche, Ton, Sprache).
{rules}{language_rule(concept.get("_language"))}

Gib nur das vollständige, überarbeitete Drehbuch der Szene aus."""}]
        text = self._ask(msgs, max_tokens=min(4096, int(target_words * 3.6) + 600), temperature=0.5, repetition_penalty=1.05)
        items = parse_script(text, ids, aliases)
        old_words = spoken_words(parse_script(scene_text, ids, aliases))
        words = spoken_words(items)
        rep = repetition_ratio(" ".join(i["text"] for i in items if i["type"] == "line"))
        unknown = sorted({i["speaker"] for i in items if i["type"] == "line" and i["speaker"] not in ids})
        if words < 0.7 * old_words or rep >= 0.2 or unknown:
            self.log(f"[Geschichte] Überarbeitung Szene {index + 1} verworfen ({words}/{old_words} Wörter, "
                     f"Wiederholungen {rep}, fremde Sprecher {unknown})")
            return None
        return {"text": text, "items": items, "words": words, "repetition": rep, "unknown_speakers": []}

    def summarize(self, scene_text):
        msgs = [{"role": "system", "content": "Du fasst Hörspielszenen sachlich zusammen."},
                {"role": "user", "content": "Fasse diese Szene in höchstens drei Sätzen zusammen: wer, was, welche "
                                            "neue Information oder Spur – und der Stand am Ende (wo sind die "
                                            "Figuren und wichtige Gegenstände, wer weiß was).\n\n" + scene_text[:6000]}]
        return self._ask(msgs, max_tokens=260, temperature=0.3).strip().replace("\n", " ")

    def write(self, prompt, minutes=10, mode="hoerspiel", user_characters=None, style=None, progress=None, language="de"):
        t0 = time.time()
        concept = self.concept(prompt, minutes, mode, user_characters, style, language=language)
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
        review = {"problems": [], "revised": []}
        if len(out) > 1:
            if progress:
                progress(0.97, "Lektorat …")
            tr = time.time()
            problems = self.review(concept, out)
            review["problems"] = problems
            self.log(f"[Geschichte] Lektorat: {len(problems)} Probleme ({round(time.time() - tr)} s)")
            for p in problems:
                self.log(f"[Geschichte]   Szene {p['szene']}: {p['problem']} → {p['korrektur']}")
            for n in sorted({p["szene"] for p in problems})[:3]:
                sc = out[n - 1]
                new = self.revise_scene(concept, n - 1, sc["text"], [p for p in problems if p["szene"] == n], per_scene)
                if new:
                    sc["previous_text"] = sc["text"]
                    sc.update(new)
                    sc["summary"] = self.summarize(sc["text"])
                    review["revised"].append(n)
                    self.log(f"[Geschichte] Szene {n} überarbeitet ({new['words']} Wörter)")
            review["seconds"] = round(time.time() - tr, 1)
        words = sum(s["words"] for s in out)
        return {"concept": concept, "scenes": out, "words": words, "review": review,
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
