extends SceneTree

const ASPECTS := preload("res://scripts/survival_aspects.gd")
const PROGRESSION := preload("res://scripts/survival_progression.gd")
var failures: Array[String] = []
var scene: Node3D
var player: Node3D
var targets: Array
var effects: Node
var attack_serial := 0

func check(value: bool, message: String) -> void:
	if not value:
		failures.append(message)

func configure(item: String, category: String, aspect: String, level: int = 3) -> void:
	var build := {"weapon": "blaster", "offensive": "modulo_drone", "defensive": "static_shield", "mobility": "pyro_boots", "passive": "", "upgrades": {}, "evolutions": {}, "synergies": [], "aspects": {category: {"path": aspect, "rank": level}}}
	build[category] = item
	player.configure_survival_build(build)
	player.set_gameplay_enabled(true)
	player.combat_state.reset()
	player.passive_state.reset()
	player.global_position = Vector3.ZERO
	player.aim_direction = Vector3.FORWARD
	player.set_physics_process(false)
	effects = player.survival_evolution_effects
	for index in range(targets.size()):
		var enemy: Node3D = targets[index]
		enemy.combat_state.max_health = 10000.0
		enemy.reset_combat_state()
		enemy.set_training_bot_enabled(false)
		enemy.global_position = [Vector3(0, 0, -3), Vector3(0, 0, -5), Vector3(2, 0, -4), Vector3(-2, 0, -4)][index]
	for projectile in get_nodes_in_group("prototype0_gameplay_projectiles"):
		projectile.queue_free()

func tick(seconds: float) -> void:
	await create_timer(seconds, false).timeout

func hit(amount: float) -> float:
	attack_serial += 1
	return player.take_damage(amount, "test", "aspect_hit:%d" % attack_serial)

func _initialize() -> void:
	scene = load("res://scenes/survival.tscn").instantiate()
	scene.records_path = "res://.godot/aspect_test_records.json"
	root.add_child(scene)
	current_scene = scene
	await physics_frame
	scene._choose_weapon("blaster")
	scene._begin_wave_combat()
	scene._clear_enemies()
	await physics_frame
	player = scene.player
	player.set_robot("polyvalent")
	for at in [Vector3(0, 0, -3), Vector3(0, 0, -5), Vector3(2, 0, -4), Vector3(-2, 0, -4)]:
		scene._spawn_enemy(at, "shooter")
	targets = scene.get_training_targets()
	# Every equipment exposes two distinct paths, then only its chosen path.
	for item in ASPECTS.PATHS:
		var category: String = "weapon" if item in ["shotgun", "blaster"] else "offensive" if item in ["javelin", "modulo_drone"] else "defensive" if item in ["static_shield", "magnetic_field"] else "mobility" if item in ["pyro_boots", "bio_injector"] else "passive"
		check(ASPECTS.choices({}, category, item).size() == 2, "%s possède deux voies" % item)
		for aspect in ASPECTS.PATHS[item]:
			for level in range(1, 4):
				configure(item, category, aspect, level)
				await physics_frame
				check(player._active_muzzle().find_child("Aspect_" + aspect, true, false) != null if category == "weapon" else player._robot_visuals.find_child("Aspect_" + aspect, true, false) != null, "%s palier %d possède un ajout visuel" % [aspect, level])
				var next := ASPECTS.choices(effects.build, category, item)
				check(next.is_empty() if level == 3 else next.size() == 1 and next[0].path == aspect and next[0].rank == level + 1, "%s progression verrouillée et terminée au troisième palier" % aspect)
	# Reward validity, independent power and no repeat of the same power card.
	var progression := PROGRESSION.new()
	progression.choose_weapon("blaster")
	for wave in range(1, 12):
		var offer := progression.reward_choices(wave)
		var card: Dictionary = offer[0]
		for candidate in offer:
			if candidate.kind == "evolution":
				card = candidate
		var power_before: int = progression.upgrades.weapon.power
		check(progression.apply_reward(wave, card), "choix valide vague %d" % wave)
		check(not progression.apply_reward(wave, card), "un seul choix par vague")
		if card.kind == "evolution":
			check(progression.upgrades.weapon.power == power_before, "évolution indépendante de la puissance")
	# Charged rail really damages the aligned rear target; normal shots do not.
	configure("blaster", "weapon", "rail")
	# This harness disables Player physics, so prepare its real aim/idle pose
	# explicitly and let the warm-up transition settle before muzzle-based shots.
	player._begin_weapon_aim()
	player._update_aim_pose_state(true)
	for settle_frame in 90:
		player._visual_rig.update_visual_state(Vector3.ZERO, Vector3.FORWARD, 0.0, player.move_speed, 1.0 / 60.0)
		await physics_frame
	check(player._visual_rig.is_aim_pose_committed(), "visée préparée avant les tirs du Perforateur")
	var before: float = targets[1].get_health()
	var front_before: float = targets[0].get_health()
	player._fire_blaster_projectile(50.0, 0.0, Vector3.FORWARD)
	await tick(0.4)
	check(targets[0].get_health() < front_before, "tir normal atteint la cible avant du Perforateur")
	check(is_equal_approx(targets[1].get_health(), before), "Perforateur réservé aux tirs chargés")
	front_before = targets[0].get_health()
	player._blaster_next_attack_ready_at = -1.0
	player._fire_blaster_projectile(50.0, 1.0, Vector3.FORWARD)
	await tick(0.4)
	check(targets[0].get_health() < front_before, "tir chargé atteint la cible avant du Perforateur")
	check(targets[1].get_health() < before, "rayon chargé atteint la cible arrière")
	var cover := StaticBody3D.new()
	cover.collision_layer = 1
	var cover_shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(2.0, 2.0, 0.3)
	cover_shape.shape = box
	cover.add_child(cover_shape)
	scene.add_child(cover)
	cover.global_position = Vector3(0, 1, -4)
	await physics_frame
	before = targets[1].get_health()
	player._blaster_next_attack_ready_at = -1.0
	player._fire_blaster_projectile(50.0, 1.0, Vector3.FORWARD)
	await tick(0.4)
	check(is_equal_approx(targets[1].get_health(), before), "rayon perforant arrêté par un couvert")
	cover.queue_free()
	await physics_frame
	configure("blaster", "weapon", "arc")
	await physics_frame
	player._fire_blaster_projectile(50.0, 1.0, Vector3.FORWARD)
	await tick(0.4)
	before = targets[2].get_health()
	check(not effects.arc_marks.is_empty(), "tir chargé marque le conducteur")
	player._blaster_next_attack_ready_at = -1.0
	player._fire_blaster_projectile(20.0, 0.0, Vector3.FORWARD)
	await tick(0.4)
	check(targets[2].get_health() < before, "tir normal sur conducteur produit les rebonds")
	configure("shotgun", "weapon", "breaker")
	await physics_frame
	before = targets[1].get_health()
	player._perform_shotgun_attack()
	await tick(0.35)
	check(targets[1].get_health() < before, "Bélier ouvre un couloir traversant")
	configure("shotgun", "weapon", "sweeper")
	check(player._shotgun_pellet_angles.size() == 12, "Éventail ultime contient douze plombs")
	check(is_equal_approx(player._shotgun_pellet_damage * 12.0, 6.0 * 20.0 * 0.65), "Éventail répartit les dégâts sans doubler la puissance")
	# Drones are deployed through the normal action and really shoot.
	for aspect in ["hunter", "sentry"]:
		configure("modulo_drone", "offensive", aspect)
		await physics_frame
		before = targets[0].get_health()
		player._perform_modulo_drone()
		await tick(1.3)
		check(not effects.agents.is_empty() and targets[0].get_health() < before, "%s déployé et offensif" % aspect)
	# Harpoon recall damages without moving the player; elites cannot be stunned.
	configure("javelin", "offensive", "harpoon")
	await physics_frame
	player._perform_javelin()
	await tick(0.6)
	check(effects.has_javelin_anchor() and targets[0].combat_state.is_stunned(), "Harpon cloue un ennemi léger")
	before = targets[0].get_health()
	player._perform_javelin()
	check(player.global_position.is_zero_approx() and targets[0].get_health() < before, "rappel du Harpon blesse sans téléportation")
	targets[0].get_node("TrainingBot").survival_role = "boss"
	targets[0].combat_state.reset()
	effects.javelin_hit(targets[0], targets[0].global_position)
	check(not targets[0].combat_state.is_stunned() and targets[0].combat_state.get_slow_percent() > 0.0, "Harpon ralentit le boss sans l'immobiliser")
	targets[0].get_node("TrainingBot").survival_role = "shooter"
	configure("javelin", "offensive", "beacon")
	player.aim_direction = Vector3.RIGHT
	await physics_frame
	player._perform_javelin()
	await tick(0.3)
	check(effects.has_javelin_anchor(), "Balise posée sur le sol libre")
	var destination: Vector3 = effects.javelin_anchor
	targets[0].global_position = destination
	await physics_frame
	player._perform_javelin()
	check(player.global_position.is_zero_approx() and effects.has_javelin_anchor(), "Balise refuse une destination occupée")
	targets[0].global_position = Vector3(0, 0, -3)
	await physics_frame
	player._perform_javelin()
	check(player.global_position.is_equal_approx(destination), "second appui rejoint la Balise")
	# Both shield paths preserve movement and attacks, with finite absorption.
	configure("static_shield", "defensive", "carapace")
	player._perform_static_shield()
	check(player._stasis_remaining == 0.0 and player.get_current_move_speed() > 0.0, "Carapace ne déclenche pas de stase")
	await physics_frame
	before = targets[0].get_health()
	player._fire_blaster_projectile(20.0, 0.0, Vector3.FORWARD)
	await tick(0.4)
	check(targets[0].get_health() < before and effects.shield_remaining > 0.0, "tir réel possible pendant le bouclier")
	before = player.get_health()
	hit(30.0)
	check(player.get_health() == before, "Carapace absorbe les premiers dégâts")
	var remaining: float = effects.shield_health
	hit(remaining + 20.0)
	check(is_equal_approx(player.get_health(), before - 20.0) and effects.shield_remaining == 0.0, "Carapace rompt et laisse passer le surplus")
	configure("static_shield", "defensive", "counter")
	await physics_frame
	before = targets[0].get_health()
	player._perform_static_shield()
	hit(60.0)
	await tick(1.0)
	check(targets[0].get_health() < before, "Riposte transforme les impacts en décharge visée")
	# Enemy projectiles charge the capacitor; wall crossing slows pursuers.
	configure("magnetic_field", "defensive", "capacitor")
	await physics_frame
	player._perform_magnetic_field()
	await tick(0.3)
	check(is_instance_valid(effects.wall), "Condensateur déployé")
	targets[0].get_node("TrainingBot")._spawn_attack_visual(player, "capacitor_enemy:1")
	await tick(0.5)
	check(effects.wall_energy > 0.0, "tir ennemi réellement absorbé et stocké")
	before = targets[0].get_health()
	player._perform_magnetic_field()
	check(targets[0].get_health() < before and effects.wall == null, "second appui décharge le Condensateur")
	configure("magnetic_field", "defensive", "rampart")
	await physics_frame
	player._perform_magnetic_field()
	await tick(0.3)
	targets[0].global_position = effects.wall.global_position
	await tick(0.1)
	check(targets[0].combat_state.get_slow_percent() > 0.0 and player._magnetic_width > 4.0, "Rempart large ralentit au passage")
	# Dash charges, persistent fire, injection bounds and interruption on damage.
	configure("pyro_boots", "mobility", "thruster")
	player._last_move_direction = Vector3.RIGHT
	player._perform_pyro_boots()
	player._cancel_dash()
	await physics_frame
	player._perform_pyro_boots()
	check(player.is_dash_active(), "deuxième dash disponible pendant la recharge")
	player._cancel_dash()
	await physics_frame
	player._perform_pyro_boots()
	check(not player.is_dash_active() and effects.dash_charges() == 0, "troisième dash refusé")
	configure("pyro_boots", "mobility", "trail")
	await physics_frame
	player._last_move_direction = Vector3.FORWARD
	player._perform_pyro_boots()
	player._update_dash(0.12)
	player._cancel_dash()
	check(not effects.zones.is_empty(), "dash laisse du feu au sol")
	targets[0].global_position = effects.zones[0].position
	before = targets[0].get_health()
	await tick(0.3)
	check(targets[0].get_health() < before, "feu persistant touche après le dash")
	configure("bio_injector", "mobility", "overdrive")
	player._perform_bio_injector()
	check(player.get_attack_speed_multiplier() > player._bio_attack_speed_multiplier, "Surcharge accélère tirs et recharge")
	for index in range(30):
		effects.damaged_targets[targets[0].get_instance_id()] = true
		effects.enemy_died(targets[0])
	check(player._bio_remaining <= 8.001 and player._bio_remaining > 3.0, "éliminations prolongent Survoltage jusqu'à huit secondes")
	configure("bio_injector", "mobility", "metabolism")
	player.combat_state.health = 500.0
	player._perform_bio_injector()
	player.velocity = Vector3.RIGHT
	await tick(0.3)
	check(player.get_health() > 500.0, "Métabolisme soigne en mouvement")
	hit(10.0)
	before = player.get_health()
	await tick(0.3)
	check(is_equal_approx(player.get_health(), before), "coup reçu suspend la régénération mobile")
	# Both Baroud paths can actually save a run, once, including versus a boss.
	configure("baroud", "passive", "revenge")
	player.set_physics_process(true)
	player.combat_state.health = 30.0
	hit(100.0)
	check(player.passive_state.baroud_active, "fatal déclenche Contre-attaque")
	targets[0].take_damage(180.0, "player", "revenge_damage:1")
	check(not player.passive_state.baroud_active and player.get_health() > 100.0 and player.passive_state.baroud_used, "dégâts effectifs sauvent Baroud et consomment le sauvetage")
	configure("baroud", "passive", "escape")
	player.set_physics_process(true)
	player.combat_state.health = 30.0
	hit(100.0)
	check(player.get_current_move_speed() > player.move_speed, "Repli vital accélère la fuite")
	hit(5000.0)
	check(player.passive_state.baroud_active, "courte protection permet le départ du repli")
	await tick(1.9)
	check(not player.passive_state.baroud_active and player.get_health() > 100.0, "fuite sans impact sauve Baroud")
	# Omnivamp counts effective damage, caps and decays reserve; harvest is attributed.
	configure("omnivamp", "passive", "reserve")
	targets[0].take_damage(2000.0, "player", "reserve_damage:1")
	check(effects.reserve > 0.0 and effects.reserve <= 145.0, "soins excédentaires deviennent une réserve bornée")
	before = effects.reserve
	await tick(0.3)
	check(effects.reserve < before, "réserve se dissipe")
	before = player.get_health()
	hit(20.0)
	check(player.get_health() == before, "réserve absorbe les dégâts")
	configure("omnivamp", "passive", "harvest")
	targets[0].take_damage(10.0, "player", "harvest_damage:1")
	effects.enemy_died(targets[0])
	effects.enemy_died(targets[1])
	check(effects.pickups.size() == 1, "fragment uniquement pour un ennemi blessé par le joueur")
	player.combat_state.health = 500.0
	await tick(0.9)
	check(player.get_health() > 500.0 and effects.pickups.is_empty(), "fragment attiré puis ramassé pour soigner")
	# Pause freezes effects and cleanup removes all persistent gameplay.
	configure("pyro_boots", "mobility", "trail")
	effects.pyro_step(Vector3.ZERO)
	var clock_before: float = effects.clock
	scene._pause_run()
	await create_timer(0.3, true).timeout
	check(is_equal_approx(effects.clock, clock_before) and effects.zones.size() == 1, "pause fige les effets persistants")
	scene._resume_run()
	effects.clear_transients()
	check(effects.zones.is_empty() and effects.agents.is_empty() and effects.pickups.is_empty() and effects.javelin_anchor == Vector3.INF, "nettoyage entre les vagues")
	player.apply_loadout({"weapon": "blaster", "defensive": "static_shield"})
	check(not player.survival_mode and player.survival_evolution_effects == null and player._blaster_damage == 20.0, "retour au Duel rétablit les valeurs et retire les aspects")
	player._perform_static_shield()
	check(player._stasis_remaining > 0.0, "bouclier de Duel garde sa stase")
	paused = false
	scene.queue_free()
	await process_frame
	for failure in failures:
		push_error(failure)
	print("SURVIVAL ASPECTS TEST: %s (%d échecs)" % ["PASS" if failures.is_empty() else "FAIL", failures.size()])
	quit(0 if failures.is_empty() else 1)
