extends Node3D
## Visual skin for the existing tide terrain. Never owns a collider or an actor.
## Floating gardens are parented to the actual barges, including their animation.
const BATCH := preload("res://scripts/environment/arena_detail_batch.gd")
const STONE := preload("res://shaders/tideglass_stone.gdshader")
const ATLAS := preload("res://art/environment/tideglass/conservatory_materials.png")
const LIGHTING := preload("res://scripts/environment/arena_lighting_profile.gd")
const METAL_SHADER := """
shader_type spatial;
uniform sampler2D atlas : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform vec2 quadrant = vec2(0.5, 0.0);
uniform float metal = 0.45;
uniform vec4 tint : source_color = vec4(0.16, 0.30, 0.25, 1.0);
varying vec3 world;
varying vec3 wn;
void vertex() { world = (MODEL_MATRIX * vec4(VERTEX,1.0)).xyz; wn = MODEL_NORMAL_MATRIX * NORMAL; }
void fragment() {
    vec2 p = abs(wn.x) > 0.7 ? world.zy : abs(wn.z) > 0.7 ? world.xy : world.xz;
    vec3 tex = texture(atlas, quadrant + vec2(0.01) + fract(p * 0.32) * 0.48).rgb;
    ALBEDO = mix(tint.rgb, tex, 0.50);
    METALLIC = metal;
    ROUGHNESS = 0.32 + tex.g * 0.14;
    SPECULAR = 0.45;
}
"""
const LEAF_SHADER := """
shader_type spatial;
render_mode cull_disabled;
uniform float clock = 0.0;
uniform sampler2D atlas : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
void vertex() {
    VERTEX.x += sin(clock * 0.8 + VERTEX.z * 2.0) * UV.y * UV.y * 0.018;
}
void fragment() {
    float edge = pow(abs(UV.x * 2.0 - 1.0), 2.0);
    float midrib = 1.0 - smoothstep(0.014, 0.035, abs(UV.x - 0.5));
    vec3 tex = texture(atlas, vec2(0.01, 0.51) + vec2(UV.x, 1.0 - UV.y) * 0.48).rgb;
    vec3 col = tex * (1.15 + COLOR.rgb * 1.5) * (0.90 + edge * 0.10) + COLOR.rgb * 0.07;
    col = mix(col, vec3(dot(col, vec3(0.2126,0.7152,0.0722))), 0.13);
    ALBEDO = mix(col, vec3(0.23, 0.31, 0.09), midrib * 0.12);
    ROUGHNESS = 0.67;
    SPECULAR = 0.20;
    BACKLIGHT = COLOR.rgb * 0.26;
}
"""

var initialized := false
var _stage: Node3D
var _basin: Node3D
var _stone: ShaderMaterial
var _wall: ShaderMaterial
var _pool: ShaderMaterial
var _leaf: ShaderMaterial
var _green: ShaderMaterial
var _brass: ShaderMaterial
var _soil: StandardMaterial3D
var _green_recess: ShaderMaterial
var _leaf_count := 0
var _planters := 0
var _batches := 0
var _float_gardens: Array[Node3D] = []
var _lilies: Node3D
var _medallions: Array[Dictionary] = []
var _planar: SubViewport
var _mirror_camera: Camera3D
var _reflection_frames := 0
var _render_quality := -1
var _saved_msaa := Viewport.MSAA_DISABLED
var _shadow_defaults: Array = []
var _main_view: Viewport
var _roof_shadow_meshes: Array[MeshInstance3D] = []
const REFLECTED_LAYER := 1 << 18

func configure(stage: Node3D, basin: Node3D) -> void:
	_stage = stage
	_basin = basin
	set_meta("visual_only", true)
	_finish.call_deferred()

func _finish() -> void:
	# The shared presentation first finishes and batches the legacy decoration.
	# Skin its finished result once, so it cannot re-create the mechanical pots.
	for frame in 12:
		if not is_inside_tree() or _stage.is_queued_for_deletion():
			return
		var presentation := _stage.get_node_or_null("CompactArenaPresentation")
		if presentation != null and bool(presentation.get("_initialized")):
			break
		await get_tree().process_frame
	if not is_inside_tree() or _stage.is_queued_for_deletion():
		return
	_make_materials()
	_finish_surfaces()
	_build_island_edges()
	_build_stairs()
	var index := 0
	var floating_bodies: Array[Node3D] = []
	for entry in _basin.get("barges"):
		floating_bodies.append(entry.body)
	for body in _basin.get_children():
		# Godot gives repeated unnamed bodies generated names; use their actual
		# gameplay role rather than the display name to find all three gardens.
		if body is StaticBody3D and bool(body.get_meta("blocks_navigation", false)) and body not in floating_bodies:
			_skin_planter(body, Vector3(3, 1, 1.1) if absf(body.position.x) < 1.0 else Vector3(1.4, 1, 2.7), index)
			index += 1
	for entry in _basin.get("barges"):
		_skin_planter(entry.body, entry.size, index)
		_float_gardens.append(entry.body.get_node("ConservatoryPlanter"))
		index += 1
	_build_glazing()
	_build_roof_shadows()
	_build_lilies()
	_build_medallions()
	_sunlight()
	_build_planar_reflections()
	initialized = true
	update_tide(float(_basin.get("elapsed")), float(_basin.get("water_level")))

func _material(color: String, roughness: float, metallic: float = 0.0) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(color)
	material.roughness = roughness
	material.metallic = metallic
	return material

func _make_materials() -> void:
	_stone = ShaderMaterial.new()
	_stone.shader = STONE
	_stone.set_shader_parameter("stone_color", Color("#ded9ca"))
	_stone.set_shader_parameter("surface_atlas", ATLAS)
	_wall = _stone.duplicate()
	_wall.set_shader_parameter("wall", true)
	_pool = _stone.duplicate()
	_pool.set_shader_parameter("basin", true)
	_pool.set_shader_parameter("stone_color", Color("#438881"))
	var metal_shader := Shader.new()
	metal_shader.code = METAL_SHADER
	_green = ShaderMaterial.new()
	_green.shader = metal_shader
	_green.set_shader_parameter("atlas", ATLAS)
	_green.set_shader_parameter("tint", Color("#315b48"))
	_green_recess = _green.duplicate()
	_green_recess.set_shader_parameter("tint", Color("#122e28"))
	_brass = _green.duplicate()
	_brass.set_shader_parameter("quadrant", Vector2(0.5, 0.5))
	_brass.set_shader_parameter("tint", Color("#bda16b"))
	_brass.set_shader_parameter("metal", 0.72)
	_soil = _material("#1e2d21", 0.95)
	_leaf = ShaderMaterial.new()
	var shader := Shader.new()
	shader.code = LEAF_SHADER
	_leaf.shader = shader
	_leaf.set_shader_parameter("atlas", ATLAS)

func _finish_surfaces() -> void:
	for mesh in _stage.find_children("*", "MeshInstance3D", true, false):
		var label := str(mesh.name)
		if label == "IslandTiles":
			mesh.material_override = _stone
		elif label == "ContinuousDeck":
			mesh.material_override = _pool
		elif label == "PorcelainWall":
			mesh.material_override = _wall
		elif label == "RampGrip":
			mesh.visible = false
		# Keep all authored outer gardens, recolour the structural ironwork.
		elif label.begins_with("GlassFlyingButtress") or label.begins_with("ButtressOuterFoot") or label.begins_with("GreenhouseVaultRib"):
			mesh.material_override = _green

func _flush(batch: RefCounted, parent: Node3D, label: String, shadows: bool = true) -> void:
	var meshes: Array[MeshInstance3D] = batch.flush(parent, label)
	_batches += meshes.size()
	for mesh in meshes:
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

func _build_island_edges() -> void:
	var batch := BATCH.new()
	for polygon in _basin.get("islands"):
		var center := Vector2.ZERO
		for p in polygon:
			center += p
		center /= polygon.size()
		for i in polygon.size():
			var a: Vector2 = polygon[i]
			var b: Vector2 = polygon[(i + 1) % polygon.size()]
			var inward := (center - (a + b) * 0.5).normalized()
			batch.beam(_brass, Vector3(a.x, 1.37, a.y), Vector3(b.x, 1.37, b.y), 0.075)
			a += inward * 0.17
			b += inward * 0.17
			batch.beam(_green, Vector3(a.x, 1.382, a.y), Vector3(b.x, 1.382, b.y), 0.095)
	_flush(batch, self, "IslandInlays", false)

func _build_stairs() -> void:
	var batch := BATCH.new()
	for ramp in _basin.get("ramps"):
		var direction: Vector2 = ramp.direction
		var side := Vector2(-direction.y, direction.x)
		var basis := Basis(Vector3(side.x, 0, side.y), Vector3.UP, Vector3(direction.x, 0, direction.y))
		for step in 12:
			var t := (float(step) + 0.5) / 12.0
			var p: Vector2 = ramp.start + direction * float(ramp.length) * t
			var at := Vector3(p.x, 1.35 * (1.0 - t) - 0.025, p.y)
			batch.box(_stone, at, Vector3(float(ramp.width) * 0.99, 0.075, float(ramp.length) / 12.0 - 0.009), basis)
	_flush(batch, self, "SubmergedStoneSteps", false)

func _skin_planter(body: StaticBody3D, size: Vector3, index: int) -> void:
	_planters += 1
	for child in body.get_children():
		if child is Node3D and not child is CollisionShape3D:
			child.hide()
	var root := Node3D.new()
	root.name = "ConservatoryPlanter"
	root.set_meta("visual_only", true)
	root.set_meta("cover_size", size)
	body.add_child(root)
	var batch := BATCH.new()
	batch.beveled_box(_green, Vector3.ZERO, size * Vector3(0.99, 0.94, 0.99), 0.07)
	batch.beveled_box(_green, Vector3(0, size.y * 0.43, 0), Vector3(size.x + 0.07, 0.12, size.z + 0.07), 0.035)
	batch.beveled_box(_green_recess, Vector3(0, -size.y * 0.42, 0), Vector3(size.x + 0.04, 0.12, size.z + 0.04), 0.03)
	batch.beveled_box(_soil, Vector3(0, size.y * 0.48, 0), Vector3(size.x * 0.86, 0.04, size.z * 0.80), 0.03)
	for sign_value in [-1.0, 1.0]:
		batch.beveled_box(_green_recess, Vector3(0, 0, sign_value * size.z * 0.496), Vector3(size.x * 0.90, size.y * 0.65, 0.055), 0.025)
		batch.beveled_box(_green, Vector3(0, 0, sign_value * size.z * 0.511), Vector3(size.x * 0.84, size.y * 0.53, 0.04), 0.015)
		for y in [-size.y * 0.46, size.y * 0.43]:
			batch.box(_brass, Vector3(0, y, sign_value * size.z * 0.49), Vector3(size.x, 0.045, 0.065))
			batch.box(_brass, Vector3(sign_value * size.x * 0.49, y, 0), Vector3(0.065, 0.045, size.z))
		for other in [-1.0, 1.0]:
			var at := Vector3(sign_value * (size.x * 0.5 - 0.07), 0, other * (size.z * 0.5 - 0.07))
			batch.beveled_box(_brass, at, Vector3(0.17, size.y, 0.17), 0.025)
			batch.beveled_box(_brass, at + Vector3.UP * (size.y * 0.42), Vector3(0.29, 0.19, 0.29), 0.045)
	var long_x := size.x > size.z
	for plant in 3:
		var offset := (float(plant) - 1.0) * maxf(size.x, size.z) * 0.25
		var at := Vector3(offset if long_x else 0.0, size.y * 0.50, 0.0 if long_x else offset)
		_plant(batch, at, 0.91 + float((index + plant) % 3) * 0.12, index * 7 + plant)
	_flush(batch, root, "EnamelBrassAndBotanicals")

func _plant(batch: RefCounted, at: Vector3, scale: float, seed_value: int) -> void:
	var colors := [Color("#668444"), Color("#7e9656"), Color("#456b3f"), Color("#8d9e59")]
	for index in 5:
		var angle := float(index) * 2.39996 + float(seed_value) * 0.71
		var length := (0.85 + float((index + seed_value) % 4) * 0.19) * scale
		var rise := (0.45 + float((index * 3 + seed_value) % 5) * 0.20) * scale
		_leaf_mesh(batch, at, Vector3(cos(angle), 0, sin(angle)), length, length * 0.20, rise, colors[(index + seed_value) % 4])
	# Fern fronds give a second silhouette beneath the broad banana leaves.
	for index in 3:
		var angle := float(index) * 2.1 + seed_value
		var direction := Vector3(cos(angle), 0, sin(angle))
		for pair in 7:
			var t := (float(pair) + 1.0) / 8.0
			var point := at + direction * t * scale * 0.95 + Vector3.UP * sin(t * PI * 0.65) * 0.38 * scale
			for side in [-1.0, 1.0]:
				var outward: Vector3 = (direction * 0.35 + Vector3(-direction.z, 0, direction.x) * side).normalized()
				_leaf_mesh(batch, point, outward, (1.0 - t * 0.8) * 0.35 * scale, 0.065 * scale, 0.06, colors[(index + 2) % 4], 4)

func _leaf_mesh(batch: RefCounted, at: Vector3, direction: Vector3, length: float, width: float, rise: float, color: Color, segments: int = 10) -> void:
	var surface: SurfaceTool = batch._surface(_leaf)
	for row in segments:
		for column in 4:
			var points: Array[Vector3] = []
			var uvs: Array[Vector2] = []
			for corner in [Vector2(0,0), Vector2(1,0), Vector2(1,1), Vector2(0,1)]:
				var t: float = (float(row) + corner.y) / float(segments)
				var u: float = (float(column) + corner.x) / 4.0
				var point := _leaf_point(at, direction, length, width, rise, u, t)
				points.append(point)
				uvs.append(Vector2(u, t))
			for tri in [[0,2,1], [0,3,2]]:
				for vertex in tri:
					var uv := uvs[vertex]
					var u := clampf(uv.x, 0.002, 0.998)
					var t := clampf(uv.y, 0.002, 0.998)
					var du := _leaf_point(at, direction, length, width, rise, u + 0.001, t) - _leaf_point(at, direction, length, width, rise, u - 0.001, t)
					var dt := _leaf_point(at, direction, length, width, rise, u, t + 0.001) - _leaf_point(at, direction, length, width, rise, u, t - 0.001)
					var normal := du.cross(dt).normalized()
					surface.set_normal(normal)
					surface.set_color(color.srgb_to_linear())
					surface.set_uv(uvs[vertex])
					surface.add_vertex(points[vertex])
				batch.triangles += 1
	_leaf_count += 1

func _leaf_point(at: Vector3, direction: Vector3, length: float, width: float, rise: float, u: float, t: float) -> Vector3:
	var across := (u * 2.0 - 1.0) * pow(maxf(0.0, sin(t * PI)), 0.72) * width
	var crosswise := Vector3(-direction.z, 0, direction.x)
	var point := at + direction * length * t + crosswise * across
	point.y += rise * sin(t * PI * 0.68) - absf(across) * 0.27 + sin(t * 17.0) * absf(across) * 0.06
	return point

func _build_glazing() -> void:
	var batch := BATCH.new()
	var panes := BATCH.new()
	var glass := _material("#91c8be", 0.18, 0.08)
	glass.albedo_color.a = 0.11
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.cull_mode = BaseMaterial3D.CULL_DISABLED
	# Outside the walkable footprint: tall side bays frame the arena, with no roof
	# over the duel and no foreground wall between camera and fighters.
	for side in [-1.0, 1.0]:
		var x: float = side * 13.05
		for z in [-10.0, -5.0, 0.0, 5.0, 10.0]:
			batch.beveled_box(_green, Vector3(x, 2.7, z), Vector3(0.29, 5.4, 0.34), 0.045)
			for y in [0.20, 0.46, 4.95, 5.25]:
				batch.beveled_box(_brass, Vector3(x, y, z), Vector3(0.44, 0.12, 0.48), 0.025)
			batch.box(_brass, Vector3(x - side * 0.16, 2.75, z + 0.07), Vector3(0.022, 4.3, 0.026))
		for z in [-7.5, -2.5, 2.5, 7.5]:
			for y in [0.6, 2.7, 5.35]:
				batch.box(_green, Vector3(x, y, z), Vector3(0.19, 0.10, 5.0))
				batch.box(_brass, Vector3(x - side * 0.11, y + 0.035, z), Vector3(0.035, 0.025, 5.0))
			panes.box(glass, Vector3(x + side * 0.04, 2.95, z), Vector3(0.012, 4.55, 4.72))
	_flush(batch, self, "ConservatoryMullions")
	_flush(panes, self, "ConservatoryGlass", false)

func _build_lilies() -> void:
	_lilies = Node3D.new()
	_lilies.name = "TidalLilies"
	add_child(_lilies)
	var batch := BATCH.new()
	var lily := _material("#697f3a", 0.56)
	lily.cull_mode = BaseMaterial3D.CULL_DISABLED
	for side in [-1.0, 1.0]:
		for index in 6:
			var at := Vector3(side * (11.4 + sin(index * 1.7) * 0.35), 0, -6.8 + float(index % 3) * 0.53 + (8.7 if index > 2 else 0.0))
			var radius := 0.16 + float(index % 3) * 0.055
			for segment in 15:
				var a := 0.30 + float(segment) * (TAU - 0.6) / 15.0
				var b := 0.30 + float(segment + 1) * (TAU - 0.6) / 15.0
				batch.triangle(lily, at, at + Vector3(cos(a), 0, sin(a)) * radius, at + Vector3(cos(b), 0, sin(b)) * radius)
	_flush(batch, _lilies, "LilyPads", false)

func _build_roof_shadows() -> void:
	# The cutaway roof leaves fighters visible while its mullions cast the real
	# diagonal conservatory shadows seen on the stone and underwater floor.
	var batch := BATCH.new()
	var diagonal := Basis(Vector3.UP, deg_to_rad(-24.0))
	for z in [-10.0, -5.0, 0.0, 5.0, 10.0, 15.0]:
		batch.beam(_green, diagonal * Vector3(-16.0, 7.5, z), diagonal * Vector3(16.0, 7.5, z), 0.20)
	for x in [-10.0, -5.0, 0.0, 5.0, 10.0]:
		batch.beam(_green, diagonal * Vector3(x, 7.5, -14.0), diagonal * Vector3(x, 7.5, 18.0), 0.14)
	_roof_shadow_meshes = batch.flush(self, "CutawayRoofShadows")
	for mesh in _roof_shadow_meshes:
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY

func _sunlight() -> void:
	var scene := _stage.get_parent()
	var sun := scene.get_node_or_null("ArenaKeyLight") as DirectionalLight3D
	if sun != null:
		sun.light_color = Color("#fff0d4")
		sun.light_energy = 1.18
		sun.shadow_blur = 2.0
	for child in scene.get_children():
		if child is WorldEnvironment:
			child.environment.background_mode = Environment.BG_SKY
			child.environment.ambient_light_color = Color("#b4ccbe")
			child.environment.ambient_light_energy = 0.38

func _build_planar_reflections() -> void:
	# Render only architectural frames and the real gardens. Omitting the basin
	# floor allows the mirrored camera to sit below water without seeing its back.
	for mesh in find_children("ConservatoryMullions*", "MeshInstance3D", true, false):
		mesh.layers |= REFLECTED_LAYER
	for mesh in find_children("ConservatoryGlass*", "MeshInstance3D", true, false):
		mesh.layers |= REFLECTED_LAYER
	for body in _basin.get_children():
		var garden := body.get_node_or_null("ConservatoryPlanter")
		if garden != null:
			for mesh in garden.find_children("*", "MeshInstance3D", true, false):
				mesh.layers |= REFLECTED_LAYER
	_planar = SubViewport.new()
	_planar.name = "WaterReflectionView"
	_planar.world_3d = get_viewport().world_3d
	_planar.transparent_bg = false
	_planar.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_planar.positional_shadow_atlas_size = 0
	_planar.msaa_3d = Viewport.MSAA_2X
	add_child(_planar)
	_mirror_camera = Camera3D.new()
	_mirror_camera.name = "WaterMirrorCamera"
	_mirror_camera.cull_mask = REFLECTED_LAYER
	_planar.add_child(_mirror_camera)
	_mirror_camera.current = true
	var water: ShaderMaterial = _basin.get("_water_material")
	water.set_shader_parameter("planar_reflection", _planar.get_texture())
	water.set_shader_parameter("use_planar_reflection", true)
	_main_view = get_viewport()
	_saved_msaa = _main_view.msaa_3d
	_shadow_defaults = [int(ProjectSettings.get_setting("rendering/lights_and_shadows/directional_shadow/size", 1024)),
		bool(ProjectSettings.get_setting("rendering/lights_and_shadows/directional_shadow/16_bits", true)),
		int(ProjectSettings.get_setting("rendering/lights_and_shadows/directional_shadow/soft_shadow_filter_quality", 0))]
	_refresh_reflection()

func _process(_delta: float) -> void:
	if initialized:
		_reflection_frames += 1
		if _reflection_frames % 3 == 0:
			_refresh_reflection()

func _refresh_reflection() -> void:
	if not is_instance_valid(_mirror_camera):
		return
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	var quality := 1
	var presentation := _stage.get_node_or_null("CompactArenaPresentation")
	if presentation != null:
		quality = int(presentation.get("_quality"))
	if quality != _render_quality and DisplayServer.get_name() != "headless":
		# Thin roof bars alias at the low preset's small shadow atlas. Keep the
		# structural frame and its reflection, with this extra shadow layer off.
		for mesh in _roof_shadow_meshes:
			mesh.visible = quality > 0
		var profile := LIGHTING.new()
		profile.shadow_atlas_normal = 2048
		profile.shadow_atlas_low = 1024
		profile.antialiasing_normal = Viewport.MSAA_2X
		profile.apply_render_quality(get_viewport(), quality)
		_render_quality = quality
	var width := 640 if quality > 0 else 320
	var viewport_size := get_viewport().get_visible_rect().size
	_planar.size = Vector2i(width, maxi(1, roundi(width * viewport_size.y / maxf(1.0, viewport_size.x))))
	var plane: float = _basin.get("water_level")
	var position := camera.global_position
	position.y = 2.0 * plane - position.y
	var basis := camera.global_basis
	var right := -Vector3(basis.x.x, -basis.x.y, basis.x.z)
	var up := Vector3(basis.y.x, -basis.y.y, basis.y.z)
	var back := Vector3(basis.z.x, -basis.z.y, basis.z.z)
	_mirror_camera.global_transform = Transform3D(Basis(right, up, back), position)
	_mirror_camera.fov = camera.fov
	_mirror_camera.near = camera.near
	_mirror_camera.far = camera.far
	_planar.render_target_update_mode = SubViewport.UPDATE_ONCE

func _build_medallions() -> void:
	for kit in _stage.get_children():
		if not kit is RepairKit:
			continue
		var cross_root: Node3D = kit.get("_floating_cross")
		for child in cross_root.get_children():
			if child is Node3D:
				child.hide()
		var root := Node3D.new()
		root.name = "ConservatoryHealthMedallion"
		cross_root.add_child(root)
		var cross := _material("#e4ffe9", 0.31)
		cross.emission_enabled = true
		cross.emission = Color("#a7ebba")
		cross.emission_energy_multiplier = 0.45
		var face := _material("#318965", 0.28, 0.12)
		var batch := BATCH.new()
		batch.cylinder(_green, Vector3.ZERO, 0.45, 0.15, Basis.IDENTITY, 40)
		batch.cylinder(face, Vector3.UP * 0.085, 0.39, 0.018, Basis.IDENTITY, 40)
		batch.ring(_brass, Vector3.UP * 0.08, 0.435, 0.075, 0.09, Basis.IDENTITY, 40)
		batch.beveled_box(cross, Vector3.UP * 0.112, Vector3(0.55, 0.034, 0.15), 0.013)
		batch.beveled_box(cross, Vector3.UP * 0.112, Vector3(0.15, 0.034, 0.55), 0.013)
		for index in 4:
			var angle := float(index) * PI * 0.5
			batch.beveled_box(_brass, Vector3(cos(angle) * 0.44, 0.09, sin(angle) * 0.44), Vector3(0.12, 0.13, 0.12), 0.022)
		_flush(batch, root, "MedicalMedallion", false)
		_medallions.append({"kit": kit, "face": face, "cross": cross})

func update_tide(clock: float, water_level: float) -> void:
	if not initialized:
		return
	_leaf.set_shader_parameter("clock", clock)
	_pool.set_shader_parameter("clock", clock)
	_pool.set_shader_parameter("water_level", water_level)
	_lilies.position.y = maxf(0.025, water_level + 0.018)
	_lilies.visible = water_level > 0.02
	for entry in _medallions:
		var available: bool = entry.kit.get_visual_state_name() == "available"
		entry.face.albedo_color = Color("#318965") if available else Color("#56605b")
		entry.cross.albedo_color = Color("#e4ffe9") if available else Color("#8a9390")
		entry.cross.emission_energy_multiplier = 0.45 if available else 0.0

func get_snapshot() -> Dictionary:
	return {"initialized": initialized, "visual_only": true, "planters": _planters,
		"floating_gardens": _float_gardens.size(), "leaves": _leaf_count, "batches": _batches,
		"scene_reflections": is_instance_valid(_planar), "planar_reflections": is_instance_valid(_planar),
		"render_quality": _render_quality}

func _exit_tree() -> void:
	if _render_quality >= 0 and is_instance_valid(_main_view) and not _shadow_defaults.is_empty():
		_main_view.msaa_3d = _saved_msaa
		RenderingServer.directional_shadow_atlas_set_size(_shadow_defaults[0], _shadow_defaults[1])
		RenderingServer.directional_soft_shadow_filter_set_quality(_shadow_defaults[2])
