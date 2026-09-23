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
        'ForearmFrontPlate', 'ForearmTopPlate', 'ElbowAxle', 'ShoulderBridge',
        # V18: flat front plates; the knee is painted round instead
        'KneeCap', 'KneeJoint')
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
# V17: the arms were thicker than the sheet's and faceted. Their cores and
# joints slim across the bone (x/z), and their normals are smoothed.
SLIM = {'UpperArmCore': 0.82, 'ForearmCore': 0.82, 'ElbowJoint': 0.86, 'WristJoint': 0.9}
SMOOTH = ('UpperArmCore', 'ForearmCore', 'ElbowJoint', 'WristJoint', 'ShoulderJoint',
          'WhiteHousing', 'KneeCap')
# V20: the shoulder joints read as big black balls; they shrink about their
# own centre (skinned, so the vertices move, not the node).
SHRINK = {'ShoulderJoint': 0.5}             # V22: smaller again, sheet caps
SMOOTH_ANGLE = 50                            # degrees; sharper edges stay sharp
# V17: the sheet's headband, 1 cm over her hair, ear unit to ear unit.
BAND = dict(clear=0.010, width=0.024, thick=0.010, end_x=0.142, end_y=1.470, z=-0.008)
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
    k = {'SCALAR': 1, 'VEC2': 2, 'VEC3': 3, 'VEC4': 4, 'MAT4': 16}[acc['type']]
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
CALM = r'(UpperLeg|LowerLeg|Hips|Spine)'   # V20: + Spine, the waist harness
# V16: the graphite panel between the legs, in bind-pose metres: a V, narrow
# below the navel and widening to the inner thighs.
CROTCH = dict(top=0.012, bottom=0.05, y=(0.73, 0.86))
# V18: the sheet's graphite knee, all the way round the leg, bind-pose metres.
KNEE_Y = (0.475, 0.545)
# V22: the sheet's high graphite collar: suit above this height, near the neck.
COLLAR = dict(y=1.215, half_width=0.065)


def put(j, views, i, arr):
    """Overwrite a tightly packed float accessor in place."""
    acc = j['accessors'][i]
    assert 'byteStride' not in j['bufferViews'][acc['bufferView']]
    raw = bytearray(views[acc['bufferView']])
    off = acc.get('byteOffset', 0)
    data = arr.astype(np.float32).tobytes()
    raw[off:off + len(data)] = data
    views[acc['bufferView']] = bytes(raw)


def smooth_normals(j, views, mesh):
    cos = np.cos(np.radians(SMOOTH_ANGLE))
    for p in j['meshes'][mesh]['primitives']:
        P = accessor(j, views, p['attributes']['POSITION'])
        N = accessor(j, views, p['attributes']['NORMAL'])
        out = N.copy()
        keys = {}
        for v, k in enumerate(map(tuple, np.round(P, 5))):
            keys.setdefault(k, []).append(v)
        for group in keys.values():
            for v in group:
                near = [u for u in group if N[u] @ N[v] > cos]
                n = N[near].sum(0)
                out[v] = n / (np.linalg.norm(n) or 1)
        put(j, views, p['attributes']['NORMAL'], out)


def quat_mat(q):
    x, y, z, w = q
    return np.array([[1 - 2*(y*y + z*z), 2*(x*y - z*w), 2*(x*z + y*w)],
                     [2*(x*y + z*w), 1 - 2*(x*x + z*z), 2*(y*z - x*w)],
                     [2*(x*z - y*w), 2*(y*z + x*w), 1 - 2*(x*x + y*y)]])


def world_matrix(j, i):
    parent = {c: n for n, x in enumerate(j['nodes']) for c in x.get('children', [])}
    M = np.eye(4)
    while i is not None:
        x = j['nodes'][i]
        L = np.eye(4)
        L[:3, :3] = quat_mat(x.get('rotation', [0, 0, 0, 1])) * np.array(x.get('scale', [1, 1, 1]))
        L[:3, 3] = x.get('translation', [0, 0, 0])
        M = L @ M
        i = parent.get(i)
    return M


def add_blob(j, views, data, target=None):
    j['bufferViews'].append({'buffer': 0, 'byteLength': len(data), **({'target': target} if target else {})})
    views.append(data)
    return len(j['bufferViews']) - 1


def add_headband(j, views, material):
    """A flattened tube over the top of her hair, parented to the head bone."""
    hair = next(x for x in j['nodes'] if x.get('name') == 'Hair')
    H = np.vstack([accessor(j, views, p['attributes']['POSITION'])
                   for p in j['meshes'][hair['mesh']]['primitives']])
    H = H[np.abs(H[:, 2] - BAND['z']) < 0.03]
    xs = np.linspace(-BAND['end_x'], BAND['end_x'], 41)
    ys = []
    for x in xs:
        s = H[np.abs(H[:, 0] - x) < 0.008]
        ys.append(s[:, 1].max() + BAND['clear'] if len(s) and abs(x) < 0.1 else np.nan)
    ys = np.array(ys)
    ok = ~np.isnan(ys)
    # Past the hair's crown the band runs down to the ear unit tops.
    ends = np.array([-BAND['end_x'], BAND['end_x']])
    ys = np.interp(xs, np.r_[ends[0], xs[ok], ends[1]],
                   np.r_[BAND['end_y'], ys[ok], BAND['end_y']])
    ys = np.convolve(np.pad(ys, 2, mode='edge'), np.ones(5) / 5, 'valid')
    path = np.c_[xs, ys, np.full_like(xs, BAND['z'])]
    ring = 10
    verts, norms = [], []
    for k, c in enumerate(path):
        t = path[min(k + 1, len(path) - 1)] - path[max(k - 1, 0)]
        t /= np.linalg.norm(t)
        up = np.cross([0, 0, 1], t)                  # outward, in the arc's plane
        up /= np.linalg.norm(up)
        for a in np.linspace(0, 2 * np.pi, ring, endpoint=False):
            d = np.cos(a) * up * BAND['thick'] / 2 + np.sin(a) * np.array([0, 0, 1.0]) * BAND['width'] / 2
            n = np.cos(a) * up / BAND['thick'] + np.sin(a) * np.array([0, 0, 1.0]) / BAND['width']
            verts.append(c + d)
            norms.append(n / np.linalg.norm(n))
    idx = []
    for k in range(len(path) - 1):
        for r in range(ring):
            a, b = k * ring + r, k * ring + (r + 1) % ring
            idx += [a, b + ring, b, a, a + ring, b + ring]
    head = next(i for i, x in enumerate(j['nodes']) if x.get('name') == 'J_Bip_C_Head')
    inv = np.linalg.inv(world_matrix(j, head))
    V = (inv[:3, :3] @ np.array(verts).T).T + inv[:3, 3]
    N = (inv[:3, :3] @ np.array(norms).T).T
    N /= np.linalg.norm(N, axis=1)[:, None]
    accs = []
    for arr, typ in ((V, 'VEC3'), (N, 'VEC3')):
        bv = add_blob(j, views, arr.astype(np.float32).tobytes(), 34962)
        a = {'bufferView': bv, 'componentType': 5126, 'count': len(arr), 'type': typ}
        if len(accs) == 0:
            a['min'], a['max'] = V.min(0).tolist(), V.max(0).tolist()
        j['accessors'].append(a)
        accs.append(len(j['accessors']) - 1)
    bv = add_blob(j, views, np.array(idx, np.uint16).tobytes(), 34963)
    j['accessors'].append({'bufferView': bv, 'componentType': 5123, 'count': len(idx), 'type': 'SCALAR'})
    j['meshes'].append({'name': 'ARISU_Headband', 'primitives': [{
        'attributes': {'POSITION': accs[0], 'NORMAL': accs[1]},
        'indices': len(j['accessors']) - 1, 'material': material}]})
    j['nodes'].append({'name': 'ARISU_Headband', 'mesh': len(j['meshes']) - 1})
    j['nodes'][head].setdefault('children', []).append(len(j['nodes']) - 1)


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
            on = (pos[:, 1] > COLLAR['y']) & (np.abs(pos[:, 0]) < COLLAR['half_width'])
            for t in tri[on[tri].all(1)]:
                d.polygon([tuple(uv[v]) for v in t], fill=255)
            on = (pos[:, 1] > KNEE_Y[0]) & (pos[:, 1] < KNEE_Y[1])
            for t in tri[on[tri].all(1)]:
                d.polygon([tuple(uv[v]) for v in t], fill=255)
    calm = np.asarray(calm.filter(ImageFilter.GaussianBlur(12))) / 255.0
    # V20: a soft edge instead of a hard one, so the triangle steps of the
    # painted bands blur out.
    soft = im.filter(ImageFilter.MaxFilter(5)).filter(ImageFilter.GaussianBlur(3))
    return np.asarray(soft) / 255.0, calm


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
        gloves = np.zeros(L.shape)
    lab, _ = ndimage.label(a[..., 3] > 8)
    sizes = ndimage.sum(np.ones_like(L), lab, range(1, lab.max() + 1))
    big = 1 + int(np.argmax(sizes))
    islands = ((lab > 0) & (lab != big)) if mark else np.zeros(L.shape, bool)
    glove = np.maximum(islands, gloves)[..., None]
    dark = GRAPHITE * (0.9 + 0.2 * (base / 60).clip(0, 1))[..., None] + 40 * line
    rgb = rgb * (1 - glove) + dark * glove
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

    for n in j['nodes']:
        name = n.get('name', '')
        if 'mesh' not in n:
            continue
        for k, f in SLIM.items():
            if k in name:
                sc = n.get('scale', [1, 1, 1])
                n['scale'] = [sc[0] * f, sc[1], sc[2] * f]
        if any(k in name for k in SMOOTH):
            smooth_normals(j, views, n['mesh'])
    for n in j['nodes']:
        for k, f in SHRINK.items():
            if k in n.get('name', '') and 'mesh' in n:
                for p in j['meshes'][n['mesh']]['primitives']:
                    P = accessor(j, views, p['attributes']['POSITION'])
                    c = P.mean(0)
                    P = c + (P - c) * f
                    put(j, views, p['attributes']['POSITION'], P)
                    acc = j['accessors'][p['attributes']['POSITION']]
                    acc['min'], acc['max'] = P.min(0).tolist(), P.max(0).tolist()
    add_headband(j, views, white)

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

    # V19: VRoid's dark-red outline drew a red edge round her; the matcap's
    # blue tint turned graphite navy; the cyan did not glow as on the sheet.
    for i in (suit, shoes):
        mt = mats[i]['extensions']['VRMC_materials_mtoon']
        mt['outlineColorFactor'] = [0.14, 0.14, 0.16]
        mt['matcapFactor'] = [0.35, 0.35, 0.35]
        mt['shadeColorFactor'] = [0.80, 0.81, 0.84]
    cyan = next(i for i, m in enumerate(mats) if m['name'] == 'ARISU_Cyan')
    mats[cyan]['emissiveFactor'] = [0.24, 0.93, 1.0]
    mats[cyan].setdefault('extensions', {})['KHR_materials_emissive_strength'] = {'emissiveStrength': 1.6}
    j.setdefault('extensionsUsed', [])
    if 'KHR_materials_emissive_strength' not in j['extensionsUsed']:
        j['extensionsUsed'].append('KHR_materials_emissive_strength')

    j['asset']['generator'] = j['asset'].get('generator', '') + ' + make_white_suit'
    write(dst, j, views)
    print(f'hid {hidden} nodes; repainted material {suit}; wrote {dst}')


if __name__ == '__main__':
    main(*sys.argv[1:3])
