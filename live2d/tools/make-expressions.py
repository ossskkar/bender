#!/usr/bin/env python3
"""Write hand-made .exp3.json expressions for the samples that ship none.

    tools/make-expressions.py            # write into glue/expressions/
    tools/make-expressions.py --check    # report what differs, write nothing

Four of the eight samples -- Hiyori, Rice, Mark, Wanko -- ship no expressions at
all, so on them the five face states and the four reactions had nothing to say
(see arisu-face.js, whose tables are empty for these four). This writes the
missing files, and `patch-sdk.sh` copies them into the SDK tree and registers
them in each .model3.json.

Why hand-written files rather than a parameter patch per frame: an expression is
what the Cubism SDK cross-fades, remembers and blends, and it is what the
settings panel's per-state picker can offer. Driving the same parameters from
our own per-frame code would fight the blink updater and the lip sync for the
same parameter ids, which is the trap arisu-face.js already documents.

The names are the vocabulary arisu-face.js maps: five states (idle, listening,
thinking, speaking, asleep) and four reactions (surprised, amused, confused,
sad). Speech is deliberately absent as an expression -- the mouth belongs to the
lip sync, and an expression that opens it would hold it open over her voice.

Read the per-model spec before editing a value: which rig has which parameter is
the whole content of this file. Mark has no mouth form and no eye-smile, Rice has
no mouth and no brows at all, Wanko names its parameters the old way
(PARAM_EYE_L_OPEN, not ParamEyeLOpen). An expression naming a parameter a rig
does not have is not an error -- Cubism ignores it -- and that is exactly why
this is worth getting right rather than guessing.
"""
from __future__ import annotations

import argparse
import json
import pathlib
import sys

HERE = pathlib.Path(__file__).resolve().parent
OUT = HERE.parent / "glue" / "expressions"

FADE = 0.5

# --- per-model parameter names ---------------------------------------------------
#
# `None` means the rig has no such parameter, and every value written for it is
# dropped rather than emitted as a no-op: a file that names a parameter the rig
# lacks is a file nobody can tell was meant to do nothing.
SPEC = {
    "Hiyori": {
        "eye_l": "ParamEyeLOpen", "eye_r": "ParamEyeROpen",
        "smile_l": "ParamEyeLSmile", "smile_r": "ParamEyeRSmile",
        "brow_l": "ParamBrowLY", "brow_r": "ParamBrowRY",
        "brow_form_l": "ParamBrowLForm", "brow_form_r": "ParamBrowRForm",
        "mouth_form": "ParamMouthForm", "mouth_open": "ParamMouthOpenY",
        "tilt": "ParamAngleZ",
    },
    "Rice": {                       # eyes only: no mouth, no brows
        "eye_l": "ParamEyeLOpen", "eye_r": "ParamEyeROpen",
        "gaze_x": "ParamEyeBallX", "gaze_y": "ParamEyeBallY",
        "tilt": "ParamAngleZ",
    },
    "Mark": {                       # brows and eyes, no mouth form
        "eye_l": "ParamEyeLOpen", "eye_r": "ParamEyeROpen",
        "brow_l": "ParamBrowLY", "brow_r": "ParamBrowRY",
        "mouth_open": "ParamMouthOpenY", "tilt": "ParamAngleZ",
    },
    "Wanko": {                      # the old parameter naming
        "eye_l": "PARAM_EYE_L_OPEN", "eye_r": "PARAM_EYE_R_OPEN",
        "mouth_form": "PARAM_MOUTH_FORM", "mouth_open": "PARAM_MOUTH_OPEN_Y",
        "tilt": "PARAM_ANGLE_Z",
        "ear_l": "PARAM_EAR_L", "ear_r": "PARAM_EAR_R",
        "bashful": "PARAM_TERE",
    },
}

# --- what each expression does ---------------------------------------------------
#
# A dict of `role -> (value, blend)`. Roles are the spec keys above. Blend is
# "Add" unless a state has to *hold* a value against something else -- only
# asleep does, where the eyes must stay shut whatever the blink updater wants.
#
# Kept deliberately small: this is a face reading as a mood, not a rig test. The
# existing tables in arisu-face.js were chosen by reading each .exp3.json, and
# the same three rules apply here: never close the eyes into a listening face,
# never hold the mouth open (lip sync owns it), and never pull the mouth far from
# neutral on anything used while she is speaking.
STATES: dict[str, dict[str, tuple[float, str]]] = {
    "idle": {
        "mouth_form": (0.15, "Add"),
        "brow_l": (-0.05, "Add"), "brow_r": (-0.05, "Add"),
    },
    "listening": {
        "brow_l": (-0.25, "Add"), "brow_r": (-0.25, "Add"),
        "eye_l": (0.10, "Add"), "eye_r": (0.10, "Add"),
    },
    "thinking": {
        "brow_l": (0.30, "Add"), "brow_r": (-0.10, "Add"),
        "eye_l": (-0.15, "Add"), "eye_r": (-0.15, "Add"),
        "mouth_form": (-0.20, "Add"),
        "tilt": (6.0, "Add"),
        "gaze_x": (0.35, "Add"), "gaze_y": (-0.35, "Add"),
    },
    "asleep": {
        "eye_l": (0.0, "Overwrite"), "eye_r": (0.0, "Overwrite"),
        "brow_l": (0.15, "Add"), "brow_r": (0.15, "Add"),
        "mouth_form": (-0.10, "Add"),
    },
    "speaking": {
        "mouth_form": (0.10, "Add"),
    },
}

REACTIONS: dict[str, dict[str, tuple[float, str]]] = {
    "surprised": {
        "eye_l": (0.35, "Add"), "eye_r": (0.35, "Add"),
        "brow_l": (-0.50, "Add"), "brow_r": (-0.50, "Add"),
        "mouth_open": (0.20, "Add"),
        "ear_l": (0.30, "Add"), "ear_r": (0.30, "Add"),
    },
    "amused": {
        "smile_l": (0.80, "Add"), "smile_r": (0.80, "Add"),
        "mouth_form": (0.90, "Add"),
        "eye_l": (-0.10, "Add"), "eye_r": (-0.10, "Add"),
        "bashful": (0.40, "Add"),
        "ear_l": (0.20, "Add"), "ear_r": (0.20, "Add"),
    },
    "confused": {
        "brow_l": (-0.40, "Add"), "brow_r": (0.20, "Add"),
        "eye_l": (-0.10, "Add"), "eye_r": (-0.10, "Add"),
        "mouth_form": (-0.30, "Add"),
        "tilt": (-7.0, "Add"),
        "gaze_x": (-0.40, "Add"),
    },
    "sad": {
        "brow_l": (-0.30, "Add"), "brow_r": (-0.30, "Add"),
        "brow_form_l": (-0.60, "Add"), "brow_form_r": (-0.60, "Add"),
        "eye_l": (-0.20, "Add"), "eye_r": (-0.20, "Add"),
        "mouth_form": (-0.90, "Add"),
        "gaze_y": (-0.30, "Add"),
    },
}


def build(model: str, kind: str, body: dict[str, tuple[float, str]]) -> dict:
    spec = SPEC[model]
    params = []
    for role, (value, blend) in body.items():
        pid = spec.get(role)
        if not pid:
            continue                 # this rig has no such parameter
        params.append({"Id": pid, "Value": round(float(value), 3), "Blend": blend})
    return {
        "Type": "Live2D Expression",
        "FadeInTime": FADE,
        "FadeOutTime": FADE,
        "Parameters": params,
    }


def wanted() -> dict[pathlib.Path, str]:
    out: dict[pathlib.Path, str] = {}
    for model in SPEC:
        for name, body in {**STATES, **REACTIONS}.items():
            doc = build(model, name, body)
            if not doc["Parameters"]:
                continue             # nothing this rig can say with this face
            path = OUT / model / f"exp_{name}.exp3.json"
            out[path] = json.dumps(doc, indent=2) + "\n"
    return out


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--check", action="store_true",
                    help="report differences and exit non-zero; write nothing")
    args = ap.parse_args()

    files = wanted()
    changed, missing = [], []
    for path, text in sorted(files.items()):
        if not path.exists():
            missing.append(path)
            continue
        if path.read_text() != text:
            changed.append(path)

    if args.check:
        for p in missing:
            print(f"  missing  {p.relative_to(HERE.parent)}")
        for p in changed:
            print(f"  differs  {p.relative_to(HERE.parent)}")
        if missing or changed:
            print(f"{len(missing)} missing, {len(changed)} differing")
            return 1
        print(f"{len(files)} expression files up to date")
        return 0

    for path, text in sorted(files.items()):
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text)
    print(f"wrote {len(files)} expression files under "
          f"{OUT.relative_to(HERE.parent)}/")
    for model in SPEC:
        names = sorted(p.stem.replace("exp_", "") for p in files
                       if p.parent.name == model)
        print(f"  {model:<7} {', '.join(names) if names else '(nothing drivable)'}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
