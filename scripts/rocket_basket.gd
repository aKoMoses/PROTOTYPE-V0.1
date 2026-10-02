extends RefCounted

const PASSIVE_HITS := preload("res://scripts/passive_state.gd")

const DATA := preload("res://scripts/combat_data.gd")
const ROCKET := preload("res://scripts/homing_rocket.gd")


static func launch(caster: Node3D, direction: Vector3, source: String, attack_id: String, cooldowns: Dictionary, damage_multiplier: float = 1.0, credit: Callable = Callable(), cooldown_basis: float = -1.0) -> Array:
	var rockets: Array = []
	if caster.has_method("passive_authoritative") and not bool(caster.call("passive_authoritative")):
		return rockets
	var definition: Dictionary = DATA.MODULE_DEFINITIONS.rocket_basket
	caster.set_meta("rocket_latest_volley", attack_id)
	if caster.has_method("register_offensive_attack"):
		caster.call("register_offensive_attack", attack_id)
	var volley := {"hits": {}, "bonus": false, "cooldown": float(definition.cooldown) if cooldown_basis < 0.0 else cooldown_basis}
	var side := direction.cross(Vector3.UP).normalized()
	caster.get_node("/root/GameSfx").play_module_event("rocket_launch", caster.global_position)
	for index in range(int(definition.projectiles)):
		var rocket := ROCKET.new()
		var id := "%s:%d" % [attack_id, index]
		rocket.configure(caster, id, direction.rotated(Vector3.UP, deg_to_rad(float(index - 2) * 9.0)))
		caster.get_tree().current_scene.add_child(rocket)
		# Emit at the actor's center, then fan out; no muzzle can bypass a wall.
		rocket.global_position = caster.global_position + Vector3.UP * (0.80 + 0.09 * float(index % 2))
		rocket.direction = (rocket.direction + side * float(index - 2) * 0.02).normalized()
		rocket.impacted.connect(func(target: Node3D, projectile: Node3D) -> void:
			var shield_before := PASSIVE_HITS.shield_health(target)
			var applied := float(target.call("take_damage", float(definition.damage) * damage_multiplier, source, projectile.rocket_id))
			if caster.has_method("on_direct_offensive_hit"):
				caster.call("on_direct_offensive_hit", attack_id, PASSIVE_HITS.accepted_damage(target, applied, shield_before), target)
			if applied <= 0.0:
				return
			if credit.is_valid():
				credit.call(target, applied)
			if target.is_in_group(ROCKET.GROUP):
				return
			if target.has_method("apply_slow"):
				target.call("apply_slow", float(definition.slow_duration), float(definition.slow_percent), "rocket_stack:%s" % projectile.rocket_id)
			var target_id := target.get_instance_id()
			volley.hits[target_id] = int(volley.hits.get(target_id, 0)) + 1
			if int(volley.hits[target_id]) == int(definition.projectiles) and not bool(volley.bonus):
				volley.bonus = true
				if str(caster.get_meta("rocket_latest_volley", "")) == attack_id:
					cooldowns["rocket_basket"] = maxf(0.0, float(cooldowns.get("rocket_basket", 0.0)) - float(volley.cooldown) * float(definition.cooldown_refund))
				if target.has_method("apply_burn"):
					target.call("apply_burn", float(definition.burn_duration), DATA.BURN_DAMAGE_PER_SECOND, "%s:rocket_basket" % source)
		)
		rockets.append(rocket)
	return rockets


static func clear(caster: Node3D) -> void:
	caster.set_meta("rocket_latest_volley", "")
	if not caster.is_inside_tree():
		return
	for rocket in caster.get_tree().get_nodes_in_group(ROCKET.GROUP):
		if rocket.caster == caster:
			rocket._destroy()


static func snapshot(caster: Node3D) -> Array:
	var values: Array = []
	for rocket in caster.get_tree().get_nodes_in_group(ROCKET.GROUP):
		if rocket.caster == caster and not rocket.is_queued_for_deletion():
			values.append({"id": rocket.rocket_id, "position": rocket.global_position, "direction": rocket.direction, "health": rocket.health})
	return values


static func receive_snapshot(caster: Node3D, values: Array) -> void:
	var existing := {}
	var new_volley := false
	for rocket in caster.get_tree().get_nodes_in_group(ROCKET.GROUP):
		if rocket.caster == caster:
			existing[rocket.rocket_id] = rocket
	for value in values:
		var rocket: Node3D = existing.get(str(value.id))
		if rocket == null:
			new_volley = true
			rocket = ROCKET.new()
			rocket.configure(caster, str(value.id), value.direction, true)
			caster.get_tree().current_scene.add_child(rocket)
		rocket.global_position = value.position
		rocket.direction = value.direction
		rocket.health = float(value.health)
		existing.erase(str(value.id))
	if new_volley:
		caster.get_node("/root/GameSfx").play_module_event("rocket_launch", caster.global_position)
	for rocket in existing.values():
		rocket._destroy()
