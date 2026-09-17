import bpy, math, runpy
SCRIPT='/Users/oscar/Downloads/REPLACE.py'  # ponytail: edit per round, also object names and render prefix
from mathutils import Vector
from mathutils.bvhtree import BVHTree
scn=bpy.context.scene; vl=bpy.context.view_layer
runpy.run_path(SCRIPT, run_name='__main__')
vl.update(); dg=bpy.context.evaluated_depsgraph_get()
def bvh(o):
    oe=o.evaluated_get(dg); return BVHTree.FromPolygons([oe.matrix_world @ v.co for v in oe.data.vertices],[tuple(p.vertices) for p in oe.data.polygons]), [oe.matrix_world @ v.co for v in oe.data.vertices]
for side in ('L','R'):
    ib,_=bvh(bpy.data.objects['ARISU_Foot_V222B_%s_Instep'%side])
    for part in ('GraphiteBar','CyanStatus'):
        o=bpy.data.objects['ARISU_Foot_V223C_%s_%s'%(side,part)]; db,ps=bvh(o)
        x0,x1=min(p.x for p in ps),max(p.x for p in ps); y0,y1=min(p.y for p in ps),max(p.y for p in ps)
        gaps=[]
        for u in (0.02,0.25,0.5,0.75,0.98):
            for w in (0.1,0.5,0.9):
                x=x0+(x1-x0)*u; y=y0+(y1-y0)*w
                h,_,_,_=ib.ray_cast(Vector((x,y,0.5)),Vector((0,0,-1)),1.0)
                d,_,_,_=db.ray_cast(Vector((x,y,(h.z if h else 0)-0.05)),Vector((0,0,1)),1.0)
                gaps.append(round((d.z-h.z)*1000,1) if (h and d) else None)
        print('DETAIL',side,part,'x',round(x0,4),round(x1,4),'y',round(y0,4),round(y1,4),'z',round(min(p.z for p in ps),4),round(max(p.z for p in ps),4),'| underside minus instep top mm (+ = air, - = buried)',gaps)
cam=scn.camera; od='/Users/oscar/Documents/claude-projects/arisu/v1-build'
def shot(name, ang, z, scale, x=0.0, w=1080, h=1080, elev=0.0):
    a=math.radians(ang); e=math.radians(elev); cam.data.ortho_scale=scale
    cam.location=(x+4*math.sin(a)*math.cos(e),-4*math.cos(a)*math.cos(e),z+4*math.sin(e)); cam.rotation_euler=(math.pi/2-e,0,a)
    scn.render.resolution_x, scn.render.resolution_y = w, h
    scn.render.filepath=f'{od}/arisu_v2_23c_{name}.png'; bpy.ops.render.render(write_still=True); print('RENDERED', name)
shot('closeup_feet_front',0,0.1,0.35); shot('closeup_feet_three_quarter',35,0.1,0.35); shot('closeup_feet_side',90,0.08,0.25); shot('closeup_feet_top_oblique',0,0.08,0.35,elev=55)
shot('front',0,0.85,2.0,w=1080,h=1920); shot('three_quarter',35,0.85,2.0,w=1080,h=1920)
bpy.ops.wm.save_as_mainfile(filepath=od+'/arisu_v2_23c_candidate.blend', copy=True)
