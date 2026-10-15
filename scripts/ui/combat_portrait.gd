extends "res://scripts/robot_forge_preview.gd"

## Reuse the combat model and paint, but keep the versus portrait facing inward.
const PREPARATION_STATES := ["warm_up", "box_01", "idle"]
const PREPARATION_BLEND := 0.35
var face_left := false
var _opaque_paint := Shader.new()

func _ready() -> void:
	super._ready()
	_turntable.rotation.y = deg_to_rad(18.0 if face_left else -18.0)
	# Leave room for elbows and the wider warm-up stance on every chassis.
	_viewport.get_node("Showroom/PreviewCamera").size *= 0.92
	# Chassis paint uses transparency for combat concealment. In this opaque
	# showroom it can sort rear armour over the face; keep the shader local.
	_opaque_paint.code = CHASSIS_VISUALS.PAINT_SHADER.code.replace("ALPHA = visibility_opacity;", "").replace("depth_prepass_alpha", "depth_draw_opaque")

func _process(delta: float) -> void:
	if not is_visible_in_tree() or _animation_player == null or _clips.is_empty():
		return
	_clip_elapsed += delta
	if _clip_elapsed >= _clip_duration:
		_clip_index = (_clip_index + 1) % _clips.size()
		_play_clip()
	_animation_player.advance(delta)

func _setup_animations() -> void:
	super._setup_animations()
	# Only in-place preparation gestures belong in the versus portraits.
	# The inherited setup already gives each portrait its own rooted clips.
	var preparation: Array[StringName] = []
	for state in PREPARATION_STATES:
		for clip_name in _clips:
			if String(clip_name).get_file().to_lower() == state:
				preparation.append(clip_name)
	_clips = preparation
	start_preparation()

func start_preparation() -> void:
	if _animation_player == null or _clips.is_empty():
		return
	# Different openings and playback rates keep the duel from moving in sync.
	_clip_index = 1 if face_left and _clips.size() > 1 else 0
	_play_clip()
	var opening_offset := 0.6 if face_left else 1.2
	_animation_player.seek(opening_offset, true)
	var clip := _animation_player.get_animation(_clips[_clip_index])
	_clip_duration = minf(_clip_duration, (clip.length - opening_offset) / _animation_player.get_playing_speed())

func _play_clip() -> void:
	if _animation_player == null or _clips.is_empty():
		return
	var clip_name := _clips[_clip_index]
	var clip := _animation_player.get_animation(clip_name)
	var speed := 1.05 if face_left else 0.95
	_clip_elapsed = 0.0
	# Warm-up is eighteen seconds long; show a short gesture during the reveal.
	_clip_duration = minf(3.2, clip.length / speed)
	_animation_player.play(clip_name, PREPARATION_BLEND, speed)

func set_chassis(value: String) -> void:
	super.set_chassis(value)
	if _model == null:
		return
	for mesh in _model.find_children("*", "MeshInstance3D", true, false):
		for surface in range(mesh.get_surface_override_material_count()):
			var material := mesh.get_surface_override_material(surface) as ShaderMaterial
			if material != null and material.shader == CHASSIS_VISUALS.PAINT_SHADER:
				var copy := material.duplicate() as ShaderMaterial
				copy.shader = _opaque_paint
				mesh.set_surface_override_material(surface, copy)
