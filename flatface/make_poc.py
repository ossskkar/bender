#!/usr/bin/env python3
"""Composite the sprite set into the proof-of-concept clip.

Nothing here is a neural net -- the expensive work happened in make_sprites.py.
This is just image compositing at 25fps: a base pose, the eye box swapped for a
blink, the mouth box swapped for whichever openness the audio is at. It is the
same thing the web page will do at runtime, which is the point: if this looks
right, the live avatar looks right.

  python3 make_poc.py --sprites sprites --audio poc.wav --out arisu_poc.mp4
"""
import argparse, json, os, subprocess, tempfile, wave
import numpy as np
from PIL import Image, ImageDraw, ImageFilter

FPS = 25
SPEECH_AT = 4.0      # seconds into the clip that her voice starts
FEATHER = 7          # px of blur on the overlay mask; hides the box edge


def envelope(wav_path, fps=FPS):
    """Per-frame 0..1 loudness, normalised to the clip's own peak.

    Same shape as the browser's analyser output (see lain arisu-lipsync.js):
    what matters for a mouth is the gaps between syllables surviving, so this
    is RMS with no smoothing beyond the frame window itself.
    """
    with wave.open(wav_path) as w:
        n, sw, ch, rate = w.getnframes(), w.getsampwidth(), w.getnchannels(), w.getframerate()
        raw = np.frombuffer(w.readframes(n), dtype={1: np.int8, 2: np.int16, 4: np.int32}[sw])
    if ch > 1:
        raw = raw.reshape(-1, ch).mean(axis=1)
    x = raw.astype(np.float32) / np.iinfo(np.int16).max
    step = rate / fps
    out = [float(np.sqrt((x[int(i * step):int((i + 1) * step)] ** 2).mean() + 1e-9))
           for i in range(int(len(x) / step))]
    out = np.array(out)
    return out / max(out.max(), 1e-6)


def feathered(box, size):
    m = Image.new("L", size, 0)
    ImageDraw.Draw(m).rectangle([box[0], box[1], box[0] + box[2], box[1] + box[3]], fill=255)
    return m.filter(ImageFilter.GaussianBlur(FEATHER))


def eye_boxes(size, face_json):
    """The two eye boxes, from the landmarks measured for this portrait.

    faces/<id>.json already carries eyeL/eyeR as fractions of the frame for the
    hologram renderer, so this reuses them and adds eyeBox: how wide and tall the
    blink box is, in the same fractions. Three attempts at finding the eyes
    automatically are in the Backlog -- a gaze diff finds the iris but not the
    eye, and a shut-eye probe smears over half the cheek. Measuring two points
    per portrait, once, is smaller and it is right.
    """
    f = json.load(open(face_json))
    w, h = size
    bw, bh = [c * s / 2 for c, s in zip(f.get("eyeBox", [0.176, 0.09]), (w, h))]
    return [[int(f[k][0] * w - bw), int(f[k][1] * h - bh), int(2 * bw), int(2 * bh)]
            for k in ("eyeL", "eyeR")]


def blink(img, boxes, k):
    """Close the lids by squashing each eye box down onto the lower lash line.

    LivePortrait's own eye retargeting was tried first and rejected: on a face
    with anime eyes it smears the iris into a rainbow instead of lowering a lid.
    This moves only pixels that are already in the artwork. The gap the eye
    leaves behind is filled with the cheek strip from below it, flipped -- which
    on a cel-shaded face lands her lower lashes above the closing eye and reads
    as the drawn upper lash line. k is 1 open, 0 shut.
    """
    if k >= 0.99:
        return img
    out = img.copy()
    for (x, y, w, h) in boxes:
        nh = max(2, int(round(h * k)))
        gap = h - nh
        eye = img.crop((x, y, x + w, y + h)).resize((w, nh), Image.LANCZOS)
        fill = img.crop((x, y + h, x + w, y + h + gap)).transpose(Image.FLIP_TOP_BOTTOM)
        # Tone-matching this strip to what it covers was tried and reverted: the
        # region it replaces contains her lashes and eyeshadow, so matching its
        # mean turns the lid into a grey bar. The cheek tone as-is is closer.
        patch = Image.new("RGB", (w, h))
        patch.paste(fill, (0, 0))
        patch.paste(eye, (0, gap))
        # An ellipse, not a rectangle: the corners of an eye are skin, and a
        # straight edge there is the one thing that reads as a pasted box.
        m = Image.new("L", (w, h), 0)
        ImageDraw.Draw(m).ellipse([-w * 0.08, -h * 0.10, w * 1.08, h * 1.02], fill=255)
        out.paste(patch, (x, y), m.filter(ImageFilter.GaussianBlur(5)))
    return out


class Compositor:
    def __init__(self, d, face_json):
        self.man = json.load(open(os.path.join(d, "poses.json")))
        self.img = {p: Image.open(os.path.join(d, f"{p}.png")).convert("RGB")
                    for p in list(self.man["poses"]) + ["neutral"]
                    if os.path.exists(os.path.join(d, f"{p}.png"))}
        self.size = self.img["neutral"].size
        self.masks = {p: feathered(v["box"], self.size)
                      for p, v in self.man["poses"].items() if v["box"]}
        self.eyes = eye_boxes(self.size, face_json)

    def frame(self, base="neutral", overlays=(), lids=1.0):
        out = self.img[base].copy()
        for p in overlays:
            if p and p in self.masks:
                out.paste(self.img[p], (0, 0), self.masks[p])
        return blink(out, self.eyes, lids)


def hologram(img):
    """The signal-face look from faces/renderer.js, as a filter on a finished frame.

    Same idea as the renderer: contours emit and flat fill only glows faintly, so
    she reads as a volume rather than a poster. Red and blue are sampled either
    side of green for the chromatic split, and the projection is interlaced in a
    three-line cycle. Constants lifted from rasterHologram so the clip and the
    live renderer are the same character.
    """
    g = np.asarray(img.convert("L"), np.float32) / 255.0
    soft = np.asarray(Image.fromarray((g * 255).astype(np.uint8))
                      .filter(ImageFilter.GaussianBlur(1.4)), np.float32) / 255.0
    edge = np.clip(np.abs(g - soft) * 12.0, 0, 1)         # contours
    v = np.clip(edge * 1.05 + g * 0.60, 0, 1)   # 0.60, not the renderer 0.20: flat cel fill emits almost nothing at 0.20
    vr = np.roll(v, -1, axis=1)                            # chromatic split
    vb = np.roll(v, 1, axis=1)
    rows = np.array([1.0, 0.66, 0.42])[np.arange(v.shape[0]) % 3][:, None]
    out = np.stack([vr * rows * 120, v * rows * 235, vb * rows * 255], axis=2)
    a = np.clip(np.maximum(np.maximum(v, vr), vb), 0, 1)[:, :, None]
    out = out * (0.25 + a * 0.75)                          # over black
    lit = Image.fromarray(np.clip(out, 0, 255).astype(np.uint8))
    bloom = lit.filter(ImageFilter.GaussianBlur(3))
    return Image.fromarray(np.clip(
        np.asarray(lit, np.float32) + np.asarray(bloom, np.float32) * 0.55,
        0, 255).astype(np.uint8))


def script(env, n_frames, have_blink_sprites=False):
    """(base, [overlays]) per frame. The sequence Oscar asked to see."""
    mouths = ["mouth0", "mouth1", "mouth2", "mouth3", "mouth4"]
    blinks = [0.9, 3.6, 5.6, 7.4, 9.1]          # seconds a blink starts
    plan = []
    for i in range(n_frames):
        t = i / FPS
        base, ov = "neutral", []
        if 1.6 <= t < 2.1:   ov.append("gaze_right")
        elif 2.1 <= t < 2.6: ov.append("gaze_left")
        if 2.8 <= t < 3.9:   base = "curious"
        if 9.3 <= t:         base = "smile"
        # A blink is four frames at 25fps: down, shut, and two coming back up.
        lids = 1.0
        for b in blinks:
            f = (t - b) * FPS
            if 0 <= f < 4:
                if have_blink_sprites:
                    ov.append(["blink_half", "blink_shut", "blink_shut", "blink_half"][int(f)])
                else:
                    # Geometric fallback never reaches 0: a fully squashed eye is
                    # where the seams show, and at 40ms nobody sees it.
                    lids = [0.55, 0.12, 0.30, 0.70][int(f)]
        k = int(t * FPS - SPEECH_AT * FPS)
        if 0 <= k < len(env):
            ov.append(mouths[min(4, int(env[k] * 4.6))])  # 4.6: measured on a real say(1) clip, spreads the ladder instead of pinning it open
        plan.append((base, ov, lids))
    return plan


if __name__ == "__main__":
    a = argparse.ArgumentParser()
    a.add_argument("--sprites", default="sprites")
    a.add_argument("--audio", required=True)
    a.add_argument("--out", default="arisu_poc.mp4")
    a.add_argument("--style", choices=("plain", "hologram"), default="plain")
    a.add_argument("--face-json", dest="face_json", required=True,
                   help="faces/<id>.json -- where her eyes are in this portrait")
    args = a.parse_args()

    env = envelope(args.audio)
    total = int((SPEECH_AT + len(env) / FPS + 1.2) * FPS)
    c = Compositor(args.sprites, args.face_json)
    tmp = tempfile.mkdtemp()
    for i, (base, ov, lids) in enumerate(script(env, total, "blink_shut" in c.img)):
        f = c.frame(base, ov, lids)
        if args.style == "hologram":
            f = hologram(f)
        f.save(os.path.join(tmp, f"f{i:04d}.png"))
    subprocess.run([
        "ffmpeg", "-y", "-framerate", str(FPS), "-i", os.path.join(tmp, "f%04d.png"),
        "-itsoffset", str(SPEECH_AT), "-i", args.audio,
        "-vf", "pad=ceil(iw/2)*2:ceil(ih/2)*2",  # 532x535: yuv420p needs even sides
        "-c:v", "libx264", "-pix_fmt", "yuv420p", "-crf", "18",
        # No -shortest: the clip runs on past her last word, back to idle.
        "-c:a", "aac", args.out], check=True,
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    print(f"{args.out}  {total/FPS:.1f}s, {total} frames")
