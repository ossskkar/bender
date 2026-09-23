"""Checks for the parts of the flat-face pipeline that can silently go wrong.

    python3 test_flatface.py

Not a framework: these are the three things that broke while building it.
"""
import json, os, sys, tempfile, wave
import numpy as np
from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from make_poc import envelope, eye_boxes, blink, Compositor

HERE = os.path.dirname(os.path.abspath(__file__))
SPRITES = os.path.join(HERE, "sprites")
FACE = os.path.join(HERE, "..", "faces", "arisu.json")


def test_envelope_follows_loudness():
    """A loud half and a silent half must not come back as one level."""
    path = os.path.join(tempfile.mkdtemp(), "t.wav")
    rate = 16000
    loud = (np.sin(np.arange(rate) * 0.1) * 20000).astype(np.int16)
    quiet = np.zeros(rate, np.int16)
    with wave.open(path, "w") as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(rate)
        w.writeframes(np.concatenate([loud, quiet]).tobytes())
    e = envelope(path)
    assert len(e) == 50, len(e)          # 2s at 25fps
    assert e[:25].mean() > 0.9, e[:25].mean()
    assert e[25:].max() < 0.01, e[25:].max()


def test_blink_touches_only_the_eyes():
    """The whole point of the box: a blink must not repaint her mouth."""
    img = Image.open(os.path.join(SPRITES, "neutral.png")).convert("RGB")
    boxes = eye_boxes(img.size, FACE)
    assert len(boxes) == 2, boxes
    for x, y, w, h in boxes:
        assert x >= 0 and y >= 0 and x + w <= img.size[0] and y + h <= img.size[1]
    assert blink(img, boxes, 1.0) is img            # open is a no-op, not a re-encode
    shut = np.array(blink(img, boxes, 0.15), np.int16)
    d = np.abs(np.array(img, np.int16) - shut).max(axis=2)
    assert d.max() > 30, "lids did not move"
    mouth_band = d[int(0.62 * img.size[1]):, :]
    assert mouth_band.max() == 0, f"blink leaked onto the mouth ({mouth_band.max()})"


def test_mouth_boxes_are_the_mouth():
    """If a pose's box grows to the whole face, the overlay stops composing."""
    man = json.load(open(os.path.join(SPRITES, "poses.json")))
    w, h = man["size"]
    for name in ("mouth2", "mouth3", "mouth4"):
        x, y, bw, bh = man["poses"][name]["box"]
        assert bw < 0.6 * w and bh < 0.45 * h, (name, man["poses"][name]["box"])
        assert y > 0.45 * h, (name, "box reaches above the nose")


def test_compositor_speaks_without_disturbing_the_eyes():
    c = Compositor(SPRITES, FACE)
    quiet = np.array(c.frame("neutral", []), np.int16)
    talking = np.array(c.frame("neutral", ["mouth4"]), np.int16)
    d = np.abs(quiet - talking).max(axis=2)
    assert d.max() > 30, "mouth overlay did nothing"
    assert d[:int(0.45 * d.shape[0]), :].max() == 0, "mouth overlay reached her eyes"


if __name__ == "__main__":
    for name, fn in sorted(globals().items()):
        if name.startswith("test_"):
            fn(); print("ok", name)
