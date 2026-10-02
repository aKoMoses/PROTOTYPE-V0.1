extends Node3D
## Arena-only presentation adapter. The parent still owns availability,
## collection, recharge and pickup feedback; this child owns only the platform.
var _kit: Node3D
var _cross: Node3D
var _base: MeshInstance3D
var _clock := 0.0
var _corner_material: StandardMaterial3D
var _glass_material: StandardMaterial3D

func _ready() -> void:
	call_deferred("_bind")

func _bind() -> void:
	_kit = get_parent() as Node3D
	_cross = _kit.get_node_or_null("ConsumableKit/FloatingCross") as Node3D
	_base = _kit.get_node_or_null("PermanentBase") as MeshInstance3D
	var halo := _kit.get_node_or_null("ConsumableKit/GroundHalo")
	if halo != null:
		for mesh in halo.get_children():
			if mesh is MeshInstance3D:
				mesh.visible = false
	var face := _kit.get("_available_face_material") as StandardMaterial3D
	if face != null:
		face.albedo_color = Color("#e5fff6")
		face.emission = Color("#a4f0e3")
		face.emission_energy_multiplier = 1.35
	var back := _kit.get("_available_back_material") as StandardMaterial3D
	if back != null:
		back.albedo_color = Color(0.24, 0.56, 0.49, 0.15)
		back.emission = Color("#6eaa9c")
	_corner_material = StandardMaterial3D.new()
	_corner_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_corner_material.emission_enabled = true
	_corner_material.emission = Color("#ffaa44")
	for bolt_name in ["NorthWestBolt","NorthEastBolt","SouthWestBolt","SouthEastBolt"]:
		var bolt := get_node_or_null(bolt_name) as MeshInstance3D
		if bolt != null:
			bolt.material_override = _corner_material
	var enamel := get_node_or_null("MedicalEnamel") as MeshInstance3D
	if enamel != null:
		var source := enamel.get_active_material(0)
		# Courtyard dressing can supply its own shader finish. Keep that finish;
		# only the authored standard enamel exposes these emission properties.
		if source is StandardMaterial3D:
			_glass_material = source.duplicate() as StandardMaterial3D
			_glass_material.emission_enabled = true
			_glass_material.emission = Color("#24786d")
			enamel.material_override = _glass_material

func _process(delta: float) -> void:
	if not is_instance_valid(_cross):
		return
	_clock += delta
	var state: String = _kit.call("get_visual_state_name")
	visible = state != "disabled"
	_base.visible = false
	var available := state=="available"
	if _corner_material != null:
		_corner_material.albedo_color = Color("#ffbf63") if available else Color("#665438")
		_corner_material.emission_energy_multiplier = 1.8 if available else 0.0
	if _glass_material != null:
		_glass_material.emission_energy_multiplier = .30 if available else 0.0
	# A slight pulse stays on the inset platform instead of floating over it.
	_cross.position.y = 0.06 + sin(_clock * 2.4) * 0.008
	_cross.scale = Vector3.ONE * (0.68 + (sin(_clock * 3.9) * 0.012 if state == "available" else 0.0))
