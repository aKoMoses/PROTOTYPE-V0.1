extends Node3D

## One reusable emissive mesh, no lights, no hitboxes and no combat decisions.
var _accent: MeshInstance3D
var _material: StandardMaterial3D
var _clock := 0.0
var _previous_inertia := 0.0


func _ready() -> void:
	_accent = MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = 0.06
	mesh.height = 0.12
	mesh.radial_segments = 8
	mesh.rings = 4
	_accent.mesh = mesh
	_accent.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_material = StandardMaterial3D.new()
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.emission_enabled = true
	_material.emission = Color("#bbecdb")
	_material.albedo_color = Color("#bbecdb")
	_accent.material_override = _material
	add_child(_accent)
	_accent.visible = false


func _process(delta: float) -> void:
	var actor := get_parent() as Node3D
	if not is_instance_valid(actor) or not actor.has_method("get_passive_status"):
		return
	_clock += delta
	var state: Dictionary = actor.call("get_passive_status")
	var revealed := not actor.has_method("get_presentation_visibility_weight") or float(actor.call("get_presentation_visibility_weight")) > 0.1
	var alive := not actor.has_method("is_real_dead") or not bool(actor.call("is_real_dead"))
	var glow := float(state.get("alternator", 0.0)) > 0.0
	var flash := str(actor.call("get_passive_id")) == "alternator" and float(state.get("pulse", 0.0)) > 0.0
	_accent.visible = alive and revealed and (glow or flash)
	if _accent.visible:
		_accent.global_position = actor.call("get_passive_weapon_point")
		_accent.scale = Vector3.ONE * (2.5 if flash else 1.0 + sin(_clock * 5.0) * 0.12)
		_material.emission_energy_multiplier = 2.0 if flash else 1.0
	var inertia := float(state.get("inertia", 0.0))
	if inertia > _previous_inertia + 0.1 and alive and revealed and actor.has_method("get_training_bot_muzzle_transform"):
		var scene := get_tree().current_scene
		var vfx := scene.get_node_or_null("VFXManager") if scene != null else null
		if vfx != null:
			vfx.call("burst", actor.global_position + Vector3.UP * 0.2, Vector3.UP, Color("#bbecdb"), 4, 2.0, 0.2, 0.04, 45.0)
	_previous_inertia = inertia
