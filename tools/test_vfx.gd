extends SceneTree

# Headless integration and bounded-lifetime stress of the production VFX.
const STEP := 1.0 / 60.0
const STRESS_SECONDS := 180.0
var _failures: Array[String] = []
var _checks := 0
var _scene: Node
var _manager: Node
var _player: Node3D
var _target: Node3D


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(_scene)
	current_scene = _scene
	await process_frame
	_manager = _scene.get_node_or_null("VFXManager")
	_player = _scene.get_node_or_null("Player") as Node3D
	_target = _scene.get_node_or_null("TargetDummy") as Node3D
	_check(_manager != null and _player != null and _target != null, "production scene exposes manager, player and target")
	if _manager == null or _player == null or _target == null:
		_finish()
		return
	_target.call("set_training_bot_enabled", false)
	_player.call("set_gameplay_enabled", true)
	await _test_status_lifetime(_target)
	await _test_status_lifetime(_player)
	await _test_flash_reentry()
	await _test_attachment_and_normals()
	await _test_visual_only()
	await _test_budget_preserves_damage()
	await _test_weapon_motion()
	await _test_round_reset_cleanup()
	await _test_stress(1)
	await _test_stress(0)
	await _test_real_time_cleanup()
	current_scene = null
	_scene.queue_free()
	await process_frame
	_finish()


func _test_status_lifetime(actor: Node3D) -> void:
	actor.call("reset_combat_state")
	var status := actor.get_node_or_null("StatusVFX")
	_check(status != null, "%s owns attached StatusVFX" % actor.name)
	if status == null:
		return
	var state: RefCounted = actor.get("combat_state")
	var previously_processing := actor.is_processing()
	var previously_physics_processing := actor.is_physics_processing()
	actor.set_process(false)
	actor.set_physics_process(false)
	for effect in ["BURN", "SLOW", "STUN", "SPOTTED"]:
		actor.call("reset_combat_state")
		_apply_status(actor, effect, 0.3)
		status.call("sync", actor.call("get_active_effect_types"))
		var active: Array = status.call("get_active_effects")
		_check(active.size() == 1 and active.has(effect), "%s %s is independently visible" % [actor.name, effect])
		var original_position := actor.position
		actor.position += Vector3(0.8, 0.0, -0.3)
		_check(status.get_parent() == actor and (status as Node3D).global_position.distance_to(actor.global_position) < 0.1, "%s %s follows moving actor" % [actor.name, effect])
		actor.position = original_position
		state.call("update", 0.29)
		status.call("sync", actor.call("get_active_effect_types"))
		_check((status.call("get_active_effects") as Array).has(effect), "%s %s persists until gameplay expiry" % [actor.name, effect])
		state.call("update", 0.02)
		status.call("sync", actor.call("get_active_effect_types"))
		var counts: Dictionary = status.call("get_debug_counts")
		_check(int(counts["active_effects"]) == 0 and int(counts["emitting_particles"]) == 0, "%s %s stops at gameplay expiry" % [actor.name, effect])
	actor.call("reset_combat_state")
	for effect in ["BURN", "SLOW", "STUN", "SPOTTED"]:
		_apply_status(actor, effect, 0.4)
	status.call("sync", actor.call("get_active_effect_types"))
	_check((status.call("get_active_effects") as Array).size() == 4, "%s all statuses coexist" % actor.name)
	state.call("update", 0.2)
	_apply_status(actor, "BURN", 0.5)
	state.call("update", 0.21)
	status.call("sync", actor.call("get_active_effect_types"))
	var refreshed: Array = status.call("get_active_effects")
	_check(refreshed.size() == 1 and refreshed.has("BURN"), "%s reapplication refreshes only its visual lifetime" % actor.name)
	actor.call("reset_combat_state")
	status.call("sync", actor.call("get_active_effect_types"))
	_check((status.call("get_active_effects") as Array).is_empty(), "%s round reset clears all status visuals" % actor.name)
	actor.set_process(previously_processing)
	actor.set_physics_process(previously_physics_processing)
	await process_frame


func _apply_status(actor: Node, effect: String, duration: float) -> void:
	match effect:
		"BURN": actor.call("apply_burn", duration, 0.0, "vfx_test")
		"SLOW": actor.call("apply_slow", duration, 30.0, "vfx_test")
		"STUN": actor.call("apply_stun", duration, "vfx_test")
		"SPOTTED": actor.call("apply_spotted", duration, "vfx_test")


func _test_flash_reentry() -> void:
	var visual := Node3D.new()
	var mesh := MeshInstance3D.new()
	mesh.mesh = BoxMesh.new()
	var original_overlay := StandardMaterial3D.new()
	original_overlay.albedo_color = Color(0.2, 0.3, 0.4, 0.12)
	mesh.material_overlay = original_overlay
	visual.add_child(mesh)
	_scene.add_child(visual)
	_manager.call("hit_flash", visual, false)
	_check(mesh.material_overlay != original_overlay, "hit flash adds a brief overlay")
	_manager.call("_process", 0.025)
	_manager.call("hit_flash", visual, true)
	_manager.call("_process", 0.025)
	_check(mesh.material_overlay != original_overlay, "second hit refreshes flash without early restoration")
	_manager.call("_process", 0.2)
	_check(mesh.material_overlay == original_overlay, "repeated hit flash restores authored overlay")
	_manager.call("hit_flash", visual, false)
	_manager.call("clear")
	_check(mesh.material_overlay == original_overlay, "round clear restores active hit overlays")
	visual.queue_free()
	await process_frame


func _test_visual_only() -> void:
	_target.call("reset_combat_state")
	var before := float(_target.call("get_health"))
	for surface in ["metal", "wall", "ground", "robot", "shield"]:
		_manager.call("impact", _target.global_position + Vector3.UP, Vector3.UP, surface, 1.0)
	_manager.call("burst", _target.global_position, Vector3.UP, Color.WHITE, 12)
	_manager.call("tracer", _player.global_position, _target.global_position)
	_manager.call("hit_flash", _target)
	await create_timer(0.12).timeout
	_check(is_equal_approx(before, float(_target.call("get_health"))), "VFX impact/burst/tracer/flash never apply gameplay damage")
	_manager.call("clear")


func _test_attachment_and_normals() -> void:
	_manager.call("clear")
	var socket := Marker3D.new()
	_scene.add_child(socket)
	socket.position = Vector3(2.0, 1.0, -3.0)
	_manager.call("muzzle", socket, "blaster", 0.0)
	var normal_size := 0.0
	for effect in _manager.get("_active"):
		if str(effect["kind"]) == "muzzle":
			normal_size = maxf(normal_size, (effect["size"] as Vector3).x)
	socket.position += Vector3(0.7, 0.0, 0.4)
	socket.rotation = Vector3(0.1, 1.1, -0.15)
	_manager.call("_process", 0.01)
	var attached_count := 0
	var correctly_attached := true
	for effect in _manager.get("_active"):
		if str(effect["kind"]) != "muzzle":
			continue
		attached_count += 1
		var node: Node3D = effect["node"]
		var expected := socket.global_position + socket.global_basis.orthonormalized() * (effect["offset"] as Vector3)
		correctly_attached = correctly_attached and node.global_position.distance_to(expected) < 0.001 and node.global_basis.z.normalized().dot(socket.global_basis.z.normalized()) > 0.999
	_check(attached_count == 2 and correctly_attached, "muzzle flash follows translated/rotated socket precisely")
	_manager.call("clear")
	_manager.call("muzzle", socket, "blaster", 1.0)
	var charged_size := 0.0
	for effect in _manager.get("_active"):
		if str(effect["kind"]) == "muzzle":
			charged_size = maxf(charged_size, (effect["size"] as Vector3).x)
	_check(charged_size > normal_size * 1.3, "charged muzzle has a distinct silhouette")
	socket.queue_free()
	await process_frame
	_manager.call("_process", 0.01)
	var dangling_attachments := 0
	for effect in _manager.get("_active"):
		if effect["attachment"] != null:
			dangling_attachments += 1
	_check(dangling_attachments == 0, "freed muzzle socket releases attached flashes")
	for normal in [Vector3.UP, Vector3.BACK, Vector3.RIGHT, Vector3(0.2, 0.8, -0.4).normalized()]:
		_manager.call("clear")
		var position := Vector3(1.0, 0.0, -2.0)
		_manager.call("impact", position, normal, "metal", 1.0)
		var checked_particles := false
		var checked_decal := false
		var outward_particles := true
		var aligned_decal := true
		for effect in _manager.get("_active"):
			var node: Node3D = effect["node"]
			if node is GPUParticles3D:
				var material: ParticleProcessMaterial = node.process_material
				checked_particles = true
				outward_particles = outward_particles and material.direction.dot(normal) > 0.999 and material.spread < 90.0 and material.gravity.is_zero_approx() and (node.global_position - position).dot(normal) > 0.0
			if str(effect["kind"]) == "decal":
				checked_decal = true
				aligned_decal = aligned_decal and node.global_basis.y.normalized().dot(normal) > 0.999 and (node.global_position - position).dot(normal) > 0.0
		_check(checked_particles and outward_particles and checked_decal and aligned_decal, "impact normal %s keeps sparks outward and decal on surface" % normal)
	_manager.call("clear")


func _test_budget_preserves_damage() -> void:
	_player.call("reset_combat_state")
	_target.call("reset_combat_state")
	_player.position = Vector3.ZERO
	_target.position = Vector3(0.0, 0.0, -4.0)
	await physics_frame
	var start := Vector3(0.0, 0.82, -0.75)
	var endpoint := _target.position + Vector3.UP * 0.82
	for index in range(20):
		_player.call("_spawn_blaster_projectile", start, endpoint, start.distance_to(endpoint), true, _target, 20.0, 0.0, 5000 + index)
	_scene.call("_trim_fx_budget")
	await create_timer(0.65).timeout
	var damage := 1000.0 - float(_target.call("get_health"))
	_check(absf(damage - 400.0) < 0.1, "20 damage-bearing projectiles survive visual budget pressure (damage %.1f)" % damage)
	_target.call("reset_combat_state")
	_manager.call("clear")


func _test_weapon_motion() -> void:
	for charge in [0.0, 1.0]:
		_player.call("reset_combat_state")
		_player.call("set_weapon", "blaster")
		_target.call("reset_combat_state")
		_player.position = Vector3.ZERO
		_target.position = Vector3(0.0, 0.0, -4.0)
		_player.set("aim_direction", Vector3.FORWARD)
		_player.call("set_touch_move_vector", Vector2(1.0, 0.0))
		await physics_frame
		var before := _player.position
		var direction := (_target.position - _player.position).normalized()
		var expected_damage := 50.0 if charge > 0.0 else 20.0
		_player.call("_fire_blaster_projectile", expected_damage, charge, direction)
		await create_timer(0.4).timeout
		_player.call("clear_touch_inputs")
		var damage := 1000.0 - float(_target.call("get_health"))
		_check(_player.position.distance_to(before) > 0.1 and absf(damage - expected_damage) < 0.1, "moving blaster charge %.1f retains exact damage %.1f" % [charge, damage])
	_target.call("reset_combat_state")
	_manager.call("clear")


func _test_round_reset_cleanup() -> void:
	_player.call("reset_combat_state")
	_target.call("reset_combat_state")
	_player.call("_create_stasis_fx")
	await process_frame
	var shield := _player.get("_stasis_visual") as Node
	_check(is_instance_valid(shield), "stasis shield registers its resettable visual")
	_player.call("reset_module_state")
	await process_frame
	_check(_player.get("_stasis_visual") == null and not is_instance_valid(shield), "round reset removes the active stasis visual")

	_player.call("set_weapon", "shotgun")
	await process_frame
	var shotgun_muzzle := _player.get("_shotgun_muzzle") as Node3D
	var module_start: Vector3 = _player.call("_module_visual_start", Vector3.FORWARD)
	_check(shotgun_muzzle != null and module_start.distance_to(shotgun_muzzle.global_position) < 0.001, "module visuals use the equipped weapon muzzle")
	_player.call("set_weapon", "blaster")

	_player.position = Vector3.ZERO
	_target.position = Vector3(0.0, 0.0, -4.0)
	await physics_frame
	for module_kind in ["drone", "javelin"]:
		_target.call("reset_combat_state")
		var health_before := float(_target.call("get_health"))
		_player.set("_module_busy", true)
		var token_property := "_module_token" if module_kind == "drone" else "_javelin_launch_token"
		var token := int(_player.get(token_property))
		var direction := (_target.position - _player.position).normalized()
		if module_kind == "drone":
			_player.call("_emit_modulo_drone", token, _player.position, direction)
		else:
			_player.call("_emit_javelin", token, _player.position, direction)
		_scene.call("clear_transient_fx")
		_player.call("reset_module_state")
		await process_frame
		await create_timer(0.7).timeout
		_check(is_equal_approx(health_before, float(_target.call("get_health"))), "%s projectile cannot damage after round reset" % module_kind)
	_check(get_nodes_in_group("prototype0_gameplay_projectiles").is_empty(), "round reset leaves no gameplay projectile visuals")
	_manager.call("clear")


func _test_stress(quality: int) -> void:
	_manager.call("clear")
	_manager.set("quality", quality)
	_manager.set_process(false)
	var frames := roundi(STRESS_SECONDS / STEP)
	var peak_active := 0
	var peak_decals := 0
	var peak_particles := 0
	var halfway_nodes := 0
	var max_effects := int(_manager.get("max_effects"))
	var max_decals := int(_manager.get("max_decals"))
	var max_particles := int(_manager.get("max_particles"))
	var factor := 0.5 if quality == 0 else 1.0
	var active_limit := int(max_effects * factor) + int(max_decals * factor) + int(max_particles * factor)
	var limits_respected := true
	for frame in range(frames):
		if frame % 3 == 0:
			_manager.call("tracer", Vector3.ZERO, Vector3(1.0, 0.8, -4.0))
		if frame % 6 == 0:
			_manager.call("burst", Vector3.ZERO, Vector3.UP, Color(1.0, 0.55, 0.2), 8)
		if frame % 12 == 0:
			var normal := Vector3.UP if frame % 24 == 0 else Vector3.BACK
			_manager.call("impact", Vector3(float(frame % 7) * 0.1, 0.0, -2.0), normal, "metal", 1.0)
		_manager.call("_process", STEP)
		if frame % 60 == 0:
			var counts: Dictionary = _manager.call("get_debug_counts")
			peak_active = maxi(peak_active, int(counts["active"]))
			peak_decals = maxi(peak_decals, int(counts["decals"]))
			peak_particles = maxi(peak_particles, int(counts["particles"]))
			limits_respected = limits_respected and int(counts["active"]) <= active_limit and int(counts["decals"]) <= int(max_decals * factor) and int(counts["particles"]) <= int(max_particles * factor) and int(counts["pooled"]) <= max_effects + max_decals + max_particles
			await process_frame
		if frame == frames / 2:
			halfway_nodes = _descendant_count(_manager)
	var final_nodes := _descendant_count(_manager)
	_check(limits_respected, "quality %d stress respects effect, decal and particle caps" % quality)
	_check(final_nodes <= halfway_nodes + 8, "quality %d pool plateaus over 3 simulated minutes (%d -> %d nodes)" % [quality, halfway_nodes, final_nodes])
	_manager.call("_process", 30.0)
	var expired: Dictionary = _manager.call("get_debug_counts")
	_check(int(expired["active"]) == 0 and int(expired["decals"]) == 0 and int(expired["particles"]) == 0, "quality %d all transient effects expire naturally" % quality)
	_manager.call("clear")
	var cleared: Dictionary = _manager.call("get_debug_counts")
	_check(int(cleared["active"]) == 0 and int(cleared["hit_flashes"]) == 0, "quality %d clear leaves no active effects" % quality)
	print("[VFXStress] quality=%d simulated_seconds=%.1f active_peak=%d decals_peak=%d particle_emitters_peak=%d nodes=%d pooled=%d" % [quality, STRESS_SECONDS, peak_active, peak_decals, peak_particles, final_nodes, int(cleared["pooled"])])
	_manager.set_process(true)
	await process_frame


func _test_real_time_cleanup() -> void:
	_manager.call("clear")
	_manager.call("tracer", Vector3.ZERO, Vector3.FORWARD)
	_manager.call("burst", Vector3.ZERO, Vector3.UP, Color.WHITE, 5, 2.0, 0.1)
	await create_timer(0.7).timeout
	var counts: Dictionary = _manager.call("get_debug_counts")
	_check(int(counts["active"]) == 0 and int(counts["particles"]) == 0, "real SceneTree frames retire expired transient effects")


func _descendant_count(node: Node) -> int:
	var total := node.get_child_count()
	for child in node.get_children():
		total += _descendant_count(child)
	return total


func _check(condition: bool, label: String) -> void:
	_checks += 1
	if condition:
		print("PASS: " + label)
	else:
		_failures.append(label)
		push_error("FAIL: " + label)


func _finish() -> void:
	print("VFX INTEGRATION TEST: %s (%d checks, %d failures)" % ["PASS" if _failures.is_empty() else "FAIL", _checks, _failures.size()])
	quit(0 if _failures.is_empty() else 1)
