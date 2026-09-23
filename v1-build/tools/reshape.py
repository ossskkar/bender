"""Change her proportions in the VRM itself -- Blender's "apply pose as rest".

Each bone may carry a scale for its own vertices and a scale for the offsets
to its children, in the bone's local frame (VRoid bones point down +y). The
skeleton is re-posed with those scales, every skinned vertex, normal and blend
shape delta is baked into that pose, and the pose without its scales becomes
the new rest: new bone translations, new inverse bind matrices, same rotations.
Rotations never change, so the VRMA clips, which carry rotations plus a hips
translation that three-vrm-animation rescales by hips height, still fit.

A uniform scale on a bone applies to its whole subtree (the head: hair bones,
headset, face). Non-skinned meshes under a scaled bone move and scale with it;
spring colliders and joint radii in a scaled subtree scale too.

    python3 reshape.py <in.vrm> <out.vrm>
"""
import json, sys
import numpy as np
sys.path.insert(0, __file__.rsplit('/', 1)[0])
from make_white_suit import read, write, accessor, put, quat_mat

# name -> (own vertex scale xyz, child offset scale xyz, whole subtree?)
HEAD = 0.92
LEG = 1.06
THIGH_SLIM = 0.95
RESHAPE = {
    'J_Bip_C_Head': ((HEAD,) * 3, (HEAD,) * 3, True),
    'J_Bip_L_UpperLeg': ((THIGH_SLIM, LEG, THIGH_SLIM), (1, LEG, 1), False),
    'J_Bip_R_UpperLeg': ((THIGH_SLIM, LEG, THIGH_SLIM), (1, LEG, 1), False),
    'J_Bip_L_LowerLeg': ((1, LEG, 1), (1, LEG, 1), False),
    'J_Bip_R_LowerLeg': ((1, LEG, 1), (1, LEG, 1), False),
}


def trs(node):
    M = np.eye(4)
    M[:3, :3] = quat_mat(node.get('rotation', [0, 0, 0, 1])) * np.array(node.get('scale', [1, 1, 1]))
    M[:3, 3] = node.get('translation', [0, 0, 0])
    return M


def main(src, dst):
    j, binchunk = read(src)
    views = [bytes(binchunk[bv.get('byteOffset', 0):bv.get('byteOffset', 0) + bv['byteLength']])
             for bv in j['bufferViews']]
    nodes = j['nodes']
    parent = {c: i for i, n in enumerate(nodes) for c in n.get('children', [])}
    byname = {n.get('name'): i for i, n in enumerate(nodes)}

    own = [np.ones(3) for _ in nodes]        # scale of a bone's own vertices
    off = [np.ones(3) for _ in nodes]        # scale of offsets to its children
    subtree = [1.0] * len(nodes)             # uniform factor inherited from above
    for name, (o, c, whole) in RESHAPE.items():
        i = byname[name]
        own[i], off[i] = np.array(o, float), np.array(c, float)
        if whole:
            stack = list(nodes[i].get('children', []))
            while stack:
                k = stack.pop()
                subtree[k] = o[0]
                stack += nodes[k].get('children', [])
    for k, f in enumerate(subtree):
        if f != 1.0:
            own[k] = own[k] * f
            off[k] = off[k] * f

    # Old rest worlds, and new ones: same rotations, child offsets scaled.
    old_world, new_world = [None] * len(nodes), [None] * len(nodes)
    order = [i for i in range(len(nodes)) if i not in parent]
    new_t = {}
    k = 0
    while k < len(order):
        i = order[k]; k += 1
        n = nodes[i]
        L = trs(n)
        p = parent.get(i)
        if p is None:
            old_world[i] = L
            new_world[i] = L.copy()
        else:
            old_world[i] = old_world[p] @ L
            t = np.array(n.get('translation', [0, 0, 0])) * off[p]
            new_t[i] = t
            Ln = L.copy(); Ln[:3, 3] = t
            new_world[i] = new_world[p] @ Ln
        order += n.get('children', [])

    # Feet stay on the floor: the legs grew, so the hips rise by as much.
    feet = [byname['J_Bip_L_Foot'], byname['J_Bip_R_Foot']]
    drop = np.mean([old_world[f][1, 3] - new_world[f][1, 3] for f in feet])
    hips = byname['J_Bip_C_Hips']
    new_t[hips] = new_t.get(hips, np.array(nodes[hips]['translation'])) + [0, drop, 0]
    for i in order:                          # recompute worlds with the lift
        p = parent.get(i)
        if p is not None:
            L = trs(nodes[i]); L[:3, 3] = new_t[i]
            new_world[i] = new_world[p] @ L

    def deform(i):
        """Where a bone's own vertices go: its new place, scaled in its frame."""
        D = new_world[i].copy()
        D[:3, :3] = D[:3, :3] @ np.diag(own[i])
        return D

    done = set()
    for n in nodes:
        if 'mesh' not in n or 'skin' not in n:
            continue
        skin = j['skins'][n['skin']]
        joints = skin['joints']
        ibm = accessor(j, views, skin['inverseBindMatrices']).reshape(-1, 4, 4).transpose(0, 2, 1)
        X = np.array([deform(b) @ ibm[q] for q, b in enumerate(joints)])     # bind -> new
        for p in j['meshes'][n['mesh']]['primitives']:
            at = p['attributes']
            if at['POSITION'] in done:
                continue
            J = accessor(j, views, at['JOINTS_0']).astype(int)
            W = accessor(j, views, at['WEIGHTS_0'])
            W = W / W.sum(1, keepdims=True).clip(1e-9)
            M = np.einsum('vk,vkab->vab', W, X[J])                         # per-vertex blend
            P = accessor(j, views, at['POSITION'])
            P2 = np.einsum('vab,vb->va', M[:, :3, :3], P) + M[:, :3, 3]
            put(j, views, at['POSITION'], P2)
            acc = j['accessors'][at['POSITION']]
            acc['min'], acc['max'] = P2.min(0).tolist(), P2.max(0).tolist()
            if 'NORMAL' in at and at['NORMAL'] not in done:
                Nn = accessor(j, views, at['NORMAL'])
                Ninv = np.linalg.inv(M[:, :3, :3]).transpose(0, 2, 1)
                N2 = np.einsum('vab,vb->va', Ninv, Nn)
                put(j, views, at['NORMAL'], N2 / np.linalg.norm(N2, axis=1, keepdims=True).clip(1e-9))
                done.add(at['NORMAL'])
            for tgt in p.get('targets', []):
                if 'POSITION' in tgt and tgt['POSITION'] not in done:
                    acc = j['accessors'][tgt['POSITION']]
                    if 'bufferView' not in acc or 'sparse' in acc:
                        continue                       # an all-zero target
                    Dl = accessor(j, views, tgt['POSITION'])
                    D2 = np.einsum('vab,vb->va', M[:, :3, :3], Dl)
                    put(j, views, tgt['POSITION'], D2)
                    acc['min'], acc['max'] = D2.min(0).tolist(), D2.max(0).tolist()
                    done.add(tgt['POSITION'])
            done.add(at['POSITION'])
        new_ibm = np.array([np.linalg.inv(new_world[b]) for b in joints]).transpose(0, 2, 1)
        put(j, views, skin['inverseBindMatrices'], new_ibm.reshape(-1))

    # New rest translations; meshes hanging off a scaled bone scale with it.
    for i, t in new_t.items():
        nodes[i]['translation'] = [float(v) for v in t]
        p = parent.get(i)
        if 'mesh' in nodes[i] and 'skin' not in nodes[i] and p is not None and subtree[i] != 1.0:
            nodes[i]['scale'] = (np.array(nodes[i].get('scale', [1, 1, 1])) * subtree[i]).tolist()

    ext = j.get('extensions', {})
    sb = ext.get('VRMC_springBone', {})
    for c in sb.get('colliders', []):
        f = subtree[c['node']] if c['node'] != byname['J_Bip_C_Head'] else HEAD
        for shape in c.get('shape', {}).values():
            if 'radius' in shape:
                shape['radius'] *= f
            for key in ('offset', 'tail'):
                if key in shape:
                    shape[key] = [v * f for v in shape[key]]
    for s in sb.get('springs', []):
        for jn in s.get('joints', []):
            if 'hitRadius' in jn:
                jn['hitRadius'] *= subtree[jn['node']]
    look = ext.get('VRMC_vrm', {}).get('lookAt', {})
    if 'offsetFromHeadBone' in look:
        look['offsetFromHeadBone'] = [v * HEAD for v in look['offsetFromHeadBone']]

    j['asset']['generator'] = j['asset'].get('generator', '') + ' + reshape'
    write(dst, j, views)
    print(f'hips +{drop * 100:.1f} cm; reshaped {len(RESHAPE)} bones; wrote {dst}')


if __name__ == '__main__':
    main(*sys.argv[1:3])
