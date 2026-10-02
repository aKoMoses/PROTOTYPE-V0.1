extends "res://scripts/robot_forge_preview.gd"

## Reuse the combat model and paint, but keep the versus portrait facing inward.
var face_left := false
var _opaque_paint := Shader.new()

func _ready() -> void:
	super._ready()
	_turntable.rotation.y = deg_to_rad(18.0 if face_left else -18.0)
	_viewport.get_node("Showroom/PreviewCamera").size *= 0.84
	# Chassis paint uses transparency for combat concealment. In this opaque
	# showroom it can sort rear armour over the face; keep the shader local.
	_opaque_paint.code = CHASSIS_VISUALS.PAINT_SHADER.code.replace("ALPHA = visibility_opacity;", "").replace("depth_prepass_alpha", "depth_draw_opaque")

func _process(delta: float) -> void:
	if is_visible_in_tree() and _animation_player != null:
		_animation_player.advance(delta)

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
