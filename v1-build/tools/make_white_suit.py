"""V12+: towards the Type-02 sheet -- white suit, graphite seams, no box armour.

Works on the VRM (glTF binary) directly, no Blender: repaints the VRoid
one-piece texture, drops the torso and leg box plates Codex added in V5-V11
(their nodes lose their mesh; bones and skins are untouched), and turns the
knee caps graphite. Rig, expressions, springs and clips are unchanged.

    python3 make_white_suit.py <in.vrm> <out.vrm>
"""
import io, json, re, struct, sys
import numpy as np
from PIL import Image, ImageDraw, ImageFilter
from scipy import ndimage

HIDE = ('ARISU_Torso_', 'ThighFront', 'ThighRail', 'ThighCore', 'ThighCyan',
        'ShinFront', 'ShinCore', 'ShinCyan', 'HipConnector', 'HipJoint',
        # V14: the arm plates, so the arms are plain white sleeves
        'ArmFrontPlate', 'ArmTopPlate', 'PlateSaddle', 'ForearmStatus',
        'ForearmFrontPlate', 'ForearmTopPlate', 'ElbowAxle', 'ShoulderBridge')
KEEP = ()
GRAPHITE_MESHES = ('KneeCap',)
# The sheet's arms are white with graphite elbows and wrists.
WHITE_MESHES = ('UpperArmCore', 'ForearmCore')
RED = (226, 75, 75)                          # sheet: accent red #E24B4B
# Where the chest mark goes, in suit-texture pixels (front centre line).
MARK = (1024, 600)
# The sheet's over-ear units are about half again the V5 ones. Each side's
# three pieces scale together about the housing, which moves out a little so
# the bigger shell clears her hair.
EAR = 'ARISU_V5_Head_'
EAR_SCALE = 1.45
EAR_OUT = 0.004
EAR_DOWN = 0.032                             # V5 sat above the ears
SUIT = 'Onepiece'
WHITE = np.array([247, 248, 250], float)     # sheet: primary white #F7F8FA
GRAPHITE = np.array([46, 46, 51], float)     # sheet: graphite #2E2E33
# The sheet's seams are faint grey lines, not graphite (V15).
SEAM = np.array([128, 134, 146], float)
HAIR = np.array([80, 102, 134], float)       # sheet #5B7CA6, less the renderer's lift


def read(path):
    b = open(path, 'rb').read()
    n = struct.unpack('<I', b[12:16])[0]
    j = json.loads(b[20:20 + n])
    m = struct.unpack('<I', b[20 + n:24 + n])[0]
    return j, bytearray(b[28 + n:28 + n + m])


def write(path, j, views):
    """Rebuild the buffer from per-view bytes, 4-byte aligned."""
    out = bytearray()
    for bv, data in zip(j['bufferViews'], views):
        out += b'\0' * (-len(out) % 4)
        bv['byteOffset'] = len(out)
        bv['byteLength'] = len(data)
        out += data
    out += b'\0' * (-len(out) % 4)
    j['buffers'][0]['byteLength'] = len(out)
    js = json.dumps(j, separators=(',', ':')).encode()
    js += b' ' * (-len(js) % 4)
    total = 12 + 8 + len(js) + 8 + len(out)
    with open(path, 'wb') as f:
        f.write(struct.pack('<4sII', b'glTF', 2, total))
        f.write(struct.pack('<I4s', len(js), b'JSON') + js)
        f.write(struct.pack('<I4s', len(out), b'BIN\0') + out)


def accessor(j, views, i):
    acc = j['accessors'][i]
    bv = j['bufferViews'][acc['bufferView']]
    dt = {5121: np.uint8, 5123: np.uint16, 5125: np.uint32, 5126: np.float32}[acc['componentType']]
    k = {'SCALAR': 1, 'VEC2': 2, 'VEC3': 3, 'VEC4': 4}[acc['type']]
    raw = views[acc['bufferView']]
    stride = bv.get('byteStride', np.dtype(dt).itemsize * k)
    off = acc.get('byteOffset', 0)
    a = np.ndarray((acc['count'], k), dt, raw, off, (stride, np.dtype(dt).itemsize))
    if acc.get('normalized'):
        a = a / float(np.iinfo(dt).max)
    return a.astype(np.float64)


# Suit regions the sheet paints graphite, found on the mesh itself: which bones
# a triangle is skinned to, and for the torso sides which way it faces in the
# bind pose. (bone pattern, minimum |normal.x| or None)
GRAPHITE_REGIONS = [
    (r'(Hand|Thumb|Index|Middle|Ring|Little)', None),   # gloves
    (r'Neck', None),                                     # high collar
    (r'(Spine|Chest|Hips)', 0.62),                       # side panels
]
# V16: the sheet's legs are clean white; the VRoid harness pattern there fades.
CALM = r'(UpperLeg|LowerLeg|Hips)'
# V16: the graphite panel between the legs, in bind-pose metres: a V, narrow
# below the navel and widening to the inner thighs.
CROTCH = dict(top=0.012, bottom=0.05, y=(0.73, 0.86))


def graphite_mask(j, views, suit, size):
    """Texture pixels of the suit that the sheet shows in graphite."""
    names = [n.get('name', '') for n in j['nodes']]
    im = Image.new('L', (size, size), 0)
    d = ImageDraw.Draw(im)
    calm = Image.new('L', (size, size), 0)
    dc = ImageDraw.Draw(calm)
    for ni, node in enumerate(j['nodes']):
        if 'mesh' not in node or 'skin' not in node:
            continue
        joints = j['skins'][node['skin']]['joints']
        for p in j['meshes'][node['mesh']]['primitives']:
            if p.get('material') != suit:
                continue
            at = p['attributes']
            uv = accessor(j, views, at['TEXCOORD_0']) * size
            J = accessor(j, views, at['JOINTS_0']).astype(int)
            W = accessor(j, views, at['WEIGHTS_0'])
            nx = np.abs(accessor(j, views, at['NORMAL'])[:, 0])
            pos = accessor(j, views, at['POSITION'])
            tri = accessor(j, views, p['indices']).astype(int).reshape(-1, 3)
            for pattern, side in GRAPHITE_REGIONS:
                bone = np.array([bool(re.search(pattern, names[x])) for x in joints])
                on = (W * bone[J]).sum(1) > 0.5
                if side is not None:
                    on &= nx > side
                for t in tri[on[tri].all(1)]:
                    d.polygon([tuple(uv[v]) for v in t], fill=255)
            bone = np.array([bool(re.search(CALM, names[x])) for x in joints])
            on = (W * bone[J]).sum(1) > 0.5
            for t in tri[on[tri].all(1)]:
                dc.polygon([tuple(uv[v]) for v in t], fill=255)
            y0, y1 = CROTCH['y']
            f = np.clip((y1 - pos[:, 1]) / (y1 - y0), 0, 1)
            half = CROTCH['top'] + (CROTCH['bottom'] - CROTCH['top']) * f
            on = (np.abs(pos[:, 0]) < half) & (pos[:, 1] > y0) & (pos[:, 1] < y1) & (pos[:, 2] > -0.02)
            for t in tri[on[tri].all(1)]:
                d.polygon([tuple(uv[v]) for v in t], fill=255)
    calm = np.asarray(calm.filter(ImageFilter.GaussianBlur(12))) / 255.0
    return np.asarray(im.filter(ImageFilter.MaxFilter(5))) > 0, calm


def white_suit(png, gloves=None, mark=True, calm=None):
    im = Image.open(io.BytesIO(png)).convert('RGBA')
    a = np.asarray(im).astype(float)
    L = a[..., :3].mean(-1)
    base = np.asarray(Image.fromarray(L.astype(np.uint8)).filter(
        ImageFilter.GaussianBlur(10))).astype(float)
    detail = L - base
    # The fill becomes white; its own soft shading survives as a light tone.
    shade = np.clip(0.86 + (base - 32) / 400, 0.80, 1.0)[..., None]
    rgb = WHITE * shade
    # Seams and panel edges -- anything that stands out from its
    # surroundings, lighter or darker -- become graphite lines.
    line = np.clip((np.abs(detail) - 5) / 14, 0, 1)
    if calm is not None:
        line = line * (1 - 0.8 * calm)
    line = line[..., None]
    rgb = rgb * (1 - line) + SEAM * line
    # The two small islands at the top of the atlas are the gloves: graphite,
    # as on the sheet, with their seams a little lighter.
    if gloves is None:
        gloves = np.zeros(L.shape, bool)
    lab, _ = ndimage.label(a[..., 3] > 8)
    sizes = ndimage.sum(np.ones_like(L), lab, range(1, lab.max() + 1))
    big = 1 + int(np.argmax(sizes))
    islands = ((lab > 0) & (lab != big)) if mark else np.zeros(L.shape, bool)
    glove = (islands | gloves)[..., None]
    dark = GRAPHITE * (0.9 + 0.2 * (base / 60).clip(0, 1))[..., None] + 40 * line
    rgb = np.where(glove, dark, rgb)
    a[..., :3] = rgb
    im = Image.fromarray(a.astype(np.uint8), 'RGBA')
    # The power mark: an open grey ring with a red stroke through its gap.
    d = ImageDraw.Draw(im)
    x, y, r = MARK[0], MARK[1], (34 if mark else 0)
    d.arc((x - r, y - r, x + r, y + r), -60, 240, fill=(150, 154, 162, 255), width=9)
    d.rounded_rectangle((x - 5, y - r - 10, x + 5, y + 6), 4, fill=RED + (255,))
    a = np.asarray(im).astype(float)
    buf = io.BytesIO()
    Image.fromarray(a.astype(np.uint8), 'RGBA').save(buf, 'PNG', optimize=True)
    return buf.getvalue()


def main(src, dst):
    j, binchunk = read(src)
    views = [bytes(binchunk[bv.get('byteOffset', 0):bv.get('byteOffset', 0) + bv['byteLength']])
             for bv in j['bufferViews']]
    mats = j['materials']
    graphite = next(i for i, m in enumerate(mats) if m['name'] == 'ARISU_Graphite')
    white = next(i for i, m in enumerate(mats) if m['name'] == 'ARISU_Head_White_V225F')

    hidden = 0
    for node in j['nodes']:
        name = node.get('name', '')
        if 'mesh' not in node:
            continue
        mesh = j['meshes'][node['mesh']]
        if any(h in name for h in HIDE) and not any(k in name for k in KEEP):
            del node['mesh']
            hidden += 1
        elif any(g in name for g in GRAPHITE_MESHES):
            for p in mesh['primitives']:
                p['material'] = graphite
        elif any(w in name for w in WHITE_MESHES):
            for p in mesh['primitives']:
                p['material'] = white

    for side in 'LR':
        sign = 1 if side == 'L' else -1
        parts = [n for n in j['nodes'] if n.get('name', '').startswith(EAR + side + '_')]
        pivot = np.array(next(n for n in parts if 'Housing' in n['name'])['translation'])
        for n in parts:
            t = pivot + (np.array(n['translation']) - pivot) * EAR_SCALE
            t[0] += sign * EAR_OUT
            t[1] -= EAR_DOWN
            n['translation'] = t.tolist()
            n['scale'] = [EAR_SCALE] * 3

    suit = next(i for i, m in enumerate(mats) if SUIT in m['name'])
    tex = mats[suit]['pbrMetallicRoughness']['baseColorTexture']['index']
    img = j['images'][j['textures'][tex]['source']]
    size = Image.open(io.BytesIO(views[img['bufferView']])).size[0]
    dark, calm = graphite_mask(j, views, suit, size)
    views[img['bufferView']] = white_suit(views[img['bufferView']], dark, calm=calm)
    # MToon's shade colour is multiplied under the lit colour; a white suit
    # needs a light shade or its unlit side reads as grey plastic.
    mt = mats[suit].get('extensions', {}).get('VRMC_materials_mtoon')
    if mt:
        mt['shadeColorFactor'] = [0.78, 0.80, 0.86]
        mt.pop('shadeMultiplyTexture', None)

    # The added white parts were a cool grey (0.69-0.86); the sheet's white is
    # the suit's, so they match it now.
    for m in mats:
        if m['name'] in ('ARISU_Armor_White', 'ARISU_Head_White_V225F'):
            m['pbrMetallicRoughness']['baseColorFactor'] = [0.93, 0.94, 0.96, 1.0]
            m['pbrMetallicRoughness']['metallicFactor'] = 0.0

    # V15: white shoes, as on the sheet -- the same repaint, without the mark.
    shoes = next(i for i, m in enumerate(mats) if 'Shoes' in m['name'])
    simg = j['images'][j['textures'][mats[shoes]['pbrMetallicRoughness']['baseColorTexture']['index']]['source']]
    views[simg['bufferView']] = white_suit(views[simg['bufferView']], mark=False)
    mats[shoes]['extensions']['VRMC_materials_mtoon']['shadeColorFactor'] = [0.78, 0.80, 0.86]

    # V15: her hair lifted to the sheet's blue-grey, strand shading kept.
    hair = next(i for i, m in enumerate(mats) if m['name'].startswith('N00_000_Hair_00'))
    himg = j['images'][j['textures'][mats[hair]['pbrMetallicRoughness']['baseColorTexture']['index']]['source']]
    h = np.asarray(Image.open(io.BytesIO(views[himg['bufferView']])).convert('RGBA')).astype(float)
    on = h[..., 3] > 8
    h[..., :3] = np.clip(h[..., :3] * (HAIR / h[on][:, :3].mean(0)), 0, 255)
    buf = io.BytesIO()
    Image.fromarray(h.astype(np.uint8), 'RGBA').save(buf, 'PNG', optimize=True)
    views[himg['bufferView']] = buf.getvalue()

    j['asset']['generator'] = j['asset'].get('generator', '') + ' + make_white_suit'
    write(dst, j, views)
    print(f'hid {hidden} nodes; repainted material {suit}; wrote {dst}')


if __name__ == '__main__':
    main(*sys.argv[1:3])
