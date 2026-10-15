extends SceneTree

const DATA := preload("res://scripts/combat_data.gd")
const STATE := preload("res://scripts/combat_state.gd")
const PASSIVE := preload("res://scripts/passive_state.gd")
const LONGSHOT := preload("res://scripts/longshot_state.gd")
const NETWORK := preload("res://scripts/network_combat_state.gd")
var failures: Array[String] = []
var checks := 0

func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures.append(label)

func _initialize() -> void:
	var fixture := Node.new()
	root.add_child(fixture)
	current_scene = fixture
	var blaster: Dictionary = DATA.WEAPON_DEFINITIONS.blaster
	var shotgun: Dictionary = DATA.WEAPON_DEFINITIONS.shotgun
	var melee: Dictionary = DATA.WEAPON_DEFINITIONS.mekatana
	var rifle: Dictionary = DATA.WEAPON_DEFINITIONS.longshot
	var combo := float(melee.base_damage[0]) + float(melee.base_damage[1]) * float(melee.second_bonus) + float(melee.base_damage[2]) * float(melee.third_full_bonus)
	var melee_cycle := 0.0
	for step in 3:
		melee_cycle += float(melee.preparation[step]) + float(melee.active[step]) + float(melee.recovery[step])
	var perfect_salvo := float(shotgun.pellets_per_shot) * float(shotgun.pellet_damage) * DATA.CRIT_MULTIPLIER
	var longshot_cycle := 2.0 * LONGSHOT.damage_at_distance(float(rifle.distance_max), false) + LONGSHOT.damage_at_distance(float(rifle.distance_max), true)
	# Ideal pressure before heat, in each specialist's range. Shotgun includes reload;
	# full salvos trigger its guaranteed crit. Burn is excluded because it refreshes.
	for tempo in [1.0, float(DATA.MODULE_DEFINITIONS.bio_injector.attack_speed_multiplier)]:
		# Bio accelerates specialist attacks; player Blaster keeps its own cadence.
		var reference: float = float(blaster.max_damage) / (float(blaster.charge_time) + float(blaster.cooldown))
		var rates := {
			"mekatana": combo * tempo / melee_cycle,
			"longshot": longshot_cycle * tempo / (3.0 * float(rifle.cooldown)),
			"shotgun": perfect_salvo * float(shotgun.magazine_size) / (float(shotgun.magazine_size) * (float(shotgun.attack_preparation) + float(shotgun.attack_recovery)) / tempo + float(shotgun.reload_duration)),
		}
		for weapon in rates:
			var rate: float = rates[weapon]
			check(rate >= reference and rate <= float(DATA.ROBOT_DEFINITIONS.agile.max_health) * 0.60, "%s rewards its preferred range while preserving reaction time (tempo %.1f)" % [weapon, tempo])
			print("BALANCE_RATE: %s tempo=%.1f damage_per_second=%.2f reference=%.2f" % [weapon, tempo, rate, reference])
	var punch: Dictionary = DATA.MODULE_DEFINITIONS.fulguro_punch
	var max_punch := float(punch.damage_max) + float(punch.wall_damage_max)
	var burn := DATA.BURN_DAMAGE_PER_SECOND * DATA.BURN_DURATION
	var agile_health: float = DATA.ROBOT_DEFINITIONS.agile.max_health
	for burst in [float(blaster.max_damage), perfect_salvo + burn, combo, LONGSHOT.damage_at_distance(float(rifle.distance_max), true), max_punch]:
		check(burst <= agile_health * 0.55, "one complete attack leaves a reaction window even on Agile")
	var boosted_shot := float(blaster.max_damage) * (1.0 + float(DATA.MODULE_DEFINITIONS.alternator.damage_bonus))
	for chassis in DATA.ROBOT_DEFINITIONS:
		var state := STATE.new(float(DATA.ROBOT_DEFINITIONS[chassis].max_health))
		state.apply_damage(max_punch, "opponent", "full_punch")
		state.apply_damage(boosted_shot, "opponent", "charged_alternator")
		check(not state.is_dead(), chassis + " survives a full wall punch followed by charged Alternator Blaster")
		state.reset()
		state.apply_damage(state.max_health * 0.5)
		check(is_equal_approx(state.heal(state.max_health * 0.30), state.max_health * 0.30), chassis + " repair kit still restores 30 percent")
		var replica := NETWORK.new()
		replica.authoritative = false
		replica.receive_snapshot(_snapshot(state))
		check(is_equal_approx(replica.max_health, state.max_health) and is_equal_approx(replica.health, state.health), chassis + " authoritative health survives replication")
	for module in ["permutation", "eclipse"]:
		var shield: float = DATA.MODULE_DEFINITIONS[module].shield_amount
		check(shield >= DATA.MAX_HEALTH * 0.15, module + " protection keeps pace with chassis health")
	var last_chance := PASSIVE.new()
	last_chance.configure("baroud")
	last_chance.intercept_damage(DATA.MAX_HEALTH * 2.0, DATA.MAX_HEALTH)
	last_chance.process(PASSIVE.BAROUD_DURATION * 0.5)
	check(last_chance.baroud_active and is_equal_approx(last_chance.baroud_health, PASSIVE.BAROUD_MAX_HEALTH * 0.5), "Baroud keeps its full gauge and 2.5-second decay")
	last_chance.process(PASSIVE.BAROUD_DURATION * 0.5)
	check(last_chance.real_dead, "larger Baroud gauge cannot extend the last chance")
	for failure in failures:
		push_error(failure)
	print("COMBAT BALANCE: %s (%d checks)" % ["PASS" if failures.is_empty() else "FAIL", checks])
	quit(0 if failures.is_empty() else 1)

func _snapshot(state: RefCounted) -> Dictionary:
	var host := NETWORK.new(state.max_health)
	host.health = state.health
	return host.snapshot()
