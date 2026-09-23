#!/usr/bin/env python
"""Render Arisu expression/mouth sprites from ONE flat portrait, with LivePortrait.

Every frame is a warp of the original artwork -- nothing is redrawn or
regenerated, so her face, hair and cybernetics stay exactly as painted.

The source image is prepared once (the slow part on CPU); after that each pose
is a stitch + warp_decode of the same appearance features. Poses are dials, not
driving videos: eye openness, lip openness, gaze, smile, eyebrows.

Run from the LivePortrait checkout:
  cd ~/tools/LivePortrait && .venv/bin/python <this> --source X.png --out DIR
"""
import argparse, json, os, sys
import cv2, numpy as np, torch

sys.path.insert(0, os.path.expanduser("~/tools/LivePortrait"))
from src.config.argument_config import ArgumentConfig
from src.config.inference_config import InferenceConfig
from src.config.crop_config import CropConfig
from src.live_portrait_wrapper import LivePortraitWrapper
from src.utils.cropper import Cropper
from src.utils.camera import get_rotation_matrix
from src.utils.crop import prepare_paste_back, paste_back
from src.utils.io import load_image_rgb
from src.utils.retargeting_utils import calc_eye_close_ratio, calc_lip_close_ratio

# Lifted verbatim from src/gradio_pipeline.py -- these index the 21 implicit
# keypoints LivePortrait uses. Magic numbers are theirs, not ours.
def d_gaze(dx, dy, d):
    if dx > 0:
        d[0, 11, 0] += dx * 0.0007; d[0, 15, 0] += dx * 0.001
    else:
        d[0, 11, 0] += dx * 0.001;  d[0, 15, 0] += dx * 0.0007
    d[0, 11, 1] += dy * -0.001; d[0, 15, 1] += dy * -0.001
    blink = -dy / 2.
    d[0, 11, 1] += blink * -0.001; d[0, 15, 1] += blink * -0.001
    return d

def d_smile(s, d):
    for i, k, m in ((20,1,-0.01),(14,1,-0.02),(17,1,0.0065),(17,2,0.003),
                    (13,1,-0.00275),(16,1,-0.00275),(3,1,-0.0035),(7,1,-0.0035)):
        d[0, i, k] += s * m
    return d

def d_eyebrow(e, d):
    if e > 0:
        d[0, 1, 1] += e * 0.001; d[0, 2, 1] += e * -0.001
    else:
        d[0, 1, 0] += e * -0.001; d[0, 2, 0] += e * 0.001
        d[0, 1, 1] += e * 0.0003; d[0, 2, 1] += e * -0.0003
    return d

def d_lip_wide(v, d):   # lip_variation_one: corners out, "ee"
    d[0, 14, 1] += v * 0.001; d[0, 3, 1] += v * -0.0005
    d[0, 7, 1] += v * -0.0005; d[0, 17, 2] += v * -0.0005
    return d

def d_lip_round(v, d):  # lip_variation_two: pursed, "oh"
    d[0, 20, 2] += v * -0.001; d[0, 20, 1] += v * -0.001; d[0, 14, 1] += v * -0.001
    return d


def diff_box(a, b, pad=10):
    """Where two renders actually differ, as [x, y, w, h].

    Two renders of the same face are never bit-identical: the generator repaints
    the whole crop, so the entire head moves by a fraction of a level (measured:
    mean 0.67, peak 124 for a mouth that only changed at the lips). An absolute
    threshold therefore returns either the mouth or the whole portrait depending
    on the pose. Scaling it to the pose's OWN peak change is what separates the
    part that moved from the noise floor, for a big blink and a small gaze alike.
    """
    d = np.abs(a.astype(np.int16) - b.astype(np.int16)).max(axis=2)
    ys, xs = np.where(d > max(12, 0.35 * d.max()))
    if len(xs) == 0:
        return None
    x0, x1 = max(0, xs.min() - pad), min(a.shape[1], xs.max() + pad)
    y0, y1 = max(0, ys.min() - pad), min(a.shape[0], ys.max() + pad)
    return [int(x0), int(y0), int(x1 - x0), int(y1 - y0)]


class Poser:
    def __init__(self, source):
        cfg = InferenceConfig(flag_force_cpu=True, device_id=0, flag_use_half_precision=False)
        self.w = LivePortraitWrapper(inference_cfg=cfg)
        self.cropper = Cropper(crop_cfg=CropConfig(), image_type="human_face",
                               flag_force_cpu=True, device_id=0)
        img = load_image_rgb(source)
        crop = self.cropper.crop_source_image(img, self.cropper.crop_cfg)
        if crop is None:
            sys.exit("No face found in the source image.")
        I_s = self.w.prepare_source(crop['img_crop_256x256'])
        self.lmk = crop['lmk_crop']
        self.M_c2o = crop['M_c2o']
        self.mask = prepare_paste_back(cfg.mask_crop, crop['M_c2o'],
                                       dsize=(img.shape[1], img.shape[0]))
        self.img = img
        self.x_s_info = self.w.get_kp_info(I_s)
        self.R_s = get_rotation_matrix(self.x_s_info['pitch'], self.x_s_info['yaw'],
                                       self.x_s_info['roll'])
        self.f_s = self.w.extract_feature_3d(I_s)
        self.x_s = self.w.transform_keypoint(self.x_s_info)
        # The portrait's own resting openness. A pose asking for these is a no-op.
        self.eye0 = round(float(calc_eye_close_ratio(self.lmk[None]).mean()), 2)
        self.lip0 = round(float(calc_lip_close_ratio(self.lmk[None])[0][0]), 2)

    @torch.no_grad()
    def render(self, eye=None, lip=None, smile=0., eyebrow=0., gaze_x=0., gaze_y=0.,
               wide=0., round_=0.):
        eye = self.eye0 if eye is None else eye
        lip = self.lip0 if lip is None else lip
        delta = self.x_s_info['exp'].clone()
        if gaze_x or gaze_y: delta = d_gaze(gaze_x, gaze_y, delta)
        if smile:            delta = d_smile(smile, delta)
        if eyebrow:          delta = d_eyebrow(eyebrow, delta)
        if wide:             delta = d_lip_wide(wide, delta)
        if round_:           delta = d_lip_round(round_, delta)
        x_d = self.x_s_info['scale'] * (self.x_s_info['kp'] @ self.R_s + delta) + self.x_s_info['t']
        if eye != self.eye0:
            x_d = x_d + self.w.retarget_eye(self.x_s, self.w.calc_combined_eye_ratio([[eye]], self.lmk))
        if lip != self.lip0:
            x_d = x_d + self.w.retarget_lip(self.x_s, self.w.calc_combined_lip_ratio([[lip]], self.lmk))
        x_d = self.w.stitching(self.x_s, x_d)
        out = self.w.parse_output(self.w.warp_decode(self.f_s, self.x_s, x_d)['out'])[0]
        return paste_back(out, self.M_c2o, self.img, self.mask)


# Mouth openness levels the amplitude-driven lip sync steps through, plus the
# eye and expression poses. Kept deliberately small: every extra pose is another
# minute of CPU and another file the phone has to load.
def poses(p):
    m = {f"mouth{i}": dict(lip=v) for i, v in enumerate([0.0, 0.08, 0.16, 0.26, 0.38])}
    m["mouth_wide"]  = dict(lip=0.3, wide=12.)
    m["mouth_round"] = dict(lip=0.35, round_=12.)
    m["neutral"]     = dict()
    # No blink poses. LivePortrait's eye retargeting was tried on this portrait
    # and rejected: on anime eyes it smears the iris into a rainbow rather than
    # lowering a lid (sprites/blink_shut.png is kept as the evidence). Blinks are
    # done geometrically in make_poc.py instead.
    m["gaze_left"]   = dict(gaze_x=-12.)
    m["gaze_right"]  = dict(gaze_x=12.)
    m["gaze_up"]     = dict(gaze_y=8.)
    m["gaze_down"]   = dict(gaze_y=-8.)
    m["smile"]       = dict(smile=1.0)
    m["smile_big"]   = dict(smile=1.6, lip=0.2)
    m["curious"]     = dict(eyebrow=8., eye=0.5)
    m["concerned"]   = dict(eyebrow=-8.)
    return m


if __name__ == "__main__":
    a = argparse.ArgumentParser()
    a.add_argument("--source", required=True)
    a.add_argument("--out", required=True)
    a.add_argument("--only", default=None, help="comma-separated pose names")
    args = a.parse_args()
    os.makedirs(args.out, exist_ok=True)
    p = Poser(args.source)
    print(f"source resting ratios: eye={p.eye0} lip={p.lip0}", flush=True)
    todo = poses(p)
    if args.only:
        keep = args.only.split(",")
        todo = {k: v for k, v in todo.items() if k in keep}
    # Neutral first and always: every other pose is stored with the box where it
    # actually differs from it, so the page can overlay just the mouth or just the
    # eyes and compose blink x viseme without rendering the product of the two.
    base = p.render()
    cv2.imwrite(os.path.join(args.out, "neutral.png"), base[:, :, ::-1])
    manifest = {"source_eye_ratio": p.eye0, "source_lip_ratio": p.lip0,
                "size": [int(base.shape[1]), int(base.shape[0])], "poses": {}}
    for name, kw in todo.items():
        if name == "neutral":
            manifest["poses"][name] = {"params": kw, "box": None}
            continue
        img = p.render(**kw)
        cv2.imwrite(os.path.join(args.out, f"{name}.png"), img[:, :, ::-1])
        manifest["poses"][name] = {"params": kw, "box": diff_box(base, img)}
        print(f"  {name} box={manifest['poses'][name]['box']}", flush=True)
        json.dump(manifest, open(os.path.join(args.out, "poses.json"), "w"), indent=1)
    print("done")
