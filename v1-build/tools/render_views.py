import bpy, math, sys, runpy
argv = sys.argv[sys.argv.index('--') + 1:]
script, outdir, tag = argv
runpy.run_path(script, run_name='__main__')
scn = bpy.context.scene; cam = scn.camera
for name, ang in (('front', 0), ('three_quarter', 35), ('side', 90), ('back', 180)):
    a = math.radians(ang)
    cam.location = (4 * math.sin(a), -4 * math.cos(a), 0.85)
    cam.rotation_euler = (math.pi / 2, 0, a)
    scn.render.filepath = f'{outdir}/arisu_{tag}_{name}.png'
    bpy.ops.render.render(write_still=True)
    print('RENDERED', scn.render.filepath)
print('SOURCE_OBJECTS', [(o.name, o.type, len(o.data.materials) if o.type=='MESH' else 0) for o in scn.objects if not o.name.startswith('ARISU_') and o.type in {'MESH','CURVE'}])
bpy.ops.wm.save_mainfile()
