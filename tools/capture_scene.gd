extends SceneTree

var output_path := ""


func _initialize() -> void:
	var arguments := OS.get_cmdline_user_args()
	if arguments.size() > 0:
		output_path = arguments[0]
	else:
		output_path = "user://prototype0_capture.png"
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	# Main builds the arena and its runtime children during _ready(). Wait one
	# frame before looking up the player/target so capture options are reliable.
	await process_frame
	var flow := scene.get_node_or_null("Interface")
	if arguments.size() >= 2 and arguments[1] in ["menu_clip_2", "menu_clip_3"]:
		scene.set("_menu_showcase_elapsed", 3.3 if arguments[1] == "menu_clip_2" else 6.3)
	if arguments.size() >= 2 and flow != null:
		if arguments[1] == "equipment":
			flow.call("_open_equipment")
		elif arguments[1] == "duel" or arguments[1] == "duel_live":
			flow.call("_start_duel")
			if arguments[1] == "duel_live":
				flow.call("_begin_live_round")
		elif arguments[1] == "fight":
			flow.call("_start_duel")
			flow.call("_begin_fight")
		elif arguments[1] == "damage":
			flow.call("_start_duel")
			flow.call("_begin_live_round")
			var damage_target: Node = scene.get_node_or_null("TargetDummy")
			if damage_target != null:
				damage_target.call("take_damage", 50.0, "capture", "damage_capture")
		elif arguments[1] == "damage_chain":
			flow.call("_start_duel")
			flow.call("_begin_live_round")
			var chain_target: Node = scene.get_node_or_null("TargetDummy")
			if chain_target != null:
				chain_target.call("take_damage", 50.0, "capture:shot", "chain_1")
				chain_target.call("take_damage", 60.0, "capture:burn", "chain_2")
				chain_target.call("take_damage", 70.0, "capture:module", "chain_3")
		elif arguments[1] == "shotgun_damage":
			flow.call("_start_duel")
			flow.call("_begin_live_round")
			var shotgun_player: Node = scene.get_node_or_null("Player")
			var shotgun_target: Node = scene.get_node_or_null("TargetDummy")
			if shotgun_player != null and shotgun_target != null:
				shotgun_player.position = Vector3(-1.7, 0.0, 0.8)
				shotgun_target.position = Vector3(1.0, 0.0, -1.8)
				shotgun_target.call("set_training_bot_enabled", false)
				shotgun_player.set("aim_direction", Vector3(2.7, 0.0, -2.6).normalized())
				shotgun_player.call("set_weapon", "shotgun")
				shotgun_player.call("_perform_shotgun_attack")
				await create_timer(0.42).timeout
		elif arguments[1] == "result" or arguments[1] == "winner_focus":
			flow.call("_start_duel")
			flow.call("_begin_live_round")
			var result_target: Node = scene.get_node_or_null("TargetDummy")
			if result_target != null:
				result_target.call("take_damage", 1000.0, "capture", "result_capture")
			flow.call("resolve_round", false, true)
			await create_timer(1.8 if arguments[1] == "result" else 0.9).timeout
	# Les options de capture (par exemple `duel_live touch_preview`) ne sont pas
	# des coordonnees. Ne deplacer le joueur que pour deux valeurs numeriques.
	if arguments.size() >= 3 and arguments[1].is_valid_float() and arguments[2].is_valid_float():
		var capture_player := scene.get_node_or_null("Player") as Node3D
		if capture_player != null:
			capture_player.position = Vector3(float(arguments[1]), 0.0, float(arguments[2]))
	if arguments.size() >= 4 and arguments[3] == "effects":
		var capture_player := scene.get_node_or_null("Player") as Node3D
		var capture_target := scene.get_node_or_null("TargetDummy")
		if capture_player != null and capture_target != null:
			capture_player.position = Vector3.ZERO
			capture_target.position = Vector3(0.0, 0.0, -2.6)
			capture_target.call("set_training_bot_enabled", false)
			capture_target.call("reset_combat_state")
			capture_target.call("apply_burn", 3.5, 20.0, "capture")
			capture_target.call("apply_slow", 1.5, 30.0, "capture")
			capture_target.call("apply_stun", 1.5, "capture")
			capture_target.call("apply_spotted", 5.0, "capture")
			print("CAPTURE EFFECTS: ", capture_target.call("get_active_effect_types"))
	if arguments.size() >= 4 and arguments[3] == "blaster":
		var blaster_player := scene.get_node_or_null("Player")
		var blaster_target := scene.get_node_or_null("TargetDummy")
		if blaster_player != null and blaster_target != null:
			blaster_player.position = Vector3(0.0, 0.0, 0.0)
			blaster_target.position = Vector3(0.0, 0.0, -4.0)
			blaster_player.set("aim_direction", Vector3(0.0, 0.0, -1.0))
			blaster_player.call("set_weapon", "blaster")
			blaster_player.call("reset_combat_state")
			blaster_target.call("reset_combat_state")
			blaster_player.call("_fire_blaster_projectile", 50.0, 1.0, Vector3(0.0, 0.0, -1.0))
			print("CAPTURE BLASTER: charged shot started")
	if arguments.size() >= 4 and arguments[3] == "blaster_charge":
		var charging_player := scene.get_node_or_null("Player")
		var charging_target := scene.get_node_or_null("TargetDummy")
		if charging_player != null and charging_target != null:
			charging_player.position = Vector3(0.0, 0.0, 0.0)
			charging_target.position = Vector3(0.0, 0.0, -4.0)
			charging_target.call("set_training_bot_enabled", false)
			charging_player.set("aim_direction", Vector3(0.0, 0.0, -1.0))
			charging_player.call("set_weapon", "blaster")
			charging_player.call("_begin_blaster_charge")
			print("CAPTURE BLASTER: charge started")
	if arguments.size() >= 4 and (arguments[3] == "shotgun" or arguments[3] == "shotgun_live"):
		var shotgun_player := scene.get_node_or_null("Player")
		var shotgun_target := scene.get_node_or_null("TargetDummy")
		if shotgun_player != null and shotgun_target != null:
			shotgun_player.position = Vector3(-1.7, 0.0, 0.8)
			shotgun_target.position = Vector3(1.0, 0.0, -1.8)
			shotgun_player.set("aim_direction", Vector3(2.7, 0.0, -2.6).normalized())
			shotgun_player.call("set_weapon", "shotgun")
			shotgun_player.call("reset_combat_state")
			shotgun_target.call("reset_combat_state")
			shotgun_player.call("_perform_shotgun_attack")
			print("CAPTURE SHOTGUN: salvo started")
	if arguments.size() >= 4 and (arguments[3] == "bot" or arguments[3] == "bot_impact"):
		var bot_player := scene.get_node_or_null("Player")
		var bot_target := scene.get_node_or_null("TargetDummy")
		if bot_player != null and bot_target != null:
			bot_player.position = Vector3(-5.0, 0.0, 3.0)
			bot_target.position = Vector3(-5.0, 0.0, -3.0)
			bot_target.call("reset_combat_state")
			bot_target.call("apply_spotted", 5.0, "capture")
			bot_target.call("set_training_bot_enabled", true)
			var training_bot := bot_target.get_node_or_null("TrainingBot")
			if training_bot != null:
				training_bot.set("_next_attack_at", 0.12)
			print("CAPTURE BOT: telegraph started")
	if arguments.size() >= 4 and (arguments[3] == "drone" or arguments[3] == "javelin"):
		var module_player := scene.get_node_or_null("Player")
		var module_target := scene.get_node_or_null("TargetDummy")
		if module_player != null and module_target != null:
			module_player.position = Vector3(-1.7, 0.0, 0.8)
			module_target.position = Vector3(1.0, 0.0, -1.8)
			module_player.set("aim_direction", Vector3(2.7, 0.0, -2.6).normalized())
			module_player.call("reset_combat_state")
			module_target.call("reset_combat_state")
			if arguments[3] == "drone":
				module_player.call("_perform_modulo_drone")
			else:
				module_player.set("_offensive_module_id", "javelin")
				module_player.call("_perform_javelin")
			print("CAPTURE MODULE: ", arguments[3])
	if arguments.size() >= 4 and (arguments[3] == "magnetic" or arguments[3] == "stasis"):
		var defensive_player := scene.get_node_or_null("Player")
		var defensive_target := scene.get_node_or_null("TargetDummy")
		if defensive_player != null and defensive_target != null:
			defensive_player.position = Vector3(0.0, 0.0, 0.0)
			defensive_target.position = Vector3(0.0, 0.0, -3.0)
			defensive_player.set("aim_direction", Vector3(0.0, 0.0, -1.0))
			defensive_player.call("reset_combat_state")
			defensive_target.call("reset_combat_state")
			defensive_player.set("_defensive_module_id", "static_shield" if arguments[3] == "stasis" else "magnetic_field")
			defensive_player.call("_perform_defensive_module")
			print("CAPTURE DEFENSIVE: ", arguments[3])
	if arguments.size() >= 4 and arguments[3] == "baroud":
		var passive_player := scene.get_node_or_null("Player")
		if passive_player != null:
			passive_player.position = Vector3(0.0, 0.0, 0.0)
			passive_player.call("reset_combat_state")
			passive_player.call("set_passive", "baroud")
			passive_player.call("take_damage", 1000.0, "capture", "baroud_capture")
			print("CAPTURE PASSIVE: baroud")
	var settle_frames := 30
	if arguments.size() >= 2 and arguments[1] in ["winner_focus", "result", "shotgun_damage"]:
		settle_frames = 0
	elif arguments.size() >= 2 and arguments[1] in ["damage", "damage_chain"]:
		settle_frames = 8
	if arguments.size() >= 4:
		match arguments[3]:
			"blaster": settle_frames = 30
			"blaster_charge": settle_frames = 14
			"shotgun_live": settle_frames = 6
			"shotgun": settle_frames = 22
			"bot": settle_frames = 18
			"bot_impact": settle_frames = 44
			"drone", "javelin": settle_frames = 32
			"magnetic": settle_frames = 18
			"stasis", "baroud": settle_frames = 12
	for _frame in range(settle_frames):
		await process_frame
	var image := get_root().get_viewport().get_texture().get_image()
	image.save_png(output_path)
	quit()
