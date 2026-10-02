extends Node3D

## Rigid, authored Blender joints. Playback belongs to this garage instance.
signal service_started
signal service_finished
signal manual_control_cancelled

const SOURCE := preload("res://art/forge-garage/service_arm.glb")
var model: Node3D
var animator: AnimationPlayer
var contact: Node3D
var clip: StringName = &""
var elapsed := 0.0
var active := false
var particles: GPUParticles3D
var manual_control := false
var manual_phase := "SCANNER MANUEL"


func _ready() -> void:
	model = SOURCE.instantiate() as Node3D
	add_child(model)
	contact = model.find_child("ToolContact", true, false) as Node3D
	for node in model.find_children("*", "AnimationPlayer", true, false):
		animator = node as AnimationPlayer
		break
	if animator == null:
		push_error("Forge arm: imported animation player missing")
		return
	for library_name in animator.get_animation_library_list():
		var library := animator.get_animation_library(library_name).duplicate(true) as AnimationLibrary
		animator.remove_animation_library(library_name)
		animator.add_animation_library(library_name, library)
	for candidate in animator.get_animation_list():
		var clip_label := String(candidate).get_slice("/", String(candidate).get_slice_count("/") - 1).to_lower().replace("_", "").replace(" ", "").replace("-", "")
		# Godot recognizes _cycle as an import loop suffix and removes it.
		if clip_label in ["service", "servicecycle"]:
			clip = candidate
			break
	if clip == &"":
		push_error("Forge arm: service_cycle not exported: " + str(animator.get_animation_list()))
		return
	animator.get_animation(clip).loop_mode = Animation.LOOP_NONE
	animator.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	_build_sparks()
	seek_service(0.0)
	active = false


func start_service() -> bool:
	if active or animator == null or clip == &"":
		return false
	elapsed = 0.0
	active = true
	animator.play(clip)
	animator.seek(0.0, true)
	animator.advance(0.0)
	service_started.emit()
	return true


func cancel_service() -> void:
	var was_manual := manual_control
	manual_control = false
	seek_service(0.0)
	active = false
	if particles != null:
		particles.emitting = false
	if was_manual:
		manual_control_cancelled.emit()


func begin_manual_control() -> void:
	cancel_service()
	manual_control = true
	active = true
	animator.pause()


func end_manual_control() -> void:
	manual_control = false
	cancel_service()


func advance_service(delta: float) -> void:
	if not active or animator == null or manual_control:
		return
	elapsed += delta
	animator.advance(delta)
	if particles != null:
		particles.emitting = elapsed >= 3.95 and elapsed <= 5.70
	if elapsed >= animator.get_animation(clip).length:
		active = false
		if particles != null:
			particles.emitting = false
		service_finished.emit()


func seek_service(seconds: float) -> void:
	if animator == null or clip == &"":
		return
	elapsed = clampf(seconds, 0.0, animator.get_animation(clip).length)
	animator.play(clip)
	animator.seek(elapsed, true)
	animator.advance(0.0)
	if particles != null:
		particles.emitting = elapsed >= 3.95 and elapsed <= 5.70


func phase_name() -> String:
	if manual_control:
		return manual_phase
	if not active:
		return "ATELIER OPÉRATIONNEL"
	if elapsed < 3.9:
		return "MISE EN POSITION"
	if elapsed <= 5.7:
		return "CONTRÔLE DU CHÂSSIS"
	return "RETOUR DU BRAS"


func _build_sparks() -> void:
	if contact == null:
		return
	particles = GPUParticles3D.new()
	particles.name = "ContactSparks"
	particles.amount = 20
	particles.lifetime = 0.26
	particles.emitting = false
	particles.visibility_aabb = AABB(Vector3(-1, -1, -1), Vector3(2, 2, 2))
	var material := ParticleProcessMaterial.new()
	material.direction = Vector3(-0.3, 0.7, 0.5)
	material.spread = 55.0
	material.initial_velocity_min = 0.6
	material.initial_velocity_max = 1.8
	material.gravity = Vector3(0, -4, 0)
	material.scale_min = 0.6
	material.scale_max = 1.3
	particles.process_material = material
	var mesh := SphereMesh.new()
	mesh.radius = 0.007
	mesh.height = 0.014
	mesh.radial_segments = 6
	mesh.rings = 3
	var glow := StandardMaterial3D.new()
	glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glow.albedo_color = Color("#ffc15f")
	glow.emission_enabled = true
	glow.emission = Color("#ff9a34")
	glow.emission_energy_multiplier = 3.0
	mesh.material = glow
	particles.draw_pass_1 = mesh
	contact.add_child(particles)
