"""Convert a MagicaVoxel OBJ export into one that needs no palette texture.

MagicaVoxel colours a model through a 256x1 palette PNG plus UVs. This
rewrites the faces so each palette slot (UV index) becomes its own named
material with a flat colour, which also lets the game paint the "body"
material in team colours.

usage:
  python3 tools/split_voxel_obj.py IN.obj OUT_DIR NAME [--flip] SLOT=MAT:R,G,B ...

  --flip   rotate 180 degrees about Y (use when the nose points along +Z;
           the game expects cars to face -Z)
  SLOT     1-based UV (vt) index from the source file
"""
import os
import sys

args = sys.argv[1:]
flip = "--flip" in args
args = [a for a in args if a != "--flip"]
src, out_dir, name = args[:3]
spec = {}
for a in args[3:]:
    k, v = a.split("=")
    mat, rgb = v.split(":")
    spec[int(k)] = (mat, [float(x) for x in rgb.split(",")])

verts, normals, faces = [], [], {}
for line in open(src):
    t = line.split()
    if not t:
        continue
    if t[0] in ("v", "vn"):
        x, y, z = map(float, t[1:4])
        if flip:
            x, z = -x, -z
        (verts if t[0] == "v" else normals).append(f"{t[0]} {x:g} {y:g} {z:g}")
    elif t[0] == "f":
        parts = [p.split("/") for p in t[1:]]
        slot = int(parts[0][1])
        faces.setdefault(slot, []).append("f " + " ".join(f"{p[0]}//{p[2]}" for p in parts))

missing = sorted(set(faces) - set(spec))
if missing:
    sys.exit(f"no material given for slots {missing}")

os.makedirs(out_dir, exist_ok=True)
with open(os.path.join(out_dir, name + ".obj"), "w") as o:
    o.write(f"# Converted from a MagicaVoxel export by tools/split_voxel_obj.py\nmtllib {name}.mtl\no car\n")
    o.write("\n".join(verts) + "\n" + "\n".join(normals) + "\n")
    for slot in sorted(faces):
        o.write(f"usemtl {spec[slot][0]}\n" + "\n".join(faces[slot]) + "\n")
with open(os.path.join(out_dir, name + ".mtl"), "w") as o:
    done = set()
    for slot in sorted(faces):
        mat, (r, g, b) = spec[slot]
        if mat not in done:
            done.add(mat)
            o.write(f"newmtl {mat}\nKd {r} {g} {b}\nKs 0.25 0.25 0.25\nNs 60\n\n")
print({s: len(f) for s, f in sorted(faces.items())})
