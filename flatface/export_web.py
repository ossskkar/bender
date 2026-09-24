#!/usr/bin/env python3
"""Shrink a sprite set into what the browser loads.

A set is ~40MB of 1086x1448 PNGs. The page draws her at phone size, so half
that and JPEG is indistinguishable and ~20x smaller. poses.json goes along
with the boxes scaled, because the page masks by the same boxes.

  python3 export_web.py --sprites sprites-ayame --out ../../lain/arisu/flat/ayame
"""
import argparse, json, os
from PIL import Image

SCALE = 0.5
QUALITY = 88

a = argparse.ArgumentParser()
a.add_argument("--sprites", required=True)
a.add_argument("--out", required=True)
a.add_argument("--face-json", dest="face_json", required=True)
args = a.parse_args()

os.makedirs(args.out, exist_ok=True)
man = json.load(open(os.path.join(args.sprites, "poses.json")))

for f in sorted(os.listdir(args.sprites)):
    if not f.endswith(".png"):
        continue
    im = Image.open(os.path.join(args.sprites, f)).convert("RGB")
    w, h = int(im.width * SCALE), int(im.height * SCALE)
    # ponytail: whole frame per pose, not just its box -- 2MB total on a tailnet
    # page. Crop overlays to their boxes if the first load ever feels slow.
    im.resize((w, h), Image.LANCZOS).save(
        os.path.join(args.out, f[:-4] + ".jpg"), quality=QUALITY, optimize=True)

man["size"] = [int(man["size"][0] * SCALE), int(man["size"][1] * SCALE)]
for p in man["poses"].values():
    if p.get("box"):
        p["box"] = [int(v * SCALE) for v in p["box"]]
man["face"] = json.load(open(args.face_json))   # eyes, for the geometric blink
json.dump(man, open(os.path.join(args.out, "poses.json"), "w"), indent=1)

print(args.out, sum(os.path.getsize(os.path.join(args.out, f))
                    for f in os.listdir(args.out)) // 1024, "KB")
