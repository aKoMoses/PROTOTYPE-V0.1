extends CanvasLayer

## First-to-three match driven by the lobby host. The local Player uses its existing
## weapons and modules; the remote fighter is represented by the arena's bot
## model, whose position and health are mirrored from the other human client.

const CREAM := Color("#f3ddbb")
const CYAN := Color("#42d9e5")
const GREEN := Color("#69d687")
const RED := Color("#d95b4d")

var _main: Node3D
var _player: CharacterBody3D
var _target: StaticBody3D
var _flow: CanvasLayer
var _touch: Control
var _session: Node
var _host_id := 0
var _guest_id := 0
var _round_number := 0
var _host_score := 0
var _guest_score := 0
var _phase := "starting"
var _state_clock := 0.0
var _remote_position := Vector3.ZERO
var _status: Label
var _score: Label
var _health: Label
var _return_button: Button


func configure(main: Node3D, host_id: int, guest_id: int) -> void:
	_main = main
	_player = main.get_node("Player") as CharacterBody3D
	_target = main.get_node("TargetDummy") as StaticBody3D
	_flow = main.get_node("Interface") as CanvasLayer
	_touch = _flow.get_node("TouchControls") as Control
	_session = get_node("/root/NetworkSession")
	_host_id = host_id
	_guest_id = guest_id
	_session.round_prepared.connect(_on_round_prepared)
	_session.round_live.connect(_on_round_live)
	_session.round_finished.connect(_on_round_finished)
	_session.opponent_state.connect(_on_opponent_state)
	_session.opponent_hit.connect(_on_opponent_hit)
	_session.opponent_effect.connect(_on_opponent_effect)
	_session.connection_changed.connect(_on_connection_changed)
	_session.room_changed.connect(_on_room_changed)
	_player.died.connect(_on_local_death)
	_build_overlay()
	_flow.call("_show_screen", 3)
	_flow.get_node("FlowRoot").visible = false
	_flow.call("_start_match_music")
	_touch.visible = false
	_player.call("set_gameplay_enabled", false)
	_target.set("network_proxy", true)
	_target.call("set_training_bot_enabled", false)
	_target.call("set_duel_mode", true)
	_target.call("reset_combat_state")
	_target.position = _other_spawn()
	_remote_position = _target.position
	_update_labels()
	_session.match_ready()


func _build_overlay() -> void:
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	var top := HBoxContainer.new()
	top.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	top.offset_left = 26
	top.offset_top = 18
	top.offset_right = -26
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(top)
	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(info)
	_score = _label("0 — 0", 30, CYAN)
	info.add_child(_score)
	_health = _label("", 17, CREAM)
	info.add_child(_health)
	_return_button = Button.new()
	_return_button.text = "QUITTER LE MATCH"
	_return_button.custom_minimum_size = Vector2(180, 46)
	_return_button.pressed.connect(_leave_match)
	top.add_child(_return_button)
	_status = _label("En attente de l'autre joueur…", 25, CREAM)
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_status.offset_left = -380
	_status.offset_right = 380
	_status.offset_top = 82
	root.add_child(_status)


func _label(value: String, size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = value
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _is_host() -> bool:
	return _session.local_peer_id() == _host_id


func _my_spawn() -> Vector3:
	return Vector3(-3.5, 0.0, 17.0) if _is_host() else Vector3(3.5, 0.0, 15.5)


func _other_spawn() -> Vector3:
	return Vector3(3.5, 0.0, 15.5) if _is_host() else Vector3(-3.5, 0.0, 17.0)


func _process(delta: float) -> void:
	if _phase in ["countdown", "live"]:
		_state_clock += delta
		if _state_clock >= 0.1:
			_state_clock = 0.0
			_session.send_state(_player.global_position, _player.get("aim_direction"),
				float(_player.call("get_health")), float(_player.call("get_max_health")), str(_player.call("get_weapon_id")))
		_target.global_position = _target.global_position.lerp(_remote_position, minf(1.0, delta * 13.0))
		_update_health()


func _on_round_prepared(round_number: int, host_score: int, guest_score: int) -> void:
	_round_number = round_number
	_host_score = host_score
	_guest_score = guest_score
	_phase = "countdown"
	_main.call("clear_transient_fx")
	_player.call("set_gameplay_enabled", false)
	_player.call("clear_touch_inputs")
	_player.position = _my_spawn()
	_player.call("apply_loadout", _flow.get("loadout"))
	_player.call("reset_combat_state")
	_target.position = _other_spawn()
	_target.call("reset_combat_state")
	_remote_position = _target.position
	_touch.visible = false
	_status.text = "MANCHE %d  •  PRÉPAREZ-VOUS" % round_number
	_status.add_theme_color_override("font_color", CREAM)
	_update_labels()


func _on_round_live() -> void:
	_phase = "live"
	_player.call("set_gameplay_enabled", true)
	_touch.visible = DisplayServer.is_touchscreen_available() or OS.has_feature("mobile")
	_status.text = "COMBAT"
	_status.add_theme_color_override("font_color", CYAN)


func _on_round_finished(host_score: int, guest_score: int, winner_id: int, match_over: bool) -> void:
	_phase = "finished" if match_over else "round_result"
	_host_score = host_score
	_guest_score = guest_score
	_player.call("set_gameplay_enabled", false)
	_touch.visible = false
	_status.text = ("MATCH GAGNÉ" if winner_id == _session.local_peer_id() else "MATCH PERDU") if match_over else ("MANCHE GAGNÉE" if winner_id == _session.local_peer_id() else "MANCHE PERDUE")
	_status.add_theme_color_override("font_color", GREEN if winner_id == _session.local_peer_id() else RED)
	_update_labels()


func _on_opponent_state(position: Vector3, aim: Vector3, health: float, max_health: float, weapon: String) -> void:
	if _phase not in ["countdown", "live"]:
		return
	_remote_position = position
	if aim.length_squared() > 0.01:
		_target.look_at(_target.global_position + aim, Vector3.UP)
	var state: Object = _target.get("combat_state")
	if state != null:
		state.max_health = max_health
		state.health = minf(health, max_health)
		_target.call("_on_health_changed", state.health, max_health)
	if weapon in ["blaster", "shotgun"]:
		_target.call("set_duel_profile", weapon)


func _on_opponent_hit(amount: float, source_id: String, attack_id: String) -> void:
	if _phase != "live":
		return
	_player.call("take_damage", amount, source_id, attack_id)
	if float(_player.call("get_health")) <= 0.0:
		_on_local_death()


func _on_opponent_effect(effect: String, duration: float, value: float) -> void:
	if _phase != "live":
		return
	match effect:
		"burn": _player.call("apply_burn", duration, value, "opponent")
		"slow": _player.call("apply_slow", duration, value, "opponent")
		"stun": _player.call("apply_stun", duration, "opponent")
		"spotted": _player.call("apply_spotted", duration, "opponent")


func _on_local_death() -> void:
	if _phase != "live":
		return
	_phase = "reported"
	_player.call("set_gameplay_enabled", false)
	_touch.visible = false
	_status.text = "FIN DE MANCHE…"
	_session.report_death()


func _on_connection_changed(is_connected: bool, message: String) -> void:
	if not is_connected:
		_finish_to_lobby(message)


func _on_room_changed(room: Dictionary) -> void:
	if room.is_empty() or int(room.get("guest_id", 0)) == 0:
		_finish_to_lobby("L'autre joueur a quitté le match.")


func _update_labels() -> void:
	var my_score := _host_score if _is_host() else _guest_score
	var their_score := _guest_score if _is_host() else _host_score
	_score.text = "TOI %d — %d ADVERSAIRE" % [my_score, their_score]
	_update_health()


func _update_health() -> void:
	_health.text = "PV %d / %d  •  adversaire %d / %d" % [
		roundi(float(_player.call("get_health"))), roundi(float(_player.call("get_max_health"))),
		roundi(float(_target.call("get_health"))), roundi(float(_target.call("get_max_health")))
	]


func _leave_match() -> void:
	_session.leave_room()
	_finish_to_lobby("Match quitté.")


func _finish_to_lobby(message: String) -> void:
	if not is_inside_tree():
		return
	_phase = "closed"
	_target.set("network_proxy", false)
	_target.call("set_training_bot_enabled", false)
	_target.call("set_duel_mode", false)
	_player.call("set_gameplay_enabled", false)
	_touch.visible = false
	_flow.call("_stop_match_music")
	_flow.get_node("FlowRoot").visible = true
	_flow.call("_open_lobby")
	var lobby := _flow.get_node_or_null("FlowRoot/NetworkLobby")
	if lobby != null:
		lobby.call("_on_connection_changed", _session.connected, message)
	queue_free()
