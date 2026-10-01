extends Node3D

## Presentation reads the current state so actor resets and network replicas
## use the same shell without granting protection locally.
var _shell: MeshInstance3D
var _ring: MeshInstance3D
var _label: Label3D
var _material: StandardMaterial3D
var _clock := 0.0


func _ready() -> void:
	name = "PermutationShield"
	visible = false
	_material = StandardMaterial3D.new()
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_material.albedo_color = Color(0.55, 0.38, 1.0, 0.12)
	_material.emission_enabled = true
	_material.emission = Color("#ae85ff")
	_material.emission_energy_multiplier = 1.1
	var sphere := SphereMesh.new()
	sphere.radius = 0.88
	sphere.height = 2.25
	_shell = MeshInstance3D.new()
	_shell.mesh = sphere
	_shell.position.y = 1.05
	_shell.material_override = _material
	_shell.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_shell)
	var torus := TorusMesh.new()
	torus.inner_radius = 0.81
	torus.outer_radius = 0.88
	_ring = MeshInstance3D.new()
	_ring.mesh = torus
	_ring.position.y = 1.15
	var ring_material := _material.duplicate() as StandardMaterial3D
	ring_material.albedo_color.a = 0.75
	_ring.material_override = ring_material
	_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_ring)
	_label = Label3D.new()
	_label.position.y = 2.4
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.font_size = 25
	_label.pixel_size = 0.008
	_label.modulate = Color("#cbb2ff")
	add_child(_label)


func _process(delta: float) -> void:
	var actor := get_parent() as Node3D
	var state = actor.get("combat_state")
	var weight := float(actor.call("get_presentation_visibility_weight")) if actor.has_method("get_presentation_visibility_weight") else 1.0
	visible = state != null and state.shield_health > 0.0 and state.shield_remaining > 0.0 and weight > 0.0
	if not visible:
		return
	_clock += delta
	_material.albedo_color.a = (0.10 + 0.025 * sin(_clock * 9.0)) * weight * minf(1.0, state.shield_remaining / 0.35)
	(_ring.material_override as StandardMaterial3D).albedo_color.a = 0.75 * weight * minf(1.0, state.shield_remaining / 0.35)
	_ring.rotation = Vector3(0.3 * sin(_clock * 3.0), _clock * 2.0, 0.2)
	_label.text = "BOUCLIER %d" % ceili(state.shield_health)
	_label.modulate.a = weight
