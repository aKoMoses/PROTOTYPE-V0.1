extends RefCounted
## Compose the foreground from the same service modules used on the real covers.
## All bulky modules sit outside the walkable footprint; interior plates are flush.
const KIT := preload("res://scripts/environment/arena_visual_kit.gd")

static func build(id: String, stage: Node3D, palette: Dictionary) -> RefCounted:
	var kit := KIT.new(palette)
	match id:
		"heliostat":
			# Replace the repeated tilted slabs with heat-exchanger service bays.
			for mesh in stage.find_children("*", "VisualInstance3D", true, false):
				if str(mesh.name).begins_with("TerraceReflector") or str(mesh.name).begins_with("SmallSolarPedestal") or str(mesh.name).begins_with("ReflectorBackRail"):
					mesh.visible = false
			for side in [-1.0, 1.0]:
				var facing := Basis(Vector3.UP, 0.0 if side < 0 else PI)
				for index in range(3):
					var at := Vector3(side * 14.92, -0.03, (float(index) - 1.0) * 7.375)
					kit.service_station(at, "solar", 31 + index, facing)
				kit.details.pipe(palette.metal, Vector3(side * 14.4, 0.10, -9.6), Vector3(side * 14.4, 0.10, 9.6), 0.075)
			for entry in [{"at": Vector3(-5.75, 0.012, -1.4), "yaw": -0.31}, {"at": Vector3(5.8, 0.012, 0.8), "yaw": 0.31}, {"at": Vector3(-1.75, 0.012, 7.8), "yaw": 0.0}]:
				kit.floor_hatch(entry.at, Vector2(1.6, 0.70), Basis(Vector3.UP, entry.yaw))
		"tideglass":
			# Replant only the exterior architecture, preserving moving cover roots.
			var architecture := stage.get_node_or_null("ExpandedArchitecture")
			var index := 0
			if architecture != null:
				for mesh in architecture.find_children("LegacyLayerBotanical*", "MeshInstance3D", true, false):
					mesh.visible = false
				for source in architecture.find_children("LayeredTropicalFronds*", "MeshInstance3D", true, false):
					if not source.is_visible_in_tree():
						continue
					var at: Vector3 = stage.to_local(source.global_position)
					source.visible = false
					if index % 3 == 0:
						kit.palm(at, 1.65 + float(index % 4) * 0.09, index + 17)
						if index % 6 == 0:
							kit.fern(at + Vector3(0.20, 0, -0.15), 0.84, index + 27)
					index += 1
			# Larger foreground bouquets replace the wide flat legacy leaves.
			for side in [-1.0, 1.0]:
				for i in range(4):
					var at := Vector3(side * 18.375, 0.69, [-6.6, -2.4, 1.4, 9.4][i] * 1.25)
					kit.palm(at, 2.35 + float(i % 2) * 0.20, i + 41)
					kit.fern(at + Vector3(side * 0.3, 0, 0.2), 0.85, i + 51)
			for i in range(5):
				kit.palm(Vector3((-8.3 + float(i) * 4.15) * 1.25, 0.64, -18.75), 2.6, i + 63)
			for side in [-1.0, 1.0]:
				kit.service_station(Vector3(side * 14.6, 0, -8.4), "garden", 51, Basis(Vector3.UP, 0.0 if side < 0 else PI))
				kit.service_station(Vector3(side * 14.6, 0, 7.9), "garden", 52, Basis(Vector3.UP, 0.0 if side < 0 else PI))
				kit.details.pipe(palette.metal, Vector3(side * 14.15, 0.14, -10.6), Vector3(side * 14.15, 0.14, 10.2), 0.11)
			for x in [-7.15, 7.15]:
				kit.floor_hatch(Vector3(x, 1.364, -5.6), Vector2(1.35, 0.68))
		"clockwork":
			# Drive bays form a varied foreground on the outer clock plate.
			for index in range(4):
				var angle: float = [0.14, 0.86, 1.30, 1.70][index] * PI
				var at := Vector3(cos(angle) * 14.55, -0.17, sin(angle) * 14.55)
				var facing := Basis(Vector3.UP, -angle + PI * 0.5)
				kit.service_station(at, "clock", 61 + index, facing)
				kit.gear(at + Vector3.UP * 0.16 + facing * Vector3(0.6, 0, 0.75), 0.59, Basis.IDENTITY, 20)
			for x in [-6.8, 6.8]:
				kit.floor_hatch(Vector3(x, 0.012, 5.3), Vector2(1.9, 0.80), Basis(Vector3.UP, 0.18 * signf(x)))
	return kit
