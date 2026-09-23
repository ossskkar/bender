"""Small rigid parts from the sheet, attached to bones: the white hip plates
with their red marks at the belt line.

Each part is a bevelled box placed on the suit's surface (found from the
body mesh), turned to face along the surface, and parented to a bone so it
moves with her. Run after long_hair.py (final coordinates).

    python3 add_parts.py <in.vrm> <out.vrm>
"""
import sys
import numpy as np
sys.path.insert(0, __file__.rsplit('/', 1)[0])
from make_white_suit import read, write, accessor, world_matrix, add_blob

# name, bone, (x, y) on her front in metres, box size (w, h, d), material, lift
PARTS = [
    ('ARISU_L_HipPlate', 'J_Bip_C_Hips', (0.088, 0.945), (0.052, 0.026, 0.010), 'ARISU_Head_White_V225F', 0.002),
    ('ARISU_R_HipPlate', 'J_Bip_C_Hips', (-0.088, 0.945), (0.052, 0.026, 0.010), 'ARISU_Head_White_V225F', 0.002),
    ('ARISU_L_HipMark', 'J_Bip_C_Hips', (0.096, 0.945), (0.010, 0.010, 0.004), 'ARISU_Red', 0.009),
    ('ARISU_R_HipMark', 'J_Bip_C_Hips', (-0.096, 0.945), (0.010, 0.010, 0.004), 'ARISU_Red', 0.009),
]
BEVEL = 0.25        # fraction of the smaller face size cut off each corner


def box(w, h, d):
    """A box with chamfered front edges, front face towards +z, back at z=0."""
    bw, bh = w / 2, h / 2
    c = min(w, h) * BEVEL
    front = [(-bw + c, -bh), (bw - c, -bh), (bw, -bh + c), (bw, bh - c),
             (bw - c, bh), (-bw + c, bh), (-bw, bh - c), (-bw, -bh + c)]
    V, N, I = [], [], []
    def quad(a, b, cc, dd, n):
        k = len(V)
        V.extend([a, b, cc, dd]); N.extend([n] * 4)
        I.extend([k, k + 1, k + 2, k, k + 2, k + 3])
    k = len(V)                                        # front octagon, a fan
    for x, y in front:
        V.append((x, y, d)); N.append((0, 0, 1))
    for i in range(1, 7):
        I.extend([k, k + i, k + i + 1])
    for i in range(8):                                # sides
        (x0, y0), (x1, y1) = front[i], front[(i + 1) % 8]
        n = np.array([y1 - y0, -(x1 - x0), 0.0])
        n /= np.linalg.norm(n)
        quad((x0, y0, 0), (x1, y1, 0), (x1, y1, d), (x0, y0, d), tuple(n))
    return np.array(V, float), np.array(N, float), I


def main(src, dst):
    j, binchunk = read(src)
    views = [bytes(binchunk[bv.get('byteOffset', 0):bv.get('byteOffset', 0) + bv['byteLength']])
             for bv in j['bufferViews']]
    body = next(n for n in j['nodes'] if n.get('name') == 'Body')
    P = np.vstack([accessor(j, views, p['attributes']['POSITION'])
                   for p in j['meshes'][body['mesh']]['primitives']])
    mats = {m['name']: i for i, m in enumerate(j['materials'])}
    for name, bone, (x, y), size, mat, lift in PARTS:
        near = P[(np.abs(P[:, 0] - x) < 0.01) & (np.abs(P[:, 1] - y) < 0.01)]
        front = near[near[:, 2].argmax()]
        # The surface's slope across her: the front-most points either side.
        side = lambda dx: P[(np.abs(P[:, 0] - (x + dx)) < 0.006) & (np.abs(P[:, 1] - y) < 0.01)][:, 2].max()
        dzdx = (side(0.012) - side(-0.012)) / 0.024
        yaw = np.arctan2(-dzdx, 1.0)
        R = np.array([[np.cos(yaw), 0, np.sin(yaw)], [0, 1, 0], [-np.sin(yaw), 0, np.cos(yaw)]])
        V, N, I = box(*size)
        centre = np.array([x, y, front[2] + lift - 0.004])
        Vw = (R @ V.T).T + centre
        Nw = (R @ N.T).T
        b = next(i for i, n in enumerate(j['nodes']) if n.get('name') == bone)
        inv = np.linalg.inv(world_matrix(j, b))
        Vl = (inv[:3, :3] @ Vw.T).T + inv[:3, 3]
        Nl = (inv[:3, :3] @ Nw.T).T
        Nl /= np.linalg.norm(Nl, axis=1)[:, None]
        acc = []
        for arr in (Vl, Nl):
            bv = add_blob(j, views, arr.astype(np.float32).tobytes(), 34962)
            a = {'bufferView': bv, 'componentType': 5126, 'count': len(arr), 'type': 'VEC3'}
            if not acc:
                a['min'], a['max'] = Vl.min(0).tolist(), Vl.max(0).tolist()
            j['accessors'].append(a)
            acc.append(len(j['accessors']) - 1)
        bv = add_blob(j, views, np.array(I, np.uint16).tobytes(), 34963)
        j['accessors'].append({'bufferView': bv, 'componentType': 5123, 'count': len(I), 'type': 'SCALAR'})
        j['meshes'].append({'name': name, 'primitives': [{
            'attributes': {'POSITION': acc[0], 'NORMAL': acc[1]},
            'indices': len(j['accessors']) - 1, 'material': mats[mat]}]})
        j['nodes'].append({'name': name, 'mesh': len(j['meshes']) - 1})
        j['nodes'][b].setdefault('children', []).append(len(j['nodes']) - 1)
    j['asset']['generator'] = j['asset'].get('generator', '') + ' + add_parts'
    write(dst, j, views)
    print(f'added {len(PARTS)} parts; wrote {dst}')


if __name__ == '__main__':
    main(*sys.argv[1:3])
