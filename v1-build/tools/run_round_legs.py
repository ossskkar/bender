import bpy, math, runpy
from mathutils import Vector
from mathutils.bvhtree import BVHTree
scn=bpy.context.scene; vl=bpy.context.view_layer
runpy.run_path('/Users/oscar/Downloads/SCRIPT.py', run_name='__main__')
vl.update(); dg=bpy.context.evaluated_depsgraph_get()
def wpts(o):
    oe=o.evaluated_get(dg); return [oe.matrix_world @ v.co for v in oe.data.vertices]
def bvhof(o):
    return BVHTree.FromPolygons(wpts(o),[tuple(p.vertices) for p in o.evaluated_get(dg).data.polygons])
b=bpy.data.objects['Body']; be=b.evaluated_get(dg); me=be.to_mesh()
bb=BVHTree.FromPolygons([be.matrix_world @ v.co for v in me.vertices],[tuple(p.vertices) for p in me.polygons])
print('MASK', b.modifiers['ARISU_HIDE_TOPS01_RENDER'].show_render, 'BASE', len(b.data.vertices), len(b.data.polygons), 'EVAL', len(me.polygons))
def front(t,x,z):
    h,_,_,_=t.ray_cast(Vector((x,-0.5,z)),Vector((0,1,0)),1.0); return h.y if h else None
def back(t,x,z):
    h,_,_,_=t.ray_cast(Vector((x,0.5,z)),Vector((0,-1,0)),1.0); return h.y if h else None
st=lambda L:(round(min(L),1),round(max(L),1),round(sum(L)/len(L),1),len(L)) if L else None
for side in ('L','R'):
    shells={'ThighCore':'V217_%s_ThighFront'%side,'KneeJoint':'V217_%s_KneeCap'%side,'ShinCore':'V218_%s_ShinFront'%side}
    for core,shell in shells.items():
        co=bpy.data.objects['ARISU_Lower_V21%s_%s_%s'%('8' if core=='ShinCore' else '7',side,core)]; so=bpy.data.objects['ARISU_Lower_'+shell]
        cb=bvhof(co); sb=bvhof(so); ps=wpts(co)
        x0,x1=min(p.x for p in ps),max(p.x for p in ps); z0,z1=min(p.z for p in ps),max(p.z for p in ps)
        diffs=[]; worst=None
        for u in (0.1,0.3,0.5,0.7,0.9):
            for t in (0.05,0.25,0.5,0.75,0.95):
                x=x0+(x1-x0)*u; z=z0+(z1-z0)*t
                cf=front(cb,x,z); sbk=back(sb,x,z)
                if cf is None or sbk is None: continue
                d=(cf-sbk)*1000; diffs.append(d)
                if worst is None or d<worst[0]: worst=(round(d,1),round(x,3),round(z,3))
        yb=(round(min(p.y for p in ps),4),round(max(p.y for p in ps),4)); bf=front(bb,(x0+x1)/2,(z0+z1)/2)
        # rear protrusion: core back vs body back surface
        bbk=back(bb,(x0+x1)/2,(z0+z1)/2)
        print('CORE', side, core, 'y', yb, 'z', round(z0,3), round(z1,3), '| core front minus local shell back mm (+ = behind shell, target +2)', st(diffs), 'worst', worst,
              '| body front', round(bf,4) if bf else None, 'body back', round(bbk,4) if bbk else None, 'rear protrusion mm', round((yb[1]-bbk)*1000,1) if bbk else None)
    sh=bpy.data.objects['ARISU_Lower_V218_%s_ShinFront'%side]; N=40; R,C=8,5
    bk=[sh.matrix_world @ sh.data.vertices[N+k].co for k in range(N)]
    fine=[]; worst=None
    for r in range(R-1):
        for c in range(C-1):
            a,b2,d,e=bk[r*C+c],bk[r*C+c+1],bk[(r+1)*C+c+1],bk[(r+1)*C+c]
            for u in (0.25,0.5,0.75):
                for t in (0.25,0.5,0.75):
                    p=a.lerp(b2,u).lerp(e.lerp(d,u),t); fy=front(bb,p.x,p.z)
                    if fy is not None:
                        v=(fy-p.y)*1000; fine.append(v)
                        if worst is None or v<worst[0]: worst=(round(v,1),round(p.x,3),round(p.z,3))
    print('SHIN', side, 'interior clr', st(fine), 'worst', worst)
    kc=wpts(bpy.data.objects['ARISU_Lower_V217_%s_KneeCap'%side]); sp=wpts(sh)
    kb=min(p.z for p in kc); stp=max(p.z for p in sp)
    print('KNEESHIN', side, 'gap mm', round((kb-stp)*1000,1), 'front step mm', round((min(p.y for p in sp if p.z>stp-0.012)-min(p.y for p in kc if p.z<kb+0.012))*1000,1))
    an=wpts(bpy.data.objects['ARISU_Lower_V218_%s_Ankle'%side]); ax=(min(p.x for p in an)+max(p.x for p in an))/2; az=(min(p.z for p in an)+max(p.z for p in an))/2
    print('ANKLE', side, 'front', round(min(p.y for p in an),4), 'back', round(max(p.y for p in an),4), 'body front at centre', round(front(bb,ax,az),4), 'stand-off mm', round((front(bb,ax,az)-min(p.y for p in an))*1000,1), 'body back', round(back(bb,ax,az),4), 'rear protrusion mm', round((max(p.y for p in an)-back(bb,ax,az))*1000,1))
for side in ('L','R'):
    kj=wpts(bpy.data.objects['ARISU_Lower_V217_%s_KneeJoint'%side]); x0,x1=min(p.x for p in kj),max(p.x for p in kj); z0,z1=min(p.z for p in kj),max(p.z for p in kj); ybk=max(p.y for p in kj); yf=min(p.y for p in kj)
    rear=[]; frontd=[]
    for u in (0.05,0.5,0.95):
        for w in (0.1,0.5,0.9):
            x=x0+(x1-x0)*u; z=z0+(z1-z0)*w; bk=back(bb,x,z); fr=front(bb,x,z)
            if bk is not None: rear.append(round((ybk-bk)*1000,1))
            if fr is not None: frontd.append(round((fr-yf)*1000,1))
    print('KNEEJOINT', side, 'x', round(x0,3), round(x1,3), 'y', round(yf,4), round(ybk,4), 'z', round(z0,3), round(z1,3), '| rear protrusion mm (+ out)', rear, '| front stand-out mm (+ in front of body)', frontd)
    hc=wpts(bpy.data.objects['ARISU_Lower_V220_%s_HipConnector'%side]); hx0,hx1=min(p.x for p in hc),max(p.x for p in hc); hz0,hz1=min(p.z for p in hc),max(p.z for p in hc); hyf=min(p.y for p in hc)
    vis=[round((front(bb,hx0+(hx1-hx0)*u,hz0+(hz1-hz0)*w)-hyf)*1000,1) for u in (0.1,0.5,0.9) for w in (0.05,0.3,0.5,0.7,0.95) if front(bb,hx0+(hx1-hx0)*u,hz0+(hz1-hz0)*w) is not None]
    pvb=bvhof(bpy.data.objects['ARISU_Torso_PelvisBridge']); hjb=bvhof(bpy.data.objects['ARISU_Lower_V217_%s_HipJoint'%side])
    pvf=front(pvb,(hx0+hx1)/2,0.912); hjf=front(hjb,(hx0+hx1)/2,0.86)
    print('HIPCONN', side, 'x', round(hx0,3), round(hx1,3), 'y', round(hyf,4), round(max(p.y for p in hc),4), 'z', round(hz0,3), round(hz1,3), '| front vs body front mm (+ = in front)', vis, '| pelvis front at z0.912', round(pvf,4) if pvf else None, '| hipjoint front at z0.86', round(hjf,4) if hjf else None)
pv=wpts(bpy.data.objects['ARISU_Torso_PelvisBridge']); hj=wpts(bpy.data.objects['ARISU_Lower_V217_L_HipJoint'])
print('HIP gap mm', round((min(p.z for p in pv)-max(p.z for p in hj))*1000,1))
be.to_mesh_clear()
cam=scn.camera; od='/Users/oscar/Documents/claude-projects/arisu/v1-build'
def shot(name, ang, z, scale, x=0.0, w=1080, h=1080, elev=0.0):
    a=math.radians(ang); e=math.radians(elev); cam.data.ortho_scale=scale
    cam.location=(x+4*math.sin(a)*math.cos(e),-4*math.cos(a)*math.cos(e),z+4*math.sin(e)); cam.rotation_euler=(math.pi/2-e,0,a)
    scn.render.resolution_x, scn.render.resolution_y = w, h
    scn.render.filepath=f'{od}/arisu_TAG_{name}.png'; bpy.ops.render.render(write_still=True); print('RENDERED', name)
shot('front',0,0.85,1.9,h=1440); shot('three_quarter',35,0.85,1.9,h=1440); shot('side',90,0.85,1.9,h=1440); shot('back',180,0.85,1.9,h=1440)
shot('closeup_hips_front',0,0.88,0.3); shot('closeup_hips_three_quarter',35,0.88,0.3)
shot('closeup_knees_front',0,0.52,0.28); shot('closeup_knees_back',180,0.52,0.28)
shot('closeup_legs_side',90,0.6,0.8); shot('closeup_shin_ankle_front',0,0.33,0.4)
bpy.ops.wm.save_mainfile()
