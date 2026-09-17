import bpy, math, runpy
from mathutils import kdtree, Vector
scn=bpy.context.scene; vl=bpy.context.view_layer
wingstate={n:(tuple(bpy.data.objects[n].location),tuple(bpy.data.objects[n].rotation_euler)) for n in ('ARISU_Torso_ChestWing_-1','ARISU_Torso_ChestWing_1')}
runpy.run_path('/Users/oscar/Downloads/SCRIPT.py', run_name='__main__')
vl.update(); dg=bpy.context.evaluated_depsgraph_get()
b=bpy.data.objects['Body']; m=b.modifiers['ARISU_HIDE_TOPS01_RENDER']
print('MASK', m.show_viewport, m.show_render, 'BASE', len(b.data.vertices), len(b.data.polygons))
be=b.evaluated_get(dg); me=be.to_mesh(); print('EVALFACES', len(me.polygons))
bv=[be.matrix_world @ v.co for v in me.vertices]
kd=kdtree.KDTree(len(bv))
for i,v in enumerate(bv): kd.insert(Vector((v.x,0,v.z)), i)
kd.balance()
col=bpy.data.collections['ARISU_V1_EXOSUIT']
print('TORSO', len([o for o in col.objects if o.name.startswith('ARISU_Torso_')]))
print('ARMWHITE same', bpy.data.objects['ARISU_L_ForearmTopPlate'].material_slots[0].material == bpy.data.objects['ARISU_Torso_ChestFront'].material_slots[0].material, 'dup', bpy.data.materials.get('ARISU_ArmorWhite'))
for n in ('ARISU_Torso_ChestWing_-1','ARISU_Torso_ChestWing_1'):
    o=bpy.data.objects[n]; print('XFORM', n, 'loc', tuple(round(v,4) for v in o.location), 'rot_deg', tuple(round(math.degrees(v),2) for v in o.rotation_euler), 'dims', tuple(round(v,4) for v in o.dimensions))
for n in ('ARISU_Torso_ChestWing_-1','ARISU_Torso_ChestWing_1'):
    o=bpy.data.objects[n]; mw=o.matrix_world; c=mw.translation
    sgn=-1 if n.endswith('_-1') else 1
    outer=mw @ Vector((sgn*0.5,0,0)); inner=mw @ Vector((-sgn*0.5,0,0))
    print('WINGEDGE', n, 'outer edge y minus centre y mm', round((outer.y-c.y)*1000,1), '(positive = behind centre)', 'inner', round((inner.y-c.y)*1000,1))
cf=bpy.data.objects['ARISU_Torso_ChestFront']
print('CF mesh verts', len(cf.data.vertices), 'faces', len(cf.data.polygons))
print('WINGS unchanged', all((tuple(bpy.data.objects[n].location),tuple(bpy.data.objects[n].rotation_euler))==v for n,v in wingstate.items()))
from mathutils.bvhtree import BVHTree
bvh=BVHTree.FromPolygons(bv,[tuple(p.vertices) for p in me.polygons])
def wb(n):
    o=bpy.data.objects[n].evaluated_get(dg); ps=[o.matrix_world @ v.co for v in o.data.vertices]
    return tuple(round(f(getattr(p,a) for p in ps),4) for a in 'xyz' for f in (min,max))
for n in ('ARISU_Torso_ChestInset','ARISU_Torso_ChestArc','ARISU_Torso_ArcBreak','ARISU_Torso_RedStroke','ARISU_Torso_CyanNode','ARISU_Torso_ChestWing_-1','ARISU_Torso_ChestWing_1'):
    print('BOUNDS', n, 'x/y/z min,max', wb(n))
# shell front surface y near inset centre and at wing inner seam
def shell_front_y(x,z):
    hit,_,_,_=BVHTree.FromObject(bpy.data.objects['ARISU_Torso_ChestFront'], dg).ray_cast(Vector((x,-0.4,z)),Vector((0,1,0)),0.6)
    return round(hit.y,4) if hit else None
print('SHELLFRONT at x0 z1.135', shell_front_y(0,1.135), 'x0 z1.12', shell_front_y(0,1.12), 'x0.035 z1.13', shell_front_y(0.035,1.13), 'x+/-0.075 z1.133', shell_front_y(0.075,1.133), shell_front_y(-0.075,1.133))
cb=BVHTree.FromObject(bpy.data.objects['ARISU_Torso_ChestFront'], dg)
def sfy(x,z):
    h,_,_,_=cb.ray_cast(Vector((x,-0.4,z)),Vector((0,1,0)),0.6); return h.y if h else None
ib=wb('ARISU_Torso_ChestInset')
for (x,z) in ((0,1.128),(ib[0]+0.01,ib[4]+0.01),(ib[1]-0.01,ib[4]+0.01),(ib[0]+0.01,ib[5]-0.01),(ib[1]-0.01,ib[5]-0.01)):
    y=sfy(x,z); print('INSETGAP at', round(x,3), round(z,3), 'shell front', round(y,4), 'inset back', ib[3], 'gap mm', round((y-ib[3])*1000,1))
for n in ('ARISU_Torso_ChestWing_-1','ARISU_Torso_ChestWing_1'):
    o=bpy.data.objects[n].evaluated_get(dg); ps=[o.matrix_world @ v.co for v in o.data.vertices]
    inner=min(ps,key=lambda p:abs(p.x)); ix=abs(inner.x)
    innerpts=[p for p in ps if abs(abs(p.x)-ix)<0.004]
    sy=sfy(inner.x if n.endswith('1') and not n.endswith('_-1') else inner.x, 1.133)
    print('WINGSEAM', n, 'inner x', round(inner.x,4), 'inner-edge y range', round(min(p.y for p in innerpts),4), round(max(p.y for p in innerpts),4), 'local shell front', round(sy,4) if sy else None,
          '| inner back vs shell mm', round((max(p.y for p in innerpts)-sy)*1000,1) if sy else None, '(+ = behind shell = overlap, - = in front)',
          '| max forward of wing vs shell mm', round((sy-min(p.y for p in ps))*1000,1) if sy else None,
          '| outer vs inner back y mm', round((max(p.y for p in ps)-max(p.y for p in innerpts))*1000,1))
ibx=wb('ARISU_Torso_ChestInset')
for n in ('ARISU_Torso_ChestArc','ARISU_Torso_ArcBreak','ARISU_Torso_RedStroke','ARISU_Torso_CyanNode'):
    b=wb(n); print('EMBLEM', n, 'back y', b[3], 'gap to inset front mm', round((ibx[2]-b[3])*1000,1))
pb=wb('ARISU_Torso_PelvisBridge')
for (x,z) in ((0,(pb[4]+pb[5])/2),(pb[0]+0.01,pb[4]+0.005),(pb[1]-0.01,pb[4]+0.005),(pb[0]+0.01,pb[5]-0.005),(pb[1]-0.01,pb[5]-0.005),(0,pb[4]+0.003)):
    h,_,_,_=bvh.ray_cast(Vector((x,-0.4,z)),Vector((0,1,0)),0.6)
    print('PELVISGAP at', round(x,3), round(z,3), 'body front', round(h.y,4) if h else None, 'pelvis back', pb[3], 'gap mm', round((h.y-pb[3])*1000,1) if h else None)
for n in ('ARISU_Torso_ChestWing_-1','ARISU_Torso_ChestWing_1'):
    print('WINGLOCALDEPTH', n, round(max(v.co.y for v in bpy.data.objects[n].data.vertices)-min(v.co.y for v in bpy.data.objects[n].data.vertices),4))
pv=bpy.data.objects['ARISU_Torso_PelvisBridge']; PN=25
print('PELVIS mesh', len(pv.data.vertices), len(pv.data.polygons))
pbk=[pv.matrix_world @ pv.data.vertices[PN+k].co for k in range(PN)]
def bclr(p):
    h,_,_,_=bvh.ray_cast(Vector((p.x,-0.4,p.z)),Vector((0,1,0)),0.6); return (h.y-p.y)*1000 if h else None
pvc=[c for c in (bclr(p) for p in pbk) if c is not None]; pfine=[]; pworst=None
for r in range(4):
    for c in range(4):
        a,b2,d,e=pbk[r*5+c],pbk[r*5+c+1],pbk[(r+1)*5+c+1],pbk[(r+1)*5+c]
        for u in (0.25,0.5,0.75):
            for t in (0.25,0.5,0.75):
                p=a.lerp(b2,u).lerp(e.lerp(d,u),t); v=bclr(p)
                if v is not None:
                    pfine.append(v)
                    if pworst is None or v<pworst[0]: pworst=(v,round(p.x,3),round(p.z,3))
st=lambda L:(round(min(L),1),round(max(L),1),round(sum(L)/len(L),1),len(L))
print('PELVIS back vertex clearance mm', st(pvc)); print('PELVIS 9 pts/cell clearance mm', st(pfine), 'worst', pworst[1:])
print('WING rot unchanged', all(tuple(bpy.data.objects[n].rotation_euler)==v[1] for n,v in wingstate.items()))
# base-mesh back grid (81 back verts are indices 81..161); face centres + 3x3 interior points per cell
R=C=9; N=81
bw=[cf.matrix_world @ cf.data.vertices[N+k].co for k in range(N)]
def clr(p):
    hit,_,_,_=bvh.ray_cast(Vector((p.x,-0.4,p.z)),Vector((0,1,0)),0.6)
    return (hit.y-p.y)*1000 if hit else None
vc=[c for c in (clr(p) for p in bw) if c is not None]
fc=[]; fine=[]; worst=None
for r in range(R-1):
    for c in range(C-1):
        a,b2,d,e=bw[r*C+c],bw[r*C+c+1],bw[(r+1)*C+c+1],bw[(r+1)*C+c]
        cen=(a+b2+d+e)/4; v=clr(cen)
        if v is not None: fc.append(v)
        for u in (0.25,0.5,0.75):
            for t in (0.25,0.5,0.75):
                p=a.lerp(b2,u).lerp(e.lerp(d,u),t); v=clr(p)
                if v is not None:
                    fine.append(v)
                    if worst is None or v<worst[0]: worst=(v,round(p.x,3),round(p.z,3))
st=lambda L:(round(min(L),1),round(max(L),1),round(sum(L)/len(L),1),len(L))
print('BACK vertex clearance mm min/max/mean/n', st(vc))
print('BACK face-centre clearance mm min/max/mean/n', st(fc))
print('BACK 9 interior points per cell min/max/mean/n', st(fine), 'worst at x,z', worst[1:])
near=[clr(p) for p in [cf.matrix_world @ v.co for v in cf.data.vertices[N:]] if 0.045<=abs(p.x)<=0.075 and 1.13<=p.z<=1.17]
print('BACK verts near x +/-0.06 z~1.15 mm', [round(v,1) for v in near if v is not None])
fr=[cf.matrix_world @ cf.data.vertices[k].co for k in range(N)]
cenf=min(fr,key=lambda p:abs(p.x)+abs(p.z-1.135)); print('SHELL FRONT y near x0 z1.135', round(cenf.y,4), 'at', round(cenf.x,3), round(cenf.z,3))
for n in ('ARISU_Torso_ChestInset','ARISU_Torso_ChestArc','ARISU_Torso_ArcBreak','ARISU_Torso_RedStroke','ARISU_Torso_CyanNode','ARISU_Torso_PelvisBridge'):
    o=bpy.data.objects[n]; ys=[(o.matrix_world @ v.co).y for v in o.data.vertices]; print('WORLDY', n, 'loc', tuple(round(v,4) for v in o.location), 'world y', round(min(ys),4), '..', round(max(ys),4))
# local clearance: for each piece vertex, local body front surface = min y of body verts within 6 mm in x/z (front half only)
for n in ('ARISU_Torso_ChestWing_-1','ARISU_Torso_ChestWing_1','ARISU_Torso_AbRailUpper_-1','ARISU_Torso_AbRailUpper_1','ARISU_Torso_AbRailLower_-1','ARISU_Torso_AbRailLower_1','ARISU_Torso_PelvisBridge'):
    o=bpy.data.objects[n]; oe=o.evaluated_get(dg); om=oe.to_mesh(); ws=[oe.matrix_world @ v.co for v in om.vertices]
    ymax=max(w.y for w in ws); back=[w for w in ws if w.y>ymax-0.004]
    pen=[]; 
    for w in back:
        near=[bv[i].y for (_,i,_) in kd.find_range(Vector((w.x,0,w.z)),0.006) if bv[i].y<0.0]
        if near: pen.append(w.y-min(near))   # >0: vertex behind body front surface (inside), <0: gap
    oe.to_mesh_clear()
    if pen: print('LOCAL', n, 'back-face vertices sampled', len(pen), 'max penetration mm', round(max(pen)*1000,1), 'min gap mm', round(-max(pen)*1000,1) if max(pen)<0 else '-', 'smallest-depth mm', round(min(pen)*1000,1))
be.to_mesh_clear()
cam=scn.camera; od='/Users/oscar/Documents/claude-projects/arisu/v1-build'
def shot(name, ang, z, scale, x=0.0, w=1080, h=1080, elev=0.0):
    a=math.radians(ang); e=math.radians(elev); cam.data.ortho_scale=scale
    cam.location=(x+4*math.sin(a)*math.cos(e),-4*math.cos(a)*math.cos(e),z+4*math.sin(e)); cam.rotation_euler=(math.pi/2-e,0,a)
    scn.render.resolution_x, scn.render.resolution_y = w, h
    scn.render.filepath=f'{od}/arisu_TAG_{name}.png'; bpy.ops.render.render(write_still=True); print('RENDERED', name)
shot('front',0,0.85,1.9,h=1440); shot('three_quarter',35,0.85,1.9,h=1440); shot('side',90,0.85,1.9,h=1440); shot('back',180,0.85,1.9,h=1440)
shot('closeup_torso_front',0,1.05,0.42); shot('closeup_torso_three_quarter',35,1.05,0.42); shot('closeup_torso_side',90,1.05,0.42)
shot('closeup_torso_low_angle',0,1.0,0.42,elev=-35)
shot('closeup_torso_top_down',0,1.05,0.42,elev=60)
bpy.ops.wm.save_mainfile()
