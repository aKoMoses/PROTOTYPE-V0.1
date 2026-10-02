extends SceneTree
var failures: Array[String] = []
var checks := 0
var scene: Node3D
var life: Node3D
var player: Node3D
var manager: Node

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures.append(message)
		push_error(message)

func frames(count: int = 4) -> void:
	for index in count:
		await physics_frame
		await process_frame

func _run() -> void:
	for mode in ["main", "training_ground", "survival"]:
		await _map(mode)
	root.get_node("GameSfx").call("clear")
	await create_timer(0.25).timeout
	check(checks > 80, "production checks completed in every mode")
	print("SCENERY LIFE: %s (%d checks, %d failures)" % ["PASS" if failures.is_empty() else "FAIL", checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func _map(mode: String) -> void:
	scene = load("res://scenes/" + mode + ".tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	await frames(8)
	life = scene.find_child("SceneryLife", true, false) as Node3D
	check(life != null, mode + " installs scenery life in its authored workshop")
	if life == null:
		scene.queue_free()
		await frames()
		return
	check(life.get_child_count() == 7, mode + " uses seven fixed batches")
	var decorative := true
	for node in life.find_children("*", "", true, false):
		decorative = decorative and not node is CollisionObject3D and not node is CollisionShape3D and not node is NavigationRegion3D
	check(decorative, mode + " adds no physical or navigation objects")
	var counts: Dictionary = life.call("get_debug_counts")
	check(counts.stations > 0 and counts.stations <= 16 and counts.loose <= 24 and counts.oil <= 8, mode + " station and object pools are bounded")
	manager = scene.get_node("VFXManager")
	player = scene.get("player")
	if mode == "main":
		var flow: Node = scene.get("game_flow")
		scene.call("set_menu_showcase_enabled", false)
		flow.call("_start_duel")
		flow.call("_begin_live_round")
		flow.set_process(false)
		scene.set_process(false)
		var target: Node3D = scene.get("target")
		target.call("set_training_bot_enabled", false)
		target.set_physics_process(false)
	elif mode == "survival":
		scene.call("_choose_weapon", "blaster")
		scene.call("_begin_wave_combat")
	else:
		if bool(scene.get("_menu").get("visible")):
			scene.call("_toggle_menu")
	player.set_physics_process(false)
	player.call("set_gameplay_enabled", true)
	scene.set_process(false)
	life.set_process(false)
	var loose: Array = life.get("_loose")
	var paper: Dictionary = loose.filter(func(entry: Dictionary) -> bool: return entry.kind == "paper")[0]
	var can: Dictionary = loose.filter(func(entry: Dictionary) -> bool: return entry.kind == "can")[0]
	var circuits: Array = life.get_parent().get("_circuits")
	var sign: Dictionary = circuits.filter(func(entry: Dictionary) -> bool: return entry.neon)[0]
	var camera := scene.get_node("CameraRig") as Node3D
	camera.call("set_target", player)
	camera.call("set_follow_offset", Vector3.ZERO, true)
	var reachable := false
	var organic := scene.get_node("OrganicWorldDetails")
	var hanging: Array = life.get("_hanging")
	var oil: Array = life.get("_oil")
	for candidate in loose.filter(func(entry: Dictionary) -> bool: return entry.kind == "paper"):
		sign = circuits[int(candidate.circuit)]
		player.global_position = candidate.origin + sign.out * 1.2 + sign.axis * 0.72
		await frames(8)
		var paired_can: Dictionary = loose.filter(func(entry: Dictionary) -> bool: return entry.kind == "can" and entry.circuit == candidate.circuit)[0]
		var paired_hanging: Dictionary = hanging.filter(func(entry: Dictionary) -> bool: return entry.circuit == candidate.circuit)[0]
		var paired_oil: Array = oil.filter(func(entry: Dictionary) -> bool: return entry.circuit == candidate.circuit)
		if paired_oil.is_empty():
			continue
		var station_visible := bool(organic.call("_visible", candidate.at + Vector3.UP * 0.15)) and bool(organic.call("_visible", paired_can.at + Vector3.UP * 0.16)) and bool(organic.call("_visible", paired_hanging.anchor)) and bool(organic.call("_visible", paired_oil[0].at + Vector3.UP * 0.04))
		if station_visible:
			paper = candidate
			can = paired_can
			reachable = true
			break
	check(reachable, mode + " contains a locally visible workshop floor station")
	if mode == "survival":
		check(loose.filter(func(entry: Dictionary) -> bool: return entry.circuit < 24).all(func(entry: Dictionary) -> bool: return absf(entry.origin.z) < 22.5), "survival accessories sit in front of the boundary walls")
	life.call("reset_transients")
	var health := float(player.call("get_health"))
	var location := player.global_position
	manager.call("impact", paper.at + Vector3.UP * 0.15, Vector3.RIGHT, "metal", 1.2)
	check((paper.velocity as Vector3).length() > 0.0 and paper.lift > 0.0, mode + " real impact lifts and pushes ground paper")
	check((can.velocity as Vector3).length() > 0.0, mode + " real impact pushes a loose can")
	check(player.global_position == location and float(player.call("get_health")) == health, mode + " effects leave actor position and health unchanged")
	var initial: Vector3 = paper.at
	life.call("_advance_loose", paper, 0.05)
	check((paper.at as Vector3).distance_to(initial) > 0.0 and paper.lift < 1.2, mode + " paper settles while sliding")
	var roll: float = can.roll
	life.call("_advance_loose", can, 0.05)
	check(can.roll > roll, mode + " can rolls according to distance travelled")
	check(hanging.any(func(entry: Dictionary) -> bool: return absf(entry.velocity) > 0.0), mode + " nearby hanging hardware receives the impact")
	check(oil.any(func(entry: Dictionary) -> bool: return entry.pulse >= 0.0 and entry.power > 0.0), mode + " nearby oil film receives a ripple")
	# A production rocket burst is observed only after its actual world placement.
	life.call("reset_transients")
	load("res://scripts/rocket_visual.gd").spawn_burst(scene, paper.origin + Vector3.UP * 0.25, Vector3.UP)
	await frames(2)
	check((paper.velocity as Vector3).length() > 0.0 and paper.lift > 0.0, mode + " rocket blast moves loose scenery")
	# Active collision geometry blocks sliding; no new gameplay body is introduced.
	life.call("reset_transients")
	var wall := StaticBody3D.new()
	wall.collision_layer = 1
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.08, 1.5, 0.8)
	shape.shape = box
	wall.add_child(shape)
	scene.add_child(wall)
	wall.global_position = paper.at + Vector3(0.20, 0.50, 0)
	await frames(3)
	paper.velocity = Vector3.RIGHT * 8.0
	initial = paper.at
	life.set("_queries", 0)
	life.call("_advance_loose", paper, 0.05)
	check(paper.at == initial and paper.velocity.x < 0.0, mode + " scenery bounces off actual obstacles")
	life.call("reset_transients")
	box.size = Vector3(2.5, 3.0, 0.12)
	wall.global_transform = Transform3D(Basis(sign.axis, Vector3.UP, sign.out), (player.global_position + paper.origin) * 0.5 + Vector3.UP)
	await frames(3)
	var rejected: int = life.get("_rejected")
	var hidden_contact: Vector3 = paper.at + Vector3.UP * 0.15
	check(not bool(organic.call("_visible", hidden_contact)), mode + " temporary obstacle actually conceals the contact")
	manager.call("impact", hidden_contact, Vector3.RIGHT, "metal", 1.2)
	check(int(life.get("_rejected")) > rejected and loose.all(func(entry: Dictionary) -> bool: return entry.velocity == Vector3.ZERO), mode + " concealed impact creates no scenery impulse")
	wall.queue_free()
	await frames(3)
	life.call("reset_transients")
	player.global_position = paper.origin + sign.out * 0.45
	await frames(2)
	life.call("_sample_wake", 0.1)
	player.global_position += sign.axis * 0.12
	life.call("_sample_wake", 0.1)
	check((paper.velocity as Vector3).length() > 0.0, mode + " local traversal creates a wake")
	life.call("reset_transients")
	life.call("_sample_wake", 0.1)
	player.global_position += sign.axis * 5.0
	life.call("_sample_wake", 0.1)
	check(loose.all(func(entry: Dictionary) -> bool: return entry.velocity == Vector3.ZERO), mode + " teleport produces no scenery impulse")
	player.global_position = paper.origin + sign.out * 1.2
	await frames(2)
	seed(44129)
	var expected := randf()
	seed(44129)
	life.call("_process", 0.03)
	check(is_equal_approx(randf(), expected), mode + " presentation preserves combat random stream")
	for quality in [1, 0]:
		manager.set("quality", quality)
		life.get_parent().set("_low", quality == 0)
		life.call("_process", 0.05)
		counts = life.call("get_debug_counts")
		check(counts.papers_visible + counts.cans_visible <= (6 if quality == 1 else 3), mode + " ground detail budget at quality %d" % quality)
		check(counts.hanging_visible <= (4 if quality == 1 else 2) and counts.oil_visible <= (4 if quality == 1 else 2), mode + " fixed detail budget at quality %d" % quality)
		check(counts.queries <= (4 if quality == 1 else 2), mode + " collision query budget at quality %d" % quality)
		check(counts.shafts_visible <= (3 if quality == 1 else 0) and counts.motes_visible <= (24 if quality == 1 else 0) and counts.bird_visible <= (1 if quality == 1 else 0), mode + " atmospheric budget at quality %d" % quality)
	manager.set("quality", 1)
	life.get_parent().set("_low", false)
	life.set("_low", false)
	var lamp: Dictionary = circuits.filter(func(entry: Dictionary) -> bool: return not entry.neon)[0]
	for circuit in circuits:
		(circuit.light.get_ref() as OmniLight3D).visible = false
	var light := lamp.light.get_ref() as OmniLight3D
	light.show()
	lamp.average = 1.0
	life.call("_draw_air", light.global_position)
	counts = life.call("get_debug_counts")
	check(counts.shafts_visible == 1 and counts.motes_visible == 8, mode + " active lamp exposes a small volume of dust")
	lamp.average = 0.0
	life.call("_draw_air", light.global_position)
	counts = life.call("get_debug_counts")
	check(counts.shafts_visible == 0 and counts.motes_visible == 0, mode + " lamp extinction hides shaft and suspended dust")
	life.set("_clock", 2.0 + float(life.get("_bird_period")) - float(life.get("_bird_phase")))
	life.call("_draw_bird", player.global_position)
	check(life.call("get_debug_counts").bird_visible == 1, mode + " bird shadow has a bounded passage")
	var bird_batch: MultiMesh = life.get("_batches").bird
	var bird_at := bird_batch.get_instance_transform(0)
	life.call("_draw_bird", player.global_position + Vector3.RIGHT * 4.0)
	check(bird_batch.get_instance_transform(0) == bird_at, mode + " ongoing bird passage stays fixed when the camera follows the player")
	life.set("_clock", 8.0 + float(life.get("_bird_period")) - float(life.get("_bird_phase")))
	life.call("_draw_bird", player.global_position)
	check(life.call("get_debug_counts").bird_visible == 0, mode + " bird shadow leaves between passages")
	life.set_process(true)
	await frames(2)
	var clock: float = life.get("_clock")
	paused = true
	for index in 6:
		await process_frame
	check(float(life.get("_clock")) == clock, mode + " pause freezes all new details")
	paused = false
	var workshop := life.get_parent().get_parent() as Node3D
	workshop.hide()
	await frames(2)
	clock = life.get("_clock")
	manager.call("impact", paper.origin + Vector3.UP * 0.15, Vector3.RIGHT, "metal", 1.2)
	await frames(2)
	check(float(life.get("_clock")) == clock and paper.velocity == Vector3.ZERO, mode + " hidden map freezes and rejects impulses")
	check((life.get("_batches") as Dictionary).values().all(func(batch: MultiMesh) -> bool: return batch.visible_instance_count == 0), mode + " hidden branch clears every batch")
	workshop.show()
	await frames(2)
	check(float(life.get("_clock")) > clock, mode + " map return resumes scenery")
	if mode == "main":
		scene.call("set_arena_variant", "test")
		await frames(8)
		var lives := scene.find_children("SceneryLife", "", true, false)
		check(lives.size() >= 2, "test arena owns independent scenery life")
		var test_life: Node = lives.filter(func(node: Node) -> bool: return node != life)[0]
		check(absf(float(test_life.call("_floor_y", Vector3(3.5, 2.5, 0.6))) - 2.4) < 0.02, "scenery respects raised platforms")
		var basis: Basis = test_life.call("_floor_basis", Vector3(3.5, 1.2, -5.45))
		check(basis.y.y < 0.99 and basis.y.y > 0.5, "ground paper and oil align with ramp normals")
		scene.call("set_arena_variant", "classic")
		await frames(3)
	manager.call("clear")
	check(loose.all(func(entry: Dictionary) -> bool: return entry.at == entry.origin and entry.velocity == Vector3.ZERO and entry.lift == 0.0), mode + " round cleanup returns loose objects to their authored position")
	check((life.get("_batches") as Dictionary).values().all(func(batch: MultiMesh) -> bool: return batch.visible_instance_count == 0), mode + " round cleanup clears GPU instances immediately")
	scene.queue_free()
	current_scene = null
	await frames(4)
