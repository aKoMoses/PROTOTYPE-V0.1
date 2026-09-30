# Armored salvage cover family

`cover_skin.tscn` and `cover_skin_b.tscn` are visual-only scenes. Each contains
one shared, baked ArrayMesh with six shared opaque StandardMaterial3D surfaces.
The sealed steel hull, bevel armor, rusty gaskets, cap straps, end louvres,
hexagonal fasteners, localized paint loss and dusty sill are authored offline.
Variant B has an additional diagonal repair plate and attached brick-red canvas.

All geometry is inside the unit box `[-0.5, 0.5]` on every axis. Long modular
subdivisions run along local X. Scale to the existing collision dimensions.
For covers whose long direction is Z, rotate the mesh 90 degrees about Y and
use local scale `(size.z, size.y, size.x)`. Keep the existing StaticBody3D and
CollisionShape3D. Clear the old mesh's material override when assigning this
ArrayMesh, otherwise its six authored materials will be replaced.

The meshes need no runtime generator, shader, texture import or external asset.
The resources have crisp flat normals, shared materials and vertex colors for
controlled wear. Each family uses fewer than 1,600 triangles and six surfaces.
The backing hull and gasket layers are recessed beneath the painted plates.
Keep these depth gaps when editing: near-coplanar armor layers created stripe
moire at gameplay distances on the Mobile perspective camera.

To rebuild after changing the source, run Godot from the project root with
`--headless --script res://tools/environment/build_cover_family.gd`.
The offline builder asserts every generated vertex lies inside the unit bounds.
Never attach that builder to a shipped scene.
