import bpy, math, runpy, json, struct, statistics as stt
from mathutils import Vector, Quaternion
from mathutils.bvhtree import BVHTree
scn=bpy.context.scene; vl=bpy.context.view_layer; arm=bpy.data.objects['Armature']; body=bpy.data.objects['Body']
od='/Users/oscar/Documents/claude-projects/arisu/v1-build'; SP='/private/tmp/claude-501/-Users-oscar-Documents-claude-projects/36984f5e-f772-4a7a-bbe5-8e1d5a2aad12/scratchpad'
coll=bpy.data.collections['ARISU_V1_EXOSUIT']
print('CLAUDE PRE ARISU meshes in collection',sum(1 for o in coll.objects if o.type=='MESH' and o.name.startswith('ARISU_')),'in scene',sum(1 for o in bpy.data.objects if o.type=='MESH' and o.name.startswith('ARISU_')))
hair=bpy.data.objects['Hair']
def wsig(o): return {g.name:[round(g.weight(v.index),6) if any(x.group==g.index for x in v.groups) else 0 for v in o.data.vertices] for g in o.vertex_groups if g.name in ('J_Bip_C_Head','ARISU_HEADSET_CHANNEL_V225F_CORE','ARISU_HEADSET_CHANNEL_V225F_BLEND')}
hw0=wsig(hair)
runpy.run_path('/Users/oscar/Downloads/arisu_v2_26b_armour_skeletal_attachment.py', run_name='__main__')
vl.update()
print('CLAUDE hair channel weights unchanged',wsig(hair)==hw0)
inv={r['name']:r for r in json.load(open(od+'/arisu_v2_25f_armour_inventory.json'))}
exec(open(SP+'/inv_sugg.py').read())  # defines SUG name->suggested bone text
ar=sorted([o for o in bpy.data.objects if o.type=='MESH' and o.name.startswith('ARISU_')],key=lambda o:o.name)
heads=[o for o in ar if o.name.startswith('ARISU_Head_V225F_')]
roots=[o.name for o in ar if o.parent is None and not any(m.type=='ARMATURE' for m in o.modifiers)]
double=[o.name for o in ar if o.parent and any(m.type=='ARMATURE' for m in o.modifiers)]
rigid=[o for o in ar if o not in heads and o.parent==arm and o.parent_type=='BONE']
skin=[o for o in ar if any(m.type=='ARMATURE' for m in o.modifiers)]
print('CLAUDE AUDIT total',len(ar),'heads',len(heads),'head parents',{o.parent_bone for o in heads},'roots',roots,'double',double,'rigid',len(rigid),'skinned',len(skin))
deform={b.name for b in arm.data.bones if b.use_deform}
for o in skin:
    sums=[]; unw=0; groups=set()
    for v in o.data.vertices:
        s=0
        for g in v.groups:
            nm=o.vertex_groups[g.group].name
            if nm in deform and g.weight>0: s+=g.weight; groups.add(nm)
        sums.append(s); unw+= s<=1e-6
    tot={}
    for v in o.data.vertices:
        for g in v.groups:
            nm=o.vertex_groups[g.group].name
            if nm in deform and g.weight>0: tot[nm]=tot.get(nm,0)+g.weight
    print('CLAUDE SKIN',o.name,'mods',[(m.name,m.type) for m in o.modifiers],'parent',o.parent,'verts',len(sums),'vgroups',len(o.vertex_groups),'unweighted',unw,'sum min/max',round(min(sums),4),round(max(sums),4),'nonzero deform bone totals',{k:round(v,2) for k,v in sorted(tot.items(),key=lambda x:-x[1])},'toebase groups present',[g.name for g in o.vertex_groups if 'ToeBase' in g.name])
print('CLAUDE MISMATCH table (rigid): object | inventory suggestion | V2.26 bone')
mm=0
for o in rigid:
    s=SUG.get(o.name,'?'); ok=o.parent_bone in s
    if not ok: mm+=1; print('CLAUDE MISMATCH',o.name,'|',s,'|',o.parent_bone)
print('CLAUDE MISMATCH count',mm,'of',len(rigid))
print('CLAUDE RIGID map',{o.name:o.parent_bone for o in rigid})
# body-relative distance metric
def body_bvh():
    dg=bpy.context.evaluated_depsgraph_get(); be=body.evaluated_get(dg)
    return BVHTree.FromPolygons([be.matrix_world@v.co for v in be.data.vertices],[tuple(p.vertices) for p in be.data.polygons])
def dist_stats():
    bb=body_bvh(); dg=bpy.context.evaluated_depsgraph_get(); res={}
    for o in ar:
        if o in heads: continue
        oe=o.evaluated_get(dg); ds=[]
        for v in list(oe.data.vertices)[::max(1,len(oe.data.vertices)//200)]:
            p=oe.matrix_world@v.co; h,n,i,d=bb.find_nearest(p)
            if h is not None: ds.append(d if (p-h).dot(n)>=0 else -d)
        res[o.name]=(stt.median(ds),min(ds))
    return res
rest=dist_stats()
pbs=arm.pose.bones
def rot(bn,axis,deg):
    pb=pbs[bn]; b=arm.data.bones[bn]; a=(arm.matrix_world.to_3x3()@b.matrix_local.to_3x3()).inverted()@Vector(axis)
    pb.rotation_mode='QUATERNION'; pb.rotation_quaternion=Quaternion(a.normalized(),math.radians(deg))@pb.rotation_quaternion
def reset():
    for pb in pbs: pb.rotation_mode='QUATERNION'; pb.rotation_quaternion=(1,0,0,0)
    vl.update()
POSES={
 'arms_down30_elbow45':[('J_Bip_L_UpperArm',(0,1,0),30),('J_Bip_R_UpperArm',(0,1,0),-30),('J_Bip_L_LowerArm',(0,0,1),-45),('J_Bip_R_LowerArm',(0,0,1),45)],
 'arms_up30':[('J_Bip_L_UpperArm',(0,1,0),-30),('J_Bip_R_UpperArm',(0,1,0),30)],
 'legs_hip25_knee45_foot20':[('J_Bip_L_UpperLeg',(1,0,0),-25),('J_Bip_R_UpperLeg',(1,0,0),-25),('J_Bip_L_LowerLeg',(1,0,0),45),('J_Bip_R_LowerLeg',(1,0,0),45),('J_Bip_L_Foot',(1,0,0),-20),('J_Bip_R_Foot',(1,0,0),-20)],
 'torso_bend15_twist15':[('J_Bip_C_Spine',(1,0,0),15),('J_Bip_C_Chest',(0,0,1),15)],
 'conversation':[('J_Bip_L_UpperArm',(0,1,0),60),('J_Bip_R_UpperArm',(0,1,0),-60),('J_Bip_L_LowerArm',(0,0,1),-30),('J_Bip_R_LowerArm',(0,0,1),30),('J_Bip_C_Spine',(1,0,0),5),('J_Bip_C_Chest',(0,0,1),-8),('J_Bip_L_UpperLeg',(1,0,0),-8),('J_Bip_L_LowerLeg',(1,0,0),12)],
}
cam=scn.camera
def shot(name, ang, z, scale, w=1080, h=1920):
    a=math.radians(ang); cam.data.ortho_scale=scale; cam.location=(4*math.sin(a),-4*math.cos(a),z); cam.rotation_euler=(math.pi/2,0,a)
    scn.render.resolution_x, scn.render.resolution_y = w, h; scn.render.filepath=f'{od}/arisu_v2_26b_{name}.png'; bpy.ops.render.render(write_still=True); print('RENDERED', name)
for pn,ops in POSES.items():
    reset()
    for bn,ax,dg_ in ops: rot(bn,ax,dg_)
    vl.update(); d=dist_stats(); flags=[]
    for n,(med,mn) in d.items():
        m0,n0=rest[n]; dm=(med-m0)*1000; dn=(mn-n0)*1000
        if abs(dm)>4 or dn<-4: flags.append((n,round(dm,1),round(dn,1)))
    flags.sort(key=lambda x:-max(abs(x[1]),-x[2]))
    print('CLAUDE POSE',pn,'objects flagged (|median body-distance change|>4mm or deeper penetration >4mm):',len(flags),flags[:25])
    shot('pose_'+pn+'_front',0,0.85,2.0); shot('pose_'+pn+'_3q',35,0.85,2.0)
    if pn.startswith('arms'): shot('pose_'+pn+'_armclose',20,1.2,0.8,1080,1080)
    if pn.startswith('legs'): shot('pose_'+pn+'_legside',90,0.5,1.1,1080,1080)
reset()
print('CLAUDE restored max |median change| mm',round(max(abs(dist_stats()[n][0]-rest[n][0]) for n in rest)*1000,3))
for n,a in (('front',0),('three_quarter',35),('side',90),('back',180)): shot(n,a,0.85,2.0)
fp=SP+'/v226b_test_export.vrm'
print('CLAUDE EXPORT result',bpy.ops.export_scene.vrm(filepath=fp, ignore_warning=True, armature_object_name='Armature'))
raw=open(fp,'rb').read(); jl=struct.unpack('<I',raw[12:16])[0]; j=json.loads(raw[20:20+jl])
names={i:n.get('name') for i,n in enumerate(j['nodes'])}; par={c:i for i,n in enumerate(j['nodes']) for c in n.get('children',[])}
meshnodes=[i for i,n in enumerate(j['nodes']) if 'mesh' in n]
rootstatic=[names[i] for i in meshnodes if par.get(i) is None and 'skin' not in j['nodes'][i]]
skinned=[names[i] for i in meshnodes if 'skin' in j['nodes'][i]]
from collections import Counter
bonepar=Counter(names.get(par.get(i)) for i in meshnodes if par.get(i) is not None and 'skin' not in j['nodes'][i])
tris=0
for m in j['meshes']:
    for pr in m['primitives']:
        tris+= (j['accessors'][pr['indices']]['count'] if 'indices' in pr else j['accessors'][pr['attributes']['POSITION']]['count'])//3
arisu_sk=[n for n in skinned if n and 'ARISU' in n]
for i in meshnodes:
    n=j['nodes'][i]
    if 'skin' in n and 'ARISU' in (names[i] or ''):
        jn=[names[k] for k in j['skins'][n['skin']]['joints']]; used={}
        for pr in j['meshes'][n['mesh']]['primitives']:
            a=j['accessors'][pr['attributes']['JOINTS_0']]; ct=a['componentType']; J=[]
            def rd(idx,fmt):
                acc=j['accessors'][idx]; bv=j['bufferViews'][acc['bufferView']]; st_=20+jl+8+bv.get('byteOffset',0)+acc.get('byteOffset',0); sz=struct.calcsize(fmt); stride=bv.get('byteStride',sz)
                return [struct.unpack_from(fmt,raw,st_+stride*k) for k in range(acc['count'])]
            for jj,ww in zip(rd(pr['attributes']['JOINTS_0'],'<4B' if ct==5121 else '<4H'),rd(pr['attributes']['WEIGHTS_0'],'<4f')):
                for a_,w_ in zip(jj,ww):
                    if w_>0: used[jn[a_]]=used.get(jn[a_],0)+w_
        print('CLAUDE EXPORT skinned',names[i],{k:round(v,1) for k,v in sorted(used.items(),key=lambda x:-x[1])})
print('CLAUDE EXPORT MB',round(len(raw)/1e6,2),'springs',len(j['extensions']['VRMC_springBone']['springs']),'mesh nodes',len(meshnodes),'unskinned root mesh nodes',rootstatic,'skinned mesh nodes',len(skinned),skinned,'unskinned mesh nodes by parent bone',dict(bonepar),'nodes',len(j['nodes']),'meshes',len(j['meshes']),'materials',len(j['materials']),'triangles',tris)
