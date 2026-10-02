extends SceneTree

const LOADOUT := preload("res://scripts/loadout_state.gd")
const FLOW := preload("res://scripts/game_flow.gd")
var failures: Array[String] = []
var checks := 0
var capture := false

func _initialize() -> void:
	_run.call_deferred()

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)

func _run() -> void:
	capture = OS.get_cmdline_user_args().has("--capture") and DisplayServer.get_name() != "headless"
	if capture:
		root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
		root.content_scale_size = Vector2i.ZERO
		root.size = Vector2i(1280, 720)
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://captures/tutorial"))
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	current_scene = main
	await process_frame
	var flow: Node = main.game_flow
	var entry: Control = flow._menu_panel.find_child("TestTutorialButton", true, false)
	check(entry != null and (entry.get_child(1) as Button).text == "Test Tutoriel", "home has the requested button")
	await shot("01-home")
	var saved_build := FileAccess.get_file_as_bytes(LOADOUT.SAVE_PATH)
	(entry.get_child(1) as Button).pressed.emit()
	await process_frame
	await process_frame
	var tutorial: Node = current_scene
	check(tutorial.name == "BeginnerTutorial", "home button launches the beginner scene")
	check(FileAccess.get_file_as_bytes(LOADOUT.SAVE_PATH) == saved_build, "tutorial bootstrap preserves the saved build")
	check(tutorial.player.training_invulnerable and not tutorial.player.training_instant_cooldowns, "safe session with actual cooldowns")
	check(tutorial._next_button.disabled, "cannot skip incomplete lesson")
	tutorial._next_lesson()
	check(tutorial.lesson == 0, "next ignores premature calls")
	await shot("02-movement")
	tutorial.player.global_position = tutorial.DESTINATION
	await wait_seconds(0.05)
	check(tutorial.lesson_completed, "movement validates arrival at the world marker")
	tutorial._next_lesson()
	check(tutorial.lesson == 1 and not tutorial.lesson_completed, "next prepares a fresh exercise")
	tutorial.player.set_physics_process(false)
	tutorial.player._set_aim_direction(Vector3.FORWARD)
	tutorial.player._fire_blaster_projectile(tutorial.player._blaster_damage, 0.0, Vector3.FORWARD)
	await wait_seconds(0.5)
	check(tutorial._hits == 1 and not tutorial.lesson_completed, "one real blaster impact does not finish two-hit lesson")
	tutorial.player._fire_blaster_projectile(tutorial.player._blaster_damage, 0.0, Vector3.FORWARD)
	await wait_seconds(0.5)
	check(tutorial.lesson_completed, "two actual projectiles complete shooting")
	await shot("03-shooting")
	tutorial._next_lesson()
	tutorial.player._fire_blaster_projectile(tutorial.player._blaster_damage, 0.0, Vector3.FORWARD)
	await wait_seconds(0.5)
	check(not tutorial.lesson_completed, "normal hit cannot validate charged-shot exercise")
	tutorial.player._fire_blaster_projectile(tutorial.player._blaster_max_damage, 1.0, Vector3.FORWARD)
	await wait_seconds(0.5)
	check(tutorial.lesson_completed, "charged projectile impact validates exercise")
	tutorial.player.set_physics_process(true)
	tutorial._next_lesson()
	tutorial.player._perform_pyro_boots(Vector3.RIGHT)
	await wait_seconds(0.8)
	check(tutorial.lesson_completed, "real completed dash validates mobility")
	tutorial._restart_lesson()
	check(not tutorial.lesson_completed and tutorial.player.get_pyro_charges() == 2, "retry resets result and mobility charges")
	tutorial._start_lesson(4)
	tutorial.player.set_physics_process(false)
	tutorial.player._set_aim_direction(Vector3.FORWARD)
	tutorial.player._perform_javelin()
	for index in 60:
		tutorial.player._update_javelin_charge(1.0 / 60)
		await process_frame
	await wait_seconds(0.5)
	check(tutorial.lesson_completed, "real Javelin impact completes offensive lesson")
	tutorial.player.set_physics_process(true)
	tutorial._next_lesson()
	tutorial.player._perform_static_shield()
	await process_frame
	check(not tutorial.lesson_completed and tutorial.player.get_stasis_remaining() > 0, "shield lesson waits for release of protection")
	tutorial._toggle_menu()
	var shield_time: float = tutorial.player.get_stasis_remaining()
	await wait_seconds(0.1)
	check(paused and is_equal_approx(tutorial.player.get_stasis_remaining(), shield_time), "pause freezes real gameplay")
	tutorial._toggle_menu()
	check(not paused and tutorial.player.is_gameplay_enabled(), "resume restores controls")
	await shot("04-shield")
	await wait_seconds(shield_time + 0.2)
	check(tutorial.lesson_completed, "shield exit completes last exercise")
	var preferences: Node = root.get_node("GamePreferences")
	var original: Dictionary = preferences.bindings.duplicate(true)
	preferences.rebind("mobility", KEY_Y, false)
	tutorial._start_lesson(3)
	check(tutorial._lesson_body.text.contains("Y"), "instructions follow remapped controls")
	preferences.bindings = original
	preferences.apply_bindings()
	# Escape pauses the introduction instead of exposing the training editor.
	var escape := InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.pressed = true
	tutorial._input(escape)
	check(tutorial.tutorial_paused and not tutorial._menu.visible, "Escape opens tutorial pause only")
	tutorial._restart_lesson()
	check(not paused and not tutorial.tutorial_paused, "retry from pause resumes safely")
	tutorial.player.set_weapon("shotgun")
	await wait_seconds(0.05)
	check(tutorial.player._weapon_id == "blaster", "weapon cycle cannot strand a required blaster lesson")
	if capture:
		root.size = Vector2i(844, 390)
		tutorial._start_lesson(2)
		await shot("05-mobile")
		check(tutorial._lesson_panel.get_global_rect().end.x <= 844, "lesson panel fits landscape width")
		var camera := root.get_camera_3d()
		var target_point: Vector2 = camera.unproject_position(tutorial._lesson_target.global_position + Vector3.UP * 0.9)
		check(not tutorial._lesson_panel.get_global_rect().has_point(target_point), "mobile instructions leave the target available for aiming")
		var player_point: Vector2 = camera.unproject_position(tutorial.player.global_position + Vector3.UP * 0.5)
		check(player_point.y < tutorial._spell_bar.get_global_rect().position.y, "mobile player stays visible above the module bar")
		root.size = Vector2i(1280, 720)
	tutorial._start_lesson(5)
	tutorial._complete_lesson()
	tutorial._next_lesson()
	check(tutorial._summary.visible and paused and not tutorial.player.is_gameplay_enabled(), "completion displays recap and stops combat")
	await shot("06-complete")
	await wait_seconds(0.05)
	var summary_content: Control = tutorial._summary.get_node("SummaryContent")
	var last_summary_button: Control = summary_content.get_child(summary_content.get_child_count() - 1)
	check(summary_content.get_child(0).get_global_rect().position.y >= 0 and last_summary_button.get_global_rect().end.y <= root.get_visible_rect().size.y, "recap and navigation fit the viewport")
	check(FileAccess.get_file_as_bytes(LOADOUT.SAVE_PATH) == saved_build, "all lessons preserve saved equipment")
	tutorial._open_free_training()
	await process_frame
	await process_frame
	check(not paused and current_scene.name == "TrainingGround", "free training opens unpaused")
	check(current_scene._loadout == LOADOUT.load_local(), "free training restores player's build")
	current_scene._return_to_main_menu()
	await process_frame
	await process_frame
	check(current_scene.name == "Main" and not paused, "return to home works")
	var ending: Node = current_scene
	current_scene = null
	ending.queue_free()
	await process_frame
	for failure in failures:
		push_error("FAIL: " + failure)
	print("BEGINNER TUTORIAL: %s (%d checks)" % ["PASS" if failures.is_empty() else "FAIL", checks])
	quit(0 if failures.is_empty() else 1)

func wait_seconds(seconds: float) -> void:
	await create_timer(seconds, true, false, true).timeout

func shot(label: String) -> void:
	if not capture:
		return
	await wait_seconds(0.3)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://captures/tutorial/" + label + ".png")
