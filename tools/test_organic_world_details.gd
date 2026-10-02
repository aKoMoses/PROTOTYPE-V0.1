extends SceneTree
## Tests actual maps, contacts, occlusion, concealment, terrain and lifecycle.
var failures: Array[String] = []
var checks := 0
var scene: Node3D
var player: Node3D
var manager: Node
var director: Node

func _initialize() -> void:
	call_deferred("_run")

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures.append(message)
		push_error(message)

func frames(count: int = 3) -> void:
	for index in count:
		await physics_frame
		await process_frame

func _run() -> void:
	await _duel()
	await _mode("training_ground")
	await _mode("survival")
	root.get_node("GameSfx").call("clear")
	await create_timer(0.3).timeout
	print("ORGANIC WORLD: %s (%d checks, %d failures)" % ["PASS" if failures.is_empty() else "FAIL", checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func load_map(mode: String) -> void:
	scene = load("res://scenes/" + mode + ".tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	await frames(6)
	player = scene.get("player")
	manager = scene.get_node("VFXManager")
	director = scene.get_node_or_null("OrganicWorldDetails")
	check(director != null, mode + " installs one organic director")
	check(director.get_child_count() == 5, mode + " uses five fixed batched meshes")

func cleanup() -> void:
	manager.call("clear")
	scene.queue_free()
	current_scene = null
	await frames(3)

func _duel() -> void:
	await load_map("main")
	var flow: Node = scene.get("game_flow")
	scene.call("set_menu_showcase_enabled", false)
	flow.call("_start_duel")
	flow.call("_begin_live_round")
	flow.set_process(false)
	scene.set_process(false)
	player.set_physics_process(false)
	player.global_position = Vector3(0, 0, 3)
	player.call("set_gameplay_enabled", true)
	var target: Node3D = scene.get("target")
	target.call("set_training_bot_enabled", false)
	target.set_physics_process(false)
	target.set_process(false)
	target.global_position = Vector3(4, 0, 3)
	scene.get_node("CameraRig").call("set_target", player)
	scene.get_node("CameraRig").call("set_follow_offset", Vector3.ZERO, true)
	await frames(35)
	director.call("_scan")
	check(director.get("_props").size() > 0, "real authored grass and cloth discovered")
	check(bool(director.call("_is_active")), "live round activates scenery responses")
	var health := float(player.call("get_health"))
	var position := player.global_position
	manager.call("impact", Vector3(0, 0.5, 1), Vector3.BACK, "concrete", 1.0)
	seed(54321)
	var expected := randf()
	seed(54321)
	director.call("_contact", Vector3(0, 0.5, 1), Vector3.BACK, "concrete", 1.0)
	check(is_equal_approx(randf(), expected), "presentation does not consume combat random state")
	check(int(director.call("get_debug_counts").bits) > 0, "production contact creates ballistic chips")
	check(player.global_position == position and is_equal_approx(float(player.call("get_health")), health), "scenery leaves actor position and health intact")
	var bit: Dictionary = director.get("_bits")[0]
	var initial := float(bit.velocity.y)
	director.call("_update_bits", 0.05)
	check(float(bit.velocity.y) < initial, "chips obey gravity after contact")
	# A real, locally visible tuft exercises the rendered shader override.
	var grass := load("res://scripts/bush_visual.gd").new() as Node3D
	grass.name = "OrganicTestGrass"
	grass.call("setup", 1.28, 2.35, 1001)
	scene.add_child(grass)
	grass.global_position = Vector3(0, 0.02, 1)
	director.call("_scan")
	var foliage := grass.get_node("LayeredHighGrass") as MeshInstance3D
	director.call("disturb_at", grass.global_position + Vector3.UP * 0.6, Vector3.RIGHT, 1.0)
	await frames(2)
	check(float(foliage.material_override.get_shader_parameter("organic_impulse_strength")) > 0.0, "impacts drive the rendered grass spring")
	var replacement := foliage.material_override.duplicate() as ShaderMaterial
	foliage.material_override = replacement
	player.global_position = grass.global_position
	await frames(5)
	check(float(replacement.get_shader_parameter("local_actor_influence")) > 0.0, "player parts the actual material after another director duplicates it")
	player.global_position += Vector3.BACK * 3.0
	await frames(5)
	var after_exit := float(foliage.material_override.get_shader_parameter("local_actor_influence"))
	check(after_exit > 0.0 and after_exit < 1.0, "grass returns progressively after exit")
	await frames(35)
	check(is_zero_approx(float(foliage.material_override.get_shader_parameter("local_actor_influence"))), "grass eventually returns to rest")
	# Actual traversal, then a teleport, must leave appropriate ground traces.
	director.call("clear")
	player.global_position = Vector3(0, 0, 3)
	await frames(3)
	for index in 18:
		player.global_position.x += 0.08
		await frames(1)
	check(int(director.call("get_debug_counts").stamps) > 0, "walking leaves alternating ground contacts")
	director.call("clear")
	await frames(2)
	player.global_position += Vector3.RIGHT * 8.0
	await frames(2)
	check(int(director.call("get_debug_counts").stamps) == 0, "teleport cannot paint a false walking trail")
	player.global_position = Vector3(0, 0, 3)
	await frames(3)
	var socket := Node3D.new()
	player.add_child(socket)
	socket.position = Vector3(0, 1, 0)
	director.call("clear")
	manager.call("muzzle", socket, "shotgun", 0.0)
	check(director.get("_bits").any(func(entry: Dictionary) -> bool: return entry.kind == "shell"), "shotgun ejects one physical shell")
	director.call("clear")
	manager.call("muzzle", socket, "blaster", 0.0)
	check(not director.get("_bits").any(func(entry: Dictionary) -> bool: return entry.kind == "shell"), "energy blaster does not eject shotgun shells")
	# A wall must hide both contact and secondary foliage response.
	var wall := StaticBody3D.new()
	wall.position = Vector3(0, 1.5, 0)
	wall.collision_layer = 1
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(12, 3, 0.6)
	shape.shape = box
	wall.add_child(shape)
	scene.add_child(wall)
	await frames(3)
	director.call("clear")
	var rejects := int(director.call("get_debug_counts").rejected)
	manager.call("impact", Vector3(0, 1, -2), Vector3.BACK, "metal", 1.0)
	check(int(director.call("get_debug_counts").bits) == 0 and int(director.call("get_debug_counts").rejected) > rejects, "wall blocks invisible secondary impact clues")
	target.global_position = Vector3(0, 0, -2)
	await frames(3)
	check(not bool(director.call("_admitted", target)), "opponent behind wall cannot produce footprints")
	var enemy_socket := Node3D.new()
	target.add_child(enemy_socket)
	enemy_socket.position.y = 1
	manager.call("muzzle", enemy_socket, "shotgun", 0.0)
	check(int(director.call("get_debug_counts").bits) == 0, "hidden opponent cannot eject visible secondary shells")
	wall.queue_free()
	await frames(3)
	# Concealment is distinct from wall occlusion: never part grass for a hidden bot.
	var bushes := get_nodes_in_group("bush_placeholder")
	var bush: Node3D = bushes.filter(func(node: Node3D) -> bool: return String(node.name) == "BushNorthCenter")[0]
	target.global_position = bush.get_meta("bush_center")
	await frames(4)
	check(not bool(director.call("_admitted", target)), "high grass concealment suppresses opponent movement clues")
	director.call("clear")
	manager.call("muzzle", enemy_socket, "shotgun", 0.0)
	check(int(director.call("get_debug_counts").bits) == 0, "concealed opponent cannot disturb grass by secondary shot effects")
	target.global_position = Vector3(4, 0, 3)
	# The production rocket factory is observed after its real world placement.
	director.call("clear")
	load("res://scripts/rocket_visual.gd").spawn_burst(scene, Vector3(0, 0.4, 1), Vector3.FORWARD)
	await frames(2)
	check(int(director.call("get_debug_counts").bits) > 0, "rocket explosion throws secondary floor debris")
	var clock := float(director.get("_clock"))
	paused = true
	for index in 8:
		await process_frame
	check(is_equal_approx(float(director.get("_clock")), clock), "pause freezes organic simulation")
	paused = false
	# Stress both budgets with hundreds of impulses, then verify complete cleanup.
	for quality in [1, 0]:
		manager.set("quality", quality)
		for index in 120:
			director.call("_add_bit", "chip", Vector3(0, 1, 1), Vector3.UP, Vector3.ZERO, Color.GRAY, 0.08, 1.0)
			director.call("_add_stamp", Vector3.ZERO, Vector3.FORWARD, Vector3.UP, true)
		await frames(2)
		var counts: Dictionary = director.call("get_debug_counts")
		check(int(counts.bits) <= (72 if quality == 1 else 28), "debris bounded at quality %d" % quality)
		check(int(counts.stamps) <= (48 if quality == 1 else 20), "traces bounded at quality %d" % quality)
		check(int(counts.ground_queries) <= (12 if quality == 1 else 4) and int(counts.collision_queries) <= (16 if quality == 1 else 4), "physics query budget bounded at quality %d" % quality)
		check(quality == 1 or int(counts.motes) == 0, "low setting disables ambient motes")
	manager.call("clear")
	check(int(director.call("get_debug_counts").bits) == 0 and int(director.call("get_debug_counts").stamps) == 0, "round cleanup removes all debris and traces immediately")
	for batch in director.get("_batches").values():
		check((batch as MultiMesh).visible_instance_count == 0, "cleanup removes batched instances from rendering")
	manager.set("quality", 1)
	# Flat floors are rendered planes; raised floors and ramp normals remain exact.
	flow.call("_select_arena", "test")
	await frames(5)
	director.set("_ground_queries", 0)
	var raised: Dictionary = director.call("_ground", Vector3(3.5, 2.5, 0.6), 1.0)
	check(not raised.is_empty() and absf(float(raised.position.y) - 2.4) < 0.02, "raised platform ground sample matches gameplay height")
	director.set("_ground_queries", 0)
	var ramp: Dictionary = director.call("_ground", Vector3(3.5, 1.5, -5.45), 2.0)
	check(not ramp.is_empty() and absf(float(ramp.position.y) - 1.2) < 0.05 and float(ramp.normal.y) < 0.99, "ramp sample follows its height and sloped normal")
	director.set("_ground_queries", 0)
	var flat: Dictionary = director.call("_ground", Vector3(10, 0.2, 0), 1.0)
	check(not flat.is_empty() and absf(float(flat.position.y)) < 0.05, "test map flat lanes use their active rendered ground")
	director.set("_ground_queries", 0)
	check(director.call("_ground", Vector3(100, 0.2, 100), 1.0).is_empty(), "outside map cannot create imaginary floor traces")
	flow.call("_select_arena", "classic")
	await frames(3)
	director.call("_add_bit", "leaf", Vector3(0, 1, 1), Vector3.UP, Vector3.ZERO, Color.GRAY, 0.1, 1.0)
	player.call("set_gameplay_enabled", false)
	await frames(2)
	check(int(director.call("get_debug_counts").bits) == 0, "opening menu clears world fragments")
	grass.queue_free()
	await cleanup()

func _mode(mode: String) -> void:
	await load_map(mode)
	if mode == "survival":
		scene.call("_choose_weapon", "blaster")
		scene.call("_begin_wave_combat")
	else:
		if bool(scene.get("_menu").get("visible")):
			scene.call("_toggle_menu")
	await frames(8)
	check(bool(director.call("_is_active")), mode + " enables details during actual combat")
	await cleanup()
