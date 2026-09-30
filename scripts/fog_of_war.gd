extends Node3D

## Fog is an opacity field anchored to the arena, not interpolated ray lengths.
## Physical rays classify cells first; filtering and history blend those cells.
## A corner becoming visible can dissolve locally without sweeping a long spoke.
const FOG_SHADER := preload("res://scripts/fog_of_war.gdshader")
const VISIBILITY_STATE := preload("res://scripts/visibility_state.gd")

@export_range(64, 1024, 16) var ray_count := 512
@export_range(0.02, 0.25, 0.005) var refresh_interval := 0.05
@export_range(0.0, 0.5, 0.01) var cover_transition_duration := 0.18
@export_range(0.0, 1.0, 0.01) var darkness := 0.66
@export var fog_color := Color(0.018, 0.025, 0.036)
@export_range(0.4, 3.0, 0.05) var cover_softness := 1.6
@export_range(0.0, 0.5, 0.01) var edge_irregularity := 0.16
@export_range(0.0, 3.0, 0.01) var eye_height := 0.72
@export_range(64, 256, 32) var mask_resolution := 192
@export_range(64.0, 160.0, 4.0) var mask_world_size := 108.0

var _observer: Node3D
var _camera: Camera3D
var _overlay: MeshInstance3D
var _material: ShaderMaterial
var _from_image: Image
var _target_image: Image
var _from_texture: ImageTexture
var _target_texture: ImageTexture
var _from_bytes := PackedByteArray()
var _target_bytes := PackedByteArray()
var _ray_distances := PackedFloat32Array()
var _enabled := true
var _profile_ready := false
var _refresh_clock := 0.0
var _transition_clock := 0.0
var _profile_updates := 0
var _radius := VISIBILITY_STATE.DEFAULT_VISION_RADIUS
var _fade_width := VISIBILITY_STATE.DEFAULT_VISION_FADE_WIDTH
var _observer_epoch := -1
var _last_profile_position := Vector3.ZERO
var _allocated_resolution := 0
var _allocated_world_size := 0.0
var _last_update_ms := 0.0
var _cell_size := 0.0
var _cell_centres := PackedFloat32Array()


func configure(observer: Node3D, camera: Camera3D) -> void:
	_observer = observer
	_camera = camera
	_ensure_overlay()
	_profile_ready = false
	_refresh_clock = 0.0
	set_process(true)
	set_physics_process(true)
	_sync_parameters()


func set_enabled(enabled: bool) -> void:
	if enabled and not _enabled:
		_profile_ready = false
		_refresh_clock = 0.0
	_enabled = enabled
	if is_instance_valid(_overlay):
		_overlay.visible = _enabled and _profile_ready and _has_observer()


func refresh_vision() -> void:
	_profile_ready = false
	_refresh_clock = 0.0


func get_debug_snapshot() -> Dictionary:
	return {
		"enabled": _enabled, "ready": _profile_ready, "rays": ray_count,
		"profile_updates": _profile_updates, "radius": _radius,
		"full_radius": maxf(0.0, _radius - _fade_width), "darkness": darkness,
		"origin": _observer.global_position if _has_observer() else Vector3.ZERO,
		"mask_resolution": _allocated_resolution, "mask_world_size": _allocated_world_size,
		"cover_softness": cover_softness, "last_update_ms": _last_update_ms,
		"history_space": "world_opacity",
	}


func sample_world_visibility(point: Vector3) -> float:
	# Filter the same mip levels as the GPU, for deterministic visual checks.
	if not _has_observer() or not _profile_ready:
		return 1.0
	var world_point := Vector2(point.x, point.z)
	var uv := world_point / _allocated_world_size + Vector2.ONE * 0.5
	var lod := _filter_lod()
	var cover_from := _sample_filtered(_from_image, uv, lod)
	var cover_target := _sample_filtered(_target_image, uv, lod)
	var cover := lerpf(cover_from, cover_target, _profile_blend())
	# Keep fully observed floor clean and the concealed field opaque; only the
	# penumbra gets the broad, irregular shoulder used by the visual shader.
	cover = smoothstep(0.12, 0.88, cover)
	var offset := world_point - Vector2(_observer.global_position.x, _observer.global_position.z)
	return VISIBILITY_STATE.distance_visibility(offset.length(), _radius, _fade_width) * cover


func _process(delta: float) -> void:
	if not _enabled or not _has_observer():
		if is_instance_valid(_overlay):
			_overlay.visible = false
		return
	_transition_clock += maxf(0.0, delta)
	_sync_parameters()
	_overlay.visible = _profile_ready


func _physics_process(delta: float) -> void:
	if not _enabled or not _has_observer():
		return
	_refresh_clock -= delta
	var epoch := int(_observer.call("get_visibility_epoch")) if _observer.has_method("get_visibility_epoch") else 0
	var radius := VISIBILITY_STATE.observer_radius(_observer)
	var rebuilt := _allocated_resolution != mask_resolution or not is_equal_approx(_allocated_world_size, mask_world_size)
	if rebuilt:
		_allocate_masks()
	var snap_profile := rebuilt or not _profile_ready or epoch != _observer_epoch or not is_equal_approx(radius, _radius)
	if _profile_ready and _observer.global_position.distance_to(_last_profile_position) > 3.0:
		snap_profile = true
	# At 60 Hz, 0.05 - 3/60 can retain a tiny positive floating residual.
	# Do not turn a configured 20 Hz refresh into an uneven 15 Hz cadence.
	if _refresh_clock > 0.000001 and not snap_profile:
		return
	_radius = radius
	_fade_width = VISIBILITY_STATE.observer_fade_width(_observer)
	_observer_epoch = epoch
	_update_cover_profile(snap_profile)
	_refresh_clock = maxf(0.02, refresh_interval)


func _has_observer() -> bool:
	return is_instance_valid(_observer) and _observer.is_inside_tree() and is_instance_valid(_camera)


func _ensure_overlay() -> void:
	if is_instance_valid(_overlay):
		return
	_material = ShaderMaterial.new()
	_material.shader = FOG_SHADER
	_material.render_priority = 126
	_allocate_masks()
	var quad := QuadMesh.new()
	quad.size = Vector2(2.0, 2.0)
	_overlay = MeshInstance3D.new()
	_overlay.name = "WorldFogOverlay"
	_overlay.mesh = quad
	_overlay.material_override = _material
	_overlay.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_overlay.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	_overlay.custom_aabb = AABB(Vector3.ONE * -4096.0, Vector3.ONE * 8192.0)
	_overlay.ignore_occlusion_culling = true
	_overlay.visible = false
	add_child(_overlay)


func _allocate_masks() -> void:
	mask_resolution = clampi(mask_resolution, 64, 256)
	mask_world_size = maxf(64.0, mask_world_size)
	_allocated_resolution = mask_resolution
	_allocated_world_size = mask_world_size
	_cell_size = mask_world_size / float(mask_resolution)
	_cell_centres.resize(mask_resolution)
	for index in range(mask_resolution):
		_cell_centres[index] = (float(index) + 0.5) * _cell_size - mask_world_size * 0.5
	_from_bytes.resize(mask_resolution * mask_resolution)
	_target_bytes.resize(mask_resolution * mask_resolution)
	_from_bytes.fill(0)
	_target_bytes.fill(0)
	_from_image = Image.create_from_data(mask_resolution, mask_resolution, false, Image.FORMAT_R8, _from_bytes)
	_target_image = Image.create_from_data(mask_resolution, mask_resolution, false, Image.FORMAT_R8, _target_bytes)
	_from_image.generate_mipmaps()
	_target_image.generate_mipmaps()
	_from_texture = ImageTexture.create_from_image(_from_image)
	_target_texture = ImageTexture.create_from_image(_target_image)
	_material.set_shader_parameter("cover_from", _from_texture)
	_material.set_shader_parameter("cover_target", _target_texture)
	_profile_ready = false


func _sync_parameters() -> void:
	if _material == null or not _has_observer():
		return
	_fade_width = VISIBILITY_STATE.observer_fade_width(_observer)
	_overlay.global_position = _camera.global_position
	_overlay.layers = _camera.cull_mask
	_material.set_shader_parameter("observer_position", _observer.global_position)
	_material.set_shader_parameter("vision_radius", maxf(0.01, _radius))
	_material.set_shader_parameter("vision_fade_width", clampf(_fade_width, 0.0, _radius))
	_material.set_shader_parameter("fog_darkness", clampf(darkness, 0.0, 1.0))
	_material.set_shader_parameter("fog_color", fog_color)
	_material.set_shader_parameter("mask_world_size", _allocated_world_size)
	_material.set_shader_parameter("filter_lod", _filter_lod())
	_material.set_shader_parameter("edge_irregularity", maxf(0.0, edge_irregularity))
	_material.set_shader_parameter("profile_blend", _profile_blend())


func _filter_lod() -> float:
	return clampf(log(maxf(1.0, cover_softness / maxf(0.01, _cell_size))) / log(2.0), 0.0, 4.0)


func _profile_blend() -> float:
	return 1.0 if cover_transition_duration <= 0.0 else clampf(_transition_clock / cover_transition_duration, 0.0, 1.0)


func _update_cover_profile(snap_profile: bool) -> void:
	var world := get_world_3d()
	if world == null:
		return
	var start_usec := Time.get_ticks_usec()
	ray_count = clampi(ray_count, 64, 1024)
	_ray_distances.resize(ray_count)
	var origin := _observer.global_position + Vector3.UP * eye_height
	var query := PhysicsRayQueryParameters3D.create(origin, origin)
	query.collision_mask = 1
	query.collide_with_areas = false
	query.collide_with_bodies = true
	if _observer is CollisionObject3D:
		query.exclude = [(_observer as CollisionObject3D).get_rid()]
	for index in range(ray_count):
		var angle := ((float(index) + 0.5) / float(ray_count) - 0.5) * TAU
		query.to = origin + Vector3(cos(angle), 0.0, sin(angle)) * maxf(0.01, _radius)
		var hit := world.direct_space_state.intersect_ray(query)
		_ray_distances[index] = INF
		if not hit.is_empty():
			var hit_position: Vector3 = hit.position
			_ray_distances[index] = Vector2(hit_position.x - origin.x, hit_position.z - origin.z).length()
	var blend := _profile_blend()
	if not snap_profile:
		for index in range(_from_bytes.size()):
			_from_bytes[index] = roundi(lerpf(float(_from_bytes[index]), float(_target_bytes[index]), blend))
	_target_bytes.fill(0)
	var padding := maxf(4.0, cover_softness * 3.0)
	var limit := _radius + padding
	var limit_squared := limit * limit
	var half_size := _allocated_world_size * 0.5
	var low_x := clampi(floori((origin.x - limit + half_size) / _cell_size), 0, mask_resolution - 1)
	var high_x := clampi(ceili((origin.x + limit + half_size) / _cell_size), 0, mask_resolution - 1)
	var low_z := clampi(floori((origin.z - limit + half_size) / _cell_size), 0, mask_resolution - 1)
	var high_z := clampi(ceili((origin.z + limit + half_size) / _cell_size), 0, mask_resolution - 1)
	# Rasterize only the neighbourhood of this observer. Physics cost remains
	# ray_count, independent of grid resolution; filtering runs in native code.
	for z in range(low_z, high_z + 1):
		var offset_z := _cell_centres[z] - origin.z
		var row := z * mask_resolution
		for x in range(low_x, high_x + 1):
			var offset_x := _cell_centres[x] - origin.x
			var squared := offset_x * offset_x + offset_z * offset_z
			if squared > limit_squared:
				continue
			var ray := posmod(floori((atan2(offset_z, offset_x) / TAU + 0.5) * float(ray_count)), ray_count)
			var distance := sqrt(squared)
			var blocked_at := _ray_distances[ray]
			var weight := 1.0
			if is_finite(blocked_at):
				# Keep the observed surface of a wall lit before its shadow rolls off.
				weight = 1.0 - smoothstep(blocked_at + 0.3, blocked_at + 1.0, distance)
			_target_bytes[row + x] = roundi(weight * 255.0)
	if snap_profile:
		_from_bytes = _target_bytes.duplicate()
	_from_image.set_data(mask_resolution, mask_resolution, false, Image.FORMAT_R8, _from_bytes)
	_target_image.set_data(mask_resolution, mask_resolution, false, Image.FORMAT_R8, _target_bytes)
	# Mip levels provide a stable two-dimensional penumbra with two GPU samples,
	# rather than a large blur loop or per-cell physics queries.
	_from_image.generate_mipmaps()
	_target_image.generate_mipmaps()
	_from_texture.update(_from_image)
	_target_texture.update(_target_image)
	_transition_clock = 0.0
	_profile_ready = true
	_profile_updates += 1
	_last_profile_position = _observer.global_position
	_last_update_ms = float(Time.get_ticks_usec() - start_usec) / 1000.0
	_sync_parameters()
	_overlay.visible = _enabled


func _sample_filtered(source: Image, uv: Vector2, lod: float) -> float:
	if uv.x < 0.0 or uv.y < 0.0 or uv.x > 1.0 or uv.y > 1.0:
		return 0.0
	var low := floori(lod)
	return lerpf(_sample_mip(source, uv, low), _sample_mip(source, uv, low + 1), lod - float(low))


func _sample_mip(source: Image, uv: Vector2, level: int) -> float:
	level = mini(level, source.get_mipmap_count())
	var dimension := maxi(1, _allocated_resolution >> level)
	var bytes := source.get_data()
	var start := source.get_mipmap_offset(level)
	var coordinate := uv * float(dimension) - Vector2.ONE * 0.5
	var left := floori(coordinate.x)
	var top := floori(coordinate.y)
	var fraction := coordinate - Vector2(float(left), float(top))
	var a := float(bytes[start + clampi(top, 0, dimension - 1) * dimension + clampi(left, 0, dimension - 1)]) / 255.0
	var b := float(bytes[start + clampi(top, 0, dimension - 1) * dimension + clampi(left + 1, 0, dimension - 1)]) / 255.0
	var c := float(bytes[start + clampi(top + 1, 0, dimension - 1) * dimension + clampi(left, 0, dimension - 1)]) / 255.0
	var d := float(bytes[start + clampi(top + 1, 0, dimension - 1) * dimension + clampi(left + 1, 0, dimension - 1)]) / 255.0
	return lerpf(lerpf(a, b, fraction.x), lerpf(c, d, fraction.x), fraction.y)
