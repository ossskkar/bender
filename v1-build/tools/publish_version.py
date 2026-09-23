"""Make a built VRM a face of its own, and her default (the latest always is).

    python3 publish_version.py <N> <stem> <render.png>

Copies v1-build/<stem>.vrm into lain/arisu/vrm/ and over arisu.vrm, cuts the
thumb from a 600x1000 front render, and adds "Arisu3D V<N>" to the web list
(ARISU_3D in lain/arisu/index.html) and the iPad list (FaceView.arisu3D).
Committing and deploying stay separate (deploy-lain).
"""
import shutil, sys
from pathlib import Path
from PIL import Image

ROOT = Path(__file__).resolve().parents[3]
LAIN = ROOT / 'lain' / 'arisu'
BUILD = ROOT / 'arisu' / 'v1-build'
FACEVIEW = ROOT / 'arisu' / 'native' / 'Arisu' / 'FaceView.swift'


def insert_after_last(path, marker, line):
    text = path.read_text()
    if line.strip() in text:
        return
    lines = text.split('\n')
    last = max(i for i, l in enumerate(lines) if marker in l)
    lines.insert(last + 1, line)
    path.write_text('\n'.join(lines))


def main(n, stem, render):
    name = f'Arisu3D V{n}'
    shutil.copy(BUILD / f'{stem}.vrm', LAIN / 'vrm' / f'{stem}.vrm')
    shutil.copy(BUILD / f'{stem}.vrm', LAIN / 'vrm' / 'arisu.vrm')
    shot = Image.open(render).crop((75, 100, 525, 700))
    shot.resize((300, 400)).save(LAIN / 'live2d' / 'thumbs' / f'{name}.png', optimize=True)
    shot.resize((240, 320)).save(LAIN / 'live2d' / 'thumbs' / 'Arisu3D.png', optimize=True)
    insert_after_last(LAIN / 'index.html', "  'Arisu3D V", f"  '{name}': '{stem}',")
    insert_after_last(FACEVIEW, '        ("Arisu3D V', f'        ("{name}", "{stem}"),')
    print(f'{name} -> {stem}; default updated')


if __name__ == '__main__':
    main(*sys.argv[1:4])
