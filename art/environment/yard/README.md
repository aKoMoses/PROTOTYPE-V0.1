# Exterior maintenance yard

`scenes/environment/salvage_yard.tscn` is an authored, visual-only scene with four
compositions: a north service gantry and attached hoist motor, a north crawler
wreck, a west canvas repair canopy, and an east auxiliary power unit. Every mesh
vertex is outside the playable square `[-29.4, 29.4]`. Scene origins are on the
exterior terrain at `y = -0.06`; supports, cables, slings and conduits have visible
attachment points. There are no physics bodies, collision shapes or navigation
resources.

The `.res` meshes are baked assets, not geometry generated at startup. They share
the arena family materials `paint_cream`, `paint_ivory`, `joint_rust` and
`steel_frame`; only rubber and subdued cyan have yard-specific materials.
Regenerate with the Godot console executable and
`--headless --path <project> --script res://tools/build_salvage_yard_assets.gd`.
The generator is an offline authoring source and must not be called by gameplay.

Budget: 6,528 triangles across 23 mesh surfaces, six unique static materials,
one rotating five-blade fan, two 12-particle peripheral emitters, two opaque cloth
meshes and no extra lights. Four spatial meshes retain independent culling.
`set_quality(level, wind_direction, wind_strength)` applies the central wind;
quality 0 disables both particle systems and the fan controller while retaining
reduced cloth motion and the complete composition. Cloth UV.y=0 is pinned to the
banner header; every canopy boundary is pinned to its supported frame. Tears are
geometry, so the red canvas does not add alpha sorting or overlapping transparent
layers.

Validation: `tools/validate_salvage_yard.gd` checks baked vertices against the
playable footprint and terrain, material sharing, and low-quality animation and
particle shutdown. `tools/capture_salvage_yard.gd` captures isolated north, west
and east views using gameplay camera offset `(0, 20.5, 17.5)` and FOV 38.
Forward Mobile/Vulkan renders were inspected on an RTX 3070 Laptop GPU; these
checks do not establish performance on an Android device.
