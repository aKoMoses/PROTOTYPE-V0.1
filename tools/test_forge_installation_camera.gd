extends SceneTree

## Sample the real installation path against the actual workshop walls.
const GARAGE := preload("res://scripts/forge_garage.gd")
const LOADOUT := preload("res://scripts/loadout_state.gd")
const MODULES := preload("res://scripts/robot_module_visuals.gd")
const STEP := 1.0 / 30.0
var garage
const SCENERY_MASK := 1 << 19
var failures: Array[String] = []
var checks := 0
var cycles := 0


func _initialize() -> void:
	_run.call_deferred()


func _setup() -> void:
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.content_scale_size = Vector2i.ZERO
	root.size = Vector2i(1280, 720)
	garage = GARAGE.new()
	var suffix := str(Time.get_ticks_usec())
	garage.library_path = "user://installation-camera-" + suffix + "-builds.cfg"
	garage.legacy_save_path = "user://installation-camera-" + suffix + "-loadout.cfg"
	root.add_child(garage)
	await process_frame
	_pause()
	# The imported workshop is a merged mesh: use its triangles, including walls,
	# the workbench and columns, rather than duplicating assumed wall coordinates.
	for label in ["WorkshopStaticMesh", "WorkshopRightWall"]:
		var mesh := garage.stage.world.find_child(label, true, false) as MeshInstance3D
		_check(mesh != null, "actual workshop geometry exists: " + label)
		if mesh != null:
			var body := StaticBody3D.new()
			body.collision_layer = SCENERY_MASK
			body.collision_mask = 0
			var collision := CollisionShape3D.new()
			collision.shape = mesh.mesh.create_trimesh_shape()
			body.add_child(collision)
			garage.stage.world.add_child(body)
			body.global_transform = mesh.global_transform
	await physics_frame
	await physics_frame


func _pause() -> void:
	garage.stage.set_process(false)
	garage.stage.automatic_service_enabled = false
	garage.focus.set_process(false)
	garage.installation.set_process(false)
	garage.module_installation.set_process(false)


func _run() -> void:
	await _setup()
	var catalogs := {"weapon": LOADOUT.WEAPONS, "offensive": LOADOUT.OFFENSIVE,
		"defensive": LOADOUT.DEFENSIVE, "mobility": LOADOUT.MOBILITY, "passive": LOADOUT.PASSIVES}
	for dimensions in [Vector2i(1280, 720), Vector2i(960, 540), Vector2i(2340, 1080)]:
		root.size = dimensions
		await process_frame
		await process_frame
		_pause()
		for chassis in LOADOUT.ROBOTS:
			for category in catalogs:
				for identifier in catalogs[category]:
					if category != "weapon" and not MODULES.has_model(identifier):
						continue
					_start(category, identifier, chassis, catalogs[category])
					var label := "%s %s %s" % [dimensions, chassis, identifier]
					_check(garage.module_installation.active, "installation starts: " + label)
					_check(garage.stage.chassis_id == chassis, "requested chassis is active: " + label)
					var blocked: Dictionary = {}
					var outside: Dictionary = {}
					var largest_step := 0.0
					var previous: Vector3 = garage.stage.camera.global_position
					for frame in 240:
						garage.module_installation.advance(STEP)
						var installer = garage.module_installation
						if not installer.active:
							break
						var camera: Camera3D = garage.stage.camera
						largest_step = maxf(largest_step, previous.distance_to(camera.global_position))
						previous = camera.global_position
						var subject := _subject()
						# The pan can look past furniture before it reaches the bay.
						# Check near-plane clearance then, and actual subject visibility
						# for established shots and every frame of payload tracking.
						var probe := subject
						if installer.phase in ["approach", "return"] and installer._phase_elapsed < 0.72:
							probe = camera.global_position - camera.global_basis.z * 0.30
						var ray := PhysicsRayQueryParameters3D.create(camera.global_position, probe, SCENERY_MASK)
						ray.hit_back_faces = true
						var hit: Dictionary = garage.stage.world.get_world_3d().direct_space_state.intersect_ray(ray)
						if not hit.is_empty() and (hit.position as Vector3).distance_to(probe) > 0.08:
							blocked[installer.phase] = {"time": installer._phase_elapsed, "camera": camera.global_position, "hit": hit.position, "subject": subject}
						if installer.phase in ["pickup", "lift", "carry", "align", "work", "release"] and installer._phase_elapsed > 0.20:
							var screen := camera.unproject_position(subject)
							if camera.is_position_behind(subject) or not Rect2(Vector2.ZERO, Vector2(garage.stage.viewport.size)).has_point(screen):
								outside[installer.phase] = screen
					_check(blocked.is_empty(), "walls never obstruct installation: " + label + " " + str(blocked))
					_check(outside.is_empty(), "equipment stays on screen: " + label + " " + str(outside))
					_check(largest_step < 1.25, "camera travels continuously: " + label + " step=" + str(largest_step))
					_check(not garage.module_installation.active and garage.loadout[category] == identifier, "installation completes: " + label)
					cycles += 1
					_pause()
		print("CAMERA RESOLUTION ", dimensions, " cycles=", cycles, " failures=", failures.size())
	garage.queue_free()
	for frame in 4:
		await process_frame
	for failure in failures.slice(0, 18):
		push_error(failure)
	print("FORGE INSTALLATION CAMERA: ", "PASS" if failures.is_empty() else "FAIL", " (", cycles, " installations; ", checks, " checks; ", failures.size(), " failures)")
	quit(0 if failures.is_empty() else 1)


func _start(category: String, identifier: String, chassis: String, catalog: Array) -> void:
	var baseline: Dictionary = garage.loadout.duplicate(true)
	baseline.robot = chassis
	baseline[category] = catalog[1] if identifier == catalog[0] else catalog[0]
	garage.set_loadout(baseline)
	garage._open_station(category)
	garage.focus.advance(1.1)
	garage._select_equipment(category, identifier)
	_pause()


func _subject() -> Vector3:
	var installer = garage.module_installation
	if installer.phase in ["lift", "carry"]:
		return garage.stage.arm.contact.global_position
	if installer.phase in ["align", "work", "release"]:
		return installer._mount_pose.origin
	if installer.phase == "return":
		return installer._provider().anchor(installer.category)
	return installer._source.origin


func _check(valid: bool, message: String) -> void:
	checks += 1
	if not valid:
		failures.append(message)
