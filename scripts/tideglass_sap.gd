extends Node3D

## One public, contested pickup. Round time owns transport, recharge and power;
## the common weapon context snapshots the power when an attack is emitted.
const BONUS := 0.35
const DURATION := 10.0
const TRANSPORT_WINDOW := 15.0
const RESPAWN := 20.0
const RADIUS := 1.25
const VFX := preload("res://scripts/tideglass_sap_vfx.gd")

var _basin: Node3D
var _actors: Array[Node3D] = []
var _charges: Dictionary = {}
var _recharge := 0.0
var _orb: Node3D
var _label: Label3D
var _effects: Dictionary = {}

func configure(stage: Node3D, basin: Node3D) -> void:
	_basin = basin
	var palette: Dictionary = stage.get("_materials")
	stage.call("_ring", self, "SapSocket", 0.9, 0.055, Vector3(0, 0.05, 0), palette.gold)
	_orb = VFX.new()
	_orb.name = "OffensiveSap"
	add_child(_orb)
	_orb.call("configure")
	_label = Label3D.new()
	_label.name = "SapReward"
	_label.font_size = 36
	_label.pixel_size = 0.008
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.modulate = Color("#ffdf8e")
	_label.outline_size = 7
	add_child(_label)
	_update_visuals()

func configure_actors(actors: Array[Node3D]) -> void:
	_actors.assign(actors)

func _runtime(actor: Node3D) -> PassiveState:
	if actor.has_method("get_passive_runtime"):
		return actor.call("get_passive_runtime") as PassiveState
	return actor.get("passive_state") as PassiveState if "passive_state" in actor else null

func _live(actor: Node3D) -> bool:
	return is_instance_valid(actor) and not actor.is_queued_for_deletion() and not (actor.has_method("is_real_dead") and bool(actor.call("is_real_dead")))

func is_available() -> bool:
	return is_instance_valid(_basin) and bool(_basin.get("active")) and not get_tree().paused and _recharge <= 0.0

func try_collect(actor: Node3D) -> bool:
	if not is_available() or not _live(actor) or not _actors.has(actor) or _charges.has(actor.get_instance_id()):
		return false
	var runtime := _runtime(actor)
	if runtime == null or runtime.real_dead:
		return false
	if Vector2(actor.global_position.x - global_position.x, actor.global_position.z - global_position.z).length() > RADIUS:
		return false
	if float(_basin.call("height_at", actor.global_position)) > 0.35:
		return false
	var ray := PhysicsRayQueryParameters3D.create(global_position + Vector3.UP * 0.55, actor.global_position + Vector3.UP * 0.72, 1 | 8)
	if not get_world_3d().direct_space_state.intersect_ray(ray).is_empty():
		return false
	_charges[actor.get_instance_id()] = {"actor": actor, "runtime": runtime, "epoch": runtime.get("_epoch"), "phase": "carried", "remaining": TRANSPORT_WINDOW}
	_recharge = RESPAWN
	_feedback(actor)
	_update_visuals()
	return true

func status(actor: Node3D) -> Dictionary:
	if not is_instance_valid(actor) or not _charges.has(actor.get_instance_id()):
		return {}
	var charge: Dictionary = _charges[actor.get_instance_id()]
	return {"phase": charge.phase, "remaining": charge.remaining, "bonus": BONUS}

func advance(delta: float) -> void:
	if not is_instance_valid(_basin) or not bool(_basin.get("active")) or get_tree().paused or delta <= 0.0:
		return
	_recharge = maxf(0.0, _recharge - delta)
	for id in _charges.keys():
		var charge: Dictionary = _charges[id]
		var actor: Node3D = charge.actor
		var runtime: PassiveState = charge.runtime
		if not _live(actor) or _runtime(actor) != runtime or runtime.get("_epoch") != charge.epoch:
			_clear_charge(id)
			continue
		if charge.phase == "carried" and float(_basin.call("height_at", actor.global_position)) >= 1.30:
			charge.phase = "active"
			charge.remaining = DURATION
			runtime.arena_weapon_multiplier = 1.0 + BONUS
			_feedback(actor)
		charge.remaining -= delta
		if float(charge.remaining) <= 0.0:
			_clear_charge(id)
	# A single nearest live fighter receives the pickup. A healthy fighter can
	# contest it too; no heal or damage event is needed to acquire the charge.
	if is_available():
		var candidates: Array[Node3D] = []
		for actor in _actors:
			if _live(actor):
				candidates.append(actor)
		candidates.sort_custom(func(a: Node3D, b: Node3D): return a.global_position.distance_squared_to(global_position) < b.global_position.distance_squared_to(global_position))
		for actor in candidates:
			if try_collect(actor):
				break
	_update_visuals()

func _clear_charge(id: int) -> void:
	var runtime: PassiveState = _charges[id].runtime
	if runtime != null:
		runtime.arena_weapon_multiplier = 1.0
	_charges.erase(id)
	if _effects.has(id):
		var effect: Node3D = _effects[id]
		effect.visible = false
		effect.queue_free()
		_effects.erase(id)

func reset_round() -> void:
	for id in _charges.keys():
		_clear_charge(id)
	_recharge = 0.0
	_update_visuals()

func _exit_tree() -> void:
	for id in _charges.keys():
		_clear_charge(id)

func get_bot_destination(actor: Node3D) -> Vector3:
	var charge := status(actor)
	if not charge.is_empty():
		if charge.phase == "active":
			return Vector3.INF
		var best := Vector3.INF
		var distance := INF
		for point in [Vector3(-7.25, 1.35, -7.5), Vector3(7.25, 1.35, -7.5), Vector3(0, 1.35, 5.5)]:
			var travel: float = actor.global_position.distance_squared_to(point)
			if travel < distance:
				distance = travel
				best = point
		return best
	return global_position if is_available() else Vector3.INF

func _feedback(actor: Node3D) -> void:
	if actor == get_tree().current_scene.get("player"):
		var sfx := get_node_or_null("/root/GameSfx")
		if sfx != null:
			sfx.call("play_event", "alternator_ready")

func _update_visuals() -> void:
	if _orb == null:
		return
	var water := maxf(0.0, float(_basin.get("water_level")))
	var clock := float(_basin.get("elapsed"))
	_orb.visible = _recharge <= 0.0
	if _orb.visible:
		_orb.call("update_effect", null, "pickup", RESPAWN, clock, water)
	_label.position.y = water + 3.5
	_label.text = "SÈVE OFFENSIVE\n+35 % · 10 s sur un îlot" if _recharge <= 0.0 else "SÈVE · RETOUR DANS %d s" % ceili(_recharge)
	var observer: Node3D = get_tree().current_scene.get("player")
	for id in _charges:
		var charge: Dictionary = _charges[id]
		var actor: Node3D = charge.actor
		if not _live(actor):
			continue
		if not _effects.has(id):
			var effect := VFX.new()
			effect.name = "SapCarrierVfx"
			add_child(effect)
			effect.call("configure")
			_effects[id] = effect
		var weight := 1.0
		if actor != observer and is_instance_valid(observer) and actor.has_method("get_visibility_weight"):
			weight = float(actor.call("get_visibility_weight", observer))
		(_effects[id] as Node3D).call("update_effect", actor, str(charge.phase), float(charge.remaining), clock, water, weight)
