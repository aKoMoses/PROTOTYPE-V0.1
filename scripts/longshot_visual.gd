extends Node3D
## The imported textured model remains intact. These small cores use no lights.

var _cycle_count := 0
var _enhanced_ready := false
var _energy_material: StandardMaterial3D
var _clock := 0.0


func _ready() -> void:
	var core := get_node("EnergyCoreRight") as MeshInstance3D
	_energy_material = core.material_override.duplicate() as StandardMaterial3D
	for name in ["EnergyCoreRight", "EnergyCoreLeft"]:
		(get_node(name) as MeshInstance3D).material_override = _energy_material
	_refresh_energy()
	set_process(_enhanced_ready)


func set_cycle(count: int, ready: bool) -> void:
	_cycle_count = clampi(count, 0, 4)
	_enhanced_ready = ready
	_refresh_energy()
	set_process(ready)


func _process(delta: float) -> void:
	_clock += delta
	if is_visible_in_tree():
		_refresh_energy()


func _refresh_energy() -> void:
	if _energy_material == null:
		return
	var progression := float(_cycle_count) / 4.0
	_energy_material.emission_energy_multiplier = 1.2 + progression * 1.15
	_energy_material.albedo_color = Color("#298f9e").lerp(Color("#74edff"), progression)
	if _enhanced_ready:
		_energy_material.emission_energy_multiplier = 3.0 + sin(_clock * 5.0) * 0.30
		_energy_material.albedo_color = Color("#b8faff")
