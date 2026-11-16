#!/usr/bin/env python3
"""Hörspiel-Probe 2: Eine vollständige Geschichte mit einem lokalen Sprachmodell schreiben.

Backends: HS_LLM_URL (lokaler OpenAI-kompatibler Server, z. B. llama.cpp unter Linux) oder HS_LLM_MLX
(mlx-lm-Modell auf Apple Silicon). Ergebnis: <out>/story.json (Konzept, Szenen, Drehbuch-Elemente, Messwerte)
und <out>/drehbuch.md.

Aufruf: python probe_story.py <out> [Minuten]
"""

import json
import os
import sys
import time
import traceback

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from probe_common import Report, log  # noqa: E402

import hs_story as S  # noqa: E402

OUT = os.path.abspath(sys.argv[1] if len(sys.argv) > 1 else "out")
MINUTES = float(sys.argv[2]) if len(sys.argv) > 2 else 10
os.makedirs(OUT, exist_ok=True)
LABEL = os.environ.get("HS_LLM_LABEL", "story")

# Beispiel aus dem Auftrag des Nutzers
PROMPT = os.environ.get("HS_STORY_PROMPT") or (
    "Erstelle ein spannendes deutsches Jugendkrimi-Hörspiel, das im Sommer 1984 spielt. Vier Jugendliche geraten in "
    "einen mysteriösen Kriminalfall rund um einen verlassenen Bahnhof. Es gibt mehrere Verdächtige, humorvolle "
    "Dialoge, überraschende Wendungen und ein spannendes Finale. Die Produktion soll sich an der Atmosphäre "
    "klassischer deutscher Jugendkrimi-Hörspiele der 1980er-Jahre orientieren.")

report = Report(os.path.join(OUT, f"{LABEL}-probe.json"))
try:
    if os.environ.get("HS_LLM_URL"):
        llm = S.OpenAIChat(os.environ["HS_LLM_URL"], name=os.environ.get("HS_LLM_NAME", "local"), log=log)
    else:
        llm = S.MLXChat(os.environ["HS_LLM_MLX"], log=log)
    report.step("Sprachmodell bereit", model=llm.name, load_seconds=llm.load_seconds)
    t0 = time.time()
    story = S.StoryWriter(llm, log=log).write(PROMPT, minutes=MINUTES)
    story["prompt"] = PROMPT
    with open(os.path.join(OUT, f"{LABEL}.json"), "w") as f:
        json.dump(story, f, indent=2, ensure_ascii=False)
    with open(os.path.join(OUT, f"{LABEL}-drehbuch.md"), "w") as f:
        f.write(S.script_text(story))
    st = story["llm_stats"]
    report.step("Geschichte fertig", seconds=round(time.time() - t0, 1), words=story["words"],
                estimated_minutes=story["estimated_minutes"], scenes=len(story["scenes"]),
                figures=len(story["concept"]["figuren"]),
                tokens_per_second=round(st["completion_tokens"] / max(st["seconds"], 1e-6), 1), llm_stats=st)
except Exception as e:  # noqa: BLE001
    report.step("Geschichte Fehler", error=repr(e), trace=traceback.format_exc()[-3000:])
    sys.exit(1)
