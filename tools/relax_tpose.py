"""Lower T-pose arms on a static (unrigged) humanoid mesh.
blender -b --python tools_relax_tpose.py -- in.usdz out.usdz [angle_deg]
Finds shoulder height/width from the mesh, then rotates arm vertices about
each shoulder pivot with a smooth blend so the shoulder bends, not tears."""
import bpy, sys, math
from mathutils import Vector, Matrix

args = sys.argv[sys.argv.index("--") + 1:]
src, dst = args[0], args[1]
angle = math.radians(float(args[2]) if len(args) > 2 else 72)

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.wm.usd_import(filepath=src)
meshes = [o for o in bpy.data.objects if o.type == 'MESH']
world = [(o, o.matrix_world.copy()) for o in meshes]
pts = [mw @ v.co for o, mw in world for v in o.data.vertices]
zmin = min(p.z for p in pts); zmax = max(p.z for p in pts); H = zmax - zmin
span = max(abs(p.x) for p in pts)

# arm band = slices where width > 60% of max span
arm = [p for p in pts if abs(p.x) > span * 0.6]
armZ = sum(p.z for p in arm) / len(arm)
armTop = max(p.z for p in arm)
# torso half-width just below the arms
torso = [abs(p.x) for p in pts if armZ - 0.1 * H < p.z < armZ - 0.04 * H]
torsoW = sorted(torso)[int(len(torso) * 0.9)]
pivotX, pivotZ = torsoW + 0.01 * H, armZ
b0, b1 = torsoW - 0.005 * H, torsoW + 0.07 * H      # blend ramp in |x|
zCut = armTop + 0.03 * H                            # ignore head/hair above arms
print(f"H={H:.3f} span={span:.3f} armZ={armZ:.3f} torsoW={torsoW:.3f}")

def smooth(t): t = max(0.0, min(1.0, t)); return t * t * (3 - 2 * t)

for o, mw in world:
    inv = mw.inverted()
    for v in o.data.vertices:
        p = mw @ v.co
        ax = abs(p.x)
        if ax < b0 or p.z > zCut or p.z < armZ - 0.12 * H:
            continue
        w = smooth((ax - b0) / (b1 - b0))
        side = 1 if p.x > 0 else -1
        th = side * angle * w
        px = side * pivotX
        dx, dz = p.x - px, p.z - pivotZ
        nx = dx * math.cos(th) + dz * math.sin(th)
        nz = -dx * math.sin(th) + dz * math.cos(th)
        v.co = inv @ Vector((px + nx, p.y, pivotZ + nz))
    o.data.update()

bpy.ops.wm.usd_export(filepath=dst, convert_orientation=True, export_global_up_selection='Y', export_global_forward_selection='NEGATIVE_Z')
print("WROTE", dst)
