extends SceneTree

const SYNERGIES := preload("res://scripts/survival_synergies.gd")
const STATS := preload("res://scripts/survival_run_stats.gd")
const ACTION_GATE := preload("res://scripts/action_gate.gd")
var failures: Array[String] = []

func check(value: bool, message: String) -> void:
	if not value:
		failures.append(message)

func _initialize() -> void:
	var scene: Node3D = load("res://scenes/survival.tscn").instantiate()
	scene.records_path = "user://test_survival_expansion.json"
	root.add_child(scene)
	current_scene = scene
	await physics_frame
	scene._choose_weapon("blaster")
	scene._begin_wave_combat()
	var player: Node3D = scene.player
	player.set_robot("polyvalent")
	player.set_training_options(true, false, false)
	var first: Array = scene.get_training_targets()
	for enemy in first:
		enemy.take_damage(5000.0, "test", str(enemy.get_instance_id()))
	await process_frame
	check(scene._state == "combat", "tuer le premier groupe attend les renforts")
	scene._spawn_reinforcements()
	check(scene._enemies.size() == 3, "trois ennemis au premier palier")
	for enemy in scene.get_training_targets():
		enemy.take_damage(5000.0, "test", str(enemy.get_instance_id()))
	await process_frame
	check(scene._state == "reward", "fin de vague après les deux groupes")
	player.combat_state.health = 500.0
	scene._choose_reward(scene.progression.reward_choices(1)[0])
	check(is_equal_approx(player.get_health(), 500.0), "aucun soin automatique après vague 1")
	scene._begin_wave_combat()
	for enemy in scene.get_training_targets():
		enemy.set_training_bot_enabled(false)
	check(is_instance_valid(scene._repair), "réparation limitée disponible vague 2")
	player.global_position = scene._repair.global_position
	scene._process(0.01)
	check(is_equal_approx(player.get_health(), 580.0) and scene._repair == null, "réparation consommée une fois pour 80 PV")
	scene._process(0.01)
	check(is_equal_approx(player.get_health(), 580.0), "pas de soin répété après ramassage")
	var elapsed: float = scene.stats.elapsed
	scene._pause_run()
	scene._process(2.0)
	check(is_equal_approx(scene.stats.elapsed, elapsed), "chronomètre exclut la pause")
	scene._resume_run()
	# Fresh stationary targets keep interaction checks independent of AI movement.
	scene._clear_enemies()
	player.global_position = Vector3.ZERO
	scene._spawn_enemy(Vector3(0, 0, -4), "chaser")
	scene._spawn_enemy(Vector3(2, 0, -4), "shooter")
	scene._spawn_enemy(Vector3(-2, 0, -4), "shooter")
	var targets: Array = scene.get_training_targets()
	for enemy in targets:
		enemy.set_training_bot_enabled(false)
		enemy.combat_state.max_health = 10000.0
		enemy.reset_combat_state()
	player.set_training_options(false, false, false)
	player.combat_state.health = 1000.0
	var bot_a: Node = targets[0].get_node("TrainingBot")
	var bot_b: Node = targets[1].get_node("TrainingBot")
	bot_a._spawn_attack_visual(player, "same_serial:1")
	bot_b._spawn_attack_visual(player, "same_serial:1")
	scene._pause_run()
	await create_timer(0.4).timeout
	check(is_equal_approx(player.get_health(), 1000.0), "projectiles ennemis suspendus pendant la pause")
	scene._resume_run()
	await create_timer(0.5).timeout
	check(is_equal_approx(player.get_health(), 1000.0 - bot_a.training_attack_damage - bot_b.training_attack_damage), "attaques simultanées de deux ennemis comptent séparément")
	player.set_training_options(true, false, false)
	var build := {"weapon": "blaster", "offensive": "modulo_drone", "defensive": "magnetic_field", "mobility": "pyro_boots", "passive": "", "evolutions": {}, "upgrades": {}}
	player.configure_survival_build(build)
	var synergy: Node = player.survival_synergies
	check(SYNERGIES.active_for(build).size() == 2, "deux synergies automatiques pour ce build")
	check(SYNERGIES.active_for({"weapon": "blaster"}).is_empty(), "aucune synergie avec un seul élément")
	check(SYNERGIES.preview({"weapon": "blaster"}, {"category": "mobility", "kind": "item", "id": "pyro_boots"}).contains("thermique"), "carte annonce la synergie qui sera activée")
	synergy.pyro_step(targets[0].global_position)
	synergy._physics_process(0.02)
	check(synergy.marked.has(targets[0].get_instance_id()), "traînée Pyro marque la cible")
	var before: float = targets[1].get_health()
	synergy.blaster_hit(targets[0], 0.2)
	check(is_equal_approx(targets[1].get_health(), before), "tir non chargé ne déclenche pas la détonation")
	player.aim_direction = Vector3.FORWARD
	player._fire_blaster_projectile(10.0, 1.0, Vector3.FORWARD)
	await create_timer(0.6).timeout
	check(targets[1].get_health() < before, "impact chargé réel provoque une explosion sur cible brûlée")
	synergy.blaster_hit(targets[0], 1.0)
	before = targets[1].get_health()
	synergy.marked[targets[0].get_instance_id()] = synergy.clock + 2.0
	synergy.blaster_hit(targets[0], 1.0)
	check(is_equal_approx(targets[1].get_health(), before), "explosion bornée sans boucle de déclenchement")
	# Actual drone crosses the player's own field before producing exactly one arc.
	synergy.clear_effects()
	player.set_touch_aim_vector(Vector2.UP)
	var field_action: int = player._try_begin_module_action("magnetic_field")
	check(field_action != 0, "le champ réserve l'action offensive")
	player._module_busy = true
	player._create_magnetic_wall(player._module_token, field_action, Vector3(0, 0, -2), Vector3.FORWARD)
	await physics_frame
	check(synergy.crosses_field(Vector3.ZERO, Vector3(0, 0, -4)), "intersection géométrique du champ reconnue")
	check(not synergy.crosses_field(Vector3(8, 0, 0), Vector3(8, 0, -4)), "tir à côté du champ non chargé")
	before = targets[1].get_health()
	var third_before: float = targets[2].get_health()
	var drone_action: int = player._try_begin_module_action("modulo_drone")
	check(drone_action != 0, "le drone réserve l'action offensive")
	player._module_busy = true
	player._module_token += 1
	player._emit_modulo_drone(player._module_token, drone_action, Vector3.ZERO, Vector3.FORWARD)
	await create_timer(0.7).timeout
	check(targets[1].get_health() < before, "drone traverse son propre champ et produit l'arc")
	check(is_equal_approx(targets[2].get_health(), third_before), "un seul rebond électrique sans évolution")
	# Shotgun echo is a separate, weaker damage source and costs no cartridge.
	build.weapon = "shotgun"
	build.mobility = "bio_injector"
	build.offensive = "javelin"
	build.defensive = "static_shield"
	player.configure_survival_build(build)
	player.set_touch_aim_vector(Vector2.UP)
	player._perform_bio_injector()
	check(synergy.armed, "injecteur arme Double détente")
	await physics_frame
	var ammo: int = player._shotgun_ammo
	player._perform_shotgun_attack()
	await create_timer(0.7).timeout
	check(player._shotgun_ammo == ammo - 1, "double salve consomme une seule cartouche")
	check(not synergy.armed and float(scene.stats.damage.get("double", 0)) > 0, "double salve effective et armement consommé")
	check(not synergy.consume_double(), "un seul double tir par activation")
	# Recast Javelin creates a persistent, bounded burning line.
	build.mobility = "pyro_boots"
	player.configure_survival_build(build)
	targets[0].apply_javelin_mark(4.0)
	player._javelin_mark_target = targets[0]
	player._recast_javelin()
	check(synergy.zones.size() > 1, "téléportation réelle laisse une ligne brûlante")
	synergy._physics_process(0.02)
	check(synergy.marked.has(targets[0].get_instance_id()), "ennemi dans le sillage brûlé")
	var zone_position: Vector3 = synergy.zones[0].visual.global_position
	player.global_position += Vector3(5, 0, 0)
	check(synergy.zones[0].visual.global_position.is_equal_approx(zone_position), "traînée ancrée au sol quand le joueur bouge")
	synergy._physics_process(5.0)
	check(synergy.zones.is_empty(), "traînées expirent")
	# Elite variants, boss second phase, and late-wave population.
	scene._clear_enemies()
	scene.wave = 3
	scene._spawn_enemy(Vector3.ZERO, "charger")
	var elite: Node3D = scene._enemies[0]
	var bot: Node = elite.get_node("TrainingBot")
	check(bot.survival_elite == "double_charge", "élite double charge vague 3")
	elite.set_training_bot_enabled(false)
	player.global_position = Vector3(0, 0, -4)
	bot._attack_action_token = bot._action_gate.try_acquire(ACTION_GATE.Kind.WEAPON, "survival_attack")
	check(bot._attack_action_token != 0, "la charge d'élite réserve l'action d'attaque")
	bot._double_charge_pending = true
	bot._charge_target = elite.global_position
	bot._charge_remaining = 0.01
	bot._update_survival_bot(elite, player, 0.02)
	check(bot._windup_remaining > 0.5 and not bot._double_charge_pending, "seconde charge précédée d'une nouvelle annonce")
	scene._clear_enemies()
	scene.wave = 6
	scene._spawn_enemy(Vector3.ZERO, "shooter")
	check(scene._enemies[0].get_node("TrainingBot").survival_elite == "spread", "élite éventail vague 6")
	scene._clear_enemies()
	scene.wave = 9
	scene._spawn_enemy(Vector3.ZERO, "chaser")
	elite = scene._enemies[0]
	elite.set_training_bot_enabled(false)
	elite.set_meta("shield_facing", Vector3.FORWARD)
	player.global_position = Vector3(0, 0, -4)
	var front: float = elite.take_damage(100.0, "player", "shield_front")
	player.global_position = Vector3(0, 0, 4)
	var rear: float = elite.take_damage(100.0, "player", "shield_rear")
	check(is_equal_approx(front, 45.0) and is_equal_approx(rear, 100.0), "bouclier réduit les tirs de face et permet le contournement")
	scene._clear_enemies()
	scene.wave = 11
	scene._start_wave()
	scene._begin_wave_combat()
	scene._spawn_reinforcements()
	check(scene._enemies.size() == 10, "dix ennemis à la dernière vague")
	var boss: Node3D = scene._enemies.back()
	bot = boss.get_node("TrainingBot")
	boss.combat_state.health = boss.combat_state.max_health * 0.5
	bot._update_survival_bot(boss, player, 0.01)
	check(bot.boss_phase_two and is_equal_approx(bot.training_attack_interval, 1.8), "boss accélère à mi-vie avec récupération")
	# Effective damage caps overkill; healing caps overflow; result stays frozen.
	var measured := STATS.new()
	var health := preload("res://scripts/combat_state.gd").new(100.0)
	health.damage_applied.connect(measured.record_damage)
	health.healing_applied.connect(measured.record_heal)
	health.apply_damage(25.0, "player", "blaster:1")
	health.heal(150.0, "repair_pickup")
	health.apply_damage(1000.0, "player", "blaster:2")
	check(is_equal_approx(measured.damage.blaster, 125.0) and is_equal_approx(measured.healing.repair_pickup, 25.0), "statistiques excluent sur-dégâts et sur-soins")
	measured.snapshot(false, 3, build)
	measured.record_damage(100.0, "player", "blaster:3")
	check(is_equal_approx(measured.damage.blaster, 125.0), "bilan figé après fin de partie")
	scene._show_result(false)
	check(scene.summary.result.build == scene.progression.build(), "bilan reprend le build réel")
	scene.summary._save_favorite()
	var saved := STATS.read_records(scene.records_path)
	check(saved.favorite_build.weapon == "blaster" and int(saved.last_run.wave) == 12, "favori et dernière partie persistés localement")
	paused = false
	scene.queue_free()
	current_scene = null
	await process_frame
	for failure in failures:
		push_error(failure)
	print("SURVIVAL EXPANSION TEST: %s (%d échecs)" % ["PASS" if failures.is_empty() else "FAIL", failures.size()])
	quit(0 if failures.is_empty() else 1)
