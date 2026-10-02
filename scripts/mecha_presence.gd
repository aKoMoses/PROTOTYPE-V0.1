extends Node3D

const WEIGHT := preload("res://scripts/mecha_weight_modifier.gd")
const AUDIO := preload("res://scripts/mecha_audio.gd")
var actor: Node3D
var observer: Node3D
var manager: Node
var rig: Node3D
var weight: SkeletonModifier3D
var cue: MeshInstance3D
var motor: AudioStreamPlayer3D
var servo: AudioStreamPlayer3D
var velocity := Vector3.ZERO
var _previous := Vector3.ZERO
var _previous_velocity := Vector3.ZERO
var _lean := Vector2.ZERO
var _clock := 0.0
var _servo_cooldown := 0.0
var _was_dashing := false
var _last_intent := ""
var _reset_state: CombatState
var _chest := -1

func _ready() -> void:
	process_priority = 90
	process_mode = Node.PROCESS_MODE_PAUSABLE
	rig = actor.get("_visual_rig") as Node3D
	_previous = actor.global_position
	if rig == null:
		queue_free()
		return
	var skeleton := rig.get("skeleton") as Skeleton3D
	if skeleton != null:
		for index in skeleton.get_bone_count():
			if String(skeleton.get_bone_name(index)).to_lower().ends_with("spine2"):
				_chest = index
		weight = WEIGHT.new()
		weight.name = "CombatWeight"
		skeleton.add_child(weight)
		# Preserve the concurrent contextual gestures and both existing hand solvers.
		for child in skeleton.get_children():
			if child.name in ["PlayerAimModifier", "AimModifier", "MechaPresence", "DroidPose"]:
				skeleton.move_child(weight, child.get_index())
				break
	cue = MeshInstance3D.new()
	cue.name = "IntentVent"
	cue.mesh = _vent_mesh()
	cue.position = Vector3(0.0, 1.18, -0.08)
	cue.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.emission_enabled = true
	material.emission_energy_multiplier = 1.4
	cue.material_override = material
	rig.add_child(cue)
	cue.top_level = true
	cue.hide()
	motor = _voice("ReactorMotor", AUDIO.stream("motor"))
	servo = _voice("JointServo", AUDIO.stream("servo"))
	_sync_state()

func _vent_mesh() -> ImmediateMesh:
	# Three inset light slits on the front and back of the reactor housing.
	# Open space between them keeps the armour visible from the gameplay camera.
	var mesh := ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for depth in [-0.18, 0.18]:
		for band in [-0.04, 0.0, 0.04]:
			var a := Vector3(-0.10, band - 0.011, depth)
			var b := Vector3(0.10, band - 0.011, depth)
			var c := Vector3(0.10, band + 0.011, depth)
			var d := Vector3(-0.10, band + 0.011, depth)
			for point in [a, b, c, a, c, d]:
				mesh.surface_add_vertex(point)
	mesh.surface_end()
	return mesh

func _voice(label: String, stream: AudioStream) -> AudioStreamPlayer3D:
	var voice := AudioStreamPlayer3D.new()
	voice.name = label
	voice.stream = stream
	voice.bus = &"Effects"
	voice.max_polyphony = 1
	voice.unit_size = 3.0
	voice.max_distance = 18.0
	voice.position.y = 0.9
	add_child(voice)
	return voice

func _sync_state() -> void:
	var state: CombatState = actor.get("combat_state")
	if state == _reset_state:
		return
	if is_instance_valid(_reset_state) and _reset_state.reset_completed.is_connected(reset):
		_reset_state.reset_completed.disconnect(reset)
	_reset_state = state
	if _reset_state != null:
		_reset_state.reset_completed.connect(reset)
	reset()

func reset() -> void:
	_previous = actor.global_position if is_instance_valid(actor) else Vector3.ZERO
	_previous_velocity = Vector3.ZERO
	velocity = Vector3.ZERO
	_lean = Vector2.ZERO
	_last_intent = ""
	_was_dashing = false
	if weight != null:
		weight.set("lean", Vector2.ZERO)
		weight.set("enabled", false)
	if cue != null:
		cue.hide()
	if motor != null:
		motor.stop()
	if servo != null:
		servo.stop()

func admitted() -> bool:
	if not is_instance_valid(actor) or not actor.is_visible_in_tree() or not is_instance_valid(observer):
		return false
	if actor.has_method("is_real_dead") and bool(actor.call("is_real_dead")):
		return false
	if actor != observer and actor.has_method("is_visible_to") and not bool(actor.call("is_visible_to", observer)):
		return false
	if actor.has_method("is_gameplay_enabled"):
		return bool(actor.call("is_gameplay_enabled"))
	return actor.has_method("is_training_bot_enabled") and bool(actor.call("is_training_bot_enabled"))

func intent() -> String:
	if actor.has_method("is_counter_guarding") and bool(actor.call("is_counter_guarding")):
		return "guard"
	if "_blaster_charge_active" in actor and bool(actor.get("_blaster_charge_active")):
		return "charge"
	if "_fulguro_phase" in actor and str(actor.get("_fulguro_phase")) == "charge":
		return "strike"
	if actor.has_method("is_shotgun_reloading") and bool(actor.call("is_shotgun_reloading")):
		return "reload"
	var bot: Node = actor.get_node_or_null("TrainingBot")
	if bot != null and bool(bot.get("enabled")):
		var equipment: Node = bot.get("_duel_equipment")
		if equipment != null:
			var counter: Node = equipment.get("_counter")
			if counter != null and str(counter.get("phase")) == "guard":
				return "guard"
			if float(equipment.get("reload_remaining")) > 0.0:
				return "reload"
		if float(bot.get("_windup_remaining")) > 0.0:
			return "strike" if str(bot.get("_attack_mode")) in ["fulguro", "pelto"] or str(bot.get("survival_role")) in ["charger", "boss"] else "charge"
	return ""

func _process(delta: float) -> void:
	_sync_state()
	if not admitted() or delta <= 0.0:
		reset()
		return
	_clock += delta
	_servo_cooldown = maxf(0.0, _servo_cooldown - delta)
	var motion := actor.global_position - _previous
	_previous = actor.global_position
	# Respawn, teleportation and pause transitions cannot create a landing burst.
	if motion.length() > maxf(1.2, delta * 25.0):
		reset()
		return
	velocity = motion / delta
	velocity.y = 0.0
	var acceleration := (velocity - _previous_velocity) / maxf(delta, 0.008)
	var local_acceleration := rig.global_basis.orthonormalized().inverse() * acceleration
	var special := "_active_action" in rig and String(rig.get("_active_action")) != ""
	var aiming := bool(rig.get("_aim_requested")) if "_aim_requested" in rig else float(rig.get("aim_weight")) > 0.2
	var desired := Vector2(-local_acceleration.x * 0.0028, local_acceleration.z * 0.0032)
	desired = desired.clamp(Vector2(-0.065, -0.075), Vector2(0.065, 0.075))
	_lean = _lean.lerp(desired, 1.0 - exp(-12.0 * delta))
	if weight != null:
		weight.set("enabled", not special and not aiming)
		weight.set("lean", _lean)
	var current_intent := intent()
	cue.visible = current_intent != ""
	if cue.visible:
		var skeleton := rig.get("skeleton") as Skeleton3D
		if skeleton != null and _chest >= 0:
			cue.global_position = skeleton.global_transform * skeleton.get_bone_global_pose(_chest).origin
			cue.global_basis = rig.global_basis.orthonormalized()
		else:
			cue.global_position = actor.global_position + Vector3.UP * 1.1
		var tint: Color = {"guard": Color("#a78ae8"), "charge": Color("#ffd078"), "strike": Color("#ff8050"), "reload": Color("#75959a")}[current_intent]
		(cue.material_override as StandardMaterial3D).albedo_color = tint
		(cue.material_override as StandardMaterial3D).emission = tint
		var housing := 2.1 if actor.has_method("get_robot_id") and str(actor.call("get_robot_id")) == "puissant" else 1.0
		cue.scale = Vector3(1.0, 1.0, housing) * (1.0 + sin(_clock * (20.0 if current_intent == "strike" else 10.0)) * 0.12)
	var chassis := str(actor.call("get_robot_id")) if actor.has_method("get_robot_id") else "polyvalent"
	var pitch: float = {"agile": 1.12, "polyvalent": 1.0, "puissant": 0.84}.get(chassis, 1.0)
	motor.pitch_scale = pitch * (1.0 + clampf(velocity.length() / 8.0, 0.0, 1.0) * 0.12)
	var engine_level := -40.0 + minf(8.0, velocity.length() * 1.1) + (4.0 if current_intent in ["strike", "charge"] else 0.0)
	motor.volume_db = lerpf(motor.volume_db, engine_level, 1.0 - exp(-6.0 * delta))
	if not motor.playing:
		motor.volume_db = engine_level
		motor.play()
	if _servo_cooldown <= 0.0 and (acceleration.length() > 22.0 and _previous_velocity.length() > 1.0 or current_intent != _last_intent and not current_intent.is_empty()):
		servo.pitch_scale = pitch
		servo.volume_db = -30.0 if actor == observer else -35.0
		servo.play()
		_servo_cooldown = 0.32
	var dash := actor.has_method("is_dash_active") and bool(actor.call("is_dash_active"))
	if dash and not _was_dashing:
		manager.call("locomotion_dust", actor.global_position, -velocity.normalized(), 1.0)
		var director := manager.get_parent().get_node_or_null("CombatPresentationPass")
		if director != null:
			director.call("react_at", actor.global_position, 0.8)
	elif _was_dashing and not dash:
		manager.call("locomotion_dust", actor.global_position, Vector3.UP, 0.55)
	elif _previous_velocity.length() > 3.0 and velocity.length() < 0.5:
		manager.call("locomotion_dust", actor.global_position, -_previous_velocity.normalized(), 0.28)
	_previous_velocity = velocity
	_was_dashing = dash
	_last_intent = current_intent

func _exit_tree() -> void:
	if is_instance_valid(_reset_state) and _reset_state.reset_completed.is_connected(reset):
		_reset_state.reset_completed.disconnect(reset)
	if is_instance_valid(weight):
		weight.queue_free()
	if is_instance_valid(cue):
		cue.queue_free()
