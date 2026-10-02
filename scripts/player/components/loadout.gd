extends Node

# Weapon definitions, equipment, Survival builds and training settings.
# Player owns shared state and keeps the scene/network API.

const PLAYER_STATE := preload("res://scripts/player/components/player_state.gd")

var player: PLAYER_STATE


func _init(controller: PLAYER_STATE) -> void:
	player = controller
	name = "LoadoutComponent"


func _load_weapon_definitions() -> void:
	player._rocket_damage_multiplier = 1.0
	player._mekatana_attack.definition = PLAYER_STATE.COMBAT_DATA.WEAPON_DEFINITIONS["mekatana"].duplicate(true)
	player._longshot_definition = PLAYER_STATE.COMBAT_DATA.WEAPON_DEFINITIONS["longshot"].duplicate(true)
	var blaster_definition: Dictionary = PLAYER_STATE.COMBAT_DATA.WEAPON_DEFINITIONS.get("blaster", {})
	player._blaster_damage = float(blaster_definition.get("damage", player._blaster_damage))
	player._blaster_max_damage = float(blaster_definition.get("max_damage", player._blaster_max_damage))
	player._blaster_cooldown = float(blaster_definition.get("cooldown", player._blaster_cooldown))
	player._blaster_charge_time = float(blaster_definition.get("charge_time", player._blaster_charge_time))
	player._blaster_max_range = float(blaster_definition.get("max_range", player._blaster_max_range))
	player._blaster_projectile_speed = float(blaster_definition.get("projectile_speed", player._blaster_projectile_speed))
	player._blaster_charge_slow_multiplier = float(blaster_definition.get("charge_slow_multiplier", player._blaster_charge_slow_multiplier))
	player._blaster_projectile_radius = float(blaster_definition.get("projectile_radius", player._blaster_projectile_radius))
	var shotgun_definition: Dictionary = PLAYER_STATE.COMBAT_DATA.WEAPON_DEFINITIONS.get("shotgun", {})
	player._shotgun_pellet_angles = shotgun_definition.get("pellet_angles", player._shotgun_pellet_angles)
	player._shotgun_pellet_speed = float(shotgun_definition.get("pellet_speed", player._shotgun_pellet_speed))
	player._shotgun_max_range = float(shotgun_definition.get("max_range", player._shotgun_max_range))
	player._shotgun_falloff_start = float(shotgun_definition.get("falloff_start", player._shotgun_falloff_start))
	player._shotgun_pellet_damage = float(shotgun_definition.get("pellet_damage", player._shotgun_pellet_damage))
	player._shotgun_minimum_damage = float(shotgun_definition.get("minimum_damage", player._shotgun_minimum_damage))
	player._shotgun_hitbox_radius = float(shotgun_definition.get("hitbox_radius", player._shotgun_hitbox_radius))
	player._shotgun_preparation = float(shotgun_definition.get("attack_preparation", player._shotgun_preparation))
	player._shotgun_recovery = float(shotgun_definition.get("attack_recovery", player._shotgun_recovery))
	player._shotgun_magazine_size = int(shotgun_definition.get("magazine_size", player._shotgun_magazine_size))
	player._shotgun_ammo = player._shotgun_magazine_size
	player._shotgun_reload_duration = float(shotgun_definition.get("reload_duration", player._shotgun_reload_duration))
	var javelin_definition: Dictionary = PLAYER_STATE.COMBAT_DATA.MODULE_DEFINITIONS.get("javelin", {})
	player._javelin_preparation = float(javelin_definition.get("preparation", player._javelin_preparation))
	player._javelin_max_range = float(javelin_definition.get("max_range", player._javelin_max_range))
	player._javelin_speed = float(javelin_definition.get("speed", player._javelin_speed))
	player._javelin_damage = float(javelin_definition.get("damage", player._javelin_damage))
	player._javelin_mark_duration = float(javelin_definition.get("mark_duration", player._javelin_mark_duration))
	player._javelin_teleport_distance = float(javelin_definition.get("teleport_distance", player._javelin_teleport_distance))
	player._javelin_collision_radius = float(javelin_definition.get("collision_radius", player._javelin_collision_radius))
	var fulguro_definition: Dictionary = PLAYER_STATE.COMBAT_DATA.MODULE_DEFINITIONS.get("fulguro_punch", {})
	player._fulguro_preparation = float(fulguro_definition.get("charge_min", fulguro_definition.get("preparation", player._fulguro_preparation)))
	player._fulguro_charge_max = float(fulguro_definition.get("charge_max", player._fulguro_charge_max))
	player._fulguro_range = float(fulguro_definition.get("range_min", fulguro_definition.get("range", player._fulguro_range)))
	player._fulguro_range_max = float(fulguro_definition.get("range_max", player._fulguro_range_max))
	player._fulguro_width = float(fulguro_definition.get("width", player._fulguro_width))
	player._fulguro_active_window = float(fulguro_definition.get("active_window", player._fulguro_active_window))
	player._fulguro_recovery = float(fulguro_definition.get("recovery", player._fulguro_recovery))
	player._fulguro_damage = float(fulguro_definition.get("damage_min", fulguro_definition.get("damage", player._fulguro_damage)))
	player._fulguro_damage_max = float(fulguro_definition.get("damage_max", player._fulguro_damage_max))
	player._fulguro_wall_damage = float(fulguro_definition.get("wall_damage_min", fulguro_definition.get("wall_damage", player._fulguro_wall_damage)))
	player._fulguro_wall_damage_max = float(fulguro_definition.get("wall_damage_max", player._fulguro_wall_damage_max))
	player._fulguro_wall_stun = float(fulguro_definition.get("wall_stun", player._fulguro_wall_stun))
	var pelto_definition: Dictionary = PLAYER_STATE.COMBAT_DATA.MODULE_DEFINITIONS.get("pelto_smash", {})
	player._pelto_damage_multiplier = 1.0
	player._pelto_preparation = float(pelto_definition.get("preparation", player._pelto_preparation))
	player._pelto_impact_duration = float(pelto_definition.get("impact_duration", player._pelto_impact_duration))
	player._pelto_recovery = float(pelto_definition.get("recovery", player._pelto_recovery))
	var bio_definition: Dictionary = PLAYER_STATE.COMBAT_DATA.MODULE_DEFINITIONS.get("bio_injector", {})
	player._bio_speed_multiplier = float(bio_definition.get("speed_multiplier", player._bio_speed_multiplier))
	player._bio_attack_speed_multiplier = float(bio_definition.get("attack_speed_multiplier", player._bio_attack_speed_multiplier))
	player._bio_other_cooldown_rate = float(bio_definition.get("other_cooldown_rate", player._bio_other_cooldown_rate))
	var magnetic_definition: Dictionary = PLAYER_STATE.COMBAT_DATA.MODULE_DEFINITIONS.get("magnetic_field", {})
	player._magnetic_preparation = float(magnetic_definition.get("preparation", player._magnetic_preparation))
	player._magnetic_distance = float(magnetic_definition.get("distance", player._magnetic_distance))
	player._magnetic_width = float(magnetic_definition.get("width", player._magnetic_width))
	player._magnetic_height = float(magnetic_definition.get("height", player._magnetic_height))
	player._magnetic_duration = float(magnetic_definition.get("duration", player._magnetic_duration))
	var static_definition: Dictionary = PLAYER_STATE.COMBAT_DATA.MODULE_DEFINITIONS.get("static_shield", {})
	player._static_duration = float(static_definition.get("duration", player._static_duration))


func apply_loadout(next_loadout: Dictionary) -> void:
	if player.passive_state != null:
		player.passive_state.clear_triggers()
	if player._counter != null:
		player._counter.cancel(true)
	player._eclipse.cancel(player)
	player._clear_permutation()
	player._cancel_mekatana_attack()
	player.reset_longshot_state()
	if player.survival_evolution_effects != null:
		player.survival_evolution_effects.clear_transients()
		player.survival_evolution_effects.queue_free()
		player.survival_evolution_effects = null
	if player.survival_synergies != null:
		player.survival_synergies.configure({})
	player.survival_mode = false
	player._survival_evolutions = {"weapon": false, "offensive": false, "defensive": false, "mobility": false, "passive": false}
	player.set_robot(str(next_loadout.get("robot", PLAYER_STATE.COMBAT_DATA.DEFAULT_ROBOT)))
	player._survival_cooldown_multipliers = {"offensive": 1.0, "defensive": 1.0, "mobility": 1.0}
	player._survival_dash_multiplier = 1.0
	player._load_weapon_definitions()
	if player.passive_state != null:
		player.passive_state.baroud_max_health = PLAYER_STATE.PASSIVE_STATE.BAROUD_MAX_HEALTH
		player.passive_state.baroud_duration = PLAYER_STATE.PASSIVE_STATE.BAROUD_DURATION
		player.passive_state.omnivamp_rate = PLAYER_STATE.PASSIVE_STATE.OMNIVAMP_RATE
	var weapon_id := str(next_loadout.get("weapon", "blaster"))
	var offensive_id := str(next_loadout.get("offensive", "javelin"))
	var defensive_id := str(next_loadout.get("defensive", "magnetic_field"))
	var mobility_id := str(next_loadout.get("mobility", "pyro_boots"))
	var passive_id := str(next_loadout.get("passive", "baroud"))
	player._offensive_module_id = offensive_id if offensive_id in ["rocket_basket", "javelin", "fulguro_punch", "pelto_smash"] else "javelin"
	player._defensive_module_id = defensive_id if defensive_id in ["magnetic_field", "static_shield", "projector", "counter"] else "magnetic_field"
	player._mobility_module_id = mobility_id if mobility_id in ["pyro_boots", "bio_injector", "permutation", "eclipse"] else "pyro_boots"
	player.set_passive(passive_id)
	player.cancel_touch_fire()
	player.reset_shotgun_state()
	player._weapon_id = weapon_id if PLAYER_STATE.COMBAT_DATA.WEAPON_DEFINITIONS.has(weapon_id) else "blaster"
	player._update_weapon_visuals()
	player._sync_weapon_readout()


func set_robot(identifier: String) -> void:
	player._robot_id = identifier if PLAYER_STATE.COMBAT_DATA.ROBOT_DEFINITIONS.has(identifier) else PLAYER_STATE.COMBAT_DATA.DEFAULT_ROBOT
	if player._visual_rig != null:
		player._visual_rig.set_chassis_appearance(player._robot_id)
	var definition: Dictionary = PLAYER_STATE.COMBAT_DATA.ROBOT_DEFINITIONS[player._robot_id]
	player.move_speed = float(definition.move_speed)
	if player.combat_state != null:
		var health_ratio: float = player.combat_state.health / maxf(1.0, player.combat_state.max_health)
		player.combat_state.max_health = float(definition.max_health)
		player.combat_state.health = clampf(health_ratio, 0.0, 1.0) * player.combat_state.max_health
		player.combat_state.health_changed.emit(player.combat_state.health, player.combat_state.max_health)


func get_robot_id() -> String:
	return player._robot_id


func configure_survival_build(build: Dictionary) -> void:
	if player.survival_synergies == null:
		player.survival_synergies = preload("res://scripts/survival_synergies.gd").new()
		player.survival_synergies.player = player
		player.add_child(player.survival_synergies)
	player.survival_synergies.configure(build)
	player._load_weapon_definitions()
	player.survival_mode = true
	player._survival_evolutions = build.get("evolutions", {}).duplicate(true)
	player._weapon_id = str(build.get("weapon", "blaster"))
	player._offensive_module_id = str(build.get("offensive", ""))
	player._defensive_module_id = str(build.get("defensive", ""))
	player._mobility_module_id = str(build.get("mobility", ""))
	player.set_passive(str(build.get("passive", "")))
	var ranks: Dictionary = build.get("upgrades", {})
	var weapon_ranks: Dictionary = ranks.get("weapon", {})
	var weapon_power := 0.65 + 0.60 * int(weapon_ranks.get("power", 0))
	var weapon_tempo := 1.20 * pow(0.72, int(weapon_ranks.get("tempo", 0)))
	for rank in range(3):
		player._mekatana_attack.definition.base_damage[rank] *= weapon_power
		player._mekatana_attack.definition.recovery[rank] *= weapon_tempo
	player._blaster_damage *= weapon_power
	player._blaster_max_damage *= weapon_power
	player._blaster_cooldown *= weapon_tempo
	# Survival needs a reliable ranged opening alongside the close-range shotgun.
	player._blaster_damage *= 1.6
	player._blaster_max_damage *= 2.0
	player._blaster_cooldown *= 0.82
	player._blaster_charge_time *= 0.70
	player._blaster_charge_slow_multiplier = 1.0
	player._blaster_projectile_speed *= 1.35
	player._shotgun_pellet_damage *= weapon_power
	player._shotgun_minimum_damage *= weapon_power
	player._shotgun_recovery *= weapon_tempo
	player._shotgun_reload_duration *= weapon_tempo
	player._longshot_definition["damage"] = float(player._longshot_definition["damage"]) * weapon_power
	player._longshot_definition["cooldown"] = float(player._longshot_definition["cooldown"]) * weapon_tempo
	player._longshot_definition["attack_preparation"] = float(player._longshot_definition["attack_preparation"]) * weapon_tempo
	if int(build.get("aspects", {}).get("weapon", {}).get("rank", 0)) == 0 and bool(player._survival_evolutions.get("weapon", false)) and player._weapon_id == "shotgun":
		player._shotgun_pellet_angles = [-16.0, -12.0, -8.0, -4.0, 4.0, 8.0, 12.0, 16.0]
	var offensive_ranks: Dictionary = ranks.get("offensive", {})
	var offensive_power := 0.65 + 0.60 * int(offensive_ranks.get("power", 0))
	player._rocket_damage_multiplier = offensive_power
	player._javelin_damage *= offensive_power
	player._fulguro_damage *= offensive_power
	player._fulguro_wall_damage *= offensive_power
	player._pelto_damage_multiplier = offensive_power
	var defensive_ranks: Dictionary = ranks.get("defensive", {})
	var defensive_power := 0.70 + 0.55 * int(defensive_ranks.get("power", 0))
	player._magnetic_duration *= defensive_power
	player._static_duration *= defensive_power
	var mobility_ranks: Dictionary = ranks.get("mobility", {})
	var mobility_power := 0.70 + 0.55 * int(mobility_ranks.get("power", 0))
	player._survival_dash_multiplier = mobility_power
	player._bio_speed_multiplier = 1.0 + 0.40 * mobility_power
	player._bio_attack_speed_multiplier = 1.0 + 0.50 * mobility_power
	var passive_ranks: Dictionary = ranks.get("passive", {})
	var passive_power := 0.65 + 0.60 * int(passive_ranks.get("power", 0))
	if player.combat_state != null:
		player.combat_state.max_health = float(PLAYER_STATE.COMBAT_DATA.ROBOT_DEFINITIONS[player._robot_id].max_health) + 250.0 * int(passive_ranks.get("tempo", 0))
		player.combat_state.health_changed.emit(player.combat_state.health, player.combat_state.max_health)
	if player.passive_state != null:
		player.passive_state.baroud_max_health = PLAYER_STATE.PASSIVE_STATE.BAROUD_MAX_HEALTH * passive_power
		player.passive_state.baroud_duration = PLAYER_STATE.PASSIVE_STATE.BAROUD_DURATION * passive_power
		player.passive_state.omnivamp_rate = PLAYER_STATE.PASSIVE_STATE.OMNIVAMP_RATE * passive_power
		# These new passives begin at their catalog values; existing survival
		# power rewards improve potency without changing timing or attack counts.
		var potency := 1.0 + 0.60 * int(passive_ranks.get("power", 0))
		match player._passive_id:
			"auxiliary_reactor": player.passive_state.tuning.reduction *= potency
			"tracker": player.passive_state.tuning.duration *= potency
			"alternator": player.passive_state.tuning.damage_bonus *= potency
			"inertia": player.passive_state.tuning.slow_percent *= potency
	player._survival_cooldown_multipliers = {
		"offensive": 1.25 * pow(0.65, int(offensive_ranks.get("tempo", 0))),
		"defensive": 1.25 * pow(0.65, int(defensive_ranks.get("tempo", 0))),
		"mobility": 1.25 * pow(0.65, int(mobility_ranks.get("tempo", 0))),
	}
	player.reset_blaster_state()
	player.reset_shotgun_state()
	player.reset_module_state()
	player._reset_action_ownership()
	player._update_weapon_visuals()
	if player.survival_evolution_effects == null:
		player.survival_evolution_effects = preload("res://scripts/survival_evolution_effects.gd").new()
		player.survival_evolution_effects.player = player
		player.add_child(player.survival_evolution_effects)
	player.survival_evolution_effects.configure(build)
	player._sync_weapon_readout()


func set_training_options(invulnerable: bool, instant_cooldowns: bool, unlimited_ammo: bool) -> void:
	player.training_invulnerable = invulnerable
	player.training_instant_cooldowns = instant_cooldowns
	player.training_unlimited_ammo = unlimited_ammo
	if instant_cooldowns:
		player._module_cooldowns.clear()
		player._blaster_next_attack_ready_at = -10.0
	if unlimited_ammo:
		player._shotgun_ammo = player._shotgun_magazine_size
		player._shotgun_reloading = false
		player._shotgun_reload_remaining = 0.0
		if player._shotgun_reload_audio != null:
			player._shotgun_reload_audio.stop()


func set_training_health_ratio(ratio: float) -> void:
	if player.combat_state == null:
		return
	player.reset_combat_state()
	player.combat_state.health = clampf(ratio, 0.01, 1.0) * player.combat_state.max_health
	player.combat_state.health_changed.emit(player.combat_state.health, player.combat_state.max_health)


func shift_pause_timers(seconds: float) -> void:
	if seconds <= 0.0:
		return
	player._last_attack_time += seconds
	player._blaster_next_attack_ready_at += seconds
	player._longshot_next_attack_ready_at += seconds
	if player._combo_expires_at > 0.0:
		player._combo_expires_at += seconds
	if player._next_attack_ready_at > 0.0:
		player._next_attack_ready_at += seconds
	if player._javelin_mark_target != null and is_instance_valid(player._javelin_mark_target):
		if player._javelin_mark_target.has_method("shift_pause_timers"):
			player._javelin_mark_target.call("shift_pause_timers", seconds)


func set_weapon(weapon_id: String) -> void:
	if player.survival_mode:
		return
	if not PLAYER_STATE.COMBAT_DATA.WEAPON_DEFINITIONS.has(weapon_id):
		return
	if player._weapon_id == weapon_id:
		return
	player._cancel_mekatana_attack()
	player._cancel_longshot_attack()
	player.reset_blaster_state()
	player.reset_shotgun_state()
	if player.passive_state != null:
		player.passive_state.clear_triggers()
	player._weapon_id = weapon_id
	player._reset_weapon_pose_to_locomotion(true)
	player._update_weapon_visuals()
	player._sync_weapon_readout()
	if player._attack_label != null:
		player._attack_label.text = "ARME : BLASTER" if player._weapon_id == "blaster" else ""


func get_offensive_module_id() -> String:
	return player._offensive_module_id


func _cycle_offensive_module() -> void:
	var choices := ["rocket_basket", "javelin", "fulguro_punch", "pelto_smash"]
	player._offensive_module_id = choices[(choices.find(player._offensive_module_id) + 1) % choices.size()]
	if player._attack_label != null:
		player._attack_label.text = "OFFENSIF : %s" % player._offensive_module_id.replace("_", " ").to_upper()


func _perform_offensive_module() -> void:
	if player._offensive_module_id == "" or player._action_gate.is_kind(PLAYER_STATE.ACTION_GATE.Kind.MODULE):
		return
	if player._offensive_module_id == "javelin" and player._can_buffer_defensive_action() and player._has_live_javelin_mark():
		player._buffer_javelin_recast()
		return
	if player._offensive_module_id == "rocket_basket":
		player._perform_rocket_basket()
	elif player._offensive_module_id == "javelin":
		player._perform_javelin()
	elif player._offensive_module_id == "fulguro_punch":
		player._perform_fulguro_punch()
	elif player._offensive_module_id == "pelto_smash":
		player._perform_pelto_smash()


func _activate_defensive_module() -> void:
	if player._action_gate.is_kind(PLAYER_STATE.ACTION_GATE.Kind.MODULE):
		return
	player._perform_defensive_module()


func _activate_mobility_module() -> void:
	if player._action_gate.is_kind(PLAYER_STATE.ACTION_GATE.Kind.MODULE):
		return
	if player._can_buffer_defensive_action() and player._mobility_module_id == "pyro_boots":
		player._buffer_dash()
		return
	player._perform_mobility_module()


func get_weapon_id() -> String:
	return player._weapon_id


func _cycle_weapon() -> void:
	var choices: Array = preload("res://scripts/loadout_state.gd").WEAPONS
	player.set_weapon(str(choices[(choices.find(player._weapon_id) + 1) % choices.size()]))
