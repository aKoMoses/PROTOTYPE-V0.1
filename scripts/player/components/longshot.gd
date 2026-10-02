extends Node

# LONGSHOT preparation, shot cycle, projectile and presentation.
# Player owns shared state and keeps the scene/network API.

const PLAYER_STATE := preload("res://scripts/player/components/player_state.gd")

var player: PLAYER_STATE


func _init(controller: PLAYER_STATE) -> void:
	player = controller
	name = "LongshotComponent"


func get_longshot_cycle_count() -> int:
	return player._longshot_state.normal_shots()


func is_longshot_enhanced_ready() -> bool:
	return player._longshot_state.is_enhanced_ready()


func get_longshot_shots_fired() -> int:
	return int(player._longshot_state.shots_fired)


func reset_longshot_state() -> void:
	player._cancel_longshot_attack()
	player._longshot_state.reset()
	player._longshot_next_attack_ready_at = -10.0


func _cancel_longshot_attack() -> void:
	player._longshot_attack_token += 1
	player._longshot_attack_busy = false
	player._action_gate.release(player._longshot_action_token)
	player._longshot_action_token = 0


func _perform_longshot_attack() -> void:
	if player._weapon_id != "longshot" or player._longshot_attack_busy or player._action_incapacitated():
		return
	if Time.get_ticks_msec() / 1000.0 < player._longshot_next_attack_ready_at:
		return
	var action_token: int = player._try_begin_weapon_action("longshot")
	if action_token == 0:
		return
	player._longshot_action_token = action_token
	player._longshot_attack_busy = true
	player._longshot_attack_token += 1
	var token := player._longshot_attack_token
	player._begin_weapon_aim()
	var timer = player.get_tree().create_timer(float(player._longshot_definition["attack_preparation"]) / player.get_attack_speed_multiplier(), false)
	timer.timeout.connect(player._emit_longshot_shot.bind(token, action_token))


func _emit_longshot_shot(token: int, action_token: int) -> void:
	if not player._longshot_emission_valid(token, action_token):
		return
	player._begin_weapon_fire()
	if player._has_skeletal_weapon_attachment():
		await player._visual_rig.skeleton.skeleton_updated
		if not player._longshot_emission_valid(token, action_token):
			return
	var enhanced: bool = player._longshot_state.next_enhanced()
	if not player._spawn_longshot_projectile(enhanced, player._longshot_state.shots_fired + 1):
		player._cancel_longshot_attack()
		return
	player._longshot_next_attack_ready_at = Time.get_ticks_msec() / 1000.0 + (0.01 if player.training_instant_cooldowns else maxf(0.0, float(player._longshot_definition["cooldown"]) - float(player._longshot_definition["attack_preparation"]))) / player.get_attack_speed_multiplier()
	player._longshot_attack_busy = false
	player._action_gate.release(action_token)
	player._longshot_action_token = 0
	player._on_longshot_emitted(enhanced, player._longshot_state.shots_fired)
	player._sync_weapon_readout()


func _longshot_emission_valid(token: int, action_token: int) -> bool:
	if token != player._longshot_attack_token or not player._longshot_attack_busy:
		return false
	if player._weapon_id != "longshot" or player._action_incapacitated() or not player._action_gate.owns(action_token, PLAYER_STATE.ACTION_GATE.Kind.WEAPON, "longshot"):
		player._cancel_longshot_attack()
		return false
	return true


func _on_longshot_emitted(_enhanced: bool, _shot_number: int) -> void:
	pass


func _spawn_longshot_projectile(enhanced: bool, shot_number: int, visual_only: bool = false) -> bool:
	var scene := player.get_tree().current_scene
	if scene == null:
		return false
	var direction: Vector3 = player._visual_rig.get_aim_forward_direction() if player._has_skeletal_weapon_attachment() else player._normalized_aim_direction()
	direction = direction.normalized()
	var start := player._longshot_muzzle.global_position if player._longshot_muzzle != null else player.global_position + Vector3.UP * 0.9 + direction * 0.7
	var definition := player._longshot_definition.duplicate(true)
	var radius := float(definition["projectile_radius"]) * (float(definition["enhanced_size_multiplier"]) if enhanced else 1.0)
	var speed := float(definition["projectile_speed"]) * (float(definition["enhanced_speed_multiplier"]) if enhanced else 1.0)
	var maximum := float(definition["max_range"])
	var projectile := PLAYER_STATE.LONGSHOT_PROJECTILE.new()
	projectile.name = "LongshotEnhancedProjectile" if enhanced else "LongshotProjectile"
	projectile.process_mode = Node.PROCESS_MODE_PAUSABLE
	scene.add_child(projectile)
	projectile.global_position = start
	projectile.look_at(start + direction, Vector3.UP)
	var excluded: Array[RID] = [player.get_rid()]
	if player.survival_mode and player.survival_evolution_effects != null:
		excluded.append_array(player.survival_evolution_effects.own_wall_exclusions())
	projectile.configure(direction, speed, maximum, 1 | 2 | 4 | 8, excluded, radius)
	player._register_projectile_motion(projectile, start, start + direction * maximum, maximum / speed, radius)
	var shot_id := "longshot:%d:%d" % [player.get_instance_id(), player._longshot_attack_token]
	var passive_attack: Dictionary = {} if visual_only else player.emit_passive_weapon()
	projectile.finished.connect(player._on_longshot_projectile_finished.bind(definition, enhanced, shot_id, visual_only, passive_attack))
	# Progress belongs to this weapon instance; only a successfully created shot commits it.
	if not visual_only:
		player._longshot_state.commit_shot()
	player._last_projectile_direction = direction
	player._mark_combat_event()
	var vfx: Node = player._vfx_manager()
	if vfx != null:
		vfx.call("projectile_visual", projectile, "longshot", 1.0 if enhanced else 0.0)
		vfx.call("muzzle", player._longshot_muzzle, "longshot", 1.0 if enhanced else 0.0)
	if player._visual_rig != null:
		player._visual_rig.play_shot_kick(0.70 if enhanced else 0.25)
	else:
		player._play_longshot_fallback_recoil(enhanced)
	var sound := player._longshot_enhanced_audio if enhanced else player._longshot_shot_audio
	if sound != null:
		sound.play()
	player._camera_impulse(0.07 if enhanced else 0.045, 0.05 if enhanced else 0.025)
	if player._attack_label != null:
		player._attack_label.text = "LONGSHOT  •  TIR AMÉLIORÉ" if enhanced else "LONGSHOT  •  %d / 4" % (shot_number % 5)
	# Check the full physical barrel route without relocating the projectile origin.
	projectile.resolve_muzzle_guard(player.global_position + Vector3.UP * 0.9)
	return true


func _on_longshot_projectile_finished(hit: Dictionary, distance: float, definition: Dictionary, enhanced: bool, shot_id: String, visual_only: bool = false, passive_attack: Dictionary = {}) -> void:
	if hit.is_empty():
		return
	var target := hit.get("collider") as Node
	while target != null and not target.has_method("take_damage"):
		target = target.get_parent()
	if not visual_only and target != null:
		var damage: float = PLAYER_STATE.LONGSHOT_STATE.damage_at_distance(distance, enhanced, definition)
		var effective: float = player.passive_weapon_damage(target, damage, "player", shot_id, passive_attack, hit.position)
		if effective > 0.0 and target.has_method("flash_impact"):
			target.call("flash_impact", enhanced)
	player._contact_fx(hit, Color("#79efff") if enhanced else Color("#43d5e8"), 1.25 if enhanced else 0.65)
	if enhanced:
		var sfx := player.get_node_or_null("/root/GameSfx")
		if sfx != null:
			sfx.call("play_event", "impact_critical")


func _create_longshot_visual() -> void:
	var scene := load("res://scenes/weapons/longshot.tscn") as PackedScene
	if scene == null:
		return
	player._longshot_pivot = Node3D.new()
	player._longshot_pivot.name = "LongshotPivot"
	player._longshot_visual = scene.instantiate() as Node3D
	player._longshot_pivot.add_child(player._longshot_visual)
	player._longshot_muzzle = player._longshot_visual.get_node("Muzzle") as Node3D
	player._attach_weapon_pivot_to_hand(player._longshot_pivot, &"longshot", Vector3(0.58, 0.88, -0.36), Vector3.ZERO, -22.0)
	player._longshot_shot_audio = AudioStreamPlayer.new()
	player._longshot_shot_audio.name = "LongshotShotAudio"
	player._longshot_shot_audio.stream = PLAYER_STATE.BLASTER_SHOT_SOUND
	player._longshot_shot_audio.pitch_scale = 0.84
	player._longshot_shot_audio.volume_db = -8.0
	player.add_child(player._longshot_shot_audio)
	player._longshot_enhanced_audio = AudioStreamPlayer.new()
	player._longshot_enhanced_audio.name = "LongshotEnhancedAudio"
	player._longshot_enhanced_audio.stream = PLAYER_STATE.BLASTER_CHARGED_SHOT_SOUND
	player._longshot_enhanced_audio.pitch_scale = 0.78
	player._longshot_enhanced_audio.volume_db = -5.0
	player.add_child(player._longshot_enhanced_audio)


func _play_longshot_fallback_recoil(enhanced: bool) -> void:
	if player._longshot_visual == null:
		return
	var tween := player.create_tween()
	tween.tween_property(player._longshot_visual, "position:z", 0.10 if enhanced else 0.06, 0.045)
	tween.tween_property(player._longshot_visual, "position:z", 0.0, 0.15)
