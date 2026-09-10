#!/usr/bin/env python3
"""Print a portrait with a coordinate grid over it, to measure landmarks.

    python3 faces/grid.py chopper       # writes faces/portraits/chopper-grid.png

Open the result, read the eye and mouth centres off the grid as fractions, and
put them in `faces/<id>.json`. Guessing them is how you get a face that blinks
next to its own eye.
"""
import sys
from pathlib import Path
from PIL import Image, ImageDraw

HERE = Path(__file__).resolve().parent


def main(cid):
    hits = [p for p in (HERE / "portraits").glob(cid + ".*")
            if p.suffix.lower() in (".png", ".jpg", ".jpeg", ".webp")
            and not p.stem.endswith("-grid")]
    if not hits:
        raise SystemExit("no faces/portraits/%s.*" % cid)
    im = Image.open(hits[0]).convert("RGB")
    w, h = im.size
    # Doubled, because a landmark read off a 300px thumbnail is a landmark
    # measured to the nearest two percent.
    out = im.resize((w * 2, h * 2), Image.LANCZOS)
    d = ImageDraw.Draw(out)
    for i in range(1, 20):
        f = i / 20
        x, y = int(f * w * 2), int(f * h * 2)
        d.line([(x, 0), (x, h * 2)], fill=(0, 255, 0))
        d.line([(0, y), (w * 2, y)], fill=(0, 255, 0))
        d.text((x + 2, 4), "%.2f" % f, fill=(0, 255, 0))
        d.text((4, y + 2), "%.2f" % f, fill=(0, 255, 0))
    dest = hits[0].with_name(cid + "-grid.png")
    out.save(dest)
    print(dest)


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else "arisu")
