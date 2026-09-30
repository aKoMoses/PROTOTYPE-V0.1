extends Node3D

const ASPECTS := preload("res://scripts/survival_aspects.gd")
const PROJECTILE := preload("res://scripts/live_projectile.gd")
const VISUALS := preload("res://scripts/survival_aspect_visuals.gd")
var player: Node3D
var build: Dictionary = {}
var clock := 0.0
var serial := 0
var generation := 0
var shield_remaining := 0.0
var shield_health := 0.0
var shield_energy := 0.0
var reserve := 0.0
var wall_energy := 0.0
var wall: Area3D
var wall_position := Vector3.ZERO
var wall_direction := Vector3.FORWARD
var shield_direction := Vector3.FORWARD
var shield_visual: Node3D
var javelin_anchor := Vector3.INF
var javelin_until := 0.0
var javelin_visual: Node3D
var agents: Array[Dictionary] = []
var zones: Array[Dictionary] = []
var pickups: Array[Dictionary] = []
var arc_marks: Dictionary = {}
var damaged_targets: Dictionary = {}
var _incoming_ids: Dictionary = {}
var _last_hit := -100.0
var _baroud_damage := 0.0
var _baroud_started := -100.0
var _baroud_safe := 0.0
var _dash_extra_ready := true
var _bio_used_time := 0.0
var _trail_next := 0.0
var _appearance: Node3D
var _reserve_visual: Node3D

func path(category: String) -> String:
	return str(ASPECTS.state(build, category).get("path", ""))

func rank(category: String) -> int:
	return int(ASPECTS.state(build, category).get("rank", 0))

func configure(next_build: Dictionary) -> void:
	clear_transients()
	build = next_build.duplicate(true)
	if _appearance != null:
		_appearance.clear_visuals()
		_appearance.queue_free()
	_appearance = VISUALS.new()
	add_child(_appearance)
	_appearance.configure(player, build)
	if path("passive") != "reserve":
		reserve = 0.0
	_dash_extra_ready = true
	if str(build.get("passive", "")) == "baroud":
		player.passive_state.baroud_duration = 4.0 + rank("passive") * 0.65 + 1.1 * int(build.get("upgrades", {}).get("passive", {}).get("power", 0))
		player.passive_state.baroud_max_health = maxf(float(player.passive_state.baroud_max_health), float(player.passive_state.baroud_duration) * 400.0 + 200.0)
	if path("weapon") == "sweeper":
		var count := 6 + rank("weapon") * 2
		var angle := 14.0 + rank("weapon") * 7.0
		var spread: Array = []
		for index in range(count):
			spread.append(lerpf(-angle, angle, float(index) / float(count - 1)))
		player._shotgun_pellet_angles = spread
		player._shotgun_pellet_damage *= 6.0 / float(count)
		player._shotgun_minimum_damage *= 6.0 / float(count)
	if path("defensive") == "rampart":
		player._magnetic_width += rank("defensive") * 0.9
	if path("mobility") == "thruster":
		player._survival_dash_multiplier *= 1.0 + max(0, rank("mobility") - 1) * 0.12

func clear_transients() -> void:
	generation += 1
	for child in get_children():
		if child is PROJECTILE:
			child.queue_free()
	if is_instance_valid(wall):
		wall.queue_free()
	wall = null
	wall_energy = 0.0
	shield_remaining = 0.0
	shield_health = 0.0
	shield_energy = 0.0
	for collection in [agents, zones, pickups]:
		for entry in collection:
			if is_instance_valid(entry.visual):
				entry.visual.queue_free()
		collection.clear()
	if is_instance_valid(shield_visual):
		shield_visual.queue_free()
	shield_visual = null
	_clear_javelin()
	arc_marks.clear()
	damaged_targets.clear()
	_incoming_ids.clear()
	reserve = 0.0
	if is_instance_valid(_reserve_visual):
		_reserve_visual.queue_free()
	_reserve_visual = null

func _physics_process(delta: float) -> void:
	if player == null or not player.survival_mode or not player.is_gameplay_enabled() or player.is_real_dead():
		return
	clock += delta
	reserve = maxf(0.0, reserve - delta * (7.0 - rank("passive")))
	if is_instance_valid(_reserve_visual):
		_reserve_visual.visible = reserve > 0.0
		_reserve_visual.rotation.y += delta
	if shield_remaining > 0.0:
		shield_remaining = maxf(0.0, shield_remaining - delta)
		if shield_remaining <= 0.0:
			_finish_shield(false)
		elif is_instance_valid(shield_visual):
			shield_visual.rotation.y += delta * 0.7
	if player.passive_state.baroud_active:
		_update_baroud(delta)
	if path("mobility") == "metabolism" and float(player._bio_remaining) > 0.0 and clock - _last_hit > 0.9 and player.velocity.length() > 0.3:
		player.heal(delta * (10.0 + rank("mobility") * 9.0), "metabolism")
	if player.get_module_cooldown("pyro_boots") <= 0.0:
		_dash_extra_ready = true
	if javelin_anchor != Vector3.INF and clock >= javelin_until:
		_clear_javelin()
	_update_agents(delta)
	_update_zones()
	_update_pickups(delta)
	_update_wall()
	for key in arc_marks.keys():
		if clock >= float(arc_marks[key]):
			arc_marks.erase(key)

func _targets() -> Array:
	return player._survival_targets().filter(func(enemy: Node) -> bool: return is_instance_valid(enemy) and enemy.get_health() > 0.0)

func _damage(enemy: Node3D, amount: float, source: String) -> float:
	serial += 1
	var applied: float = enemy.take_damage(amount, "player:" + source, "%s:%d:%d" % [source, get_instance_id(), serial])
	if applied > 0.0:
		enemy.flash_impact(false)
	return applied

func _clear_line(a: Vector3, b: Vector3, excluded: Array[RID] = []) -> bool:
	var ignored := excluded.duplicate()
	ignored.append_array(own_wall_exclusions())
	return player._solid_path_clear(a, b, ignored)

func _line_damage(origin: Vector3, direction: Vector3, distance: float, width: float, amount: float, source: String, maximum: int = 6, excluded: Node = null) -> void:
	var end: Vector3 = player._module_obstacle_endpoint(origin, origin + direction * distance, own_wall_exclusions())
	var reach := Vector2(end.x - origin.x, end.z - origin.z).length()
	var targets := _targets()
	targets.sort_custom(func(a: Node3D, b: Node3D) -> bool: return origin.distance_squared_to(a.global_position) < origin.distance_squared_to(b.global_position))
	var hit_count := 0
	for enemy in targets:
		if enemy == excluded:
			continue
		var offset: Vector3 = enemy.global_position - origin
		offset.y = 0.0
		var along := offset.dot(direction)
		if along < -0.05 or along > reach or (offset - direction * along).length() > width + 0.4:
			continue
		if not _clear_line(origin, enemy.global_position, [enemy.get_rid()]):
			continue
		_damage(enemy, amount, source)
		if source == "javelin_recall" and path("offensive") == "harpoon" and rank("offensive") == 3:
			_control(enemy, 0.6)
		hit_count += 1
		if hit_count >= maximum:
			break
	player._create_lightning_arc(origin + Vector3.UP * 0.9, end + Vector3.UP * 0.9, Color("#80eeff") if source.begins_with("rail") else Color("#ffc882"), 0.045 + width * 0.08, 0.22)

func _push(enemy: Node3D, away_from: Vector3, distance: float) -> void:
	var bot := enemy.get_node_or_null("TrainingBot")
	if bot != null and (str(bot.survival_role) == "boss" or str(bot.survival_elite) != ""):
		enemy.apply_slow(0.65, 25.0, "evolution_control")
		return
	var direction := (enemy.global_position - away_from).normalized()
	direction.y = 0.0
	var destination := enemy.global_position + direction * distance
	destination.x = clampf(destination.x, -21.0, 21.0)
	destination.z = clampf(destination.z, -21.0, 21.0)
	if _clear_line(enemy.global_position, destination, [enemy.get_rid()]):
		enemy.global_position = destination

func _control(enemy: Node3D, duration: float) -> void:
	var bot := enemy.get_node_or_null("TrainingBot")
	if bot != null and (str(bot.survival_role) == "boss" or str(bot.survival_elite) != ""):
		enemy.apply_slow(duration, 30.0, "harpoon")
	else:
		enemy.apply_stun(duration, "harpoon")

func _repulse(position: Vector3, radius: float, distance: float) -> void:
	for enemy in _targets():
		if position.distance_to(enemy.global_position) <= radius and _clear_line(position, enemy.global_position, [enemy.get_rid()]):
			_push(enemy, position, distance)
	player._survival_pulse_fx(position, radius, Color("#92dfff"))

func blaster_hit(target: Node3D, damage: float, charge: float, direction: Vector3) -> void:
	var level := rank("weapon")
	if path("weapon") == "rail" and charge >= 0.65:
		_line_damage(target.global_position + direction * 0.05, Vector3(direction.x, 0.0, direction.z).normalized(), 12.0, 0.28 if level < 3 else 0.75, damage * 0.72, "rail", [1, 2, 5][level - 1], target)
	elif path("weapon") == "arc":
		if charge >= 0.65:
			arc_marks[target.get_instance_id()] = clock + 5.0
			player._survival_pulse_fx(target.global_position, 1.0, Color("#bc93ff"))
		elif arc_marks.has(target.get_instance_id()):
			var origin := target.global_position
			var seen: Array = [target]
			for bounce in range(level):
				var next := _nearest(origin, 4.0, seen)
				if next == null:
					break
				player._create_lightning_arc(origin + Vector3.UP, next.global_position + Vector3.UP, Color("#bb99ff"), 0.10, 0.20)
				_damage(next, damage * pow(0.7, bounce + 1), "arc")
				seen.append(next)
				origin = next.global_position

func shotgun_salvo(origin: Vector3, direction: Vector3) -> void:
	if path("weapon") != "breaker":
		return
	if rank("weapon") == 3:
		_line_damage(player.global_position, direction, 6.0, 0.8, float(player._shotgun_pellet_damage) * 2.0, "battering_ram", 3)
		for enemy in _targets():
			var offset: Vector3 = enemy.global_position - player.global_position
			if offset.length() < 4.5 and direction.dot(offset.normalized()) > 0.75:
				_push(enemy, player.global_position, 0.9)
	else:
		_bolt(origin, origin + direction * 7.0, float(player._shotgun_pellet_damage) * 1.3, "heavy_slug", Color("#ffd39a"), true)

func shotgun_hit(target: Node3D, salvo: Dictionary) -> void:
	if path("weapon") != "breaker" or player.global_position.distance_to(target.global_position) > 4.5:
		return
	var key := "control:%d" % target.get_instance_id()
	if salvo.has(key):
		return
	salvo[key] = true
	target.apply_slow(0.5, 25.0, "breaker")
	if rank("weapon") >= 2:
		_control(target, 0.2)

func _nearest(position: Vector3, radius: float, excluded: Array = []) -> Node3D:
	var best: Node3D
	var distance := radius
	for enemy in _targets():
		var next_distance := position.distance_to(enemy.global_position)
		if enemy not in excluded and next_distance < distance and _clear_line(position, enemy.global_position, [enemy.get_rid()]):
			best = enemy
			distance = next_distance
	return best

func _bolt(origin: Vector3, destination: Vector3, damage: float, source: String, color: Color, heavy: bool = false) -> void:
	var projectile := PROJECTILE.new()
	projectile.name = "EvolutionProjectile"
	add_child(projectile)
	projectile.global_position = origin
	var excluded: Array[RID] = [player.get_rid()]
	excluded.append_array(own_wall_exclusions())
	projectile.configure((destination - origin).normalized(), 24.0, maxf(0.1, origin.distance_to(destination)), 1 | 2 | 8, excluded)
	var visual := _sphere(projectile, 0.13 if heavy else 0.08, color)
	var epoch := generation
	projectile.finished.connect(func(hit: Dictionary, _distance: float) -> void:
		if epoch != generation or hit.is_empty() or not player.is_gameplay_enabled():
			return
		var enemy := hit.get("collider") as Node3D
		if enemy != null and enemy.has_method("take_damage"):
			_damage(enemy, damage, source)
			if heavy and rank("weapon") >= 2:
				_control(enemy, 0.25)
			if source in ["hunter", "sentry"] and player.survival_synergies != null and player.survival_synergies.crosses_field(origin, destination):
				player.survival_synergies.drone_hit(enemy, damage)
	)
	visual.name = source

func _sphere(parent: Node3D, radius: float, color: Color) -> MeshInstance3D:
	var visual := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	visual.mesh = mesh
	visual.material_override = player._create_fx_material(color, 0.85)
	parent.add_child(visual)
	return visual

func launch_sentry(origin: Vector3, direction: Vector3) -> bool:
	if path("offensive") != "sentry":
		return false
	var position: Vector3 = player._module_obstacle_endpoint(origin, origin + direction * 4.0, own_wall_exclusions())
	position.y = 0.0
	_spawn_agent(position, null, true)
	return true

func drone_hit(target: Node3D) -> void:
	if path("offensive") == "hunter":
		_spawn_agent(target.global_position, target, false)

func _spawn_agent(position: Vector3, target: Node3D, stationary: bool) -> void:
	if agents.size() >= 3:
		var oldest: Dictionary = agents.pop_front()
		oldest.visual.queue_free()
	var visual := Node3D.new()
	visual.name = "SentryDrone" if stationary else "HunterDrone"
	add_child(visual)
	visual.global_position = position + Vector3.UP * (0.65 if stationary else 1.6)
	_sphere(visual, 0.24, Color("#83e8ad") if stationary else Color("#5bdcff"))
	for side in [-1.0, 1.0]:
		var wing := _sphere(visual, 0.10 + rank("offensive") * 0.025, Color("#e0ffff"))
		wing.position = Vector3(side * 0.35, 0.0, 0.0)
	if stationary:
		for index in range(3):
			var leg := _sphere(visual, 0.10, Color("#3c6b62"))
			leg.position = Vector3(cos(index * TAU / 3.0) * 0.26, -0.35, sin(index * TAU / 3.0) * 0.26)
	agents.append({"visual": visual, "target": target, "stationary": stationary, "until": clock + 2.4 + rank("offensive") * 1.2, "next": clock + 0.2})

func _update_agents(delta: float) -> void:
	for index in range(agents.size() - 1, -1, -1):
		var agent := agents[index]
		if clock >= float(agent.until) or not is_instance_valid(agent.visual):
			if is_instance_valid(agent.visual):
				agent.visual.queue_free()
			agents.remove_at(index)
			continue
		var target := agent.target as Node3D
		if not is_instance_valid(target) or target.get_health() <= 0.0:
			target = _nearest(agent.visual.global_position, 7.0 + rank("offensive"))
			agent.target = target
		if target == null:
			continue
		if not bool(agent.stationary):
			var destination := target.global_position + Vector3(0.7, 1.5, 0.7)
			if _clear_line(agent.visual.global_position, destination, [target.get_rid()]):
				agent.visual.global_position = agent.visual.global_position.move_toward(destination, delta * 5.0)
		if clock < float(agent.next):
			continue
		agent.next = clock + 0.8
		var position: Vector3 = agent.visual.global_position
		if not _clear_line(position, target.global_position, [target.get_rid()]):
			continue
		var source := "sentry" if bool(agent.stationary) else "hunter"
		_bolt(position, target.global_position + Vector3.UP * 0.9, float(player._drone_damage) * 0.20, source, Color("#85ecff"))
		if bool(agent.stationary) and rank("offensive") == 3:
			var second := _nearest(position, 10.0, [target])
			if second != null:
				_bolt(position, second.global_position + Vector3.UP * 0.9, float(player._drone_damage) * 0.16, source, Color("#85ecff"))

func javelin_hit(target: Node3D, position: Vector3) -> void:
	_place_javelin(position)
	if path("offensive") == "harpoon":
		_control(target, 0.45 + rank("offensive") * 0.25)

func launch_beacon(origin: Vector3, direction: Vector3) -> bool:
	if path("offensive") != "beacon":
		return false
	var position: Vector3 = player._module_obstacle_endpoint(origin, origin + direction * (4.0 + rank("offensive") * 1.2), own_wall_exclusions())
	position -= direction * 0.6
	position.y = 0.0
	if not _landing_clear(position):
		player._attack_label.text = "BALISE · EMPLACEMENT BLOQUÉ"
		player._module_cooldowns["javelin"] = 0.0
		return true
	_place_javelin(position)
	player._create_lightning_arc(origin + Vector3.UP, position + Vector3.UP * 0.4, Color("#78fff1"), 0.035, 0.25)
	return true

func _place_javelin(position: Vector3) -> void:
	_clear_javelin()
	javelin_anchor = Vector3(position.x, 0.0, position.z)
	javelin_until = clock + 3.5 + rank("offensive") * 1.5
	javelin_visual = Node3D.new()
	javelin_visual.name = "JavelinBeacon" if path("offensive") == "beacon" else "JavelinAnchor"
	add_child(javelin_visual)
	javelin_visual.global_position = javelin_anchor
	var tip := _sphere(javelin_visual, 0.18, Color("#78fff1") if path("offensive") == "beacon" else Color("#ffe394"))
	tip.position.y = 0.45
	var ring := MeshInstance3D.new()
	var mesh := TorusMesh.new()
	mesh.inner_radius = 0.45
	mesh.outer_radius = 0.55
	ring.mesh = mesh
	ring.position.y = 0.06
	ring.material_override = player._create_fx_material(Color("#78fff1"), 0.8)
	javelin_visual.add_child(ring)

func has_javelin_anchor() -> bool:
	return javelin_anchor != Vector3.INF and clock < javelin_until

func javelin_fraction() -> float:
	return clampf((javelin_until - clock) / (3.5 + rank("offensive") * 1.5), 0.0, 1.0) if has_javelin_anchor() else 0.0

func recall_javelin() -> void:
	if not has_javelin_anchor():
		return
	var origin := player.global_position
	var anchor := javelin_anchor
	if path("offensive") == "beacon":
		if not _landing_clear(anchor) or not _clear_line(origin, anchor):
			player._attack_label.text = "BALISE · DESTINATION BLOQUÉE"
			return
		player.global_position = anchor
		player.velocity = Vector3.ZERO
		player._create_teleport_fx(anchor)
		if rank("offensive") == 3:
			_repulse(anchor, 3.2, 1.4)
		player.get_node("/root/GameSfx").play_event("javelin_teleport")
	else:
		var direction := (origin - anchor).normalized()
		_line_damage(anchor, direction, anchor.distance_to(origin) + 0.2, 0.35 + rank("offensive") * 0.18, float(player._javelin_damage) * (0.40 + rank("offensive") * 0.08), "javelin_recall", 6)
		player._attack_label.text = "JAVELIN · RAPPEL"
	if player.survival_synergies != null:
		player.survival_synergies.teleport_trail(origin, anchor)
	_clear_javelin()
	if is_instance_valid(player._javelin_mark_target):
		player._javelin_mark_target.clear_javelin_mark()
	player._javelin_mark_target = null

func _clear_javelin() -> void:
	javelin_anchor = Vector3.INF
	if is_instance_valid(javelin_visual):
		javelin_visual.queue_free()
	javelin_visual = null

func _landing_clear(position: Vector3) -> bool:
	if absf(position.x) > 21.0 or absf(position.z) > 21.0:
		return false
	var shape := CylinderShape3D.new()
	shape.radius = 0.55
	shape.height = 1.6
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform.origin = position + Vector3.UP * 0.85
	query.collision_mask = 1 | 2 | 8
	query.exclude = [player.get_rid()]
	return player.get_world_3d().direct_space_state.intersect_shape(query).is_empty()

func activate_shield() -> void:
	shield_direction = player.aim_direction.normalized()
	var level := rank("defensive")
	var power := 0.70 + 0.55 * int(build.get("upgrades", {}).get("defensive", {}).get("power", 0))
	shield_remaining = 0.45 + level * 0.12 if path("defensive") == "counter" else 2.5 + level * 0.7
	shield_health = (100.0 + level * 45.0) * power
	shield_energy = 0.0
	if is_instance_valid(shield_visual):
		shield_visual.queue_free()
	shield_visual = Node3D.new()
	shield_visual.name = "MobileShield"
	player.add_child(shield_visual)
	var segments := 4 + level * 2
	for index in range(segments):
		var plate := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = Vector3(0.25, 0.30, 0.045)
		plate.mesh = mesh
		plate.material_override = player._create_fx_material(Color("#bba1ff") if path("defensive") == "counter" else Color("#81cdfa"), 0.42)
		shield_visual.add_child(plate)
		var angle := index * TAU / segments
		plate.position = Vector3(cos(angle) * 0.64, 1.0, sin(angle) * 0.64)
		plate.rotation.y = PI * 0.5 - angle
	player._attack_label.text = "BOUCLIER · %d PV" % roundi(shield_health)

func receive_damage(amount: float, attack_id: String) -> float:
	if amount <= 0.0:
		return 0.0
	if attack_id != "":
		if _incoming_ids.has(attack_id):
			return 0.0
		_incoming_ids[attack_id] = true
		if _incoming_ids.size() > 2048:
			_incoming_ids.clear()
	if player.passive_state.baroud_active and clock < _baroud_safe:
		return 0.0
	if shield_remaining > 0.0:
		var blocked := minf(amount, shield_health)
		shield_health -= blocked
		shield_energy += blocked
		amount -= blocked
		if shield_health <= 0.0:
			_finish_shield(true)
	if reserve > 0.0 and amount > 0.0:
		var blocked := minf(amount, reserve)
		reserve -= blocked
		amount -= blocked
	if amount > 0.0:
		_last_hit = clock
	return amount

func _finish_shield(broken: bool) -> void:
	shield_remaining = 0.0
	if path("defensive") == "counter" and shield_energy > 0.0:
		_line_damage(player.global_position, shield_direction, 5.0 + rank("defensive"), 1.0 + rank("defensive") * 0.25, minf(shield_energy * (0.8 + rank("defensive") * 0.2), 100.0 + rank("defensive") * 45.0), "shield_counter", 6)
	elif broken and path("defensive") == "carapace" and rank("defensive") == 3:
		_repulse(player.global_position, 3.0, 1.1)
	shield_energy = 0.0
	if is_instance_valid(shield_visual):
		shield_visual.queue_free()
	shield_visual = null

func wall_created(next_wall: Area3D, direction: Vector3) -> void:
	wall = next_wall
	wall_position = wall.global_position
	wall_direction = direction
	wall_energy = 0.0
	wall.set_meta("survival_evolution_controller", self)
	var epoch := generation
	wall.tree_exiting.connect(func() -> void:
		if epoch == generation and wall == next_wall:
			_discharge_wall()
			wall = null
	)
	for side in [-1.0, 1.0]:
		var pillar := _sphere(wall, 0.20 + rank("defensive") * 0.04, Color("#ffde72") if path("defensive") == "capacitor" else Color("#57e8d5"))
		pillar.position = Vector3(side * float(player._magnetic_width) * 0.5, 1.0, 0.0)

func wall_absorb(amount: float) -> void:
	if path("defensive") == "capacitor" and is_instance_valid(wall):
		wall_energy = minf(wall_energy + amount * 1.8, 90.0 + rank("defensive") * 70.0)
		wall.scale.y = 1.0 + wall_energy / 1000.0

func release_wall() -> bool:
	if path("defensive") != "capacitor" or not is_instance_valid(wall):
		return false
	_discharge_wall()
	wall.queue_free()
	wall = null
	return true

func _discharge_wall() -> void:
	if path("defensive") == "capacitor" and wall_energy > 0.0 and player.is_gameplay_enabled():
		_line_damage(wall_position + wall_direction * 0.2, wall_direction, 5.0 + rank("defensive") * 1.5, 1.4, wall_energy, "magnetic_discharge", 6)
	wall_energy = 0.0

func _update_wall() -> void:
	if path("defensive") != "rampart" or not is_instance_valid(wall):
		return
	for enemy in _targets():
		var local: Vector3 = wall.to_local(enemy.global_position)
		if absf(local.x) <= float(player._magnetic_width) * 0.5 + 0.35 and absf(local.z) <= 1.0:
			enemy.apply_slow(0.3, 25.0 + rank("defensive") * 12.0, "rampart")

func own_wall_exclusions() -> Array[RID]:
	var result: Array[RID] = []
	if is_instance_valid(player._magnetic_wall):
		result.append(player._magnetic_wall.get_rid())
	return result

func prepare_dash() -> bool:
	if player.get_module_cooldown("pyro_boots") <= 0.0:
		return true
	if path("mobility") == "thruster" and _dash_extra_ready:
		_dash_extra_ready = false
		player._module_cooldowns["pyro_boots"] = 0.0
		return true
	return false

func dash_charges() -> int:
	if path("mobility") != "thruster":
		return 1 if player.get_module_cooldown("pyro_boots") <= 0.0 else 0
	return 2 if player.get_module_cooldown("pyro_boots") <= 0.0 else (1 if _dash_extra_ready else 0)

func dash_started() -> void:
	if path("mobility") == "thruster" and rank("mobility") == 3:
		_repulse(player.global_position, 2.6, 0.8)

func pyro_step(at: Vector3) -> void:
	if path("mobility") != "trail" or clock < _trail_next:
		return
	_trail_next = clock + 0.10
	if zones.size() >= 32:
		zones.pop_front().visual.queue_free()
	var radius := 0.65 + rank("mobility") * 0.18
	var visual := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = 0.035
	visual.mesh = mesh
	visual.material_override = player._create_fx_material(Color("#ff7b35"), 0.55)
	add_child(visual)
	visual.global_position = at + Vector3.UP * 0.035
	zones.append({"visual": visual, "position": at, "radius": radius, "until": clock + 1.0 + rank("mobility") * 0.8, "next": clock})

func _update_zones() -> void:
	var burned_this_tick: Dictionary = {}
	for index in range(zones.size() - 1, -1, -1):
		var zone := zones[index]
		if clock >= float(zone.until):
			zone.visual.queue_free()
			zones.remove_at(index)
			continue
		if clock < float(zone.next):
			continue
		zone.next = clock + 0.25
		for enemy in _targets():
			if not burned_this_tick.has(enemy.get_instance_id()) and enemy.global_position.distance_to(zone.position) <= float(zone.radius) + 0.4 and _clear_line(zone.position, enemy.global_position, [enemy.get_rid()]):
				burned_this_tick[enemy.get_instance_id()] = true
				_damage(enemy, 7.0 + rank("mobility") * 3.0, "pyro_trail")

func bio_started() -> void:
	_bio_used_time = 0.0
	if path("mobility") == "metabolism":
		player._bio_remaining += rank("mobility") * 0.8

func attack_multiplier() -> float:
	return 1.0 + rank("mobility") * 0.15 if path("mobility") == "overdrive" and player._bio_remaining > 0.0 else 1.0

func movement_multiplier() -> float:
	return 1.40 + rank("passive") * 0.1 if player.passive_state.baroud_active and path("passive") == "escape" else 1.0

func dealt_damage(amount: float, target: Node3D = null) -> void:
	if amount <= 0.0:
		return
	if is_instance_valid(target):
		damaged_targets[target.get_instance_id()] = true
	if player.passive_state.baroud_active and path("passive") == "revenge":
		_baroud_damage += amount
		if _baroud_damage >= baroud_goal():
			_rescue_baroud()

func baroud_goal() -> float:
	return 180.0

func passive_status() -> String:
	if player.passive_state.baroud_active:
		if path("passive") == "revenge":
			return "BAROUD · %d / 180 DÉGÂTS · %.1f s" % [roundi(_baroud_damage), float(player.passive_state.baroud_remaining)]
		return "BAROUD · ÉVITE LES COUPS · %.1f s" % maxf(0.0, 1.8 - (clock - maxf(_last_hit, _baroud_started)))
	return "RÉSERVE · %d PV" % roundi(reserve) if reserve > 0.0 else ""

func start_baroud() -> void:
	_baroud_damage = 0.0
	_baroud_started = clock
	_last_hit = clock
	_baroud_safe = clock + (0.55 + rank("passive") * 0.15 if path("passive") == "escape" else 0.0)
	player._attack_label.text = "BAROUD · FUIR" if path("passive") != "revenge" else "BAROUD · INFLIGER 180 DÉGÂTS"

func _update_baroud(_delta: float) -> void:
	# Unmodified Baroud also has an attainable escape condition in Survival.
	if path("passive") != "revenge" and clock - maxf(_last_hit, _baroud_started) >= 1.8:
		_rescue_baroud()

func _rescue_baroud() -> void:
	var state = player.passive_state
	state.baroud_active = false
	state.baroud_remaining = 0.0
	state.baroud_health = 0.0
	state.real_dead = false
	# Keep baroud_used: a successful rescue cannot trigger another one this run.
	var fraction := 0.10 + rank("passive") * 0.07
	player.heal(maxf(0.0, player.get_max_health() * fraction - player.get_health()), "baroud_rescue")
	player._attack_label.text = "BAROUD · SAUVÉ"
	player._create_target_hit_fx(player.global_position, true)

func overflow_heal(amount: float) -> void:
	if path("passive") == "reserve" and amount > 0.0:
		reserve = minf(reserve + amount, 40.0 + rank("passive") * 35.0)
		if not is_instance_valid(_reserve_visual):
			_reserve_visual = Node3D.new()
			_reserve_visual.name = "VitalReserve"
			player.add_child(_reserve_visual)
			for index in range(3 + rank("passive")):
				var angle := index * TAU / (3 + rank("passive"))
				var plate := _sphere(_reserve_visual, 0.09, Color("#6cfff1"))
				plate.position = Vector3(cos(angle) * 0.65, 0.6, sin(angle) * 0.65)
		_reserve_visual.visible = true

func enemy_died(enemy: Node3D) -> void:
	if not damaged_targets.has(enemy.get_instance_id()):
		return
	damaged_targets.erase(enemy.get_instance_id())
	if path("mobility") == "overdrive" and rank("mobility") >= 2 and player._bio_remaining > 0.0:
		var extension := minf(0.35 + rank("mobility") * 0.15, maxf(0.0, 2.0 + rank("mobility") - _bio_used_time))
		player._bio_remaining += extension
		_bio_used_time += extension
	if path("passive") != "harvest":
		return
	if pickups.size() >= 40:
		pickups.pop_front().visual.queue_free()
	var visual := Node3D.new()
	add_child(visual)
	visual.global_position = enemy.global_position + Vector3.UP * 0.35
	var crystal := _sphere(visual, 0.16, Color("#8fffb2"))
	crystal.scale = Vector3(0.7, 1.6, 0.7)
	pickups.append({"visual": visual, "until": clock + 10.0, "heal": 12.0 + rank("passive") * 8.0})

func _update_pickups(delta: float) -> void:
	for index in range(pickups.size() - 1, -1, -1):
		var pickup := pickups[index]
		var at: Vector3 = pickup.visual.global_position
		var destination: Vector3 = player.global_position + Vector3.UP * 0.35
		var distance := at.distance_to(destination)
		if distance <= 0.75:
			player.heal(float(pickup.heal), "harvest")
		elif clock < float(pickup.until):
			pickup.visual.rotation.y += delta * 1.6
			if rank("passive") >= 2 and distance <= 1.0 + rank("passive") * 1.5 and _clear_line(at, destination):
				pickup.visual.global_position = at.move_toward(destination, delta * 5.0)
			continue
		pickup.visual.queue_free()
		pickups.remove_at(index)

func _exit_tree() -> void:
	clear_transients()
