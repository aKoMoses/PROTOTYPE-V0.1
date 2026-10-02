extends Node3D
## Arena-only presentation adapter. The parent still owns availability,
## collection, recharge and pickup feedback; this child owns only the platform.
var _kit: Node3D
var _cross: Node3D
var _base: MeshInstance3D
var _clock := 0.0

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
		face.albedo_color = Color("#dbead4")
		face.emission = Color("#8ebdb0")
	var back := _kit.get("_available_back_material") as StandardMaterial3D
	if back != null:
		back.albedo_color = Color(0.24, 0.56, 0.49, 0.15)
		back.emission = Color("#6eaa9c")

func _process(delta: float) -> void:
	if not is_instance_valid(_cross):
		return
	_clock += delta
	var state: String = _kit.call("get_visual_state_name")
	visible = state != "disabled"
	_base.visible = false
	# A slight pulse stays on the inset platform instead of floating over it.
	_cross.position.y = 0.06 + sin(_clock * 2.4) * 0.008
	_cross.scale = Vector3.ONE * (0.68 + (sin(_clock * 3.9) * 0.012 if state == "available" else 0.0))
