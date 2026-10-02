extends Node

# Specialized module behavior; state and public API stay on Player.
const PLAYER_STATE := preload("res://scripts/player/components/player_state.gd")

var player: PLAYER_STATE
var _cast_completed := false


func _init(controller: PLAYER_STATE) -> void:
	player = controller
	name = "DefensiveModulesComponent"


func _perform_counter() -> bool:
	if player._counter == null or player._action_incapacitated() or player._dash_active or player._pelto_pull_active or not player._module_ready("counter"):
		return false
	# An ongoing module owns its cast; COUNTER can only suspend weapon inputs.
	var token: int = player._try_begin_module_action("counter")
	if token == 0:
		return false
	player._clear_defensive_buffer()
	player._module_busy = true
	player._start_module_cooldown("counter", float(player._counter.definition.cooldown))
	player._counter.begin()
	player._mark_combat_event()
	return true


func _on_counter_finished() -> void:
	if player._active_module_id == "counter":
		player._end_module_action(player._active_module_action_token, "counter")


func is_counter_guarding() -> bool:
	return player._counter != null and player._counter.phase == "guard"


func get_surcharge_remaining() -> float:
	return player._counter.surcharge_remaining if player._counter != null else 0.0


func get_counter_hud_text() -> String:
	if player._counter == null:
		return "PRÊT"
	var state := "GARDE %.1f" % player._counter.remaining if player.is_counter_guarding() else "PRÉPA" if player._counter.phase == "preparation" else "RÉCUP" if player._counter.phase == "recovery" else "PRÊT" if player._module_ready("counter") else ""
	if player.get_surcharge_remaining() > 0.0:
		state += " SURCHARGE %.1f" % player.get_surcharge_remaining()
	return state


func _update_projector_threshold(current: float, maximum: float) -> void:
	var below := current > 0.0 and current / maxf(maximum, 1.0) < float(PLAYER_STATE.COMBAT_DATA.MODULE_DEFINITIONS.projector.health_threshold)
	var crossed := below and not player._projector_below_threshold
	player._projector_below_threshold = below
	if not crossed or player._defensive_module_id != "projector" or not player._gameplay_enabled or not player._projector_authoritative() or player.is_real_dead() or player.get_projector_passive_cooldown() > 0.0:
		return
	# This passive has no cast or action lock: it also protects during attacks.
	player._projector_passive_remaining = 0.0 if player.training_instant_cooldowns else float(PLAYER_STATE.COMBAT_DATA.MODULE_DEFINITIONS.projector.passive_cooldown)
	player.set_meta("projector_emergency_wave", true)
	player._emit_projector_wave()
	player.remove_meta("projector_emergency_wave")


func get_projector_passive_cooldown() -> float:
	return 0.0 if player.training_instant_cooldowns else player._projector_passive_remaining


func _perform_projector() -> bool:
	if player._defensive_module_id != "projector" or not player._module_ready("projector"):
		return false
	var action_token: int = player._try_begin_module_action("projector")
	if action_token == 0:
		return false
	player._start_module_cooldown("projector", float(PLAYER_STATE.COMBAT_DATA.MODULE_DEFINITIONS.projector.cooldown))
	player._projector_cast_token = action_token
	player._projector_cast_remaining = float(PLAYER_STATE.COMBAT_DATA.MODULE_DEFINITIONS.projector.cast_duration)
	player._projector_cast_visual = PLAYER_STATE.PROJECTOR.spawn_cast(player, player._projector_cast_remaining)
	player._on_projector_cast_started()
	return true


func _update_projector_cast(delta: float) -> void:
	if player._projector_cast_token == 0:
		return
	if not player._module_action_can_execute(player._projector_cast_token, "projector"):
		player._cancel_projector_cast()
		return
	player._projector_cast_remaining = maxf(0.0, player._projector_cast_remaining - delta)
	if player._projector_cast_remaining > 0.0:
		return
	var token := player._projector_cast_token
	_cast_completed = true
	player._cancel_projector_cast()
	_cast_completed = false
	player._emit_projector_wave()
	player._end_module_action(token, "projector")


func _cancel_projector_cast() -> void:
	if player._projector_cast_token != 0:
		player._end_module_action(player._projector_cast_token, "projector")
	player._projector_cast_remaining = 0.0
	player._projector_cast_token = 0
	if is_instance_valid(player._projector_cast_visual):
		if not _cast_completed:
			var voice: AudioStreamPlayer3D = player._projector_cast_visual.get_meta("charge_voice", null)
			player.get_node("/root/GameSfx").stop_module_voice(voice)
		player._projector_cast_visual.queue_free()
	player._projector_cast_visual = null


func _on_projector_cast_started() -> void:
	pass


func _emit_projector_wave() -> void:
	if not player._projector_authoritative():
		return
	var scene := player.get_tree().current_scene
	var targets: Array = []
	if scene != null and scene.has_method("get_training_targets"):
		targets = scene.call("get_training_targets")
	else:
		var target: Node = player._module_target()
		if is_instance_valid(target):
			targets.append(target)
	PLAYER_STATE.PROJECTOR.activate(player, targets, "projector:%d" % player.get_instance_id(), bool(player.get_meta("projector_emergency_wave", false)))
	player._mark_combat_event()
	player._on_projector_activated()
	if player._attack_label != null:
		player._attack_label.text = "PROJECTOR  •  ONDE DE CHOC"


func _projector_authoritative() -> bool:
	return true


func _on_projector_activated() -> void:
	pass
