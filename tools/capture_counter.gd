extends SceneTree

const COUNTER := preload("res://scripts/counter.gd")
var visual: PlayerVisualRig


func _initialize() -> void:
	call_deferred("run")


func save_capture(file_name: String) -> void:
	for frame in range(3):
		await process_frame
		visual.update_visual_state(Vector3.ZERO, Vector3.RIGHT, 0.0, 5.0, 1.0 / 60.0)
		visual.animation_tree.advance(1.0 / 60.0)
		visual.skeleton.advance(1.0 / 60.0)
		await visual.skeleton.skeleton_updated
		COUNTER.component(visual.get_parent())._sync_energy_position()
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://captures/counter"))
	root.get_texture().get_image().save_png("res://captures/counter/" + file_name + ".png")


func run() -> void:
	var scene := load("res://scenes/main.tscn").instantiate() as Node3D
	root.add_child(scene)
	current_scene = scene
	await process_frame
	var flow := scene.get_node("Interface")
	var loadout: Dictionary = flow.get("loadout").duplicate()
	loadout.defensive = "counter"
	loadout.weapon = "blaster"
	flow.set("loadout", loadout)
	flow.call("_start_duel")
	flow.call("_begin_live_round")
	var player := scene.get_node("Player") as Node3D
	var target := scene.get_node("TargetDummy") as Node3D
	player.set_physics_process(false)
	target.call("set_training_bot_enabled", false)
	player.position = Vector3(-1.8, 0, 17)
	target.position = Vector3(1.8, 0, 17)
	player.call("_set_aim_direction", Vector3.RIGHT)
	visual = player.get("_visual_rig")
	visual.animation_tree.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	visual.skeleton.modifier_callback_mode_process = Skeleton3D.MODIFIER_CALLBACK_MODE_PROCESS_MANUAL
	visual.set_aim_enabled(true, true)
	var rig := scene.get_node("CameraRig")
	rig.set_process(false)
	rig.set_physics_process(false)
	var camera := scene.get_node("CameraRig/Camera3D") as Camera3D
	camera.global_position = Vector3(0, 9, 28)
	camera.look_at(Vector3(0, 0.8, 17), Vector3.UP)
	await create_timer(0.6).timeout
	player.call("_perform_counter")
	var guard := COUNTER.component(player)
	guard.update(0.08)
	guard.update(0.16)
	await save_capture("guard")
	# Check readability at the normal combat camera, including the short window.
	var close_view := camera.global_transform
	camera.position = Vector3(0.0, 20.5, 17.5)
	rig.global_position = player.global_position + Vector3.RIGHT * 1.6
	camera.look_at(rig.global_position + Vector3.UP * 0.45, Vector3.UP)
	await save_capture("guard-gameplay")
	camera.global_transform = close_view
	guard.intercept({"id": "capture", "counter_trigger": true})
	await create_timer(0.07).timeout
	await save_capture("intercept")
	guard.update(0.45)
	await save_capture("surcharge")
	var attack: Dictionary = player.call("emit_passive_weapon")
	COUNTER.impact(target, 20, "player", "capture_boost", attack.counter_attack, target.global_position + Vector3.UP * 0.85)
	await create_timer(0.05).timeout
	await save_capture("explosion")
	print("COUNTER CAPTURE: PASS")
	quit(0)
