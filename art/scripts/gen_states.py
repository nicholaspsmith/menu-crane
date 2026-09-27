#!/usr/bin/env python3
"""Action-state variations of Mendoza (d1-clean), edited from the reference image."""
import base64, io, sys
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
from PIL import Image

sys.path.insert(0, str(Path.home() / "Code/widgets.nicksmith.software/art"))
import gen_icons as g  # noqa: E402

OUT = Path(__file__).parent / "mascot"
im = Image.open(OUT / "d1-clean-1024.png").convert("RGBA")
bg = Image.new("RGBA", im.size, "white"); bg.alpha_composite(im)
buf = io.BytesIO(); bg.convert("RGB").save(buf, "PNG")
REF = base64.b64encode(buf.getvalue()).decode()

COMMON = ("Edit this exact image. Keep the same character, the same framing, size and position, the same thick "
          "black outlines and flat colours, the same plain white background with no border or tile. Change ONLY "
          "this: ")

STATES = {
    "state-open": COMMON + "the clamshell bucket hanging from the beak is lowered on a longer cable and its two "
                           "halves are swung wide OPEN, ready to scoop; both pupils look down at the bucket.",
    "state-grab": COMMON + "the bucket is snapped firmly SHUT and a small yellow smiley-face emoji pokes out of the "
                           "top of it; the crane's eyes are happy upward-curved closed crescents, pleased with itself.",
    "state-miss": COMMON + "the bucket hangs open and EMPTY, and the crane looks puzzled: pupils looking in "
                           "different directions and one small blue sweat drop beside the head.",
    "state-clip": COMMON + "the closed bucket is carrying a small white sheet of paper (a clipboard clipping) "
                           "sticking out of its top; the pupils look toward the paper.",
}


def run(item):
    name, prompt = item
    body = {"contents": [{"parts": [{"inlineData": {"mimeType": "image/png", "data": REF}}, {"text": prompt}]}],
            "generationConfig": {"responseModalities": ["IMAGE"]}}
    resp = g._post(f"{g.API}/models/{MODEL}:generateContent?key={KEY}", body)
    for cand in resp.get("candidates", []):
        for part in cand.get("content", {}).get("parts", []):
            data = part.get("inlineData", {}).get("data")
            if data:
                raw = base64.b64decode(data)
                (OUT / f"{name}-raw.png").write_bytes(raw)
                g.postprocess(raw, size=512, pad_ratio=0.01).save(OUT / f"{name}.png")
                return f"ok {name}"
    return f"FAIL {name}: {str(resp)[:200]}"


if __name__ == "__main__":
    KEY = g._key(); MODEL = g.pick_model(KEY)
    only = sys.argv[1:]
    with ThreadPoolExecutor(4) as ex:
        for r in ex.map(run, [(k, v) for k, v in STATES.items() if not only or k in only]):
            print(r)
