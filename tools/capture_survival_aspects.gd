extends SceneTree

const ASPECTS := preload("res://scripts/survival_aspects.gd")
var output_directory: String

func _initialize() -> void:
	call_deferred("capture")

func save_frame(file_name: String) -> void:
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var error := root.get_texture().get_image().save_png(output_directory.path_join(file_name))
	print("CAPTURE %s: %s" % [file_name, error_string(error)])

func capture() -> void:
	var args := OS.get_cmdline_user_args()
	output_directory = args[0]
	DirAccess.make_dir_recursive_absolute(output_directory)
	var scene: Node3D = load("res://scenes/survival.tscn").instantiate()
	scene.records_path = "res://.godot/capture_aspects_records.json"
	root.add_child(scene)
	current_scene = scene
	await process_frame
	scene._choose_weapon("shotgun")
	scene._begin_wave_combat()
	scene.progression.aspects.weapon = {"path": "breaker", "rank": 2}
	scene.player.configure_survival_build(scene.progression.build())
	scene._spawn_reinforcements()
	for enemy in scene.get_training_targets():
		enemy.take_damage(5000.0, "test", "capture:" + str(enemy.get_instance_id()))
	await process_frame
	await create_timer(0.7, true).timeout
	await save_frame("survival-ultimate-choice.png")
	paused = false
	scene.queue_free()
	await process_frame
	scene = load("res://scenes/survival.tscn").instantiate()
	scene.records_path = "res://.godot/capture_aspects_records.json"
	root.add_child(scene)
	current_scene = scene
	await process_frame
	scene._choose_weapon("shotgun")
	scene._begin_wave_combat()
	var progression: SurvivalProgression = scene.progression
	progression.equipment = {"offensive": "javelin", "defensive": "static_shield", "mobility": "pyro_boots", "passive": "omnivamp"}
	progression.aspects = {"weapon": {"path": "breaker", "rank": 3}, "offensive": {"path": "harpoon", "rank": 3}, "defensive": {"path": "carapace", "rank": 3}, "mobility": {"path": "thruster", "rank": 3}, "passive": {"path": "reserve", "rank": 3}}
	var player: Node3D = scene.player
	player.configure_survival_build(progression.build())
	player.set_touch_aim_vector(Vector2.UP)
	var positions := [Vector3(0, 0, -3), Vector3(2, 0, -4)]
	var targets: Array = scene.get_training_targets()
	for index in range(targets.size()):
		targets[index].set_training_bot_enabled(false)
		targets[index].global_position = positions[index % positions.size()]
		targets[index].combat_state.max_health = 10000.0
		targets[index].reset_combat_state()
	player._perform_static_shield()
	player._perform_javelin()
	await create_timer(0.9, false).timeout
	await save_frame("survival-ultimate-combat.png")
	# Close views use the same equipped model and additions as normal combat.
	var camera: Camera3D = scene.get_node("CameraRig/Camera3D")
	scene.get_node("CameraRig").set_process(false)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 2.9
	camera.global_position = Vector3(-3.5, 2.3, -4.0)
	camera.look_at(Vector3(0.0, 1.05, -0.15), Vector3.UP)
	scene._hud.hide()
	scene._touch.hide()
	player.get_node("WorldUIAnchor").hide()
	player.set_physics_process(false)
	for category in ["weapon", "offensive", "defensive", "mobility", "passive"]:
		for item in ASPECTS.PATHS:
			var item_category: String = "weapon" if item in ["shotgun", "blaster"] else "offensive" if item == "javelin" else "defensive" if item in ["static_shield", "magnetic_field"] else "mobility" if item in ["pyro_boots", "bio_injector"] else "passive"
			if category != item_category:
				continue
			for path in ASPECTS.PATHS[item]:
				for level in [1, 3]:
					var build := {"weapon": "shotgun", "offensive": "", "defensive": "", "mobility": "", "passive": "", "aspects": {category: {"path": path, "rank": level}}, "upgrades": {}, "evolutions": {}}
					build[category] = item
					player.configure_survival_build(build)
					player.set_gameplay_enabled(true)
					player.aim_direction = Vector3.FORWARD
					player._begin_weapon_aim()
					player._visual_rig.update_visual_state(Vector3.ZERO, Vector3.FORWARD, 0.0, 5.0, 1.0, true)
					await create_timer(0.12, false).timeout
					await save_frame("%s-%d.png" % [path, level])
	print("SURVIVAL ASPECT CAPTURES: COMPLETE")
	quit()
