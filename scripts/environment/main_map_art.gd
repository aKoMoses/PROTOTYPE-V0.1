extends Node3D
## Authored courtyard identity. Static, batched scenery; no gameplay resources.
const SURFACE := preload("res://scripts/environment/main_map_surface.gdshader")
const MARKS := preload("res://scripts/environment/main_map_marks.gdshader")
const LEAVES := preload("res://scripts/environment/main_map_leaf.gdshader")
const WIND := preload("res://scripts/environment/scenery_wind.gd")
const PALE := Color("#c9b78b")
const STEEL := Color("#6a7774")
const DARK := Color("#313b37")
const RUST := Color("#91543b")
const THEMES := [Color("#bb7546"), Color("#477f86"), Color("#768454")]
const GLYPHS := {
	"A": [14,17,17,31,17,17,17], "B": [30,17,17,30,17,17,30], "C": [14,17,16,16,16,17,14],
	"D": [30,17,17,17,17,17,30], "E": [31,16,16,30,16,16,31], "F": [31,16,16,30,16,16,16],
	"G": [14,17,16,23,17,17,14], "H": [17,17,17,31,17,17,17], "I": [14,4,4,4,4,4,14],
	"J": [7,2,2,2,2,18,12], "K": [17,18,20,24,20,18,17], "L": [16,16,16,16,16,16,31],
	"M": [17,27,21,21,17,17,17], "N": [17,25,21,19,17,17,17], "O": [14,17,17,17,17,17,14],
	"P": [30,17,17,30,16,16,16], "Q": [14,17,17,17,21,18,13], "R": [30,17,17,30,20,18,17],
	"S": [15,16,16,14,1,1,30], "T": [31,4,4,4,4,4,4], "U": [17,17,17,17,17,17,14],
	"V": [17,17,17,17,17,10,4], "W": [17,17,17,21,21,21,10], "X": [17,17,10,4,10,17,17],
	"Y": [17,17,10,4,4,4,4], "Z": [31,1,2,4,8,16,31],
	"0": [14,17,19,21,25,17,14], "1": [4,12,4,4,4,4,14], "2": [14,17,1,2,4,8,31],
	"3": [30,1,1,14,1,1,30], "4": [2,6,10,18,31,2,2], "5": [31,16,16,30,1,1,30],
	"6": [14,16,16,30,17,17,14], "7": [31,1,2,4,8,8,8], "8": [14,17,17,14,17,17,14], "9": [14,17,17,15,1,1,14],
	"-": [0,0,0,31,0,0,0], " ": [0,0,0,0,0,0,0]
}
var _scene: Node3D
var _batches: Dictionary = {}
var _rng := RandomNumberGenerator.new()
var _leaf_materials: Array[ShaderMaterial] = []
var _initialized := false
var _lighting_ready := false
var _prepare_generation := 0
var _quality := -1
var _triangles := 0
var _clock := 0.0
var _stats := {"facades": 0, "work_corners": 0, "plants": 0, "markings": 0, "landmarks": 0, "exterior_buildings": 0, "themes": [0, 0, 0]}

func _enter_tree() -> void:
	if is_node_ready() and not _initialized:
		_prepare.call_deferred()

func _exit_tree() -> void:
	_prepare_generation += 1

func _ready() -> void:
	set_process(false)
	_scene = get_parent().get_parent() as Node3D
	_prepare.call_deferred()

func _prepare() -> void:
	if not is_inside_tree() or _initialized:
		return
	var generation := _prepare_generation
	var tree := get_tree()
	for frame in 4:
		await tree.process_frame
		if not is_inside_tree() or is_queued_for_deletion() or generation != _prepare_generation:
			return
	_rng.seed = 202610024
	_build_workshops()
	_build_ground()
	_build_exterior()
	_commit_batches()
	_configure_lighting()
	_initialized = true
	set_meta("triangles", _triangles)
	set_meta("batches", _batches.size())
	set_meta("art_counts", _stats.duplicate())
	_batches.clear()
	set_process(true)
	_process(0.0)

func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	if not _lighting_ready:
		_configure_lighting()
	_clock += delta
	var director := get_parent()
	var quality := int(director.get("_quality"))
	if quality != _quality:
		_quality = quality
		for mesh in get_children():
			if mesh is MeshInstance3D:
				mesh.visible = quality > 0 or not bool(mesh.get_meta("fine_detail", false))
				mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if quality > 0 and bool(mesh.get_meta("solid_detail", false)) else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		set_meta("active_quality", quality)
	var organic := _scene.get_node_or_null("OrganicWorldDetails")
	var clock := float(organic.get("_clock")) if organic != null else _clock
	for material in _leaf_materials:
		material.set_shader_parameter("scenery_clock", clock)
		material.set_shader_parameter("wind_strength", 0.45 if quality > 0 else 0.12)
		# Each batch covers a small cell, so the travelling gust remains local.
		material.set_shader_parameter("scenery_gust", WIND.strength(clock, material.get_meta("anchor")) * (0.6 if quality > 0 else 0.15))

func _configure_lighting() -> void:
	if not is_visible_in_tree() or String(_scene.get("arena_variant")) not in ["classic", "hazards"]:
		return
	var sun := _scene.get_node_or_null("ArenaKeyLight") as DirectionalLight3D
	if sun != null:
		sun.light_color = Color("#ffdbb3")
		sun.light_energy = 1.25
	for child in _scene.get_children():
		if child is WorldEnvironment:
			child.environment.ambient_light_color = Color("#a5b6c3")
			child.environment.ambient_light_energy = 0.43
	# Main restores this snapshot after visiting another arena.
	var cached: Environment = _scene.get("_classic_environment")
	if cached != null:
		cached.ambient_light_color = Color("#a5b6c3")
		cached.ambient_light_energy = 0.43
		_scene.set("_classic_light_color", sun.light_color)
		_scene.set("_classic_light_energy", sun.light_energy)
	_lighting_ready = true

func _build_workshops() -> void:
	var ambience := get_parent().get_node_or_null("WorkshopDressing/WorkshopAmbience")
	if ambience == null or not bool(ambience.get("_initialized")):
		return
	var life := ambience.get_node("SceneryLife")
	for circuit in ambience.get("_circuits"):
		if not circuit.neon:
			continue
		var axis: Vector3 = circuit.axis
		var out: Vector3 = circuit.out
		var source: Vector3 = circuit.at
		var theme := 1 if source.x > 0 else (0 if source.z < 0 else 2)
		var tint: Color = THEMES[theme]
		var at: Vector3 = life.call("_accessible_face", source - Vector3.UP * (source.y - 0.0), out, 0.06)
		var basis := Basis(axis, Vector3.UP, out)
		var pose := Transform3D(basis, at)
		_facade(pose, tint, _stats.facades, theme)
		_work_corner(pose, tint, theme)
		var apron := pose * Vector3(0, 0.012, 1.1)
		_loading_bay(apron, basis, tint, _stats.facades)
		_stats.facades += 1
		_stats.work_corners += 1
		_stats.themes[theme] += 1
	# The broad central counters get distinct service numbers and old paint.
	for item in [["NorthCenterCover", 0], ["SouthCenterCover", 2], ["WestSpine", 0], ["EastSpine", 1], ["WestPocketShort", 2], ["EastPocketShort", 1]]:
		var body := _scene.get_node_or_null(item[0]) as Node3D
		if body == null:
			continue
		var shape := body.get_node("Collision") as CollisionShape3D
		var size: Vector3 = shape.shape.size
		var basis := body.global_basis
		if size.z > size.x:
			basis *= Basis(Vector3.UP, PI * (-0.5 if item[0] == "EastSpine" else 0.5))
		var out := basis.z
		var at := body.global_position + out * (minf(size.x, size.z) * 0.5 + 0.065)
		at.y = 0.0
		var pose := Transform3D(basis, at)
		var tint: Color = THEMES[int(item[1])]
		_facade(pose, tint, _stats.facades, int(item[1]))
		_work_corner(pose, tint, int(item[1]))
		_loading_bay(pose * Vector3(0, 0.012, 1.0), basis, tint, _stats.facades)
		_stats.facades += 1
		_stats.work_corners += 1
		_stats.themes[int(item[1])] += 1

func _facade(pose: Transform3D, tint: Color, id: int, theme: int) -> void:
	# Accent skin and repainted strip sit directly on the existing cover face.
	_box("solid", pose, Vector3(-1.22, 0.64, 0), Vector3(0.42, 1.12, 0.024), tint, 0.20)
	_box("solid", pose, Vector3(-1.22, 0.35, 0.016), Vector3(0.40, 0.16, 0.005), tint.lightened(0.12), 0.15)
	_box("solid", pose, Vector3(-1.22, 0.105, 0.02), Vector3(0.40, 0.11, 0.01), RUST, 0.10)
	for index in 4:
		_box("fine", pose, Vector3(-1.39 + (index % 2) * 0.34, 0.16 + (index / 2) * 0.95, 0.023), Vector3(0.023, 0.023, 0.012), STEEL.lightened(0.24), 0.90)
	var plate := pose * Transform3D(Basis.IDENTITY, Vector3(1.05, 1.33, 0.02))
	_box("solid", plate, Vector3.ZERO, Vector3(0.68, 0.42, 0.028), DARK, 0.35)
	_text("marks", "POSTE", plate * Vector3(-0.28, 0.14, 0.019), pose.basis.x, Vector3.DOWN, 0.016, PALE)
	_text("marks", "%02d" % (id + 1), plate * Vector3(-0.17, -0.035, 0.020), pose.basis.x, Vector3.DOWN, 0.023, tint.lightened(0.45))
	# Torn notices and handwritten strokes replace identical pristine walls.
	var paper := pose * Vector3(0.95, 0.73, 0.040)
	_patch("paper", paper, pose.basis.x, Vector3.UP, Vector2(0.29, 0.35), PALE)
	for line in 4:
		_patch("marks", paper + Vector3.UP * (0.105 - line * 0.060) + pose.basis.z * 0.001, pose.basis.x, Vector3.UP, Vector2(_rng.randf_range(0.14, 0.23), 0.011), DARK)
	_patch("fine", paper + Vector3.UP * 0.163 + pose.basis.z * 0.003, pose.basis.x, Vector3.UP, Vector2(0.08, 0.022), Color("#968461"))
	var slogan: String = ["REVISER", "VOLTS", "RECUP"][theme]
	_text("marks", slogan, pose * Vector3(-0.42, 0.30, 0.037), pose.basis.x, Vector3.DOWN, 0.019, tint.lightened(0.32))
	# Local downward oxidation under the new fasteners, with irregular lengths.
	for index in 6:
		var x := -1.39 + _rng.randf() * 0.34
		var length := _rng.randf_range(0.08, 0.27)
		_patch("marks", pose * Vector3(x, 1.11 - length * 0.5, 0.032), pose.basis.x, Vector3.UP, Vector2(0.013, length), RUST.darkened(0.15))

func _work_corner(pose: Transform3D, tint: Color, theme: int) -> void:
	# A shallow bench hugs a solid face. No tall object enters a walking lane.
	_box("solid", pose, Vector3(-0.70, 0.61, 0.05), Vector3(0.70, 0.045, 0.19), STEEL, 0.65)
	_box("fine", pose, Vector3(-0.76, 0.64, 0.08), Vector3(0.27, 0.012, 0.16), Color("#738777"), 0.0)
	_box("fine", pose, Vector3(-0.62, 0.69, 0.08), Vector3(0.26, 0.075, 0.14), tint.darkened(0.2), 0.45)
	_box("fine", pose * Transform3D(Basis(Vector3.RIGHT, -0.28), Vector3(-0.62, 0.735, 0.012)), Vector3.ZERO, Vector3(0.27, 0.015, 0.16), tint, 0.5)
	for index in 3:
		_box("fine", pose, Vector3(-0.92 + index * 0.063, 0.66, 0.07), Vector3(0.016, 0.017, 0.12), STEEL.lightened(0.28), 0.95)
	var cup := CylinderMesh.new()
	cup.top_radius = 0.034
	cup.bottom_radius = 0.029
	cup.height = 0.065
	cup.radial_segments = 10
	_primitive("fine", cup, pose * Transform3D(Basis.IDENTITY, Vector3(-0.40, 0.668, 0.075)), PALE, 0.05)
	_ring("fine", pose * Vector3(-0.355, 0.673, 0.075), pose.basis.x, Vector3.UP, 0.024, 0.007, PALE, 0.1)
	# A looped hose stays flat against the wall, rather than across the floor.
	_ring("solid", pose * Vector3(0.45, 0.80, 0.02), pose.basis.x, Vector3.UP, 0.18, 0.016, DARK, 0.12)
	_ring("solid", pose * Vector3(0.45, 0.80, 0.04), pose.basis.x, Vector3.UP, 0.158, 0.016, DARK.lightened(0.05), 0.12)
	_box("fine", pose, Vector3(0.43, 0.99, 0.04), Vector3(0.11, 0.02, 0.045), STEEL, 0.85)
	for index in 4:
		var base := pose * Vector3(_rng.randf_range(-1.6, 1.6), 0.005, 0.30)
		_tuft(base, 0.075 + _rng.randf() * 0.030, tint.lerp(Color("#879152"), 0.65) if theme != 0 else Color("#a09660"), 8)

func _loading_bay(at: Vector3, basis: Basis, tint: Color, id: int) -> void:
	var axis := basis.x
	var out := basis.z
	var paint := tint.lerp(PALE, 0.6)
	for side in [-1, 1]:
		_line("marks", at + axis * side * 1.70 - out * 0.65, at + axis * side * 1.70 + out * 0.65, 0.09, paint)
		_line("marks", at + axis * side * 1.70 + out * 0.65, at + axis * side * 1.15 + out * 0.65, 0.09, paint)
	_text("marks", "%02d" % (id + 1), at - axis * 0.35 + out * 0.40, axis, -out, 0.085, paint)
	_arrow(at - out * 0.35, axis, -out, paint)
	# Paired, broken tyre tracks terminate at the workshop apron.
	for side in [-1, 1]:
		for index in 11:
			if _rng.randf() < 0.22:
				continue
			var t := index * 0.23
			var point: Vector3 = at + axis * (side * 0.65 + sin(t * 0.7) * 0.18) + out * (0.9 + t)
			_patch("tracks", point, axis, out, Vector2(0.12, 0.20), Color("#a18e6d"))
	_stats.markings += 1

func _build_ground() -> void:
	# Sparse navigation paint follows the broad existing workshop lanes.
	for side in [-1, 1]:
		for index in 11:
			var z := -21.0 + index * 4.0
			_line("marks", Vector3(side * 22.0, 0.013, z), Vector3(side * 22.0, 0.013, z + 1.5), 0.10, THEMES[0 if side < 0 else 1].lerp(PALE, 0.6))
		_text("marks", "SERVICE", Vector3(side * 19.2, 0.014, 21.5), Vector3.RIGHT, Vector3.FORWARD, 0.16, PALE.darkened(0.13))
	for at in [Vector3(-19, 0.012, -20), Vector3(16.5, 0.012, 20), Vector3(-2.9, 0.012, -17), Vector3(1.8, 0.012, 19)]:
		_arrow(at, Vector3.RIGHT, Vector3.FORWARD, PALE.darkened(0.12))
	for index in 45:
		var side := index % 4
		var along := -25.0 + (index / 4) * 4.7
		var base := Vector3(along, 0.005, -26.9) if side == 0 else (Vector3(along, 0.005, 26.9) if side == 1 else Vector3(-26.9 if side == 2 else 26.9, 0.005, along))
		_tuft(base + Vector3(_rng.randf_range(-0.2, 0.2), 0, _rng.randf_range(-0.2, 0.2)), _rng.randf_range(0.06, 0.115), Color("#72814c"), 12)
	# Small fissure plants remain below 12 cm, outside the concealment system.
	for at in [Vector3(-20,0,-6), Vector3(21,0,6), Vector3(-2,0,23), Vector3(3,0,-22), Vector3(-14,0,-21), Vector3(13,0,21)]:
		for index in 4:
			_tuft(at + Vector3(index * 0.085, 0.008, index * 0.13), 0.085, Color("#6e804c"), 7)

func _build_exterior() -> void:
	# Northern silhouettes are entirely beyond the playable perimeter.
	var tower := Transform3D(Basis.IDENTITY, Vector3(36, 0, -18))
	for x in [-1.3, 1.3]:
		for z in [-1.3, 1.3]:
			_box("exterior", tower, Vector3(x, 3.1, z), Vector3(0.20, 6.2, 0.20), DARK, 0.45)
			_beam("exterior", tower * Vector3(x, 0.4, z), tower * Vector3(-x, 5.8, z), 0.11, STEEL, 0.6)
	var tank := CylinderMesh.new()
	tank.top_radius = 1.8
	tank.bottom_radius = 1.8
	tank.height = 3.2
	tank.radial_segments = 20
	_primitive("exterior", tank, tower * Transform3D(Basis.IDENTITY, Vector3(0, 7.4, 0)), THEMES[1].darkened(0.15), 0.35)
	for y in [5.86, 6.3, 8.5, 9.0]:
		_ring("exterior", tower * Vector3(0, y, 0), Vector3.RIGHT, Vector3.BACK, 1.82, 0.07, STEEL, 0.7)
	var cap := CylinderMesh.new()
	cap.top_radius = 0.18
	cap.bottom_radius = 1.9
	cap.height = 0.65
	cap.radial_segments = 20
	_primitive("exterior", cap, tower * Transform3D(Basis.IDENTITY, Vector3(0, 9.32, 0)), STEEL, 0.45)
	for step in 28:
		_box("exterior", tower, Vector3(1.93, 0.35 + step * 0.31, 0), Vector3(0.06, 0.032, 0.43), PALE.darkened(0.2), 0.60)
	for z in [-0.24, 0.24]:
		_box("exterior", tower, Vector3(1.95, 4.55, z), Vector3(0.045, 8.8, 0.045), DARK, 0.60)
	_text("exterior", "EAU 07", tower * Vector3(-1.06, 7.7, 1.806), Vector3.RIGHT, Vector3.DOWN, 0.060, PALE)
	_stats.landmarks += 1
	var crane := Transform3D(Basis.IDENTITY, Vector3(-37, 0, -20))
	_box("exterior", crane, Vector3(0, 3.2, 0), Vector3(0.35, 6.4, 0.35), THEMES[0], 0.3)
	for y in 6:
		_beam("exterior", crane * Vector3(-0.35, y, 0.05), crane * Vector3(0.35, y + 1, 0.05), 0.08, DARK, 0.6)
	_beam("exterior", crane * Vector3(-3, 6.9, 0), crane * Vector3(5.4, 6.9, 0), 0.22, THEMES[0], 0.35)
	_beam("exterior", crane * Vector3(0, 8.4, 0), crane * Vector3(5.4, 6.9, 0), 0.045, DARK, 0.6)
	_beam("exterior", crane * Vector3(0, 8.4, 0), crane * Vector3(-3, 6.9, 0), 0.045, DARK, 0.6)
	_beam("exterior", crane * Vector3(4.8, 6.8, 0), crane * Vector3(4.8, 3.5, 0), 0.02, DARK, 0.5)
	_ring("exterior", crane * Vector3(4.8, 3.34, 0), Vector3.RIGHT, Vector3.UP, 0.16, 0.045, STEEL, 0.8)
	_box("exterior", crane, Vector3(-2.4, 6.9, 0), Vector3(0.9, 0.65, 0.95), DARK, 0.3)
	_stats.landmarks += 1
	for index in 4:
		var side := -1 if index < 2 else 1
		var pose := Transform3D(Basis.IDENTITY, Vector3(side * 44.0, 0, -25 + (index % 2) * 21))
		_box("exterior", pose, Vector3(0, 2.5, 0), Vector3(6.4, 5.0, 9.0), Color("#7d7260"), 0.03)
		for half in [-1, 1]:
			var roof_pose := pose * Transform3D(Basis(Vector3.RIGHT, half * 0.14), Vector3(0, 5.37, half * 2.4))
			_box("exterior", roof_pose, Vector3.ZERO, Vector3(7.1, 0.12, 5.0), THEMES[index % 3].darkened(0.3), 0.2)
			for rib in 23:
				_box("exterior", roof_pose, Vector3(-3.3 + rib * 0.30, 0.076, 0), Vector3(0.025, 0.023, 5.0), THEMES[index % 3].darkened(0.22), 0.3)
		for face in [-1, 1]:
			_triangle("exterior", pose * Vector3(face * 3.2, 5, -4.5), pose * Vector3(face * 3.2, 5.7, 0), pose * Vector3(face * 3.2, 5, 4.5), Color("#7d7260"))
		for corner in [-1, 1]:
			_box("exterior", pose, Vector3(-side * 3.24, 2.55, corner * 4.39), Vector3(0.10, 5.1, 0.12), STEEL.darkened(0.24), 0.5)
		_box("exterior", pose, Vector3(-side * 3.24, 0.38, 0), Vector3(0.05, 0.70, 8.75), THEMES[index % 3].darkened(0.16), 0.15)
		_box("exterior", pose, Vector3(-side * 3.26, 3.1, 0), Vector3(0.11, 0.09, 8.9), STEEL, 0.65)
		for bay in 3:
			var z := -3.0 + bay * 3.0
			_box("exterior", pose, Vector3(-side * 3.255, 1.5, z), Vector3(0.04, 2.7, 1.9), STEEL.darkened(0.18), 0.35)
			for rib in 11:
				_box("exterior", pose, Vector3(-side * 3.285, 0.31 + rib * 0.23, z), Vector3(0.028, 0.030, 1.87), STEEL.darkened(0.02), 0.65)
			for edge in [-1, 1]:
				_box("exterior", pose, Vector3(-side * 3.285, 1.55, z + edge * 0.985), Vector3(0.09, 2.85, 0.075), PALE.darkened(0.27), 0.25)
			_box("exterior", pose, Vector3(-side * 3.25, 3.96, z), Vector3(0.04, 0.68, 1.45), DARK, 0.45)
			for pane in [-1, 1]:
				_box("exterior", pose, Vector3(-side * 3.28, 3.96, z + pane * 0.37), Vector3(0.028, 0.54, 0.61), Color("#4d6970"), 0.25)
				_box("exterior", pose, Vector3(-side * 3.295, 4.12, z + pane * 0.37), Vector3(0.013, 0.08, 0.59), Color("#7b949a"), 0.3)
		var stack := CylinderMesh.new()
		stack.top_radius = 0.32
		stack.bottom_radius = 0.45
		stack.height = 4.2 + index * 0.5
		stack.radial_segments = 12
		_primitive("exterior", stack, pose * Transform3D(Basis.IDENTITY, Vector3(1, 7.1 + index * 0.25, -2)), RUST.darkened(0.1), 0.25)
		_stats.exterior_buildings += 1

func _arrow(at: Vector3, axis: Vector3, direction: Vector3, color: Color) -> void:
	_patch("marks", at, axis, direction, Vector2(0.13, 0.48), color)
	_triangle("marks", at + direction * 0.56, at + direction * 0.16 + axis * 0.29, at + direction * 0.16 - axis * 0.29, color)

func _tuft(at: Vector3, height: float, color: Color, blades: int) -> void:
	_stats.plants += 1
	for blade in blades:
		var angle := blade * 2.39996 + _rng.randf_range(-0.2, 0.2)
		var out := Vector3(cos(angle), 0, sin(angle))
		var across := Vector3(-out.z, 0, out.x)
		var h := height * _rng.randf_range(0.45, 1.0)
		var base := at + out * _rng.randf_range(0, 0.05)
		var tip := base + Vector3.UP * h + out * h * 0.65
		var mid := base.lerp(tip, 0.65)
		var w := h * 0.13
		_triangle("leaf", base - across * w, base + across * w, mid + across * w * 0.6, color.darkened(0.16), Vector2.ZERO, Vector2.RIGHT, Vector2(1,0.65))
		_triangle("leaf", base - across * w, mid + across * w * 0.6, mid - across * w * 0.6, color, Vector2.ZERO, Vector2(1,0.65), Vector2(0,0.65))
		_triangle("leaf", mid - across * w * 0.6, mid + across * w * 0.6, tip, color.lightened(0.06), Vector2(0,0.65), Vector2(1,0.65), Vector2(0.5,1))

func _text(kind: String, value: String, at: Vector3, right: Vector3, down: Vector3, pixel: float, color: Color) -> void:
	for letter in value.length():
		var glyph: Array = GLYPHS.get(value[letter], GLYPHS[" "])
		for row in 7:
			for col in 5:
				if int(glyph[row]) & (1 << (4 - col)):
					var center := at + right * ((letter * 6 + col) * pixel) + down * row * pixel
					_patch(kind, center, right, down, Vector2.ONE * pixel * 0.90, color)

func _line(kind: String, a: Vector3, b: Vector3, width: float, color: Color) -> void:
	var delta := b - a
	var side := delta.cross(Vector3.UP).normalized()
	if side.length_squared() < 0.01:
		side = Vector3.RIGHT
	_patch(kind, (a + b) * 0.5, side, delta.normalized(), Vector2(width, delta.length()), color)

func _patch(kind: String, at: Vector3, axis: Vector3, up: Vector3, size: Vector2, color: Color) -> void:
	var a := axis * size.x * 0.5
	var b := up * size.y * 0.5
	_triangle(kind, at - a - b, at + a - b, at + a + b, color)
	_triangle(kind, at - a - b, at + a + b, at - a + b, color)

func _ring(kind: String, at: Vector3, right: Vector3, up: Vector3, radius: float, width: float, color: Color, metallic: float) -> void:
	# A continuous tube avoids hundreds of capped cylinders per small hose.
	var segments := 24 if radius > 1.0 else 16
	var sides := 6 if radius > 1.0 else 4
	var normal := right.cross(up).normalized()
	var tint := Color(color, metallic)
	for index in segments:
		var a := index * TAU / segments
		var b := (index + 1) * TAU / segments
		var ra := right * cos(a) + up * sin(a)
		var rb := right * cos(b) + up * sin(b)
		for side in sides:
			var c := side * TAU / sides
			var d := (side + 1) * TAU / sides
			var p := at + ra * (radius + cos(c) * width * 0.5) + normal * sin(c) * width * 0.5
			var q := at + rb * (radius + cos(c) * width * 0.5) + normal * sin(c) * width * 0.5
			var r := at + rb * (radius + cos(d) * width * 0.5) + normal * sin(d) * width * 0.5
			var s := at + ra * (radius + cos(d) * width * 0.5) + normal * sin(d) * width * 0.5
			_triangle(kind, p, q, r, tint)
			_triangle(kind, p, r, s, tint)

func _beam(kind: String, a: Vector3, b: Vector3, width: float, color: Color, metallic: float) -> void:
	var mesh := CylinderMesh.new()
	mesh.top_radius = width * 0.5
	mesh.bottom_radius = width * 0.5
	mesh.height = a.distance_to(b)
	mesh.radial_segments = 6
	mesh.rings = 1
	_primitive(kind, mesh, Transform3D(Basis(Quaternion(Vector3.UP, (b - a).normalized())), (a + b) * 0.5), color, metallic)

func _box(kind: String, pose: Transform3D, at: Vector3, size: Vector3, color: Color, metallic: float) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	_primitive(kind, mesh, pose * Transform3D(Basis.IDENTITY, at), color, metallic)

func _primitive(kind: String, mesh: PrimitiveMesh, pose: Transform3D, color: Color, metallic: float) -> void:
	var arrays := mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var tint := Color(color, metallic)
	for index in range(0, indices.size(), 3):
		_triangle(kind, pose * vertices[indices[index]], pose * vertices[indices[index + 1]], pose * vertices[indices[index + 2]], tint)

func _triangle(kind: String, a: Vector3, b: Vector3, c: Vector3, color: Color, ua := Vector2.ZERO, ub := Vector2.RIGHT, uc := Vector2.ONE) -> void:
	var cell := Vector2i(floori((a.x + 60) / 16.0), floori((a.z + 60) / 16.0))
	var key := "%s_%d_%d" % [kind, cell.x, cell.y]
	if not _batches.has(key):
		_batches[key] = {"kind": kind, "v": PackedVector3Array(), "n": PackedVector3Array(), "c": PackedColorArray(), "uv": PackedVector2Array(), "anchor": a}
	var data: Dictionary = _batches[key]
	var normal := (c - a).cross(b - a).normalized()
	data.v.append_array(PackedVector3Array([a, b, c]))
	data.n.append_array(PackedVector3Array([normal, normal, normal]))
	data.c.append_array(PackedColorArray([color.srgb_to_linear(), color.srgb_to_linear(), color.srgb_to_linear()]))
	data.uv.append_array(PackedVector2Array([ua, ub, uc]))
	_triangles += 1

func _commit_batches() -> void:
	for key in _batches:
		var data: Dictionary = _batches[key]
		var arrays: Array = []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = data.v
		arrays[Mesh.ARRAY_NORMAL] = data.n
		arrays[Mesh.ARRAY_COLOR] = data.c
		arrays[Mesh.ARRAY_TEX_UV] = data.uv
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		var instance := MeshInstance3D.new()
		instance.name = "Art_" + key
		instance.mesh = mesh
		instance.visibility_range_end = 90.0 if data.kind == "exterior" else 50.0
		instance.visibility_range_end_margin = 3.0
		instance.set_meta("fine_detail", data.kind in ["fine", "tracks", "paper"])
		instance.set_meta("solid_detail", data.kind in ["solid", "fine", "exterior"])
		instance.set_meta("art_kind", data.kind)
		var material := ShaderMaterial.new()
		if data.kind == "leaf":
			material.shader = LEAVES
			material.set_shader_parameter("wind_direction", Vector2(WIND.DIRECTION.x, WIND.DIRECTION.z))
			material.set_meta("anchor", data.anchor)
			_leaf_materials.append(material)
		elif data.kind in ["marks", "tracks", "paper"]:
			material.shader = MARKS
			material.set_shader_parameter("concrete_detail", preload("res://art/environment/courtyard_concrete_detail.png"))
			material.set_shader_parameter("wear", 0.23 if data.kind == "marks" else 0.30)
		else:
			material.shader = SURFACE
			material.set_shader_parameter("detail", preload("res://art/environment/courtyard_concrete_detail.png"))
		instance.material_override = material
		add_child(instance)
