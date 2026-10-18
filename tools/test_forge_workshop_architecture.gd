extends SceneTree

## Probe the imported triangles, rather than assuming a painted window is open.
const GARAGE := preload("res://scripts/forge_garage.gd")
const SCENERY_MASK := 1 << 19
var garage
var failures: Array[String] = []
var checks := 0
var temporary_paths: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	root.size = Vector2i(1280, 720)
	garage = GARAGE.new()
	var suffix := str(Time.get_ticks_usec())
	temporary_paths = ["user://architecture-" + suffix + ".cfg", "user://architecture-legacy-" + suffix + ".cfg"]
	garage.library_path = temporary_paths[0]
	garage.legacy_save_path = temporary_paths[1]
	root.add_child(garage)
	await process_frame
	garage.stage.set_process(false)
	garage.focus.set_process(false)
	var visual := garage.stage.world.find_child("WorkshopStaticMesh", true, false) as MeshInstance3D
	_check(visual != null, "imported workshop exists")
	if visual == null:
		quit(1)
		return
	var body := StaticBody3D.new()
	body.collision_layer = SCENERY_MASK
	body.collision_mask = 0
	var collision := CollisionShape3D.new()
	collision.shape = visual.mesh.create_trimesh_shape()
	body.add_child(collision)
	garage.stage.world.add_child(body)
	body.global_transform = visual.global_transform
	await physics_frame
	await physics_frame
	for x in [-15.0, -10.0, 10.0, 15.0]:
		for y in [3.1, 8.4, 10.5]:
			var hit := _ray(Vector3(x, y, -4.5), Vector3(x, y, -6.5))
			_check(not hit.is_empty() and absf((hit.get("position", Vector3.ZERO) as Vector3).z + 5.32) < 0.08,
				"one continuous exterior wall across the workshop: " + str(Vector2(x, y)))
	for x in [1.65, 2.65, 3.63, 4.61, 5.59]:
		for y in [3.16, 4.38, 5.60]:
			_check(_ray(Vector3(x, y, -5.0), Vector3(x, y, -7.0)).is_empty(),
				"actual window opening crosses the masonry: " + str(Vector2(x, y)))
	var roof := _ray(Vector3(2.5, 10.5, 0), Vector3(2.5, 12.5, 0))
	_check(not roof.is_empty(), "workshop connects to a real roof")
	var glass := visual.find_child("WorkshopWindowGlass", true, false) as MeshInstance3D
	_check(glass != null, "window glass is separate from the opaque structure")
	if glass != null:
		var material := glass.get_active_material(0) as StandardMaterial3D
		_check(material != null and material.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA and material.albedo_color.a < 0.3,
			"glass reveals exterior depth")
		_check(glass.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "daylight crosses glass")
	var exterior := garage.stage.world.find_child("ExteriorSky", true, false) as MeshInstance3D
	_check(exterior != null and exterior.global_position.z < -20.0, "outside backdrop is beyond the window")
	var side := garage.stage.world.find_child("WorkshopRightWall", true, false) as MeshInstance3D
	_check(side != null and side.position.x > 17.0 and side.get_aabb().size.y > 11.0,
		"right wall belongs to the building, beyond the service aisle")
	var shadows := 0
	for node in garage.stage.world.find_children("*", "Light3D", true, false):
		if node.shadow_enabled:
			shadows += 1
	_check(shadows == 3, "three shadow lights retained")
	_check(garage.stage.module_stations.station_nodes.size() == 4 and garage.stage.weapon_rack.items.size() == 4,
		"all physical equipment stations remain available")
	for dimensions in [Vector2i(960, 540), Vector2i(1280, 720), Vector2i(1920, 1080), Vector2i(2340, 1080)]:
		root.size = dimensions
		for frame in 3:
			await process_frame
		garage._show_entry(false)
		garage.stage.set_process(false)
		garage.focus.set_process(false)
		for zoom in [1.0, 1.5]:
			garage.focus._desktop_zoom = zoom
			garage.focus._desktop_zoom_goal = zoom
			garage.focus.advance(0.0)
			var camera: Camera3D = garage.stage.camera
			_check(camera.global_position.y < 11.1 and camera.global_position.z < 39.0,
				"overview camera stays below and inside roof: " + str(dimensions) + " zoom=" + str(zoom))
			# The upper central ray should reach the room, never an exterior sky
			# above the small set when the player pulls the camera back.
			var pixel := Vector2(garage.stage.viewport.size) * Vector2(0.55, 0.10)
			var origin := camera.project_ray_origin(pixel)
			var room_hit := _ray(origin, origin + camera.project_ray_normal(pixel) * 80.0)
			_check(not room_hit.is_empty(), "roof closes upper overview: " + str(dimensions) + " zoom=" + str(zoom))
	garage.queue_free()
	for frame in 3:
		await process_frame
	await create_timer(0.5).timeout
	for temporary_path in temporary_paths:
		if FileAccess.file_exists(temporary_path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(temporary_path))
	for failure in failures:
		push_error(failure)
	print("FORGE WORKSHOP ARCHITECTURE: ", "PASS" if failures.is_empty() else "FAIL", " (", checks, " checks; ", failures.size(), " failures)")
	quit(0 if failures.is_empty() else 1)

func _ray(from: Vector3, to: Vector3) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(from, to, SCENERY_MASK)
	query.hit_back_faces = true
	return garage.stage.world.get_world_3d().direct_space_state.intersect_ray(query)

func _check(valid: bool, message: String) -> void:
	checks += 1
	if not valid:
		failures.append(message)
