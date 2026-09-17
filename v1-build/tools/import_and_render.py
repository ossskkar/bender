import bpy, math, sys, runpy
argv = sys.argv[sys.argv.index('--') + 1:]
vrm, script, out, blend = argv
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.preferences.addon_enable(module='bl_ext.user_default.vrm')
bpy.ops.import_scene.vrm(filepath=vrm)
if script != '-':
    runpy.run_path(script, run_name='__main__')
scn = bpy.context.scene
cam = bpy.data.objects.new('FrontCam', bpy.data.cameras.new('FrontCam'))
scn.collection.objects.link(cam)
cam.data.type = 'ORTHO'; cam.data.ortho_scale = 1.9
cam.location = (0, -4, 0.85); cam.rotation_euler = (math.pi / 2, 0, 0)
scn.camera = cam
sun = bpy.data.objects.new('Key', bpy.data.lights.new('Key', 'SUN'))
sun.data.energy = 3; sun.rotation_euler = (math.radians(60), 0, math.radians(-20))
scn.collection.objects.link(sun)
scn.world = scn.world or bpy.data.worlds.new('W'); scn.world.use_nodes = True
scn.world.node_tree.nodes['Background'].inputs[0].default_value = (0.02, 0.05, 0.07, 1)
scn.world.node_tree.nodes['Background'].inputs[1].default_value = 1.0
scn.render.engine = 'BLENDER_EEVEE_NEXT'
scn.render.resolution_x, scn.render.resolution_y = 1080, 1440
scn.render.filepath = out
bpy.ops.render.render(write_still=True)
bpy.ops.wm.save_as_mainfile(filepath=blend)
print('RENDERED', out)
