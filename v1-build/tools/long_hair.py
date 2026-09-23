"""Lengthen her hair toward the sheet's: to the hips instead of mid-back.

Everything of the hair below Y0 is stretched downward by K -- the hair mesh's
vertices, and the rest positions of the hair spring bones -- so the strands
and the physics that swings them keep matching. Rotations are unchanged; the
inverse bind matrices are rebuilt for the moved bones. A hips collider is
added so the longer hair rests on her rather than through her.

    python3 long_hair.py <in.vrm> <out.vrm>
"""
import sys
import numpy as np
sys.path.insert(0, __file__.rsplit('/', 1)[0])
from make_white_suit import read, write, accessor, put
from reshape import trs

Y0 = 1.30          # metres: where the stretch starts (shoulder level)
K = 1.45           # 1.015 m hair tips -> ~0.89 m, the sheet's hip line
# The sheet's fringe parts on her left and sweeps to her right (viewer's
# left); hers was a centre part. Front hair
# moves sideways, more toward the tips, fading out at the side locks.
SWEEP = dict(top=1.535, k=0.22, front_z=0.03, side_x=(0.05, 0.085))
HIPS_COLLIDER = dict(offset=[0.0, 0.02, -0.03], radius=0.13)


def warp(p):
    p = np.array(p, float)
    below = p[..., 1] < Y0
    p[..., 1] = np.where(below, Y0 - (Y0 - p[..., 1]) * K, p[..., 1])
    return p


def main(src, dst):
    j, binchunk = read(src)
    views = [bytes(binchunk[bv.get('byteOffset', 0):bv.get('byteOffset', 0) + bv['byteLength']])
             for bv in j['bufferViews']]
    nodes = j['nodes']
    parent = {c: i for i, n in enumerate(nodes) for c in n.get('children', [])}

    def world(i):
        M = trs(nodes[i])
        while i in parent:
            i = parent[i]
            M = trs(nodes[i]) @ M
        return M

    # Hair bones, top of each chain first, so a parent moves before its child.
    hair = [i for i, n in enumerate(nodes) if n.get('name', '').startswith('J_Sec_Hair')]
    depth = lambda i: 0 if i not in parent else 1 + depth(parent[i])
    hair.sort(key=depth)
    old = {i: world(i) for i in hair}
    for i in hair:
        target = warp(old[i][:3, 3])
        pw = world(parent[i])
        nodes[i]['translation'] = (np.linalg.inv(pw) @ np.r_[target, 1])[:3].tolist()

    mesh_node = next(n for n in nodes if n.get('name') == 'Hair')
    skin = j['skins'][mesh_node['skin']]
    ibm = accessor(j, views, skin['inverseBindMatrices']).reshape(-1, 4, 4)
    for q, b in enumerate(skin['joints']):
        ibm[q] = np.linalg.inv(world(b)).T
    put(j, views, skin['inverseBindMatrices'], ibm.reshape(-1))
    def sweep(P):
        P = P.copy()
        t = np.clip(SWEEP['top'] - P[:, 1], 0, None)
        front = np.clip((P[:, 2] - SWEEP['front_z']) / 0.02, 0, 1)
        lo, hi = SWEEP['side_x']
        centre = 1 - np.clip((np.abs(P[:, 0]) - lo) / (hi - lo), 0, 1)
        P[:, 0] += SWEEP['k'] * t * front * centre
        return P

    for p in j['meshes'][mesh_node['mesh']]['primitives']:
        a = p['attributes']['POSITION']
        P = sweep(warp(accessor(j, views, a)))
        put(j, views, a, P)
        j['accessors'][a]['min'], j['accessors'][a]['max'] = P.min(0).tolist(), P.max(0).tolist()
    # Other skins that share a hair joint must agree on its inverse bind.
    for s in j['skins']:
        if s is skin:
            continue
        m = accessor(j, views, s['inverseBindMatrices']).reshape(-1, 4, 4)
        for q, b in enumerate(s['joints']):
            if b in old:
                m[q] = np.linalg.inv(world(b)).T
        put(j, views, s['inverseBindMatrices'], m.reshape(-1))

    sb = j['extensions']['VRMC_springBone']
    hips = next(i for i, n in enumerate(nodes) if n.get('name') == 'J_Bip_C_Hips')
    sb['colliders'].append({'node': hips, 'shape': {'sphere': HIPS_COLLIDER}})
    new = len(sb['colliders']) - 1
    for g in sb.get('colliderGroups', []):
        g['colliders'].append(new)

    j['asset']['generator'] = j['asset'].get('generator', '') + ' + long_hair'
    write(dst, j, views)
    print(f'moved {len(hair)} hair bones; hair to {Y0 - (Y0 - 1.015) * K:.2f} m; wrote {dst}')


if __name__ == '__main__':
    main(*sys.argv[1:3])
