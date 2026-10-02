extends SceneTree

const PREFS := preload("res://scripts/review_preferences.gd")
const LOADOUT := preload("res://scripts/loadout_state.gd")
const PROGRESSION := preload("res://scripts/survival_progression.gd")
const DIRECTOR := preload("res://scripts/survival_director.gd")
const COUNTER := preload("res://scripts/counter.gd")
const DATA := preload("res://scripts/combat_data.gd")
var failures: Array[String] = []
var checks := 0
var capture := false
var training_completed := false
var survival_completed := false

func _initialize() -> void:
	_run.call_deferred()

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)

func _run() -> void:
	capture = OS.get_cmdline_user_args().has("--capture-review") and DisplayServer.get_name() != "headless"
	if capture:
		root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
		root.content_scale_size = Vector2i.ZERO
		root.size = Vector2i(1280, 720)
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://captures/review-fun"))
	_test_progression()
	var values := PREFS.read()
	values.quick = false
	values.difficulty = "normal"
	values.feedback = true
	check(PREFS.write(values) == OK, "experience preferences saved")
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	await process_frame
	var flow: Node = scene.game_flow
	flow._open_solo_setup()
	await shot("01-solo-options")
	var difficulty: OptionButton = flow._solo_setup.find_child("SoloDifficulty", true, false)
	difficulty.select(2)
	difficulty.item_selected.emit(2)
	var quick: CheckButton = flow._solo_setup.find_child("QuickOption", true, false)
	quick.button_pressed = true
	check(PREFS.read().difficulty == "hard" and PREFS.read().quick, "independent comfort and difficulty controls persist")
	flow._launch_solo()
	check(flow._countdown_remaining <= 3.0 and scene.bot_difficulty == "hard", "quick preparation and selected AI profile applied")
	var initial: Dictionary = scene.get_current_bot_build().duplicate(true)
	flow.round_number = 2
	scene.prepare_round(flow.loadout)
	check(scene.get_current_bot_build() == initial, "opponent is stable between rounds")
	flow._begin_live_round()
	scene.target.set_training_bot_enabled(false)
	scene.player.set_physics_process(false)
	scene.target.take_damage(123.0, "player", "longshot:123")
	scene.player.take_damage(45.0, "bot", "blaster:123")
	scene.target.heal(20.0, "repair_pickup")
	check(is_equal_approx(flow._combat_feedback.dealt, 123.0), "feedback credits effective damage once")
	check(flow._combat_feedback.opponent_repairs == 1 and flow._combat_feedback.report().contains("45"), "round report uses actual damage and opponent repairs")
	flow.resolve_round(true, false)
	check(flow._round_report.contains("BLASTER"), "defeat identifies the principal threat")
	flow._restart()
	check(scene.get_current_bot_build() == initial, "rematch keeps the same opponent")
	flow._start_duel()
	check(str(scene.get_current_bot_build().id) != str(initial.id), "new opponent consumes a fresh family from the bag")
	flow._solo_options.quick = false
	flow._store_solo_options()
	flow._restart()
	check(flow._countdown_remaining > 3.0, "full presentation stays available")
	flow._skip_precombat()
	check(flow._countdown_remaining <= 3.0 and not scene.player.is_gameplay_enabled(), "skip preserves the three-second safe countdown")
	flow._return_menu()
	flow._open_equipment()
	var garage: Control = flow._forge_garage
	var before: Dictionary = LOADOUT.load_local()
	var recommended: OptionButton = garage.find_child("RecommendedBuilds", true, false)
	recommended.select(2)
	recommended.item_selected.emit(2)
	check(garage.loadout == PREFS.PRESETS["ASSAUT"] and LOADOUT.load_local() == before, "recommended build remains a draft")
	await shot("02-garage")
	var saves := [0]
	garage.build_saved.connect(func(_equipment: Dictionary) -> void: saves[0] += 1)
	garage._save_then_play()
	garage.installation.set_process(false)
	garage.installation.advance(1.0)
	check(saves[0] == 0 and LOADOUT.load_local() == before, "save and play never starts before installation commits")
	check(garage._installation_controls.visible, "skip control remains visible during installation")
	await shot("03-installation")
	garage._skip_installation()
	garage._skip_installation()
	check(saves[0] == 1 and flow.current_screen == flow.Screen.COMBAT, "skip saves once and starts the requested duel")
	flow._return_menu()
	flow._show_screen(flow.Screen.COMBAT)
	flow.player_round_score = 3
	flow._round_report = "Principal danger : BLASTER · 45 dégâts\nRéparations adverses : 1"
	flow._show_final_result()
	await process_frame
	await process_frame
	check(flow._result_panel.scale.x >= 0.7 and flow._result_panel.get_global_rect().size.x >= 400, "result panel remains readable after detailed report")
	await shot("04-result")
	scene.queue_free()
	await process_frame
	await _test_training()
	await _test_survival()
	check(training_completed and survival_completed, "all integration sections run to completion without aborted script calls")
	paused = false
	current_scene = null
	root.get_node("GameSfx").clear()
	await create_timer(0.15).timeout
	for failure in failures:
		push_error(failure)
	print("REVIEW FUN TEST: %s (%d checks, %d failures)" % ["PASS" if failures.is_empty() else "FAIL", checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func _test_progression() -> void:
	var progression := PROGRESSION.new()
	progression.choose_weapon("blaster")
	var previous := progression.reward_choices(1).duplicate(true)
	check(progression.reroll_reward(1), "one reroll is available for a real reward")
	var next := progression.reward_choices(1)
	check(next.any(func(card: Dictionary) -> bool: return not previous.has(card)), "reroll changes at least one offered card")
	check(not progression.reroll_reward(1) and progression.rerolls_remaining == 0, "reroll cannot be used twice")
	check(progression.apply_reward(1, next[0]) and not progression.apply_reward(1, next[0]), "rerolled reward is claimable once")
	var total := 0
	for wave in range(1, 13):
		total += DIRECTOR.roles(wave).size()
		check(DIRECTOR.brief(wave) != "", "each wave has tactical guidance")
	check(total == 76 and DIRECTOR.roles(12).back() == "boss", "wave director preserves 76 enemies and final boss")
	for title in PREFS.PRESETS:
		check(LOADOUT.is_valid(PREFS.PRESETS[title]), "recommended loadout valid: " + title)
	var path := "user://review-mastery-test.cfg"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	for weapon in LOADOUT.WEAPONS:
		PREFS.unlock("survival", weapon, path)
	for id in ["counter", "javelin", "fulguro_punch"]:
		PREFS.unlock("challenge", id, path)
	check("arsenal" in PREFS.read(path).unlocked and "technicien" in PREFS.read(path).unlocked, "cosmetic mastery tracks distinct completed weapons and challenges")
	check(PREFS.unlock("survival", "blaster", path).is_empty(), "existing badge never unlocks twice")
	var invalid := PREFS.read(path)
	invalid.challenges = 123
	invalid.weapons = ["blaster", "blaster", "unknown"]
	PREFS.write(invalid, path)
	check(PREFS.read(path).challenges.is_empty() and PREFS.read(path).weapons == ["blaster"], "invalid mastery data cannot break menus or count duplicate achievements")

func _test_training() -> void:
	var ground: Node = load("res://scenes/training_ground.tscn").instantiate()
	root.add_child(ground)
	current_scene = ground
	await process_frame
	var challenge: Control = ground._challenges
	var original: Dictionary = LOADOUT.load_local()
	var origin: Vector3 = ground.player.global_position
	ground._toggle_menu()
	challenge.open()
	await shot("05-challenges")
	var escape := InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.pressed = true
	ground._input(escape)
	check(ground._menu.visible and paused and not challenge._chooser.visible, "Escape closes only the challenge chooser and keeps training paused")
	challenge.start("counter")
	ground.player.set_physics_process(false)
	ground._shooter_target.set_training_bot_enabled(false)
	ground._feedback._process(0.01)
	check(not challenge.completed, "activating a challenge does not award success")
	ground.player._perform_counter()
	var guard := COUNTER.component(ground.player)
	guard.update(float(guard.definition.preparation))
	var attack := COUNTER.weapon_attack(ground._shooter_target, "review:counter", DATA.WEAPON_DEFINITIONS.blaster)
	COUNTER.impact(ground.player, 100, "bot", "review:counter", attack, Vector3.UP)
	check(challenge.completed, "real intercepted attack completes counter challenge")
	challenge.start("javelin")
	ground.player.set_physics_process(false)
	var target: Node = ground._fixed_targets[1]
	ground.player.begin_touch_action("offensive")
	ground.player.end_touch_action("offensive")
	ground.player._update_javelin_charge(0.36)
	for frame in 90:
		await physics_frame
		if is_instance_valid(ground.player._javelin_mark_target):
			break
	check(is_instance_valid(ground.player._javelin_mark_target), "challenge fixture can be hit by the actual Javelin")
	ground._feedback._process(0.01)
	ground.player._recast_javelin()
	ground._feedback._process(0.01)
	check(challenge.completed, "real marked-target teleport completes the repositioning challenge")
	challenge.start("fulguro_punch")
	ground.player.set_physics_process(false)
	ground.player.begin_touch_action("offensive")
	ground.player._update_fulguro_attack(1.5)
	ground.player.end_touch_action("offensive")
	ground.player._update_fulguro_attack(0.01)
	for frame in 90:
		await physics_frame
		if challenge.completed:
			break
	check(challenge.completed, "actual Fulguro projection into existing wall completes challenge")
	await shot("06-challenge-success")
	ground._reset_trial()
	check(challenge.active == "fulguro_punch" and not challenge.completed and ground.player.global_position == Vector3(-24, 0, -33), "reset restarts the active challenge with its original setup")
	challenge.stop()
	check(LOADOUT.load_local() == original and ground.player.global_position.is_equal_approx(origin), "training restores position and never persists temporary challenge loadout")
	check(ground._fixed_targets[1].combat_state.max_health == 1000.0 and ground._shooter_target.visible, "training restores target health, collisions and visibility")
	ground._remove_all_fixed()
	await process_frame
	challenge.start("javelin")
	check(challenge.active == "javelin" and ground._fixed_targets.size() == 1, "challenge remains available when the player has removed all fixed targets")
	challenge.stop()
	check(ground._fixed_targets.is_empty(), "temporary challenge target is removed when leaving the challenge")
	ground.queue_free()
	await process_frame
	training_completed = true

func _test_survival() -> void:
	paused = false
	var survival: Node = load("res://scenes/survival.tscn").instantiate()
	root.add_child(survival)
	current_scene = survival
	await process_frame
	survival._choose_weapon("blaster")
	survival._begin_wave_combat()
	survival.player.set_physics_process(false)
	survival._spawn_reinforcements()
	for enemy in survival.get_training_targets():
		enemy.take_damage(10000, "player", "blaster:review")
	await process_frame
	await process_frame
	survival._reward_input_delay = -1.0
	var previous: Array = survival.progression.reward_choices(1).duplicate(true)
	survival._reroll_reward()
	check(survival.progression.rerolls_remaining == 0, "survival UI consumes exactly one reroll")
	check(survival._reward_overlay.find_child("RewardReroll", true, false).disabled, "reroll control is disabled after use")
	await shot("07-survival-rewards")
	survival._choose_reward(survival.progression.reward_choices(1)[0])
	check(survival.wave == 2 and survival._threat_label.text == DIRECTOR.brief(2), "next wave uses director guidance after reward")
	await shot("08-survival-wave")
	paused = false
	survival.queue_free()
	await process_frame
	survival_completed = true

func shot(name: String) -> void:
	if not capture:
		return
	await create_timer(0.15).timeout
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png("res://captures/review-fun/" + name + ".png") == OK, "capture saved: " + name)
