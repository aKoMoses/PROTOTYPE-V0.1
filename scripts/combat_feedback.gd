extends Control

## Presentation and observations only: never changes combat time or damage.
signal action_observed(id: String)
const PREFS := preload("res://scripts/review_preferences.gd")
const LABELS := preload("res://scripts/survival_run_stats.gd")
const SIGNATURE := preload("res://scripts/combat_signature.gd")
var actor: Node3D
var enabled := true
var received: Dictionary = {}
var opponent_repairs := 0
var dealt := 0.0
var elapsed := 0.0
var _notice: Label
var _remaining := 0.0
var _priority := 0
var _markers: Array[Dictionary] = []
var _registered: Dictionary = {}
var _signature: Control
var _signature_seen: Dictionary = {}
var _actor_state: CombatState
var _last_position := Vector3.ZERO
var _had_mark := false

static func attach(scene: Node, player: Node3D, top: float = 90.0) -> Control:
	var layer := CanvasLayer.new()
	layer.name = "CombatFeedbackLayer"
	layer.layer = 4
	scene.add_child(layer)
	var script = load("res://scripts/combat_feedback.gd")
	var feedback := Control.new()
	feedback.set_script(script)
	feedback.name = "CombatFeedback"
	feedback.actor = player
	feedback.set_meta("notice_top", top)
	layer.add_child(feedback)
	return feedback

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	process_mode = Node.PROCESS_MODE_PAUSABLE
	enabled = bool(PREFS.read().feedback)
	_notice = Label.new()
	_notice.name = "ActionNotice"
	_notice.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_notice.position = Vector2(-240, float(get_meta("notice_top", 90.0)))
	_notice.size = Vector2(480, 55)
	_notice.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_notice.add_theme_font_size_override("font_size", 19)
	_notice.add_theme_color_override("font_outline_color", Color("#0c151c"))
	_notice.add_theme_constant_override("outline_size", 6)
	_notice.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_notice)
	_notice.hide()
	_signature = SIGNATURE.new()
	_signature.name = "SuccessSignature"
	_signature.notice_top = float(get_meta("notice_top", 90.0))
	add_child(_signature)
	bind_actor(actor)

func bind_actor(player: Node3D) -> void:
	if is_instance_valid(actor) and actor.has_signal("combat_signature_requested") and actor.is_connected("combat_signature_requested", _signature_success):
		actor.disconnect("combat_signature_requested", _signature_success)
	if _actor_state != null:
		_actor_state.damage_applied.disconnect(_received)
		_actor_state.reset_completed.disconnect(reset_round)
	for entry in _registered.values():
		var previous: Node3D = entry.actor.get_ref()
		if is_instance_valid(previous):
			entry.state.damage_applied.disconnect(_hit.bind(previous))
			entry.state.healing_applied.disconnect(_healed)
	_registered.clear()
	actor = player
	_actor_state = null
	if is_instance_valid(actor):
		_actor_state = actor.get("combat_state")
		_actor_state.damage_applied.connect(_received)
		_actor_state.reset_completed.connect(reset_round)
		if actor.has_signal("combat_signature_requested"):
			actor.connect("combat_signature_requested", _signature_success)
	reset_round()

func register_target(target: Node3D) -> void:
	if not is_instance_valid(target):
		return
	var state: CombatState = target.get("combat_state")
	var id := target.get_instance_id()
	if _registered.has(id):
		var previous: Dictionary = _registered[id]
		if previous.state == state:
			return
		previous.state.damage_applied.disconnect(_hit.bind(target))
		previous.state.healing_applied.disconnect(_healed)
	_registered[id] = {"actor": weakref(target), "state": state}
	state.damage_applied.connect(_hit.bind(target))
	state.healing_applied.connect(_healed)

func sync_targets() -> void:
	for id in _registered.keys():
		var target: Node3D = _registered[id].actor.get_ref()
		if is_instance_valid(target):
			register_target(target)
		else:
			_registered.erase(id)

func reset_round() -> void:
	received.clear()
	opponent_repairs = 0
	dealt = 0.0
	elapsed = 0.0
	_markers.clear()
	_remaining = 0.0
	_priority = 0
	_notice.hide()
	_signature_seen.clear()
	if _signature != null:
		_signature.clear()
	_had_mark = false
	if is_instance_valid(actor):
		_last_position = actor.global_position
	queue_redraw()

func _process(delta: float) -> void:
	sync_targets()
	var live := is_instance_valid(actor) and bool(actor.call("is_gameplay_enabled")) and not bool(actor.call("is_real_dead"))
	if not live:
		_notice.hide()
		_markers.clear()
		if not enabled or not _winner_presentation():
			_signature.clear()
		_remaining = 0.0
		_priority = 0
		_had_mark = false
		queue_redraw()
		return
	elapsed += delta
	if not enabled:
		_signature.clear()
	if _remaining > 0.0:
		_notice.visible = enabled and _signature.kind.is_empty()
		_remaining = maxf(0.0, _remaining - delta)
		_notice.modulate.a = minf(1.0, _remaining * 4.0)
		if _remaining <= 0.0:
			_notice.hide()
			_priority = 0
	for index in range(_markers.size() - 1, -1, -1):
		_markers[index].time -= delta
		if _markers[index].time <= 0.0:
			_markers.remove_at(index)
	var has_mark := is_instance_valid(actor.get("_javelin_mark_target"))
	if _had_mark and not has_mark and actor.global_position.distance_to(_last_position) > maxf(1.0, delta * 8.0):
		observe("javelin", "REPOSITIONNEMENT RÉUSSI", Color("#93e8ff"))
	_had_mark = has_mark
	_last_position = actor.global_position
	queue_redraw()

func observe(id: String, text: String, color: Color = Color("#75e7ec")) -> void:
	action_observed.emit(id)
	announce(text, color, 2)

func announce(text: String, color: Color = Color("#75e7ec"), priority: int = 1) -> void:
	if not enabled or (_remaining > 0.0 and priority < _priority):
		return
	_notice.text = text
	_notice.add_theme_color_override("font_color", color)
	_notice.modulate.a = 1.0
	_notice.show()
	_remaining = 1.25
	_priority = priority

func _signature_success(kind: String, target: Node3D, event_id: String) -> void:
	if not SIGNATURE.STYLES.has(kind) or event_id.is_empty() or not is_instance_valid(actor):
		return
	if bool(actor.call("is_real_dead")):
		return
	if not bool(actor.call("is_gameplay_enabled")) and not _winner_presentation():
		return
	var key := kind + ":" + event_id
	if _signature_seen.has(key):
		return
	# Observations still validate guided challenges when confirmations are disabled.
	if _signature_seen.size() >= 128:
		_signature_seen.erase(_signature_seen.keys()[0])
	_signature_seen[key] = true
	action_observed.emit(kind)
	if not enabled or not can_present_target(target):
		return
	_notice.hide()
	_signature.show_success(kind, target, actor, target.global_position + Vector3.UP * 0.9)
	var sfx := get_node_or_null("/root/GameSfx")
	if sfx != null:
		sfx.call("play_signature", kind)
	# A short impulse on the successful attacker's camera, honoring its setting.
	if actor.has_method("_camera_impulse"):
		var strength: float = {"shotgun": 0.045, "counter": 0.025, "fulguro_punch": 0.065, "longshot": 0.028}[kind]
		actor.call("_camera_impulse", 0.075, strength)

func _winner_presentation() -> bool:
	if not is_instance_valid(actor) or bool(actor.call("is_real_dead")):
		return false
	var scene := get_tree().current_scene
	var flow := scene.get_node_or_null("Interface") if scene != null else null
	if flow != null and flow.has_method("resolve_round"):
		# WINNER_FOCUS lasts longer than the card, allowing a lethal success to read.
		if int(flow.get("round_phase")) == 6 and bool(flow.get("_round_result_bot_dead")):
			return true
	var network := scene.get_node_or_null("NetworkMatch") if scene != null else null
	if network != null and str(network.get("_phase")) in ["round_result", "finished"]:
		var opponent: Node = network.get("_target")
		return is_instance_valid(opponent) and bool(opponent.call("is_real_dead"))
	return false

func can_present_target(target: Node3D) -> bool:
	if not is_instance_valid(target) or not target.is_visible_in_tree():
		return false
	if target != actor and target.has_method("is_visible_to") and not bool(target.call("is_visible_to", actor)):
		return false
	var camera := get_viewport().get_camera_3d()
	if camera == null or camera.is_position_behind(target.global_position + Vector3.UP * 0.9):
		return false
	return Rect2(Vector2.ZERO, get_viewport_rect().size).grow(-18.0).has_point(camera.unproject_position(target.global_position + Vector3.UP * 0.9))

func _received(amount: float, source: String, attack: String) -> void:
	if not is_instance_valid(actor) or not bool(actor.call("is_gameplay_enabled")):
		return
	var key := damage_kind(source, attack)
	received[key] = float(received.get(key, 0.0)) + amount

static func damage_kind(source: String, attack: String) -> String:
	for key in ["fulguro", "javelin", "shotgun", "longshot", "blaster", "mekatana", "pelto", "rocket", "burn", "arena_hazard"]:
		if key in source or key in attack:
			return {"fulguro": "fulguro_punch", "pelto": "pelto_smash", "rocket": "rocket_basket", "burn": "BRÛLURE", "arena_hazard": "PIÈGES"}.get(key, key)
	return "AUTRES"

func _hit(amount: float, source: String, attack: String, target: Node3D) -> void:
	if not source.begins_with("player") or not is_instance_valid(actor) or not bool(actor.call("is_gameplay_enabled")):
		return
	dealt += amount
	if not is_instance_valid(target):
		return
	# A current hit must not expose an off-screen or concealed actor.
	var camera := get_viewport().get_camera_3d()
	var in_sight := not target.has_method("is_visible_to") or bool(target.call("is_visible_to", actor))
	if enabled and camera != null and target.visible and in_sight and not camera.is_position_behind(target.global_position):
		if _markers.size() >= 8:
			_markers.pop_front()
		_markers.append({"at": target.global_position + Vector3.UP, "time": 0.18, "critical": "critical" in attack or attack.ends_with(":wall")})
	if attack.ends_with(":wall") and "fulguro" in attack:
		_signature_success("fulguro_punch", target, attack)
	elif "critical" in attack and "shotgun" not in attack:
		announce("PLEIN IMPACT", Color("#ffda80"), 1)

func _healed(_amount: float, source: String) -> void:
	if source == "repair_pickup" and is_instance_valid(actor) and bool(actor.call("is_gameplay_enabled")):
		opponent_repairs += 1

func report() -> String:
	var keys := received.keys()
	keys.sort_custom(func(a: String, b: String) -> bool: return float(received[a]) > float(received[b]))
	var lines := PackedStringArray()
	lines.append("%d dégâts infligés · %.0f s de combat" % [roundi(dealt), elapsed])
	if not keys.is_empty():
		var key: String = keys[0]
		lines.append("Principal danger : %s · %d dégâts" % [LABELS.label_for(key), roundi(received[key])])
	if opponent_repairs > 0:
		lines.append("Réparations prises par l’adversaire : %d" % opponent_repairs)
	return "\n".join(lines)

func _draw() -> void:
	var camera := get_viewport().get_camera_3d()
	if camera == null or not enabled or not _signature.kind.is_empty():
		return
	for marker in _markers:
		if camera.is_position_behind(marker.at):
			continue
		var at: Vector2 = camera.unproject_position(marker.at)
		var color := Color("#ffe09a") if marker.critical else Color("#8bf7ff")
		color.a = clampf(float(marker.time) / 0.18, 0.0, 1.0)
		for direction in [Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]:
			draw_line(at + direction * 7, at + direction * 13, Color(0.03, 0.05, 0.07, color.a), 5)
			draw_line(at + direction * 7, at + direction * 13, color, 2)
