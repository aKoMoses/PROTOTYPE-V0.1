extends RefCounted
## Architectural dressing only: no bodies, areas, lights or combat logic.
## Repeated masonry, metalwork and foliage share a handful of batched surfaces.


static func build(stage: Node3D, arena_id: String) -> void:
	if arena_id not in ["heliostat", "tideglass", "clockwork"]:
		return
	var root := Node3D.new()
	root.name = "LegacyArenaArchitecture"
	root.set_meta("visual_only", true)
	stage.add_child(root)
	var materials: Dictionary = (stage.get("_materials") as Dictionary).duplicate()
	var batches: Dictionary = {}
	match arena_id:
		"heliostat": _solar(stage, root, materials, batches)
		"tideglass": _greenhouse(stage, root, materials, batches)
		"clockwork": _horology(stage, root, materials, batches)
	_flush(stage, root, batches)
	root.set_meta("batched_surfaces", batches.size())


static func _solar(stage: Node3D, root: Node3D, palette: Dictionary, batches: Dictionary) -> void:
	palette["solar_stone"] = stage.call("_surface_material", Color("#bbaa85"), 8, 0.82, 0.0)
	palette["solar_shadow"] = stage.call("_surface_material", Color("#79614a"), 8, 0.9, 0.0)
	palette["solar_enamel"] = stage.call("_material", Color("#337477"), 0.35, 0.40)
	# Narrow exterior cloisters give the terrace an inhabited architectural edge.
	# Their posts, arcade vaults and galleries all remain outside x = +/-11 m.
	for side in [-1.0, 1.0]:
		var x: float = float(side) * 13.4
		_box(stage, batches, "solar_stone", palette, Vector3(1.55, 0.22, 14.5), Vector3(x, -0.36, 0))
		_box(stage, batches, "solar_shadow", palette, Vector3(1.62, 0.15, 14.8), Vector3(x, -0.55, 0))
		for z in [-6.9, -2.3, 2.3, 6.9]:
			_box(stage, batches, "solar_stone", palette, Vector3(0.56, 2.4, 0.62), Vector3(x, 1.04, z))
			_box(stage, batches, "stone_light", palette, Vector3(0.79, 0.20, 0.85), Vector3(x, -0.12, z))
			_box(stage, batches, "stone_light", palette, Vector3(0.86, 0.22, 0.88), Vector3(x, 2.28, z))
			_box(stage, batches, "solar_shadow", palette, Vector3(0.60, 0.055, 0.70), Vector3(x, 2.13, z))
			for flute in [-1.0, 0.0, 1.0]:
				_box(stage, batches, "solar_shadow", palette, Vector3(0.018, 1.55, 0.05), Vector3(x - side * 0.287, 1.05, z + flute * 0.14))
			_bar(stage, batches, "bronze", palette, Vector3(side * 11.8, -0.67, z), Vector3(x, -0.67, z), 0.11)
		for bay in range(3):
			var z := -4.6 + float(bay) * 4.6
			_arc(stage, batches, "solar_stone", palette, Vector3(x, 1.00, z), 2.30, 1.14, PI * 0.5, 0.0, 0.23, true)
			_arc(stage, batches, "gold", palette, Vector3(x - side * 0.16, 1.00, z), 2.34, 1.18, PI * 0.5, 0.0, 0.032, true)
			# A recessed patinated lattice beneath each arch casts a quiet silhouette.
			for i in range(5):
				var local_z := z - 1.60 + float(i) * 0.8
				_bar(stage, batches, "solar_enamel", palette, Vector3(x + side * 0.12, 0.25, local_z), Vector3(x + side * 0.12, 1.21, local_z), 0.055)
				_bar(stage, batches, "bronze", palette, Vector3(x + side * 0.13, 0.42, local_z - 0.28), Vector3(x + side * 0.13, 1.10, local_z + 0.28), 0.025)
				_bar(stage, batches, "bronze", palette, Vector3(x + side * 0.13, 1.10, local_z - 0.28), Vector3(x + side * 0.13, 0.42, local_z + 0.28), 0.025)
		_box(stage, batches, "solar_stone", palette, Vector3(1.14, 0.28, 14.6), Vector3(x, 2.56, 0))
		_box(stage, batches, "solar_stone", palette, Vector3(1.23, 0.07, 14.72), Vector3(x, 2.74, 0))
		for edge in [-1.0, 1.0]:
			_box(stage, batches, "gold", palette, Vector3(0.032, 0.025, 14.72), Vector3(x + edge * 0.595, 2.782, 0))
		for i in range(15):
			_box(stage, batches, "solar_shadow", palette, Vector3(1.18, 0.13, 0.21), Vector3(x, 2.40, -6.9 + float(i) * 0.985))
			_box(stage, batches, "solar_enamel", palette, Vector3(0.49, 0.018, 0.38), Vector3(x, 2.784, -6.9 + float(i) * 0.985))
	# Two tapering enamel blades frame the distant caged sun, anchored on the roof.
	for side in [-1.0, 1.0]:
		var frame := Node3D.new()
		frame.position = Vector3(side * 4.7, 0, -12.25)
		frame.rotation.z = -side * 0.14
		root.add_child(frame)
		stage.call("_prism", frame, "SunCageEnamelFin", PackedVector2Array([Vector2(-0.25, -0.35), Vector2(0.25, -0.35), Vector2(0.40, 0.35), Vector2(-0.40, 0.35)]), 5.1, Vector3(0, 2.55, 0), palette["solar_enamel"])
		stage.call("_box", frame, "FinGoldSpine", Vector3(0.055, 5.1, 0.055), Vector3(0, 2.55, 0.40), palette["gold"])
		_box(stage, batches, "solar_stone", palette, Vector3(1.35, 0.40, 1.55), Vector3(side * 4.7, -0.25, -12.25))
		_bar(stage, batches, "bronze", palette, Vector3(side * 4.7, -0.42, -12.25), Vector3(side * 4.7, -0.42, -9.7), 0.12)
	# The sun crown carries broad radial blades, not another smooth wire circle.
	for i in range(18):
		var a := TAU * float(i) / 18.0
		var direction := Vector3(cos(a), sin(a), 0)
		var center := Vector3(0, 3.1, -13.38) + direction * 2.65
		_box(stage, batches, "gold", palette, Vector3(0.075, 0.56, 0.09), center, Basis(Vector3.FORWARD, a - PI * 0.5))
	# Covers receive a fine capped profile and turquoise enamel shoulders only;
	# the actual collider bounds and empty firing lanes remain untouched.
	for body in stage.get_children():
		if not body is StaticBody3D or not body.name.begins_with("CompactCover"):
			continue
		var collision := body.get_child(0) as CollisionShape3D
		if collision == null or not collision.shape is BoxShape3D:
			continue
		var size := (collision.shape as BoxShape3D).size
		var detail := Node3D.new()
		detail.name = "SolarBatteryCopperShoulders"
		body.add_child(detail)
		for side in [-1.0, 1.0]:
			stage.call("_box", detail, "EnamelBatteryShoulder", Vector3(0.15, size.y * 0.74, size.z * 0.72), Vector3(side * size.x * 0.425, 0, 0), palette["solar_enamel"])


static func _greenhouse(stage: Node3D, root: Node3D, palette: Dictionary, batches: Dictionary) -> void:
	palette["botanical_dark"] = stage.call("_material", Color("#30684a"), 0.86, 0.0)
	palette["botanical_mid"] = stage.call("_material", Color("#69945b"), 0.84, 0.0)
	palette["botanical_blue"] = stage.call("_material", Color("#387b72"), 0.76, 0.0)
	palette["botanical_stem"] = stage.call("_material", Color("#4a5740"), 0.92, 0.0)
	palette["botanical_vein"] = stage.call("_material", Color("#9bad76"), 0.9, 0.0)
	for key in ["botanical_dark", "botanical_mid", "botanical_blue"]:
		(palette[key] as StandardMaterial3D).cull_mode = BaseMaterial3D.CULL_DISABLED
	# Broad, bowed leaves give mature plants real volume. Each entire colour
	# layer of this garden is a single mesh, including raised central leaf ribs.
	for side in [-1.0, 1.0]:
		for i in range(4):
			var z: float = [-6.6, -2.4, 1.4, 9.4][i]
			var point := Vector3(side * 14.7, 0.69, z)
			if i == 1:
				# The fourth bay has its own planter and supported outrigger;
				# the other three bouquets grow from the existing authored pots.
				_box(stage, batches, "porcelain", palette, Vector3(1.8, 0.48, 2.0), Vector3(side * 14.7, 0.38, z))
				_box(stage, batches, "teal_metal", palette, Vector3(1.88, 0.075, 2.08), Vector3(side * 14.7, 0.64, z))
				_box(stage, batches, "soil", palette, Vector3(1.53, 0.025, 1.72), Vector3(side * 14.7, 0.685, z))
				_box(stage, batches, "teal_metal", palette, Vector3(1.9, 0.13, 1.86), Vector3(side * 14.7, 0.06, z))
				for edge in [-1.0, 1.0]:
					_bar(stage, batches, "teal_metal", palette, Vector3(side * 11.15, -0.58, z + edge * 0.68), Vector3(side * 14.7, 0.08, z + edge * 0.68), 0.12)
			_broad_plant(stage, batches, palette, point, 2.2 + float(i % 2) * 0.3, i + (0 if side < 0 else 7))
	for i in range(5):
		_broad_plant(stage, batches, palette, Vector3(-8.3 + float(i) * 4.15, 0.64, -15.0), 2.45 + float(i % 2) * 0.22, i + 13)
	# Articulated greenhouse ribs: copper straps, compression posts, diagonal
	# roof seams and a service balustrade rather than an undifferentiated dome.
	for z in [-12.2, -15.7, -19.2]:
		for i in range(11):
			var a := PI * float(i + 1) / 12.0
			var p := Vector3(cos(a) * 12.4, sin(a) * 8.0, z)
			_box(stage, batches, "bronze", palette, Vector3(0.24, 0.34, 0.40), p, Basis(Vector3.FORWARD, a - PI * 0.5))
			_box(stage, batches, "gold", palette, Vector3(0.06, 0.38, 0.055), p + Vector3(0, 0, 0.23), Basis(Vector3.FORWARD, a - PI * 0.5))
	for side in [-1.0, 1.0]:
		for i in range(4):
			var z := -17.7 + float(i) * 1.65
			_bar(stage, batches, "teal_metal", palette, Vector3(side * 10.9, 0.40, z), Vector3(side * 10.9, 1.4, z), 0.055)
		_bar(stage, batches, "teal_metal", palette, Vector3(side * 10.9, 1.4, -18.2), Vector3(side * 10.9, 1.4, -11.7), 0.055)
		for z in [-8.0, -3.8, 3.8, 8.0]:
			_box(stage, batches, "porcelain", palette, Vector3(0.95, 0.12, 0.8), Vector3(side * 14.2, 0.4, z))
			_bar(stage, batches, "teal_metal", palette, Vector3(side * 14.2, 0.4, z), Vector3(side * 14.2, 1.1, z), 0.10)
			_box(stage, batches, "gold", palette, Vector3(0.18, 0.09, 0.28), Vector3(side * 14.2, 1.0, z))
	# Hanging vines terminate above the far garden; none reach the fight's roof.
	for i in range(6):
		var x := -9.4 + float(i) * 3.76
		var peak := sqrt(maxf(0.0, 1.0 - pow(x / 12.4, 2.0))) * 8.0 - 0.2
		var previous := Vector3(x, peak, -13.35)
		for j in range(7):
			var p := Vector3(x + sin(float(j) * 0.9 + float(i)) * 0.15, peak - float(j + 1) * 0.29, -13.35)
			_bar(stage, batches, "botanical_stem", palette, previous, p, 0.025)
			_leaf(stage, batches, palette, p, Vector3(-1 if j % 2 == 0 else 1, 0, 0.35).normalized(), 0.48, 0.15, 0.12, "botanical_dark")
			previous = p


static func _horology(stage: Node3D, root: Node3D, palette: Dictionary, batches: Dictionary) -> void:
	palette["clock_ivory"] = stage.call("_material", Color("#bfb29b"), 0.7, 0.12)
	palette["clock_copper"] = stage.call("_surface_material", Color("#72503c"), 9, 0.46, 0.64)
	# A clock has an actual frame, cross ties, chains and weights. Everything
	# here is beyond z=-9 and leaves the square combat deck fully unobstructed.
	for side in [-1.0, 1.0]:
		var x: float = float(side) * 12.1
		_box(stage, batches, "dark_metal", palette, Vector3(1.0, 0.40, 2.3), Vector3(x, -0.2, -11.7))
		_box(stage, batches, "bronze", palette, Vector3(0.30, 7.3, 0.42), Vector3(x, 3.65, -11.7))
		_bar(stage, batches, "gold", palette, Vector3(x - side * 0.21, 0.1, -11.47), Vector3(x - side * 0.21, 7.28, -11.47), 0.042)
		for i in range(13):
			var y := 6.68 - float(i) * 0.35
			_chain_link(stage, batches, palette, Vector3(x - side * 0.47, y, -11.7), i % 2 == 0)
		stage.call("_cylinder", root, "GrandClockCounterweight", 0.43, 1.20, Vector3(x - side * 0.47, 1.76, -11.7), palette["clock_copper"], 0.43, 12)
		stage.call("_cylinder", root, "CounterweightIvoryCap", 0.46, 0.09, Vector3(x - side * 0.47, 2.41, -11.7), palette["clock_ivory"], 0.46, 12)
		stage.call("_cylinder", root, "CounterweightLowerCap", 0.46, 0.09, Vector3(x - side * 0.47, 1.10, -11.7), palette["gold"], 0.46, 12)
	_box(stage, batches, "clock_copper", palette, Vector3(25.0, 0.29, 0.46), Vector3(0, 7.16, -11.7))
	_box(stage, batches, "gold", palette, Vector3(25.1, 0.085, 0.55), Vector3(0, 7.40, -11.7))
	for i in range(16):
		var x := -11.65 + float(i) * 1.55
		_box(stage, batches, "bronze", palette, Vector3(0.22, 0.65, 0.22), Vector3(x, 6.65, -11.7))
		_bar(stage, batches, "gold", palette, Vector3(x - 0.45, 6.3, -11.7), Vector3(x + 0.45, 6.93, -11.7), 0.033)
	# Every nearer moving wheel receives an independent concentric bearing
	# and bevelled copper ribs, so the decoration follows its existing rotor.
	var wheel_index := 0
	for wheel in stage.get_children():
		if not wheel is Node3D:
			continue
		var rim := wheel.get_node_or_null("CastGearRim") as MeshInstance3D
		if rim == null or rim.mesh == null or (wheel as Node3D).position.length() > 30.0:
			continue
		wheel_index += 1
		var radius := rim.mesh.get_aabb().size.x * 0.5 / 0.975
		stage.call("_annulus", wheel, "ConcentricIvoryBearing", radius * 0.25, radius * 0.30, 0.075, Vector3(0, 0.43, 0), palette["clock_ivory"])
		stage.call("_annulus", wheel, "CopperCastInnerRace", radius * 0.42, radius * 0.465, 0.095, Vector3(0, 0.16, 0), palette["clock_copper"])
		var local_batch: Dictionary = {}
		for i in range(6):
			var a := TAU * float(i) / 6.0
			var direction := Vector3(cos(a), 0, sin(a))
			var tangent := Vector3(-sin(a), 0, cos(a))
			for side in [-1.0, 1.0]:
				_bar(stage, local_batch, "gold", palette, direction * radius * 0.38 + tangent * side * radius * 0.036 + Vector3(0, 0.17, 0), direction * radius * 0.78 + tangent * side * radius * 0.035 + Vector3(0, 0.17, 0), 0.025)
			_box(stage, local_batch, "clock_copper", palette, Vector3(radius * 0.1, 0.055, radius * 0.18), direction * radius * 0.68 + Vector3(0, 0.17, 0), Basis(Vector3.UP, -a))
		_flush(stage, wheel, local_batch, "WheelDetail%d" % wheel_index)
	# A fine pierced bezel is safely outside even the square's diagonal corners.
	for i in range(60):
		var a := TAU * float(i) / 60.0
		var p := Vector3(cos(a) * 13.04, -0.03, sin(a) * 13.04)
		var next := Vector3(cos(a + TAU / 120.0) * 12.85, -0.03, sin(a + TAU / 120.0) * 12.85)
		_bar(stage, batches, "clock_ivory", palette, p, next, 0.025)
		_box(stage, batches, "clock_copper", palette, Vector3(0.07, 0.045, 0.07), p)


static func _broad_plant(stage: Node3D, batches: Dictionary, palette: Dictionary, point: Vector3, length: float, seed: int) -> void:
	for i in range(7):
		var a := float(i) * TAU / 7.0 + float(seed) * 0.41
		var direction := Vector3(cos(a), 0, sin(a))
		var leaf_base := point + Vector3(0, 0.22 + float(i % 3) * 0.35, 0)
		_bar(stage, batches, "botanical_stem", palette, point, leaf_base + direction * 0.22, 0.045)
		var key: String = ["botanical_dark", "botanical_mid", "botanical_blue"][(seed + i) % 3]
		_leaf(stage, batches, palette, leaf_base, direction, length * (0.83 + float(i % 3) * 0.10), length * 0.28, length * 0.85, key)


static func _leaf(stage: Node3D, batches: Dictionary, palette: Dictionary, origin: Vector3, direction: Vector3, length: float, width: float, rise: float, key: String) -> void:
	var st := _batch(batches, key, palette[key])
	var across := Vector3(-direction.z, 0, direction.x)
	for i in range(9):
		var t1 := float(i) / 9.0
		var t2 := float(i + 1) / 9.0
		var c1 := origin + direction * t1 * length + Vector3.UP * (sin(t1 * PI) * 0.78 + t1 * 0.18) * rise
		var c2 := origin + direction * t2 * length + Vector3.UP * (sin(t2 * PI) * 0.78 + t2 * 0.18) * rise
		var w1 := sin(t1 * PI) * width * (0.92 + sin(t1 * TAU * 3.0) * 0.08)
		var w2 := sin(t2 * PI) * width * (0.92 + sin(t2 * TAU * 3.0) * 0.08)
		var ridge1 := c1 + Vector3.UP * w1 * 0.16
		var ridge2 := c2 + Vector3.UP * w2 * 0.16
		_tri(st, c1 - across * w1, c2 - across * w2, ridge1)
		_tri(st, ridge1, c2 - across * w2, ridge2)
		_tri(st, c1 + across * w1, ridge1, c2 + across * w2)
		_tri(st, c2 + across * w2, ridge1, ridge2)
		if length > 1.0:
			# Raised cream-green veins catch light over each bowed broad leaf.
			# Their complete garden shares one material and one mesh surface.
			_bar(stage, batches, "botanical_vein", palette, ridge1 + Vector3.UP * 0.007, ridge2 + Vector3.UP * 0.007, 0.015)
			if i in [2, 4, 6]:
				for side in [-1.0, 1.0]:
					_bar(stage, batches, "botanical_vein", palette, ridge1 + Vector3.UP * 0.007, c2 + across * side * w2 * 0.84 + Vector3.UP * w2 * 0.028, 0.009)


static func _chain_link(stage: Node3D, batches: Dictionary, palette: Dictionary, center: Vector3, across_x: bool) -> void:
	for i in range(8):
		var a := TAU * float(i) / 8.0
		var b := TAU * float(i + 1) / 8.0
		var p1 := Vector3(cos(a) * 0.105 if across_x else 0.0, sin(a) * 0.21, 0.0 if across_x else cos(a) * 0.105)
		var p2 := Vector3(cos(b) * 0.105 if across_x else 0.0, sin(b) * 0.21, 0.0 if across_x else cos(b) * 0.105)
		_bar(stage, batches, "gold", palette, center + p1, center + p2, 0.028)


static func _arc(stage: Node3D, batches: Dictionary, key: String, palette: Dictionary, center: Vector3, radius: float, height: float, plane_yaw: float, offset: float, thickness: float, half: bool) -> void:
	var count := 24
	var extent := PI if half else TAU
	var basis := Basis(Vector3.UP, plane_yaw)
	for i in range(count):
		var a := offset + extent * float(i) / float(count)
		var b := offset + extent * float(i + 1) / float(count)
		_bar(stage, batches, key, palette, center + basis * Vector3(cos(a) * radius, sin(a) * height, 0), center + basis * Vector3(cos(b) * radius, sin(b) * height, 0), thickness)


static func _box(stage: Node3D, batches: Dictionary, key: String, palette: Dictionary, size: Vector3, center: Vector3, basis: Basis = Basis.IDENTITY) -> void:
	stage.call("_append_box", _batch(batches, key, palette[key]), center, size, basis)


static func _bar(stage: Node3D, batches: Dictionary, key: String, palette: Dictionary, a: Vector3, b: Vector3, width: float) -> void:
	if a.distance_squared_to(b) < 0.000001:
		return
	var basis := Basis(Quaternion(Vector3.UP, (b - a).normalized()))
	_box(stage, batches, key, palette, Vector3(width, a.distance_to(b), width), (a + b) * 0.5, basis)


static func _batch(batches: Dictionary, key: String, material: Material) -> SurfaceTool:
	if not batches.has(key):
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		batches[key] = {"surface": st, "material": material}
	return batches[key]["surface"] as SurfaceTool


static func _flush(stage: Node3D, parent: Node3D, batches: Dictionary, prefix: String = "LegacyLayer") -> void:
	for key in batches:
		var st := batches[key]["surface"] as SurfaceTool
		st.generate_normals()
		stage.call("_instance", parent, prefix + str(key).capitalize(), st.commit(), Vector3.ZERO, batches[key]["material"])


static func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	st.add_vertex(a)
	st.add_vertex(b)
	st.add_vertex(c)
