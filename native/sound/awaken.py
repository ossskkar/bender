#!/usr/local/bin/python3.11
"""Her waking sound, synthesised (Oscar, 2026-10-01). Writes Arisu/awaken.wav.

Timed to Singularity's summon: one second of everything being drawn in -- a
rising swell of noise and a climbing sub tone, cut dead -- then at 1.0 s the
arrival: a hit, a falling sub boom, a bright detuned chord, and a long tail.

Stdlib only. Tune the constants at the top and run it again.
"""
import math
import random
import struct
import wave
from pathlib import Path

RATE = 44100
LENGTH = 3.6          # seconds
BANG = 1.0            # when she arrives; matches RealmView.stage
SWELL_GAIN = 0.55
BOOM_GAIN = 1.0
CHORD_GAIN = 0.22
REVERB_MIX = 0.35

random.seed(7)
n = int(RATE * LENGTH)
dry = [0.0] * n


def at(t):
    return int(t * RATE)


# 1. the draw-in: noise through a one-pole lowpass whose cutoff rises, under a
# sub sine climbing 35 -> 110 Hz, both growing exponentially, cut at BANG.
lp = 0.0
phase = 0.0
for i in range(at(BANG) - at(0.03)):
    t = i / RATE
    k = t / BANG
    env = (math.exp(4 * k) - 1) / (math.exp(4) - 1)
    cutoff = 300 + 6000 * k * k
    a = 1 - math.exp(-2 * math.pi * cutoff / RATE)
    lp += a * (random.uniform(-1, 1) - lp)
    phase += 2 * math.pi * (35 + 75 * k * k) / RATE
    dry[i] += SWELL_GAIN * env * (0.7 * lp + 0.6 * math.sin(phase))

# 2. the arrival
b = at(BANG)
phase = 0.0
for i in range(n - b):
    t = i / RATE
    # the hit: a short burst of bright noise
    hit = random.uniform(-1, 1) * math.exp(-t * 60) * 0.8
    # the boom: 60 Hz falling to 28 Hz, saturated so it is felt on small speakers
    f = 28 + 32 * math.exp(-t * 4)
    phase += 2 * math.pi * f / RATE
    boom = math.tanh(2.5 * math.sin(phase)) * math.exp(-t * 1.6)
    # its upper octave, so an iPad speaker that cannot reproduce 30 Hz still hears it
    boom += 0.35 * math.sin(phase * 2) * math.exp(-t * 2.5)
    # the shimmer: a bright minor chord, detuned in pairs, slow to fade
    chord = 0.0
    for hz in (440.0, 523.25, 659.25, 880.0, 1318.5):
        for d in (-1.5, 1.5):
            chord += math.sin(2 * math.pi * (hz + d) * t)
    chord *= CHORD_GAIN / 10 * min(1, t * 20) * math.exp(-t * 1.2)
    dry[b + i] += hit + BOOM_GAIN * boom + chord


# 3. a hall: Schroeder -- four combs in parallel, two allpasses in series --
# with different delays per side so the tail is wide.
def reverb(x, combs, allpasses):
    out = [0.0] * len(x)
    for d, g in combs:
        buf = [0.0] * d
        j = 0
        for i, s in enumerate(x):
            y = buf[j]
            buf[j] = s + y * g
            out[i] += y
            j = (j + 1) % d
    for d, g in allpasses:
        buf = [0.0] * d
        j = 0
        for i, s in enumerate(out):
            y = buf[j]
            buf[j] = s + y * g
            out[i] = y - g * s
            j = (j + 1) % d
    return out


wetL = reverb(dry, [(1557, 0.84), (1617, 0.84), (1491, 0.84), (1422, 0.84)], [(225, 0.5), (556, 0.5)])
wetR = reverb(dry, [(1617, 0.84), (1557, 0.84), (1356, 0.84), (1277, 0.84)], [(341, 0.5), (441, 0.5)])

left = [d + REVERB_MIX * w * 0.25 for d, w in zip(dry, wetL)]
right = [d + REVERB_MIX * w * 0.25 for d, w in zip(dry, wetR)]

# fade the last 0.3 s, normalise to -1 dBFS
fade = at(0.3)
for i in range(fade):
    g = i / fade
    left[n - 1 - i] *= g
    right[n - 1 - i] *= g
peak = max(max(abs(v) for v in left), max(abs(v) for v in right))
scale = 10 ** (-1 / 20) / peak

out = Path(__file__).resolve().parent.parent / "Arisu" / "awaken.wav"
with wave.open(str(out), "wb") as w:
    w.setnchannels(2)
    w.setsampwidth(2)
    w.setframerate(RATE)
    w.writeframes(b"".join(
        struct.pack("<hh", int(l * scale * 32767), int(r * scale * 32767)) for l, r in zip(left, right)))
print(out, f"{LENGTH}s")
