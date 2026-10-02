extends SceneTree

## Record real combat in TrainingGround, never the player's saved build.
## --write-movie art/forge-demos/<id>.ogv --fixed-fps 30 -- --demo <id>
const LOADOUT := preload("res://scripts/loadout_state.gd")

class DemoPlayer extends "res://scripts/player.gd":
	# Scripted commands use the combat API; desktop/touch polling stays inactive.
	var demo_aim := Vector3.FORWARD
	func _update_aim() -> void:
		_set_aim_direction(demo_aim)
	func _update_attack(_cast_locked_before_updates: bool = false) -> void:
		pass
	func _update_debug_effects() -> void:
		pass
	func _update_shotgun_reload_input() -> void:
		pass
	func _camera_relative_direction(value: Vector2) -> Vector3:
		return Vector3(value.x, 0, value.y).normalized()

class DemoTraining extends "res://scripts/training_ground.gd":
	func _build_player_and_camera() -> void:
		player = DemoPlayer.new()
		player.name = "Player"
		add_child(player)
		var rig := CAMERA_SCRIPT.new()
		rig.name = "CameraRig"
		var camera := Camera3D.new()
		camera.name = "Camera3D"
		camera.position = Vector3(0, 25.5, 22)
		camera.current = true
		rig.add_child(camera)
		add_child(rig)
		rig.set_target(player)
	func _apply_loadout() -> void:
		# Capturing clips never writes the user's saved equipment.
		player.apply_loadout(_loadout)

var arena: Node3D
var player: CharacterBody3D
var target: StaticBody3D
var caption: Label
var vitals: Label
var identifier := "mekatana"
var dealt := 0.0
var received := 0.0
var healed := 0.0
var evidence: Dictionary = {}
var failures: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.has("--demo"):
		identifier = args[args.find("--demo") + 1]
	var category := _category(identifier)
	if category == "":
		push_error("Unknown forge demo: " + identifier)
		quit(1)
		return
	root.content_scale_size = Vector2i(640, 360)
	root.size = Vector2i(640, 360)
	AudioServer.set_bus_mute(0, true)
	arena = DemoTraining.new()
	root.add_child(arena)
	current_scene = arena
	await process_frame
	arena.set_process(false)
	arena.set_process_input(false)
	arena.set_process_unhandled_input(false)
	arena.get_node("TrainingUI").hide()
	arena.get_node("TrainingUI").process_mode = Node.PROCESS_MODE_DISABLED
	player = arena.get("player")
	player.set_process_input(false)
	player.set_process_unhandled_input(false)
	var targets: Array = arena.call("get_training_targets")
	target = targets[1]
	for other in targets:
		if other != target:
			other.queue_free()
	arena.set("_fixed_targets", [target] as Array[StaticBody3D])
	arena.set("_moving_target", null)
	arena.set("_shooter_target", null)
	target.position = Vector3(0, 0, 5)
	target.set("training_origin", target.position)
	target.set_meta("meter_name", "Mannequin")
	(target.get("_health_readout") as Node3D).scale = Vector3.ONE * 0.65
	(player.get("_health_readout") as Node3D).scale = Vector3.ONE * 0.65
	var build := LOADOUT.defaults()
	build[category] = identifier
	if category != "weapon":
		build.weapon = "blaster"
	player.call("apply_loadout", build)
	player.call("set_training_options", false, false, false)
	player.call("set_gameplay_enabled", true)
	if identifier == "counter":
		target.call("set_duel_mode", true)
		target.call("set_duel_loadout", LOADOUT.defaults())
		var bot := target.get_node("TrainingBot")
		bot.set("enabled", true)
		bot.set_physics_process(false)
		bot.set_process(false)
	var distance := 3.0 if identifier in ["mekatana", "fulguro_punch", "projector"] else 6.0
	player.position = target.position + Vector3(0, 0, distance)
	player.set("gameplay_arena_center", Vector3.ZERO)
	var rig := arena.get_node("CameraRig") as Node3D
	rig.set_process(false)
	rig.position = Vector3.ZERO
	var camera := rig.get_node("Camera3D") as Camera3D
	camera.position = Vector3(6.5, 6.5, 15.5)
	camera.fov = 35.0
	if identifier in ["fulguro_punch", "pelto_smash", "pyro_boots", "inertia"]:
		camera.position = Vector3(8.5, 8.5, 18.5)
		camera.fov = 39.0
	camera.look_at(Vector3(0, 0.7, 7.0))
	player.call("_set_aim_direction", Vector3.FORWARD)
	player.set("_last_move_direction", Vector3.FORWARD)
	_build_caption()
	target.get("combat_state").damage_applied.connect(func(amount: float, _source: String, _attack: String) -> void: dealt += amount)
	player.get("combat_state").damage_applied.connect(func(amount: float, _source: String, _attack: String) -> void: received += amount)
	player.get("combat_state").healing_applied.connect(func(amount: float, _source: String) -> void: healed += amount)
	await _wait(0.6)
	match identifier:
		"mekatana":
			for step in range(3):
				if step > 0:
					player.call("set_move_input", Vector2(0, 1))
					await _wait(maxf(0, 3.0 - player.position.z + target.position.z) / float(player.get("move_speed")))
					player.call("set_move_input", Vector2.ZERO)
				caption.text = "COMBO · %d / 3" % (step + 1)
				player.call("_perform_mekatana_attack")
				await _wait(0.85)
		"blaster":
			caption.text = "TIR SIMPLE"
			_shoot()
			await _wait(1.1)
			caption.text = "TIR CHARGÉ"
			player.call("_begin_blaster_charge")
			await _wait(1.1)
			player.set("_blaster_charge_ratio", 1.0)
			player.call("_release_blaster_charge")
			await _wait(1.0)
		"shotgun":
			caption.text = "3 SALVES · RECHARGE"
			for shot in range(3):
				_shoot()
				await _wait(0.8)
			player.call("_start_shotgun_reload")
			await _wait(2.0)
		"longshot":
			for shot in range(5):
				caption.text = "TIR %d / 5" % (shot + 1) if shot < 4 else "5e TIR AMÉLIORÉ"
				_shoot()
				await _wait(1.1)
		"javelin":
			caption.text = "LANCER · MARQUAGE"
			player.call("_perform_offensive_module")
			await _wait(1.4)
			caption.text = "RECAST · TÉLÉPORTATION"
			player.call("_recast_javelin")
			await _wait(1.1)
		"fulguro_punch":
			caption.text = "CHARGE · PROJECTION"
			player.call("_begin_fulguro_charge")
			await _wait(1.2)
			player.call("_release_fulguro_charge")
			await _wait(2.0)
		"modulo_drone", "pelto_smash":
			caption.text = "IMPACT · BRÛLURE" if identifier == "modulo_drone" else "VAGUE · RETOUR TRACTANT"
			player.call("_perform_offensive_module")
			await _wait(3.0)
		"rocket_basket":
			caption.text = "5 ROQUETTES GUIDÉES · RALENTISSEMENT"
			player.call("_perform_offensive_module")
			await _wait(2.0)
			_verify(dealt > 0.0, "les roquettes infligent de vrais degats")
			evidence.slow = target.call("get_slow_percent")
			await _wait(1.0)
		"projector":
			caption.text = "ONDE DE CHOC · POUSSÉE · RALENTISSEMENT"
			var origin: Vector3 = target.global_position
			player.call("_perform_defensive_module")
			await _wait(0.65)
			evidence.pushed = target.global_position.distance_to(origin)
			evidence.slow = target.call("get_slow_percent")
			_verify(float(evidence.pushed) > 0.2 and float(evidence.slow) > 0.0, "la cible est projetee et ralentie")
			await _wait(1.8)
		"counter":
			caption.text = "GARDE · INTERCEPTION"
			player.call("_perform_defensive_module")
			await _wait(0.15)
			_shoot_duel_bot()
			await _wait(0.5)
			evidence.surcharge = player.call("get_surcharge_remaining")
			_verify(float(evidence.surcharge) > 0.0 and received == 0.0, "un vrai tir intercepte arme la riposte")
			caption.text = "PROCHAIN TIR · EXPLOSION DE RIPOSTE"
			_shoot()
			await _wait(1.2)
			evidence.explosions = player.get("_counter").explosions
			_verify(int(evidence.explosions) > 0 and dealt > 0.0, "la riposte touche et explose")
		"permutation":
			caption.text = "MARQUE · ÉCHANGE DE POSITIONS"
			var origin: Vector3 = player.global_position
			evidence.candidate = player.call("_permutation_target") == target
			evidence.enabled = player.call("is_gameplay_enabled")
			player.call("_perform_mobility_module")
			evidence.accepted = float(player.call("get_module_cooldown", "permutation")) > 0.0
			await _wait(1.4)
			evidence.travel = player.global_position.distance_to(origin)
			evidence.shield = player.call("get_shield_health")
			_verify(float(evidence.travel) > 3.0 and float(evidence.shield) > 0.0, "l'echange reel applique son bouclier")
			caption.text = "ÉCHANGE RÉUSSI · VITESSE +35 % · BOUCLIER"
			await _wait(1.4)
		"eclipse":
			caption.text = "DÉPLACEMENT INTANGIBLE · EXPLOSION"
			var origin: Vector3 = player.global_position
			evidence.accepted = player.call("_perform_eclipse", target.global_position + Vector3(0, 0, 2.2))
			await _wait(0.8)
			evidence.travel = player.global_position.distance_to(origin)
			evidence.shield = player.call("get_shield_health")
			_verify(float(evidence.travel) > 3.0 and dealt > 0.0 and float(evidence.shield) > 0.0, "le deplacement touche la cible et donne son bouclier")
			await _wait(1.8)
		"auxiliary_reactor":
			caption.text = "MODULE OFFENSIF · RECHARGE EN COURS"
			player.call("_perform_offensive_module")
			await _wait(1.0)
			caption.text = "IMPACTS D'ARME · RECHARGE −0,25 s"
			var cooldown: float = player.call("get_module_cooldown", "javelin")
			for shot in 3:
				_shoot()
				await _wait(0.85)
			evidence.reduction = cooldown - float(player.call("get_module_cooldown", "javelin")) - 3.0 * 0.85
			_verify(float(evidence.reduction) > 0.4, "les impacts reduisent reellement la recharge")
		"tracker":
			for shot in 3:
				caption.text = "IMPACT %d / 3 · MARQUAGE" % (shot + 1)
				_shoot()
				await _wait(0.8)
			evidence.revealed = target.call("is_spotted")
			_verify(bool(evidence.revealed), "trois impacts revelent reellement la cible")
			caption.text = "CIBLE RÉVÉLÉE · 3 SECONDES"
			await _wait(1.0)
		"alternator":
			caption.text = "IMPACT OFFENSIF · BONUS ARMÉ"
			player.call("_perform_offensive_module")
			await _wait(1.0)
			evidence.armed = player.get("passive_state").alternator_remaining
			_verify(float(evidence.armed) > 0.0, "un impact offensif arme le bonus")
			await _wait(0.4)
			var damage_before := dealt
			caption.text = "PROCHAIN TIR · DÉGÂTS +15 %"
			_shoot()
			await _wait(0.5)
			evidence.weapon_damage = dealt - damage_before
			_verify(float(evidence.weapon_damage) > 25.0 and player.get("passive_state").alternator_remaining == 0.0, "le prochain vrai tir consomme le bonus de degats")
			await _wait(0.8)
		"inertia":
			caption.text = "FIN DU DASH · BONUS ARMÉ"
			player.call("_perform_pyro_boots", Vector3.RIGHT)
			await _wait(0.3)
			evidence.armed = player.get("passive_state").inertia_remaining
			_verify(float(evidence.armed) > 0.0, "la fin du vrai dash arme le ralentissement")
			var direction: Vector3 = (target.global_position - player.global_position).normalized()
			player.set("demo_aim", direction)
			player.call("_set_aim_direction", direction)
			caption.text = "PROCHAIN TIR · CIBLE RALENTIE"
			player.call("_fire_blaster_projectile", 25.0, 0.0, direction)
			await _wait(0.4)
			evidence.slow = target.call("get_slow_percent")
			_verify(float(evidence.slow) == 20.0 and dealt > 0.0, "le vrai projectile applique le ralentissement")
			await _wait(1.3)
		"magnetic_field", "static_shield":
			caption.text = "ABSORPTION DES TIRS" if identifier == "magnetic_field" else "STASE · INVULNÉRABILITÉ"
			player.call("_perform_defensive_module")
			await _wait(0.6)
			for shot in range(3):
				target.get_node("TrainingBot").call("_attack_player", player)
				await _wait(0.3)
			await _wait(2.0)
		"pyro_boots":
			caption.text = "DASH"
			player.call("_perform_pyro_boots", Vector3.RIGHT)
			await _wait(2.0)
		"bio_injector":
			caption.text = "ATTAQUES ACCÉLÉRÉES"
			player.call("_perform_mobility_module")
			for shot in range(4):
				_shoot()
				await _wait(0.6)
		"omnivamp":
			player.call("set_training_health_ratio", 0.5)
			caption.text = "DÉGÂTS → SOIN"
			for shot in range(3):
				_shoot()
				await _wait(0.9)
		"baroud":
			caption.text = "COUP LÉTAL · DERNIÈRE CHANCE"
			player.call("take_damage", 2000.0, "forge_demo", "lethal")
			await _wait(0.2)
			_shoot()
			await _wait(2.7)
	await _wait(0.7)
	if not failures.is_empty():
		print("FORGE DEMO FAILED EVIDENCE: ", JSON.stringify(evidence), " damage=", dealt, " received=", received)
		for failure in failures:
			push_error("FORGE DEMO: " + identifier + " · " + failure)
		quit(1)
		return
	print("FORGE DEMO RECORDED: ", identifier, " damage=", dealt, " received=", received, " healed=", healed)
	if not evidence.is_empty():
		print("FORGE DEMO EVIDENCE: ", identifier, " ", JSON.stringify(evidence))
	player.call("set_gameplay_enabled", false)
	root.get_node("GameSfx").call("clear")
	await _wait(0.15)
	quit()


func _shoot() -> void:
	match str(player.call("get_weapon_id")):
		"blaster":
			player.set("_blaster_next_attack_ready_at", -1.0)
			player.call("_fire_blaster_projectile", 25.0, 0.0, Vector3.FORWARD)
		"shotgun": player.call("_perform_shotgun_attack")
		"longshot":
			player.set("_longshot_next_attack_ready_at", -1.0)
			player.call("_perform_longshot_attack")


func _shoot_duel_bot() -> void:
	# The simple training shooter's raw damage deliberately bypasses Counter.
	# Use the real duel weapon's projectile and shared impact payload instead.
	var equipment: Node = target.get_node("TrainingBot").get("_duel_equipment")
	var aim := player.global_position + Vector3.UP * 0.92
	var muzzle: Transform3D = target.call("prepare_training_bot_shot", aim)
	var volley := {"hits": 0, "base": 0.0, "passive_attack": equipment.call("emit_passive_weapon")}
	equipment.call("_launch_projectile", target, player, muzzle.origin, (aim - muzzle.origin).normalized(), 0, volley)


func _wait(seconds: float) -> void:
	await create_timer(seconds).timeout


func _build_caption() -> void:
	var layer := CanvasLayer.new()
	root.add_child(layer)
	caption = Label.new()
	caption.position = Vector2(16, 327)
	caption.size = Vector2(608, 28)
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caption.add_theme_font_size_override("font_size", 18)
	caption.add_theme_color_override("font_shadow_color", Color.BLACK)
	caption.add_theme_constant_override("shadow_offset_x", 2)
	caption.add_theme_constant_override("shadow_offset_y", 2)
	layer.add_child(caption)
	if identifier in LOADOUT.PASSIVES:
		vitals = Label.new()
		vitals.position = Vector2(14, 12)
		vitals.add_theme_font_size_override("font_size", 21)
		vitals.add_theme_color_override("font_shadow_color", Color.BLACK)
		vitals.add_theme_constant_override("shadow_offset_x", 2)
		vitals.add_theme_constant_override("shadow_offset_y", 2)
		layer.add_child(vitals)
		process_frame.connect(func() -> void:
			vitals.text = "PV · %d" % int(player.call("get_health"))
			if identifier == "auxiliary_reactor":
				vitals.text = "RECHARGE OFFENSIVE · %.1f s" % float(player.call("get_module_cooldown", "javelin"))
			elif identifier == "tracker":
				vitals.text = "CIBLE RÉVÉLÉE" if bool(target.call("is_spotted")) else "MARQUES · %d / 3" % int(player.get("passive_state").tracker_count)
			elif identifier == "alternator":
				vitals.text = "BONUS ARMÉ · +15 %" if float(player.get("passive_state").alternator_remaining) > 0.0 else "ALTERNATEUR"
			elif identifier == "inertia":
				vitals.text = "CIBLE RALENTIE · 20 %" if float(target.call("get_slow_percent")) > 0.0 else "BONUS ARMÉ · PROCHAIN TIR" if float(player.get("passive_state").inertia_remaining) > 0.0 else "INERTIE"
			elif float(player.call("get_baroud_remaining")) > 0.0:
				vitals.text = "DERNIÈRE CHANCE · %d" % int(player.call("get_baroud_health"))
		)


func _category(id: String) -> String:
	var catalog := {"weapon": LOADOUT.WEAPONS, "offensive": LOADOUT.OFFENSIVE, "defensive": LOADOUT.DEFENSIVE, "mobility": LOADOUT.MOBILITY, "passive": LOADOUT.PASSIVES}
	for category in catalog:
		var choices: Array = catalog[category]
		if choices.has(id):
			return category
	return ""


func _verify(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
