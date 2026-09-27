#!/usr/bin/env python3
"""Icon-sized variations of mascot #4, using it as a reference image."""
import base64, sys
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

sys.path.insert(0, str(Path.home() / "Code/widgets.nicksmith.software/art"))
import gen_icons as g  # noqa: E402

HERE = Path(__file__).parent
OUT = HERE / "mascot"
REF = base64.b64encode((OUT / "icon-b-raw.png").read_bytes()).decode()

COMMON = (
    "Flat cartoon app-icon illustration in the style of Matt Groening: very thick bold black outlines, flat "
    "colours, no gradients, simple shapes. Character: a friendly goofy red-crowned crane seen from the side, "
    "facing right: a round grey head with a red cap on top, two HUGE round white eyes touching each other with "
    "small black dot pupils, a long pale tan beak with a gentle smile line, a grey neck with a white stripe. A "
    "small yellow clamshell grab bucket (the kind that hangs from a construction crane) hangs from the beak on a "
    "grey ring. No text. Plain solid pure white background (#FFFFFF), no tile, frame or shadow. Framing: "
)

VARIANTS = {
    "d1": COMMON + "extreme close-up. The head alone fills almost the whole square: the two eyes are HUGE and "
                   "take up the entire upper-left half; the red cap is cut off by the top edge; the beak runs "
                   "out past the right edge; the bucket fills the bottom-right quarter; only a stub of neck at "
                   "the bottom-left.",
    "d2": COMMON + "compact and round: a very short stubby beak with the bucket hanging directly under the chin, "
                   "so the head and bucket together form one big round blob that fills the square; almost no "
                   "neck, no body.",
    "d3": COMMON + "strict diagonal: the red cap in the top-left corner, the eyes just below it, the beak "
                   "pointing straight at the bottom-right corner, and a big bucket sitting in the bottom-right "
                   "corner. Neck not visible.",
    "d4": COMMON + "a bold simplified sticker version for a tiny icon: very few shapes (white eyes, red cap, grey "
                   "head, tan beak, one solid yellow bucket with a single dividing line), each shape large, "
                   "outlines extra thick, head in the upper-left, bucket lower-right, both large.",
}


def run(item):
    name, prompt = item
    body = {
        "contents": [{"parts": [{"text": prompt}]}],
        "generationConfig": {"responseModalities": ["IMAGE"]},
    }
    resp = g._post(f"{g.API}/models/{MODEL}:generateContent?key={KEY}", body)
    for cand in resp.get("candidates", []):
        for part in cand.get("content", {}).get("parts", []):
            data = part.get("inlineData", {}).get("data")
            if data:
                raw = base64.b64decode(data)
                (OUT / f"{name}-raw.png").write_bytes(raw)
                g.postprocess(raw, size=512, pad_ratio=0.02).save(OUT / f"{name}.png")
                return f"ok {name}"
    return f"FAIL {name}: {str(resp)[:200]}"


if __name__ == "__main__":
    KEY = g._key()
    MODEL = g.pick_model(KEY)
    only = sys.argv[1:]
    items = [(k, v) for k, v in VARIANTS.items() if not only or k in only]
    with ThreadPoolExecutor(4) as ex:
        for r in ex.map(run, items):
            print(r)
