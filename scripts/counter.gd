class_name CounterGuard
extends Node3D

## One guard per actor; one shared payload per emitted attack (all pellets/cleave).
## Call impact before any damage or dependent effects. Secondary damage uses
## take_damage directly and never enters this interception path.
signal finished
signal intercepted
signal exploded(center: Vector3)

const DATA := preload("res://scripts/combat_data.gd")
const VISUAL := preload("res://scripts/counter_visual.gd")
var definition: Dictionary = DATA.MODULE_DEFINITIONS.counter.duplicate(true)
var phase := ""
var remaining := 0.0
var surcharge_remaining := 0.0
var successes := 0
var explosions := 0
var authoritative := true
var _blocked: Dictionary = {}
var _clock := 0.0
var _outline: MeshInstance3D
var _energy: MeshInstance3D
var _label: Label3D
var _panels: Node3D
var _timer_arc: MeshInstance3D
var _timer_track: MeshInstance3D
var _weapon_halo: MeshInstance3D
var _success_flash := 0.0


static func component(actor: Node) -> CounterGuard:
	return actor.get_node_or_null("CounterGuard") as CounterGuard if is_instance_valid(actor) else null


static func ensure(actor: Node) -> CounterGuard:
	var guard := component(actor)
	if guard == null:
		guard = CounterGuard.new()
		guard.name = "CounterGuard"
		actor.add_child(guard)
	return guard


func begin() -> bool:
	if phase != "":
		return false
	phase = "preparation"
	remaining = float(definition.preparation)
	_sync_visual()
	return true


func update(delta: float) -> void:
	_clock += maxf(0.0, delta)
	_success_flash = maxf(0.0, _success_flash - delta)
	surcharge_remaining = maxf(0.0, surcharge_remaining - delta)
	for key in _blocked.keys():
		if float(_blocked[key]) <= _clock:
			_blocked.erase(key)
	var rest := maxf(0.0, delta)
	while phase != "" and rest > 0.000001:
		var portion := minf(rest, remaining)
		remaining -= portion
		rest -= portion
		if remaining > 0.000001:
			break
		if phase == "preparation":
			phase = "guard"
			_play_sound("counter_guard")
			remaining = float(definition.guard_duration)
		elif phase == "guard":
			phase = "recovery"
			remaining = float(definition.failure_recovery)
		else:
			phase = ""
			remaining = 0.0
			finished.emit()
	_sync_visual()


func intercept(attack: Dictionary) -> bool:
	if not authoritative or not bool(attack.get("counter_trigger", false)):
		return false
	var id := str(attack.get("id", ""))
	if id.is_empty():
		return false
	if _blocked.has(id):
		return true
	if phase != "guard":
		return false
	# End protection synchronously, before callbacks or another same-frame hit.
	phase = "recovery"
	remaining = float(definition.success_recovery)
	_blocked[id] = _clock + 12.0 # Beyond any weapon's ordinary maximum flight.
	surcharge_remaining = float(definition.surcharge_duration)
	successes += 1
	_success_flash = 0.38
	_sync_visual()
	VISUAL.burst(get_tree().current_scene, global_position + Vector3.UP * 0.95, 1.35, 0.26, false)
	_play_sound("counter_intercept")
	_play_sound("counter_capture")
	intercepted.emit()
	return true


func cancel(clear_reward: bool = false) -> void:
	var busy := phase != ""
	phase = ""
	remaining = 0.0
	_success_flash = 0.0
	if clear_reward:
		surcharge_remaining = 0.0
		_blocked.clear()
	_sync_visual()
	if busy:
		finished.emit()


func movement_multiplier() -> float:
	return float(definition.move_multiplier) if phase in ["preparation", "guard"] else 1.0


func _process(_delta: float) -> void:
	# Follow the rendered weapon, including while gameplay physics is paused.
	if _energy != null and surcharge_remaining > 0.0:
		_sync_energy_position()
		var pulse := 1.0 + sin(_clock * 14.0) * 0.12
		_energy.scale = Vector3.ONE * pulse
		_weapon_halo.scale = Vector3.ONE * (1.0 + sin(_clock * 14.0) * 0.06)
		_weapon_halo.rotation = Vector3(0.55, _clock * 3.0, 0.35)


func _sync_energy_position() -> void:
	var actor := get_parent()
	if actor.has_method("get_passive_weapon_point"):
		_energy.global_position = actor.call("get_passive_weapon_point") + Vector3.UP * 0.18
	elif actor.has_method("get_training_bot_muzzle_transform"):
		_energy.global_position = actor.call("get_training_bot_muzzle_transform").origin + Vector3.UP * 0.18
	else:
		_energy.position = Vector3(0.5, 1.0, -0.4)
	_weapon_halo.global_position = _energy.global_position


static func weapon_attack(actor: Node, id: String, values: Dictionary) -> Dictionary:
	var guard := component(actor)
	var charged := guard != null and guard.surcharge_remaining > 0.0
	var attack := {"id": id, "counter_trigger": bool(values.get("counter_trigger", false)),
		"surcharge": charged, "resolved": false, "owner": weakref(actor)}
	if charged:
		attack["radius"] = float(guard.definition.surcharge_radius)
		attack["damage"] = float(guard.definition.surcharge_damage)
		guard.surcharge_remaining = 0.0
		guard._sync_visual()
	return attack


static func invalidate(attack: Dictionary) -> void:
	attack["resolved"] = true


static func impact(target: Node, amount: float, source: String, hit_id: String, attack: Dictionary, point: Vector3) -> float:
	if not is_instance_valid(target) or not target.has_method("take_damage"):
		invalidate(attack)
		return 0.0
	var owner_actor: Node = attack.get("owner").get_ref() if attack.get("owner") is WeakRef else null
	if is_instance_valid(owner_actor) and not enemies(owner_actor, target):
		return 0.0
	var guard := component(target)
	var can_intercept := amount > 0.0 and (not target.has_method("is_real_dead") or not bool(target.call("is_real_dead")))
	if can_intercept and guard != null and guard.intercept(attack):
		invalidate(attack)
		return 0.0
	var applied := float(target.call("take_damage", amount, source, hit_id))
	if applied <= 0.0:
		invalidate(attack)
	elif bool(attack.get("surcharge", false)) and not bool(attack.get("resolved", false)):
		attack["resolved"] = true
		if is_instance_valid(owner_actor) and owner_actor.is_inside_tree():
			explode(owner_actor, point, attack)
	return applied


static func enemies(actor: Node, target: Node) -> bool:
	if actor == target:
		return false
	if actor.has_meta("combat_team") and target.has_meta("combat_team"):
		return actor.get_meta("combat_team") != target.get_meta("combat_team")
	# The existing modes have one human faction against combat bots. Network
	# humans are opponents; ownership excludes the firing human explicitly.
	return not (actor.is_in_group("prototype0_combat_bots") and target.is_in_group("prototype0_combat_bots"))


static func _targets(node: Node, output: Array[Node3D]) -> void:
	if node is Node3D and node.has_method("take_damage"):
		output.append(node)
		return
	for child in node.get_children():
		_targets(child, output)


static func explode(actor: Node3D, point: Vector3, attack: Dictionary) -> void:
	var guard := component(actor)
	if guard != null and not guard.authoritative:
		return
	var radius := float(attack.get("radius", DATA.MODULE_DEFINITIONS.counter.surcharge_radius))
	var targets: Array[Node3D] = []
	_targets(actor.get_tree().current_scene, targets)
	for target in targets:
		if not enemies(actor, target):
			continue
		var center := target.global_position + Vector3.UP * 0.85
		if center.distance_to(point) > radius:
			continue
		var excluded: Array[RID] = []
		if actor is CollisionObject3D:
			excluded.append(actor.get_rid())
		if target is CollisionObject3D:
			excluded.append(target.get_rid())
		var query := PhysicsRayQueryParameters3D.create(point, center, 1 | 8, excluded)
		query.collide_with_areas = true
		query.hit_from_inside = true
		if not actor.get_world_3d().direct_space_state.intersect_ray(query).is_empty():
			continue
		# Dedicated source prevents Omnivamp/weapon synergies/recursive hit chains.
		target.call("take_damage", float(attack.get("damage", 10.0)), "surcharge", str(attack.id) + ":surcharge")
	spawn_ring(actor.get_tree().current_scene, point, radius, 0.22)
	var sfx := actor.get_node_or_null("/root/GameSfx")
	if sfx != null:
		sfx.call("play_module_event", "counter_release", point)
	if guard != null:
		guard.explosions += 1
		guard.exploded.emit(point)


static func spawn_ring(scene: Node, center: Vector3, radius: float, duration: float = 0.22) -> void:
	VISUAL.burst(scene, center, radius, duration, true)


func snapshot() -> Dictionary:
	return {"phase": phase, "remaining": remaining, "surcharge": surcharge_remaining, "successes": successes}


func restore(value: Dictionary) -> void:
	if authoritative:
		return
	var previous_successes := successes
	var previous_phase := phase
	phase = str(value.get("phase", ""))
	if phase not in ["preparation", "guard", "recovery"]:
		phase = ""
	var phase_limit := maxf(float(definition.guard_duration), float(definition.preparation))
	phase_limit = maxf(phase_limit, maxf(float(definition.success_recovery), float(definition.failure_recovery)))
	remaining = clampf(float(value.get("remaining", 0.0)), 0.0, phase_limit)
	surcharge_remaining = clampf(float(value.get("surcharge", 0.0)), 0.0, float(definition.surcharge_duration))
	successes = int(value.get("successes", successes))
	if successes > previous_successes:
		_success_flash = 0.38
	_sync_visual()
	if phase == "guard" and previous_phase != "guard":
		_play_sound("counter_guard")
	if successes > previous_successes:
		VISUAL.burst(get_tree().current_scene, global_position + Vector3.UP * 0.95, 1.35, 0.26, false)
		_play_sound("counter_intercept")
		_play_sound("counter_capture")


func _play_sound(event_id: String) -> void:
	var sfx := get_node_or_null("/root/GameSfx")
	if sfx != null:
		sfx.call("play_module_event", event_id, global_position + Vector3.UP * 0.85)


func _sync_visual() -> void:
	if not is_inside_tree():
		return
	if _outline == null and phase == "" and surcharge_remaining <= 0.0:
		set_process(false)
		return
	if _outline == null:
		_outline = VISUAL.ring(self, 0.99, 0.055, VISUAL.GUARD_COLOR)
		_outline.position.y = 0.07
		_panels = VISUAL.guard_panels(self)
		_timer_arc = VISUAL.timer_arc(self)
		_timer_arc.position.y = 0.10
		_timer_track = VISUAL.ring(self, 1.17, 0.16, Color("#163b4b"))
		_timer_track.position.y = 0.085
		var sphere := SphereMesh.new()
		sphere.radius = 0.16
		sphere.height = 0.32
		_energy = VISUAL.mesh(self, sphere, Color(VISUAL.REWARD_COLOR, 0.80))
		_weapon_halo = VISUAL.ring(self, 0.40, 0.065, VISUAL.REWARD_COLOR)
		VISUAL.ring(_weapon_halo, 0.43, 0.11, Color("#593a20")).position.y = -0.018
		_label = Label3D.new()
		_label.position.y = 2.45
		_label.font_size = 36
		_label.outline_size = 10
		_label.outline_modulate = Color("#101d27")
		_label.pixel_size = 0.010
		_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		add_child(_label)
	_outline.visible = phase == "guard"
	_panels.visible = phase == "guard"
	_timer_arc.visible = phase == "guard"
	_timer_track.visible = phase == "guard"
	if phase == "guard":
		var ratio := clampf(remaining / float(definition.guard_duration), 0.0, 1.0)
		VISUAL.update_timer(_timer_arc, ratio)
		var opening := 1.0 - pow(1.0 - clampf((1.0 - ratio) / 0.10, 0.0, 1.0), 3.0)
		_panels.scale = Vector3.ONE * lerpf(0.90, 1.0, opening)
	_energy.visible = surcharge_remaining > 0.0
	_weapon_halo.visible = _energy.visible
	set_process(_energy.visible)
	var actor := get_parent()
	var visibility_weight: Variant = actor.get("_presentation_visibility_weight")
	visible = not (visibility_weight is float or visibility_weight is int) or float(visibility_weight) > 0.5
	_sync_energy_position()
	_label.modulate = VISUAL.GUARD_COLOR if phase == "guard" else VISUAL.REWARD_COLOR
	_label.text = "GARDE" if phase == "guard" else "BLOQUÉ !\nTIR RENFORCÉ" if surcharge_remaining > 0.0 and _success_flash > 0.0 else "SURCHARGE %.1f s\nTIR RENFORCÉ" % surcharge_remaining if surcharge_remaining > 0.0 else ""
	_label.visible = not _label.text.is_empty()
	var rig = actor.get("_visual_rig")
	if is_instance_valid(rig) and rig.has_method("set_counter_pose"):
		var weight := 1.0
		if phase == "preparation":
			weight = smoothstep(0.0, 1.0, 1.0 - remaining / float(definition.preparation))
		elif phase == "recovery":
			var duration := float(definition.success_recovery) if _success_flash > 0.0 else float(definition.failure_recovery)
			weight = smoothstep(0.0, 1.0, clampf(remaining / duration, 0.0, 1.0))
		rig.call("set_counter_pose", phase != "", weight)
