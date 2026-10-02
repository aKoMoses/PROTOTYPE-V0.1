extends SceneTree

const DATA := preload("res://scripts/combat_data.gd")
const PROGRESSION := preload("res://scripts/survival_progression.gd")
var _failures: Array[String] = []
var _accepted: Array[Dictionary] = []
var _baseline: Dictionary = DATA.WEAPON_DEFINITIONS.mekatana.duplicate(true)


func _initialize() -> void:
	var progression = PROGRESSION.new()
	_check(progression.choose_weapon("mekatana"), "progression accepte MEKATANA")
	_check(not progression.choose_weapon("blaster"), "arme de départ reste verrouillée")
	var scene: Node3D = load("res://scenes/survival.tscn").instantiate()
	scene.set("records_path", "res://.godot/mekatana-survival-records.json")
	root.add_child(scene)
	current_scene = scene
	await physics_frame
	scene.call("_choose_weapon", "mekatana")
	scene.set_process(false)
	scene.set_physics_process(false)
	var player := scene.get_node("Player") as Node3D
	player.set_physics_process(false)
	player.set_process(false)
	_check(str(player.call("get_weapon_id")) == "mekatana" and bool(player.get("survival_mode")), "choix réel équipe MEKATANA en survie")
	var melee = player.get("_mekatana_attack")
	_assert_stats(melee.definition, 0.65, 1.20, "rang zéro")
	var build: Dictionary = scene.get("progression").build()
	build["passive"] = "omnivamp"
	build.upgrades.weapon.power = 1
	build.upgrades.weapon.tempo = 1
	player.call("configure_survival_build", build)
	_assert_stats(melee.definition, 1.25, 0.864, "rang un")
	player.call("configure_survival_build", build)
	_assert_stats(melee.definition, 1.25, 0.864, "rang un réappliqué sans cumul")
	_assert_stats(DATA.WEAPON_DEFINITIONS.mekatana, 1.0, 1.0, "config centrale intacte")
	player.call("reset_combat_state")
	player.call("set_gameplay_enabled", true)
	player.set_physics_process(false)
	# The central corridor is clear of the southern wreck's solid hull.
	player.global_position = Vector3.ZERO
	player.set("aim_direction", Vector3.FORWARD)
	scene.call("_spawn_enemy", player.global_position + Vector3.FORWARD * 1.8, "chaser")
	var target := scene.call("get_training_targets")[0] as Node3D
	target.call("set_training_bot_enabled", false)
	target.set_process(false)
	target.set_physics_process(false)
	target.get("combat_state").max_health = 1000.0
	target.call("reset_combat_state")
	await physics_frame
	player.get("combat_state").health = 600.0
	var health_before := float(player.call("get_health"))
	var target_before := float(target.call("get_health"))
	var projectile_count := get_nodes_in_group("prototype0_gameplay_projectiles").size()
	melee.hit.connect(_on_hit)
	player.call("_perform_mekatana_attack")
	player.call("_update_mekatana_attack", 0.23)
	_check(_accepted.size() == 1 and _accepted[0].target == target, "slash réel accepté une fois contre TargetDummy")
	var expected := float(DATA.WEAPON_DEFINITIONS.mekatana.base_damage[0]) * 1.25
	_check(is_equal_approx(target_before - float(target.call("get_health")), expected), "puissance de survie appliquée au dégât réel")
	var omnivamp_rate := float(player.get("passive_state").omnivamp_rate)
	_check(is_equal_approx(float(player.call("get_health")) - health_before, expected * omnivamp_rate), "Omnivamp crédite le dégât accepté une seule fois")
	_check(get_nodes_in_group("prototype0_gameplay_projectiles").size() == projectile_count, "slash ne crée aucun projectile")
	_check(target.get("combat_state").get("_effects").is_empty() and target.get("combat_state").get("_slow_effects").is_empty(), "électricité visuelle ne crée aucun statut")
	player.call("apply_loadout", {"robot": "polyvalent", "weapon": "mekatana", "passive": "omnivamp"})
	_check(not bool(player.get("survival_mode")) and not melee.is_busy(), "loadout normal quitte la survie et annule le combo")
	_assert_stats(melee.definition, 1.0, 1.0, "loadout normal restaure les bases")
	root.get_node("GameSfx").call("clear")
	_stop_audio(scene)
	scene.queue_free()
	current_scene = null
	await process_frame
	# The audio mixer retires its playbacks on a separate thread.
	await create_timer(0.10).timeout
	if _failures.is_empty():
		print("MEKATANA SURVIVAL TEST: PASS")
	else:
		for failure in _failures:
			push_error("FAIL: " + failure)
		print("MEKATANA SURVIVAL TEST: FAIL")
	quit(0 if _failures.is_empty() else 1)


func _assert_stats(definition: Dictionary, power: float, tempo: float, label: String) -> void:
	var base: Dictionary = _baseline
	for rank in range(3):
		_check(is_equal_approx(float(definition.base_damage[rank]), float(base.base_damage[rank]) * power), "%s : dégâts coup %d" % [label, rank + 1])
		_check(is_equal_approx(float(definition.recovery[rank]), float(base.recovery[rank]) * tempo), "%s : récupération coup %d" % [label, rank + 1])
		_check(is_equal_approx(float(definition.preparation[rank]), float(base.preparation[rank])) and is_equal_approx(float(definition.active[rank]), float(base.active[rank])), "%s : préparation et fenêtre active stables" % label)
	_check(is_equal_approx(float(definition.combo_window), 2.5), "%s : fenêtre de combo 2,5 s" % label)


func _on_hit(target: Node, applied: float, multiplier: float) -> void:
	_accepted.append({"target": target, "applied": applied, "multiplier": multiplier})


func _stop_audio(node: Node) -> void:
	if node is AudioStreamPlayer or node is AudioStreamPlayer3D:
		node.call("stop")
	for child in node.get_children():
		_stop_audio(child)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
