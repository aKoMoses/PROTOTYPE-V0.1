extends Node3D

## Local, passive prediction. Never emits a shot or changes the aim direction.
var endpoint := Vector3.ZERO
var origin := Vector3.ZERO
var has_contact := false
var _geometry := ImmediateMesh.new()
var _marker_geometry := ImmediateMesh.new()
var _active_geometry: ImmediateMesh
var _material := StandardMaterial3D.new()
var _visual: MeshInstance3D
var _cast: ShapeCast3D
var _overlap := PhysicsShapeQueryParameters3D.new()


func _ready() -> void:
	top_level = true
	global_transform = Transform3D.IDENTITY
	# Draw after the animation/skeleton pass has refreshed muzzle attachments.
	process_priority = 100
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_material.vertex_color_use_as_albedo = true
	_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_visual = MeshInstance3D.new()
	_visual.mesh = _geometry
	_visual.material_override = _material
	_visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_visual)
	var marker := MeshInstance3D.new()
	marker.mesh = _marker_geometry
	var marker_material := _material.duplicate() as StandardMaterial3D
	# This is a reticle at the already clipped contact, not a world surface.
	# Keep its full circle legible at oblique walls and narrow cover edges.
	marker_material.no_depth_test = true
	marker.material_override = marker_material
	marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(marker)
	_cast = ShapeCast3D.new()
	_cast.enabled = false
	_cast.collide_with_areas = true
	_cast.collide_with_bodies = true
	_cast.margin = 0.00001
	_cast.max_results = 8
	_cast.shape = SphereShape3D.new()
	add_child(_cast)
	_overlap.shape = _cast.shape
	_overlap.collide_with_areas = true
	_overlap.collide_with_bodies = true
	_overlap.margin = _cast.margin
	hide()


func _process(_delta: float) -> void:
	refresh()


func refresh() -> void:
	var actor := get_parent() as Node3D
	var camera := get_viewport().get_camera_3d()
	if actor == null or camera == null or not actor.is_visible_in_tree() or not actor.has_method("get_weapon_aim_preview"):
		hide()
		return
	var preview: Dictionary = actor.call("get_weapon_aim_preview")
	if preview.is_empty():
		hide()
		return
	var excluded: Array[RID] = []
	excluded.assign(preview["exclude"])
	origin = preview["origin"]
	var direction: Vector3 = preview["direction"]
	var maximum: float = preview["range"]
	var hit: Dictionary = {}
	# Ignore concealed actors in the prediction so the guide cannot locate them.
	# Visible surfaces still stop it, including enemy energy walls.
	for _attempt in range(16):
		hit = _contact(origin, direction * maximum, preview, excluded)
		if float(preview["radius"]) > 0.0:
			var support: Vector3 = preview["support"]
			var guard := _contact(support, origin - support, preview, excluded)
			if not guard.is_empty():
				hit = guard
		if hit.is_empty():
			break
		var collider := hit.get("collider") as Node
		var target := collider
		while target != null and not target.has_method("is_visible_to"):
			target = target.get_parent()
		if target == null or bool(target.call("is_visible_to", actor)):
			break
		if collider is CollisionObject3D:
			excluded.append(collider.get_rid())
			hit = {}
		else:
			break
	has_contact = not hit.is_empty()
	endpoint = hit["position"] if has_contact else origin + direction * maximum
	var color := Color("#73e6f5") if preview["weapon"] == "blaster" else Color("#ffd686")
	if has_contact:
		color = Color("#ffb577")
	_draw_guide(camera, color)
	show()


func _contact(start: Vector3, motion: Vector3, preview: Dictionary, excluded: Array[RID]) -> Dictionary:
	var space := get_world_3d().direct_space_state
	if float(preview["radius"]) <= 0.0:
		var ray := PhysicsRayQueryParameters3D.create(start, start + motion, int(preview["mask"]), excluded)
		ray.collide_with_areas = true
		ray.hit_from_inside = true
		return space.intersect_ray(ray)
	(_cast.shape as SphereShape3D).radius = float(preview["radius"])
	_overlap.transform = Transform3D(Basis.IDENTITY, start)
	_overlap.collision_mask = int(preview["mask"])
	_overlap.exclude = excluded
	var overlaps := space.intersect_shape(_overlap, 8)
	if not overlaps.is_empty():
		return {"position": start, "collider": overlaps[0]["collider"]}
	_cast.global_transform = Transform3D(Basis.IDENTITY, start)
	_cast.target_position = motion
	_cast.collision_mask = int(preview["mask"])
	_cast.clear_exceptions()
	for rid in excluded:
		_cast.add_exception_rid(rid)
	_cast.force_shapecast_update()
	var nearest := -1
	var distance := INF
	for index in range(_cast.get_collision_count()):
		var candidate := start.distance_squared_to(_cast.get_collision_point(index))
		if candidate < distance:
			distance = candidate
			nearest = index
	if nearest < 0:
		return {}
	return {"position": _cast.get_collision_point(nearest), "collider": _cast.get_collider(nearest)}


func _draw_guide(camera: Camera3D, color: Color) -> void:
	_geometry.clear_surfaces()
	_geometry.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	_active_geometry = _geometry
	var right := camera.global_basis.x.normalized()
	var up := camera.global_basis.y.normalized()
	var toward_camera := camera.global_basis.z.normalized()
	var path := endpoint - origin
	var length := path.length()
	if length > 0.001:
		var direction := path / length
		var side := direction.cross(toward_camera).normalized() * 0.022
		# Short dashes distinguish this guide from live projectiles and tracers.
		var distance := 0.0
		while distance < length:
			var finish := minf(length, distance + 0.32)
			var tint := Color(color, lerpf(0.50, 0.28, distance / maxf(length, 0.001)))
			_quad(origin + direction * distance, origin + direction * finish, side, tint)
			distance += 0.52
	_geometry.surface_end()
	_marker_geometry.clear_surfaces()
	_marker_geometry.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	_active_geometry = _marker_geometry
	# Offset only the marker slightly toward the camera to avoid surface z-fighting.
	var center := endpoint + toward_camera * 0.04
	var radius := 0.20 if has_contact else 0.17
	for index in range(24):
		var a := TAU * float(index) / 24.0
		var b := TAU * float(index + 1) / 24.0
		var radial_a := right * cos(a) + up * sin(a)
		var radial_b := right * cos(b) + up * sin(b)
		_triangle(center + radial_a * (radius - 0.014), center + radial_a * (radius + 0.014), center + radial_b * (radius + 0.014), Color(color, 0.9))
		_triangle(center + radial_a * (radius - 0.014), center + radial_b * (radius + 0.014), center + radial_b * (radius - 0.014), Color(color, 0.9))
	_quad(center - right * 0.06, center + right * 0.06, up * 0.01, Color(color, 0.95))
	_quad(center - up * 0.06, center + up * 0.06, right * 0.01, Color(color, 0.95))
	_marker_geometry.surface_end()


func _quad(start: Vector3, finish: Vector3, side: Vector3, color: Color) -> void:
	_triangle(start - side, start + side, finish + side, color)
	_triangle(start - side, finish + side, finish - side, color)


func _triangle(a: Vector3, b: Vector3, c: Vector3, color: Color) -> void:
	_active_geometry.surface_set_color(color)
	_active_geometry.surface_add_vertex(a)
	_active_geometry.surface_add_vertex(b)
	_active_geometry.surface_add_vertex(c)
