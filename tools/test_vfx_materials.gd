extends SceneTree

const VFX := preload("res://scripts/vfx_manager.gd")
const ASSETS := preload("res://scripts/vfx_assets.gd")
const SHOT := preload("res://scripts/live_projectile.gd")
var manager: Node3D
var failures: Array[String] = []
var checks := 0

class ProtectedActor extends Node3D:
	var remaining := 0.5
	func take_damage(_amount: float) -> float:
		return 0.0
	func get_stasis_remaining() -> float:
		return remaining


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var stage := Node3D.new()
	root.add_child(stage)
	current_scene = stage
	manager = VFX.new()
	stage.add_child(manager)
	manager.set_process(false)
	var protected := ProtectedActor.new()
	stage.add_child(protected)
	check(manager.surface_for(protected) == "shield", "player stasis uses shield contact")
	protected.remaining = 0.0
	check(manager.surface_for(protected) == "robot", "expired stasis returns to robot contact")
	protected.set_meta("duel_static_shield", true)
	check(manager.surface_for(protected) == "shield", "bot stasis uses the same shield contact")
	protected.queue_free()
	for kind in ["smoke", "decal"]:
		var a := ASSETS.texture(kind, 0)
		var b := ASSETS.texture(kind, 1)
		check(a.get_width() == 128 and a == ASSETS.texture(kind, 0), kind + " is cached at 128px")
		check(a.get_image().get_data() != b.get_image().get_data(), kind + " has distinct variants")
		check(a.get_image().get_pixel(0, 0).a == 0.0, kind + " has transparent edges")
	for style in ["spark", "debris", "dust", "energy", "spark"]:
		manager.clear()
		manager.burst(Vector3.ZERO, Vector3.RIGHT, Color.WHITE, 8, 4.0, 0.3, 0.06, 65.0, style)
		var emitter := manager.get("_active")[0].node as GPUParticles3D
		var material := emitter.process_material as ParticleProcessMaterial
		check(emitter.draw_pass_1 == ASSETS.particle_mesh(style), style + " resets pooled particle geometry")
		check(material.particle_flag_align_y == (style == "spark"), style + " resets velocity alignment")
		check(material.direction == Vector3.RIGHT and material.gravity == Vector3.ZERO, style + " stays outward")
	manager.clear()
	manager.impact(Vector3.ZERO, Vector3.UP, "metal")
	var smoke: Dictionary = {}
	var debris: Dictionary = {}
	for effect in manager.get("_active"):
		if effect.kind == "smoke":
			smoke = effect
		if effect.get("style", "") == "debris":
			debris = effect
	check(not smoke.is_empty() and not debris.is_empty(), "metal includes smoke and chipped plates")
	check(not smoke.node.visible and debris.pending_start, "secondary layers wait for contact flash")
	manager._process(0.03)
	check(debris.node.visible and not debris.pending_start and not smoke.node.visible, "debris starts before smoke")
	manager._process(0.04)
	check(smoke.node.visible and smoke.node.material_override.get_shader_parameter("progress") > 0.0, "smoke starts after flash")
	manager.clear()
	manager._process(1.0)
	check(manager.get_debug_counts().active == 0, "clearing pending layers cannot resurrect effects")
	var socket := Marker3D.new()
	stage.add_child(socket)
	manager.muzzle(socket, "blaster")
	for index in range(80):
		manager._smoke(Vector3.ZERO, Vector3.UP, 0.5, 0.6)
	var muzzle_count := 0
	for effect in manager.get("_active"):
		if effect.kind == "muzzle":
			muzzle_count += 1
	check(muzzle_count == 2, "secondary smoke saturation preserves muzzle flashes")
	manager.clear()
	socket.queue_free()
	manager.impact(Vector3.ZERO, Vector3.BACK, "shield")
	var wave: Dictionary = {}
	for effect in manager.get("_active"):
		if effect.kind == "surface_wave":
			wave = effect
	check(not wave.is_empty() and wave.node.basis.y.dot(Vector3.BACK) > 0.999, "shield wave lies on the contact surface")
	manager._process(0.15)
	check(wave.node.material_override.get_shader_parameter("progress") > 0.4, "shield shader receives expanding wave age")
	manager._process(1.0)
	check(manager.get_debug_counts().active == 0, "shield wave and fragments expire")
	await _trail_contact(stage)
	for quality in [VFX.Quality.NORMAL, VFX.Quality.LOW]:
		manager.clear()
		manager.quality = quality
		var caps_ok := true
		for index in range(900):
			manager.impact(Vector3.ZERO, Vector3.UP, ["robot", "metal", "ground", "shield"][index % 4], 1.6)
			manager._process(1.0 / 60.0)
			var counts: Dictionary = manager.get_debug_counts()
			var factor := 0.5 if quality == VFX.Quality.LOW else 1.0
			caps_ok = caps_ok and counts.active <= int((manager.max_effects + manager.max_particles + manager.max_decals) * factor)
			caps_ok = caps_ok and counts.pooled <= manager.max_effects + manager.max_particles + manager.max_decals
		check(caps_ok, "quality %d stress keeps active and pooled budgets bounded" % quality)
		manager._process(20.0)
		check(manager.get_debug_counts().active == 0, "quality %d delayed effects all expire" % quality)
		manager.impact(Vector3.ZERO, Vector3.UP, "metal")
		var has_smoke := false
		for effect in manager.get("_active"):
			has_smoke = has_smoke or effect.kind == "smoke"
		check(has_smoke == (quality == VFX.Quality.NORMAL), "quality %d preserves contact and reduces secondary layers" % quality)
	manager.clear()
	current_scene = null
	stage.queue_free()
	await process_frame
	print("VFX MATERIALS TEST: %s (%d checks, %d failures)" % ["PASS" if failures.is_empty() else "FAIL", checks, failures.size()])
	quit(0 if failures.is_empty() else 1)


func _trail_contact(stage: Node3D) -> void:
	var wall := StaticBody3D.new()
	wall.position = Vector3(0.0, 0.0, -0.5)
	wall.collision_layer = 1
	var collider := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(4.0, 4.0, 0.1)
	collider.shape = shape
	wall.add_child(collider)
	stage.add_child(wall)
	await physics_frame
	for weapon in ["blaster", "longshot", "shotgun"]:
		manager.clear()
		var shot := SHOT.new()
		stage.add_child(shot)
		shot.set_physics_process(false)
		shot.configure(Vector3.FORWARD, 22.0, 7.0, 1, [])
		manager.projectile_visual(shot, weapon)
		var trail: Dictionary = manager.get("_active").back()
		check(trail.node.scale.z < 0.002, weapon + " trail never anticipates travel")
		shot._physics_process(0.01)
		manager._process(0.01)
		check(absf(trail.node.scale.z - 0.22) < 0.001, weapon + " trail follows actual travel")
		shot._physics_process(0.02)
		check(trail.attachment == null and absf(trail.node.position.z + 0.45) < 0.001, weapon + " trail stops exactly at wall")
		manager._process(0.08)
		check(manager.get_debug_counts().active == 0, weapon + " contact tail fades within 80ms")
		await process_frame
	wall.queue_free()
	await process_frame


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		push_error("FAIL: " + label)
