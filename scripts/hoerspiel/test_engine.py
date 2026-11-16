#!/usr/bin/env python3
"""Tests der Hörspiel-Engine ohne Modelle (laufen auch unter Linux): Text, Drehbuch, Audio, Mischung, Geschichte mit
Ersatz-Sprachmodell, Prozessprotokoll.  Aufruf: python3 scripts/hoerspiel/test_engine.py"""

import json
import os
import subprocess
import sys
import tempfile
import unittest

ENGINE = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", "Resources", "HoerspielEngine"))
sys.path.insert(0, ENGINE)

import numpy as np  # noqa: E402

import hs_audio as A  # noqa: E402
import hs_produce as P  # noqa: E402
import hs_story as S  # noqa: E402
import hs_text as T  # noqa: E402


class TextTests(unittest.TestCase):
    def test_numbers(self):
        n = T.normalize_for_speech
        self.assertEqual(n("Am 14. Juli 1984 um 22:15 Uhr."), "Am vierzehnten Juli neunzehnhundertvierundachtzig um zweiundzwanzig Uhr fünfzehn.")
        self.assertEqual(n("Er war 14. Sie war 13 Jahre alt."), "Er war vierzehn. Sie war dreizehn Jahre alt.")
        self.assertEqual(n("Es kostete 3,50 DM."), "Es kostete drei Mark fünfzig.")
        self.assertEqual(n("Lindenstr. 1 – z. B. im 2. Stock"), "Lindenstraße eins, zum Beispiel im zweiten Stock")
        self.assertEqual(n("Am 03.08.1985"), "Am dritten August neunzehnhundertfünfundachtzig")
        self.assertEqual(T.cardinal(2_000_001), "zwei Millionen eins")

    def test_parse(self):
        items = T.parse_script("""[ATMO: Wind | wind]
ERZÄHLER: Es war still.
LENA (flüsternd): Hörst du das?
[GERÄUSCH: Tür | door]
Ein Satz ohne Sprecher.
[PAUSE: 9]""", ["ERZÄHLER", "LENA"])
        self.assertEqual([i["type"] for i in items], ["atmo", "line", "line", "sfx", "line", "pause"])
        self.assertEqual(items[2]["emotion"], "flüsternd")
        self.assertEqual(items[4]["speaker"], "ERZÄHLER")
        self.assertEqual(items[5]["seconds"], 6.0)
        self.assertGreater(T.repetition_ratio("a b c d " * 5), 0.5)

    def test_speaker_variants(self):
        # beobachtet im Prüfstand: Gemma schrieb „FRAU MEYER“ und „FRAU_MEYER“ für die Kennung „FRAUMEYER“
        items = T.parse_script("FRAU_MEYER (atemlos): Herr Krause!\nFRAU MEYER: Weg!\nHerr Krause: Ruhe!\nMira sagte: Komm.",
                               ["ERZÄHLER", "HERRKRAUSE", "FRAUMEYER"], {"Herr Krause": "HERRKRAUSE"})
        self.assertEqual([i["speaker"] for i in items], ["FRAUMEYER", "FRAUMEYER", "HERRKRAUSE", "ERZÄHLER"])
        self.assertEqual(items[0]["text"], "Herr Krause!")


class AudioTests(unittest.TestCase):
    def test_loudness_reference(self):
        sr = 48000
        t = np.arange(sr * 10) / sr
        x = (10 ** (-23 / 20) * np.sin(2 * np.pi * 1000 * t)).astype(np.float32)
        self.assertAlmostEqual(A.loudness_lufs(np.stack([x, x]), sr), -23.0, delta=0.1)  # EBU Tech 3341, Fall 1
        y = A.normalize_lufs(np.stack([x, x]), sr, -16)
        self.assertAlmostEqual(A.loudness_lufs(y, sr), -16.0, delta=0.2)
        self.assertLessEqual(A.peak_db(y), -0.99)

    def test_wav_roundtrip_and_tools(self):
        sr = 48000
        x = (np.random.default_rng(1).standard_normal((2, sr)) * 0.1).astype(np.float32)
        with tempfile.TemporaryDirectory() as d:
            p = A.write_wav(os.path.join(d, "a.wav"), x, sr)
            y, ysr = A.load_audio(p)
            self.assertEqual(ysr, sr)
            self.assertLess(float(np.max(np.abs(y - x))), 1e-5)
        self.assertEqual(A.fit_length(x, sr, 3.5).shape[1], int(3.5 * sr))
        self.assertEqual(A.room(x[0], sr, "Bahnhofshalle").shape, (2, sr))
        self.assertEqual(A.retro(x, sr, 1.0).shape, x.shape)
        g = A.duck_gain(np.concatenate([np.zeros(sr), x[0], np.zeros(sr)]), sr, depth_db=-12)
        self.assertAlmostEqual(float(g[sr // 2]), 1.0, places=3)
        self.assertAlmostEqual(float(g[int(1.8 * sr)]), A.gain(-12), places=3)


class StoryTests(unittest.TestCase):
    class Mock:
        name = "mock"

        def __init__(self):
            self.n = 0
            self.stats = {"prompt_tokens": 0, "completion_tokens": 0, "seconds": 0}

        def chat(self, messages, **kw):
            self.n += 1
            u = messages[-1]["content"]
            if self.n == 1:
                return "kein json {"
            if self.n == 2:
                return json.dumps({"titel": "Test", "figuren": [{"id": "Lena", "name": "Lena"}],
                                   "kapitel": [{"nr": 1, "titel": "A", "szenen": [{"nr": 1, "titel": "S1"}, {"nr": 2, "titel": "S2"}]}]})
            if "Finde echte Widersprüche" in u:
                return "Hier: " + json.dumps({"probleme": [{"szene": 2, "problem": "Die Kiste verschwindet", "korrektur": "Lena trägt sie"},
                                                           {"szene": 9, "problem": "gibt es nicht"}]})
            if "Überarbeite die Szene" in u:
                return ("ERZÄHLER: Still. Lena trägt die schwere Kiste unter dem Arm.\nLENA (leise): Hörst du das? Die Kiste klappert.\n"
                        "PETRA: Ich bin neu hier und helfe tragen.\n" + "\n".join(f"LENA: Zeile {i} geht weiter {i * 7}." for i in range(8)))
            if "zusammen" in u:
                return "Lena hört etwas."
            if "Setze die Szene" in u:
                return f"LENA: Neue Zeile Nummer {self.n} mit frischen Worten {self.n * 3}."
            return "ERZÄHLER: Still.\nLENA (leise): Hörst du das?\nPETRA: Ich bin neu hier."

    def test_write_with_retry_continuation_and_new_figure(self):
        story = S.StoryWriter(self.Mock(), log=lambda *a: None).write("Krimi", minutes=2)
        self.assertEqual(story["concept"]["titel"], "Test")
        ids = [f["id"] for f in story["concept"]["figuren"]]
        self.assertIn("ERZÄHLER", ids)
        self.assertIn("PETRA", ids, "spontane Nebenfigur wird ergänzt")
        self.assertTrue(all(s["continued"] >= 1 for s in story["scenes"]))
        self.assertEqual([p["szene"] for p in story["review"]["problems"]], [2], "Lektorat: nur gültige Szenen")
        self.assertEqual(story["review"]["revised"], [2])
        self.assertIn("Kiste", story["scenes"][1]["text"])
        self.assertIn("previous_text", story["scenes"][1], "alte Fassung bleibt erhalten")
        self.assertNotIn("previous_text", story["scenes"][0])
        self.assertEqual(S.plan_size(10), (1, 6))
        self.assertEqual(S.plan_size(30), (3, 6), "kaufmännisch gerundet wie Swift")

    def test_revision_rejected_when_worse(self):
        class Short(self.Mock):
            def chat(self, messages, **kw):
                return "LENA: Kurz."
        w = S.StoryWriter(Short(), log=lambda *a: None)
        c = {"titel": "T", "figuren": [{"id": "ERZÄHLER"}, {"id": "LENA", "name": "Lena"}]}
        old = "\n".join(f"LENA: Eine lange Zeile Nummer {i} mit Inhalt {i * 3}." for i in range(10))
        self.assertIsNone(w.revise_scene(c, 0, old, [{"problem": "x", "korrektur": "y"}], 100))

    def test_clues_in_scene_prompt(self):
        c = {"titel": "T", "figuren": [], "kapitel": [{"nr": 1, "szenen": [{"nr": 1}, {"nr": 2}]}],
             "spuren": [{"spur": "Messingsiegel", "szene": 2, "bedeutung": "Wappen der Familie"}, {"spur": "x", "szene": "?"}]}
        p2 = S.scene_prompt(c, c["kapitel"][0], c["kapitel"][0]["szenen"][1], "", "", 200, False, False, 2)
        p1 = S.scene_prompt(c, c["kapitel"][0], c["kapitel"][0]["szenen"][0], "", "", 200, True, False, 1)
        self.assertIn("Messingsiegel", p2)
        self.assertNotIn("Messingsiegel", p1)

    def test_language(self):
        de = S.concept_prompt("Krimi", 10, "hoerspiel", 1, 6)
        en = S.concept_prompt("Krimi", 10, "hoerspiel", 1, 6, language="en")
        self.assertNotIn("SPRACHE:", de)
        self.assertIn("auf Englisch", en)
        c = {"titel": "T", "_language": "fr", "figuren": [], "kapitel": [{"nr": 1, "szenen": [{"nr": 1}]}]}
        self.assertIn("auf Französisch", S.scene_prompt(c, c["kapitel"][0], c["kapitel"][0]["szenen"][0], "", "", 200, True, True, 1))

    def test_audiobook_prompt(self):
        c = {"titel": "T", "_mode": "hoerbuch", "_style": "spannend", "figuren": [], "kapitel": [{"nr": 1, "szenen": [{"nr": 1}]}]}
        p = S.scene_prompt(c, c["kapitel"][0], c["kapitel"][0]["szenen"][0], "", "", 300, True, True)
        self.assertIn("Format – Hörbuch", p)
        self.assertNotIn("[GERÄUSCH", p)


class VoiceTextTests(unittest.TestCase):
    def test_prepare_text_and_reference(self):
        # hs_voice ohne mlx importierbar? (mlx wird erst beim Laden eines Modells gebraucht)
        try:
            import hs_voice as V
        except ImportError as e:
            self.skipTest(f"hs_voice nicht importierbar: {e}")
        self.assertIn("vierzehnten", V.prepare_text("Am 14. Juli war es heiß.", "de"))
        self.assertEqual(V.prepare_text("On  July 14,\n1984.", "en"), "On July 14, 1984.")
        self.assertTrue(V.reference_text("fr").startswith("Je ne sais pas"))
        self.assertEqual(V.reference_text("xx"), V.REFERENCE_TEXT)


class MixTests(unittest.TestCase):
    def test_assemble(self):
        sr = P.SR
        tone = lambda f, d: (0.2 * np.sin(2 * np.pi * f * np.arange(int(sr * d)) / sr)).astype(np.float32)  # noqa: E731
        script = "[MUSIK: Titel | theme]\n[ATMO: Wind | wind]\nERZÄHLER: Es war still.\nLENA: Hallo?\n[GERÄUSCH: Tür | door]\nLENA: Da!"
        story = {"concept": {"figuren": [{"id": "ERZÄHLER"}, {"id": "LENA"}]},
                 "scenes": [{"title": "A", "room": "halle", "items": T.parse_script(script, ["ERZÄHLER", "LENA"])}]}
        with tempfile.TemporaryDirectory() as d:
            voice = {ln["key"]: A.write_wav(os.path.join(d, ln["key"] + ".wav"), tone(200, 1.2), sr) for ln in P.line_list(story)}
            sfx = {k: A.write_wav(os.path.join(d, k + ".wav"), tone(900, 3), sr) for k in ("wind", "door")}
            _, pieces = P.music_plan(story)
            music = {k: A.write_wav(os.path.join(d, k + ".wav"), np.stack([tone(330, v["seconds"])] * 2), sr) for k, v in pieces.items()}
            master, stems, tl, metrics, chapters = P.assemble(story, voice, sfx, music, retro_amount=1.0)
        self.assertAlmostEqual(metrics["loudness_lufs"], -16.0, delta=0.3)
        self.assertLessEqual(metrics["peak_dbfs"], -0.99)
        self.assertEqual(len(chapters), 1)
        self.assertIn("Sprecher LENA", stems)
        self.assertIn("abspann", pieces)


class ProtocolTests(unittest.TestCase):
    def test_engine_protocol(self):
        p = subprocess.run([sys.executable, os.path.join(ENGINE, "engine.py")], input='{"id":"1","cmd":"status"}\n{"id":"2","cmd":"x"}\n{"id":"3","cmd":"quit"}\n',
                           capture_output=True, text=True, timeout=60)
        lines = [json.loads(x) for x in p.stdout.splitlines()]
        self.assertEqual(lines[0]["event"], "ready")
        self.assertEqual(lines[1]["event"], "result")
        self.assertEqual(lines[2]["event"], "error")
        self.assertEqual(lines[3]["event"], "result")


if __name__ == "__main__":
    unittest.main(verbosity=1)
