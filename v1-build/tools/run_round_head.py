import bpy, math, runpy, bmesh, json, struct
from mathutils import Vector
from mathutils.bvhtree import BVHTree
scn=bpy.context.scene; vl=bpy.context.view_layer; arm=bpy.data.objects['Armature']; H=bpy.data.objects['Hair']
P='ARISU_Head_V225F_'; od='/Users/oscar/Documents/claude-projects/arisu/v1-build'; SP='/private/tmp/claude-501/-Users-oscar-Documents-claude-projects/36984f5e-f772-4a7a-bbe5-8e1d5a2aad12/scratchpad'
def ev(o):
    dg=bpy.context.evaluated_depsgraph_get(); oe=o.evaluated_get(dg)
    return [oe.matrix_world@v.co for v in oe.data.vertices],[tuple(p.vertices) for p in oe.data.polygons]
def bvh_of(o):
    pts,f=ev(o); return BVHTree.FromPolygons(pts,f)
def outermost(tree,y,z,s):
    o=Vector((0,y,z)); d=Vector((s,0,0)); last=None
    for _ in range(50):
        h,_,_,_=tree.ray_cast(o,d,0.3)
        if not h: break
        last=abs(h.x); o=h+d*1e-5
    return last
before_hair=bvh_of(H)
runpy.run_path('/Users/oscar/Downloads/arisu_v2_25f_covered_microchannel_cranial_interface.py', run_name='__main__')
vl.update()
parts=sorted([o for o in bpy.data.objects if o.name.startswith(P)],key=lambda o:o.name)
print('CLAUDE count',len(parts),'old_left',[n for n in bpy.data.objects.keys() if n.startswith('ARISU_Ear')],'parents',{(o.parent.name,o.parent_type,o.parent_bone,tuple(c.name for c in o.users_collection)) for o in parts})
for o in parts:
    b=bmesh.new(); b.from_mesh(o.data); k=[tuple(sorted(v.index for v in f.verts)) for f in b.faces]; nm=sum(1 for e in b.edges if not e.is_manifold)
    bef=[f.normal.copy() for f in b.faces]; bmesh.ops.recalc_face_normals(b,faces=b.faces); b.normal_update(); fl=sum(1 for f,n in zip(b.faces,bef) if f.normal.dot(n)<0)
    print('CLAUDE MESH',o.name,'faces',len(k),'dup',len(k)-len(set(k)),'nonmanifold',nm,'not_outward',fl); b.free()
fk=bpy.data.objects['Face'].data.shape_keys; x=arm.data.vrm_addon_extension
print('CLAUDE face keys',len(fk.key_blocks),'springs',len(x.spring_bone1.springs),'customs',tuple(c.custom_name for c in x.vrm1.expressions.custom),'body mask',bpy.data.objects['Body'].modifiers['ARISU_HIDE_TOPS01_RENDER'].show_render,'hair modifiers',[m.name for m in H.modifiers])
cg=H.vertex_groups['ARISU_HEADSET_CHANNEL_V225F_CORE']; bg=H.vertex_groups['ARISU_HEADSET_CHANNEL_V225F_BLEND']; hg=H.vertex_groups['J_Bip_C_Head']
deform={g.index for g in H.vertex_groups if g.name in arm.data.bones and arm.data.bones[g.name].use_deform}
core=[v for v in H.data.vertices if any(g.group==cg.index for g in v.groups)]; bl=[v for v in H.data.vertices if any(g.group==bg.index for g in v.groups)]
chset={v.index for v in core}|{v.index for v in bl}
badc=[v.index for v in core if not (any(g.group==hg.index and abs(g.weight-1)<1e-6 for g in v.groups) and all(g.group==hg.index or g.group not in deform or g.weight==0 for g in v.groups))]
hw=[sum(g.weight for g in v.groups if g.group==hg.index) for v in bl]
others=[sum(1 for g in v.groups if g.group in deform and g.group!=hg.index and g.weight>0) for v in bl]
sums=[sum(g.weight for g in v.groups if g.group in deform) for v in bl]
import statistics as stt
print('CLAUDE CHANNEL core',len(core),'core NOT head-only',len(badc),'| blend',len(bl),'head weight min/mean/max',round(min(hw),3),round(stt.mean(hw),3),round(max(hw),3),'blend verts with >=1 other deform group',sum(1 for o in others if o>=1),'deform weight sum min/max',round(min(sums),3),round(max(sums),3))
for mn in ('ARISU_Armor_White','ARISU_Head_White_V225F'):
    m=bpy.data.materials[mn]; ex=m.vrm_addon_extension.mtoon1
    print('CLAUDE MAT',mn,'diffuse',tuple(round(c,3) for c in m.diffuse_color),'vrm base_color_factor',tuple(round(c,3) for c in ex.pbr_metallic_roughness.base_color_factor),'shade_color_factor',tuple(round(c,3) for c in ex.extensions.vrmc_materials_mtoon.shade_color_factor),'nodes Color/Base Color inputs',[(n.name,i.name,tuple(round(c,2) for c in i.default_value)) for n in m.node_tree.nodes for i in n.inputs if i.name in ('Base Color','Color','Shade Color','Lit Color') and hasattr(i,'default_value') and hasattr(i.default_value,'__len__')][:8])
# module outline for classification
poly=[(-.026,1.426),(-.017,1.414),(.007,1.412),(.027,1.424),(.023,1.446),(.009,1.456),(-.014,1.452),(-.027,1.440)]
def inside(y,z):
    c=False
    for i in range(len(poly)):
        y1,z1=poly[i]; y2,z2=poly[i-1]
        if (z1>z)!=(z2>z) and y < (y2-y1)*(z-z1)/(z2-z1)+y1: c=not c
    return c
def collide(label):
    pts,faces=ev(H); hb=BVHTree.FromPolygons(pts,faces); res={}
    for side in ('L','R'):
        for part in ('TempleShell','ArmorBlade','CyanStatus','RearFin'):
            pairs=hb.overlap(bvh_of(bpy.data.objects[P+side+'_'+part]))
            hidden=cross=0
            for hi,_ in pairs:
                vs=[pts[i] for i in faces[hi]]
                if all(inside(v.y,v.z) for v in vs): hidden+=1
                else: cross+=1
            res[side+'_'+part]=(hidden,cross)
    print('CLAUDE COLLIDE',label,'(tri-pairs fully inside module outline = hidden, crossing the outline = potentially visible)',res)
    return pts
rest=collide('rest')
# dent: outer hair surface change in a ring 1-10 mm outside the outline
for side,s in (('L',1),('R',-1)):
    ah=bvh_of(H); d=[]
    for i in range(41):
        for j in range(31):
            y=-0.045+0.09*i/40; z=1.395+0.08*j/30
            if inside(y,z): continue
            # distance to outline approx: skip points far away
            near=min(math.hypot(y-py,z-pz) for py,pz in poly)
            if near>0.012: continue
            b0=outermost(before_hair,y,z,s); b1=outermost(ah,y,z,s)
            if b0 and b1: d.append(((b1-b0)*1000,y,z))
    d.sort()
    print('CLAUDE DENT',side,'outer hair surface change outside module (mm, - = pulled in): n',len(d),'min',round(d[0][0],2),'at y/z',round(d[0][1],3),round(d[0][2],3),'count < -1mm',sum(1 for v in d if v[0]<-1),'count < -3mm',sum(1 for v in d if v[0]<-3))
# channel margin: nearest non-channel hair vertex to shell perimeter
pts,_=ev(H)
for side,s in (('L',1),('R',-1)):
    sh=bpy.data.objects[P+side+'_TempleShell']; spts,sf=ev(sh); sb=BVHTree.FromPolygons(spts,sf)
    m=min(sb.find_nearest(pts[i])[3] for i in range(len(pts)) if i not in chset and abs(pts[i].x)>0.07 and -0.05<pts[i].y<0.06 and 1.39<pts[i].z<1.48)
    print('CLAUDE MARGIN',side,'nearest non-core/non-blend hair vertex to shell surface mm',round(m*1000,2))
# sway
coreidx=sorted(v.index for v in core); chidx=coreidx; c0=[pts[i].copy() for i in chidx]
edges=[(e.vertices[0],e.vertices[1]) for e in H.data.edges if (e.vertices[0] in chset) or (e.vertices[1] in chset)]
L0=[(pts[a]-pts[b]).length for a,b in edges]
for ax,ang in (('x',15),('x',-15),('z',15),('z',-15)):
    for b in arm.pose.bones:
        if b.name.startswith(('J_Sec_Hair1_','J_Sec_Hair2_')): b.rotation_mode='XYZ'; b.rotation_euler=(0,0,0); setattr(b.rotation_euler,ax,math.radians(ang))
    vl.update(); p2=collide(f'sway {ax}{ang}')
    mv=max((p2[i]-c).length for i,c in zip(chidx,c0)); rs=sorted(((p2[a]-p2[b]).length/l) for (a,b),l in zip(edges,L0) if l>1e-6)
    print('CLAUDE SWAY',ax,ang,'core verts max move mm',round(mv*1000,3),'stretch ratio over all edges touching core/blend verts: max',round(rs[-1],2),'p95',round(rs[int(.95*len(rs))],3),'p99',round(rs[int(.99*len(rs))],3),'n',len(rs),'edges >1.5x',sum(1 for r in rs if r>1.5))
for b in arm.pose.bones:
    if b.name.startswith(('J_Sec_Hair1_','J_Sec_Hair2_')): b.rotation_euler=(0,0,0)
vl.update(); collide('restored')
pb=arm.pose.bones['J_Bip_C_Head']; pb.rotation_mode='XYZ'
def rel(): vl.update(); hm=arm.matrix_world@pb.matrix; return [hm.inverted()@o.matrix_world for o in parts]
r0=rel()
for ang in (15,-15):
    pb.rotation_euler=(0,math.radians(ang),0); r=rel(); hm=arm.matrix_world@pb.matrix
    p3,_=ev(H); herr=max(((hm.inverted()@p3[i])-(r0 and (arm.matrix_world@arm.data.bones['J_Bip_C_Head'].matrix_local).inverted()@c)).length for i,c in zip(chidx,c0))
    err=max(max(abs(a[i][j]-b[i][j]) for i in range(4) for j in range(4)) for a,b in zip(r,r0))
    print('CLAUDE YAW',ang,'module rel err',f'{err:.1e}','channel hair verts deviation from head-rigid mm',round(herr*1000,3))
    if ang==15:
        cam=scn.camera; cam.data.ortho_scale=0.42; cam.location=(0,-4,1.44); cam.rotation_euler=(math.pi/2,0,0); scn.render.resolution_x=scn.render.resolution_y=1080
        scn.render.filepath=od+'/arisu_v2_25f_posetest_yaw15.png'; bpy.ops.render.render(write_still=True)
pb.rotation_euler=(0,0,0); vl.update()
cam=scn.camera
def shot(name, ang, z, scale, w=1080, h=1080):
    a=math.radians(ang); cam.data.ortho_scale=scale; cam.location=(4*math.sin(a),-4*math.cos(a),z); cam.rotation_euler=(math.pi/2,0,a)
    scn.render.resolution_x, scn.render.resolution_y = w, h; scn.render.filepath=f'{od}/arisu_v2_25f_{name}.png'; bpy.ops.render.render(write_still=True); print('RENDERED', name)
for n,a in (('front',0),('three_quarter',35),('side',90),('back',180)): shot(n,a,0.85,2.0,1080,1920)
for n,a in (('head_front',0),('head_three_quarter',35),('head_side',90),('head_back',180)): shot(n,a,1.44,0.42)
shot('head_three_quarter_close',50,1.44,0.2)
# export
fp=SP+'/v225f_test_export.vrm'
print('CLAUDE EXPORT result',bpy.ops.export_scene.vrm(filepath=fp, ignore_warning=True, armature_object_name='Armature'))
raw=open(fp,'rb').read(); jl=struct.unpack('<I',raw[12:16])[0]; j=json.loads(raw[20:20+jl]); bo=20+jl+8
names={i:n.get('name') for i,n in enumerate(j['nodes'])}; par={c:i for i,n in enumerate(j['nodes']) for c in n.get('children',[])}
mats=[(m.get('name'),m.get('pbrMetallicRoughness',{}).get('baseColorFactor')) for m in j['materials'] if 'White' in m.get('name','')]; print('CLAUDE EXPORT white materials baseColorFactor',mats); print('CLAUDE EXPORT MB',round(len(raw)/1e6,2),'springs',len(j['extensions']['VRMC_springBone']['springs']),'module parents',sorted({names.get(par.get(i)) for i in names if 'V225F' in (names[i] or '')}))
def acc(i,fmt,sz):
    a=j['accessors'][i]; bv=j['bufferViews'][a['bufferView']]; s=bo+bv.get('byteOffset',0)+a.get('byteOffset',0); stride=bv.get('byteStride',struct.calcsize(fmt))
    return [struct.unpack_from(fmt,raw,s+stride*k) for k in range(a['count'])]
chw=[pts[v.index] for v in core]; blw=[pts[v.index] for v in bl]
for ni,n in enumerate(j['nodes']):
    if 'mesh' not in n or 'Hair' not in j['meshes'][n['mesh']]['name']: continue
    joints=[names[k] for k in j['skins'][n['skin']]['joints']]
    for sgn in (1,-1):
        keyset={(round(abs(p.x),4),round(p.z,4),round(sgn*p.y,4)) for p in chw}; bkey={(round(abs(p.x),4),round(p.z,4),round(sgn*p.y,4)) for p in blw}; bh=[]; bo_=[]
        hit=0; headw=[]; 
        for pr in j['meshes'][n['mesh']]['primitives']:
            pos=acc(pr['attributes']['POSITION'],'<fff',12)
            jt=j['accessors'][pr['attributes']['JOINTS_0']]['componentType']; J=acc(pr['attributes']['JOINTS_0'],'<4B' if jt==5121 else '<4H',4); W=acc(pr['attributes']['WEIGHTS_0'],'<4f',16)
            for p,jj,ww in zip(pos,J,W):
                if (round(abs(p[0]),4),round(p[1],4),round(p[2],4)) in keyset:
                    hit+=1; headw.append(sum(w for jn,w in zip(jj,ww) if joints[jn]=='J_Bip_C_Head'))
                k=(round(abs(p[0]),4),round(p[1],4),round(p[2],4))
                if k in bkey: bh.append(sum(w for jn,w in zip(jj,ww) if joints[jn]=='J_Bip_C_Head')); bo_.append(sum(1 for jn,w in zip(jj,ww) if w>0 and joints[jn]!='J_Bip_C_Head'))
        if hit: print('CLAUDE EXPORT channel vertices matched',hit,'(sign',sgn,') head weight min/max',round(min(headw),4),round(max(headw),4),'| core verts in Blender',len(chw),'| blend matched',len(bh),'of',len(blw),'exported head weight min/max',round(min(bh),3) if bh else None,round(max(bh),3) if bh else None,'blend verts with other joints',sum(1 for x in bo_ if x>0))
