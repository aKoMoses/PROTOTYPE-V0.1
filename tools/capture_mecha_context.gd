extends "res://tools/capture_weapon_locomotion.gd"

## Native production-rig screenshots; run with a rendering backend and -- OUTPUT.
func _capture() -> void:
	var arguments := OS.get_cmdline_user_args()
	_output_directory = arguments[0] if not arguments.is_empty() else "res://outputs/mecha-context"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_output_directory))
	root.size = Vector2i(960, 600)
	var stage := Node3D.new()
	root.add_child(stage)
	current_scene = stage
	_configure_stage(stage)
	_camera.global_position = Vector3(-3.8, 2.25, -4.4)
	_camera.look_at(Vector3(0.0, 1.15, 0.0), Vector3.UP)
	_camera.size = 3.65
	_player = load("res://scripts/player.gd").new() as CharacterBody3D
	stage.add_child(_player)
	_player.set_physics_process(false)
	_player.set_process(false)
	_player.set_gameplay_enabled(true)
	_player.get_node("WorldUIAnchor").hide()
	_rig = _player.get_node("VisualRoot") as PlayerVisualRig
	_rig.animation_tree.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	_rig.skeleton.modifier_callback_mode_process = Skeleton3D.MODIFIER_CALLBACK_MODE_PROCESS_MANUAL
	var title := Label.new()
	title.position = Vector2(24, 20)
	title.add_theme_font_size_override("font_size", 25)
	root.add_child(title)
	await _settle(Vector3.ZERO, Vector3.FORWARD, 24)
	title.text = "Repos · portage habituel"
	await _save_frame("01-ready.png")
	_rig.set_presence_context(true, true)
	_rig.presence_modifier.quiet_clip = &"look_around"
	_rig.presence_modifier.quiet_time = 3.8
	await _settle(Vector3.ZERO, Vector3.FORWARD, 1)
	title.text = "Repos · regard autour de soi"
	await _save_frame("02-look-around.png")
	_player._begin_weapon_aim()
	await _settle(Vector3.ZERO, Vector3.FORWARD, 24)
	_rig.presence_modifier.hit_clip = &"hit_to_head"
	_rig.presence_modifier.hit_time = 0.14
	await _settle(Vector3.LEFT, Vector3.FORWARD, 1)
	title.text = "Impact · tête réactive, arme alignée"
	await _save_frame("03-impact-aim.png")
	_player.set_gameplay_enabled(true)
	_rig.set_aim_enabled(false, true)
	var module_views := [
		["javelin", "preparation", 1.0], ["javelin", "active", 0.1],
		["rocket_basket", "preparation", 0.9], ["rocket_basket", "active", 0.1],
		["fulguro_punch", "preparation", 0.9], ["fulguro_punch", "active", 0.3],
		["pelto_smash", "active", 0.1], ["projector", "active", 0.1],
		["magnetic_field", "preparation", 0.9], ["counter", "active", 0.1],
		["static_shield", "active", 0.0], ["bio_injector", "active", 0.1],
		["pyro_boots", "active", 0.5], ["eclipse", "preparation", 0.9],
	]
	_camera.size = 4.0
	for view in module_views:
		_player._blaster_pivot.visible = view[0] != "pelto_smash"
		_rig.clear_fulguro_pose()
		_rig.clear_pelto_pose()
		_rig.set_counter_pose(view[0] == "counter")
		if view[0] == "fulguro_punch":
			_rig.set_fulguro_pose(view[1], view[2])
		if view[0] == "pelto_smash":
			_rig.set_pelto_pose("impact", view[2])
		_rig.set_module_pose(view[0], view[1], view[2], 0.2)
		await _settle(Vector3.ZERO, Vector3.FORWARD, 4)
		title.text = "%s · %s" % [view[0], view[1]]
		await _save_frame("module-%s-%s.png" % [view[0], view[1]])
	_rig.clear_fulguro_pose()
	_rig.clear_pelto_pose()
	_rig.set_counter_pose(false)
	_player._blaster_pivot.show()
	_player.set_gameplay_enabled(false)
	_player.show_round_result(true)
	_camera.size = 4.3
	await _settle(Vector3.ZERO, Vector3.FORWARD, 88)
	title.text = "Fin de manche · victoire"
	await _save_frame("04-victory.png")
	_player.set_gameplay_enabled(false)
	_player.show_round_result(false)
	await _settle(Vector3.ZERO, Vector3.FORWARD, 132)
	title.text = "Fin de manche · déception debout"
	await _save_frame("05-disappointment.png")
	for clip_name in ["greet_04", "laugh_02", "frustrated_01", "frustrated_02"]:
		_player.set_gameplay_enabled(false)
		_rig.play_action(StringName(clip_name))
		await _settle(Vector3.ZERO, Vector3.FORWARD, 110)
		title.text = "Fin de manche · " + clip_name
		await _save_frame("result-" + clip_name + ".png")
	stage.queue_free()
	await process_frame
	var garage := load("res://scripts/forge_garage_stage.gd").new() as Control
	root.add_child(garage)
	current_scene = garage
	garage.size = Vector2(960, 600)
	garage.set_process(false)
	garage.automatic_service_enabled = false
	garage.arm.cancel_service()
	garage.set("_pending_reaction", &"")
	var garage_times := {"greet_02": 3.6, "agree": 2.6, "standing_relax": 4.0,
		"greet_01": 1.4, "greet_03": 5.9, "greet_04": 1.8, "scratch": 4.8,
		"laugh_01": 2.0, "laugh_02": 2.0, "frustrated_02": 3.8}
	for clip_name in garage_times:
		garage.robot_animator.play("context/" + clip_name, 0.0)
		garage.robot_animator.seek(garage_times[clip_name], true)
		garage.robot_animator.advance(0.0)
		for frame in 5: await process_frame
		title.text = "Garage · " + clip_name
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(_output_directory.path_join("garage-" + clip_name + ".png"))
	print("MECHA_CONTEXT_CAPTURE: ", ProjectSettings.globalize_path(_output_directory))
	quit()
