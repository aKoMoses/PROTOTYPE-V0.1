class_name CounterGuard
extends Node3D

## One guard per actor; one shared payload per emitted attack (all pellets/cleave).
## Call impact before any damage or dependent effects. Secondary damage uses
## take_damage directly and never enters this interception path.
signal finished
signal intercepted
signal exploded(center: Vector3)

const DATA := preload("res://scripts/combat_data.gd")
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
	_sync_visual()
	spawn_ring(get_tree().current_scene, global_position + Vector3.UP * 0.85, 0.85, 0.10)
	var sfx := get_node_or_null("/root/GameSfx")
	if sfx != null:
		sfx.call("play_event", "counter_intercept")
	intercepted.emit()
	return true


func cancel(clear_reward: bool = false) -> void:
	var busy := phase != ""
	phase = ""
	remaining = 0.0
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


func _sync_energy_position() -> void:
	var actor := get_parent()
	if actor.has_method("get_passive_weapon_point"):
		_energy.global_position = actor.call("get_passive_weapon_point") + Vector3.UP * 0.10
	elif actor.has_method("get_training_bot_muzzle_transform"):
		_energy.global_position = actor.call("get_training_bot_muzzle_transform").origin + Vector3.UP * 0.10
	else:
		_energy.position = Vector3(0.5, 1.0, -0.4)


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
	if guard != null:
		guard.explosions += 1
		guard.exploded.emit(point)


static func spawn_ring(scene: Node, center: Vector3, radius: float, duration: float = 0.22) -> void:
	if not is_instance_valid(scene):
		return
	var ring := MeshInstance3D.new()
	ring.name = "CounterBurst"
	var mesh := TorusMesh.new()
	mesh.inner_radius = maxf(0.01, radius - 0.035)
	mesh.outer_radius = radius
	mesh.rings = 8
	mesh.ring_segments = 32
	ring.mesh = mesh
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = Color(0.5, 0.88, 1.0, 0.9)
	ring.material_override = material
	scene.add_child(ring)
	ring.add_to_group("prototype0_fx_budget")
	ring.global_position = center
	var tween := ring.create_tween()
	tween.tween_property(material, "albedo_color:a", 0.0, duration)
	tween.tween_callback(ring.queue_free)


func snapshot() -> Dictionary:
	return {"phase": phase, "remaining": remaining, "surcharge": surcharge_remaining, "successes": successes}


func restore(value: Dictionary) -> void:
	if authoritative:
		return
	var previous_successes := successes
	phase = str(value.get("phase", ""))
	if phase not in ["preparation", "guard", "recovery"]:
		phase = ""
	var phase_limit := maxf(float(definition.guard_duration), float(definition.preparation))
	phase_limit = maxf(phase_limit, maxf(float(definition.success_recovery), float(definition.failure_recovery)))
	remaining = clampf(float(value.get("remaining", 0.0)), 0.0, phase_limit)
	surcharge_remaining = clampf(float(value.get("surcharge", 0.0)), 0.0, float(definition.surcharge_duration))
	successes = int(value.get("successes", successes))
	_sync_visual()
	if successes > previous_successes:
		spawn_ring(get_tree().current_scene, global_position + Vector3.UP * 0.85, 0.85, 0.10)
		var sfx := get_node_or_null("/root/GameSfx")
		if sfx != null:
			sfx.call("play_event", "counter_intercept")


func _sync_visual() -> void:
	if not is_inside_tree():
		return
	if _outline == null and phase == "" and surcharge_remaining <= 0.0:
		set_process(false)
		return
	if _outline == null:
		_outline = MeshInstance3D.new()
		var torus := TorusMesh.new()
		torus.inner_radius = 0.77
		torus.outer_radius = 0.81
		torus.rings = 8
		torus.ring_segments = 32
		_outline.mesh = torus
		_outline.position.y = 0.85
		add_child(_outline)
		_energy = MeshInstance3D.new()
		var sphere := SphereMesh.new()
		sphere.radius = 0.28
		sphere.height = 0.56
		_energy.mesh = sphere
		add_child(_energy)
		for mesh_instance in [_outline, _energy]:
			var material := StandardMaterial3D.new()
			material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			material.albedo_color = Color("#89daff")
			mesh_instance.material_override = material
			mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var energy_material := _energy.material_override as StandardMaterial3D
		energy_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		energy_material.albedo_color = Color(0.4, 0.84, 1.0, 0.65)
		_label = Label3D.new()
		_label.position.y = 2.55
		_label.font_size = 26
		_label.pixel_size = 0.006
		_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		add_child(_label)
	_outline.visible = phase == "guard"
	_energy.visible = surcharge_remaining > 0.0
	set_process(_energy.visible)
	var actor := get_parent()
	var visibility_weight: Variant = actor.get("_presentation_visibility_weight")
	visible = not (visibility_weight is float or visibility_weight is int) or float(visibility_weight) > 0.5
	_sync_energy_position()
	_label.text = "GARDE %.1f" % remaining if phase == "guard" else "SURCHARGE %.1f s" % surcharge_remaining if surcharge_remaining > 0.0 else ""
	_label.visible = not _label.text.is_empty()
	var rig = actor.get("_visual_rig")
	if is_instance_valid(rig) and rig.has_method("set_counter_pose"):
		rig.call("set_counter_pose", phase != "")
