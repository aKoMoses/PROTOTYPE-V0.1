extends SceneTree

# Capture the current rules, rather than historical documentation. Running this
# tool against the starting and delivered checkouts compares definitions,
# sources and physics settings. Any presentation-only source exception is
# documented explicitly in docs/PASSE_COMPLETE.md rather than hidden here.
const SIMULATION_SOURCES := [
	"combat_data", "combat_state", "action_gate", "fulguro_punch", "pelto_smash",
	"passive_state", "projectile", "visibility_state", "training_bot",
	"bot_ai_profile", "duel_bot_equipment", "survival_progression",
	"survival_synergies", "training_dummy", "target_dummy", "camera_rig",
]

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var output := args[0] if not args.is_empty() else "res://docs/pass_gameplay_reference.json"
	var data_script: Script = load("res://scripts/combat_data.gd")
	var hashes := {}
	for name in SIMULATION_SOURCES:
		var path := "res://scripts/%s.gd" % name
		hashes[path] = FileAccess.get_file_as_string(path).replace("\r\n", "\n").sha256_text()
	var reference := {
		"engine": Engine.get_version_info().string,
		"renderer": ProjectSettings.get_setting("rendering/renderer/rendering_method"),
		"physics_ticks_per_second": Engine.physics_ticks_per_second,
		"definitions": _json_value(data_script.get_script_constant_map()),
		"simulation_sha256_normalized": hashes,
		"arena_contract": JSON.parse_string(FileAccess.get_file_as_string("res://docs/arena_gameplay_contract.json")),
	}
	var file := FileAccess.open(output, FileAccess.WRITE)
	if file == null:
		push_error("GAMEPLAY REFERENCE: cannot write %s" % output)
		quit(1)
		return
	file.store_string(JSON.stringify(reference, "\t", true) + "\n")
	file.close()
	print("GAMEPLAY REFERENCE: ", output)
	quit(0)

func _json_value(value: Variant) -> Variant:
	if value is Dictionary:
		var result := {}
		for key in value:
			result[str(key)] = _json_value(value[key])
		return result
	if value is Array:
		var result := []
		for item in value:
			result.append(_json_value(item))
		return result
	if value is Color:
		return value.to_html()
	if value is Vector3:
		return [value.x, value.y, value.z]
	if value is Vector2:
		return [value.x, value.y]
	if value is Resource:
		return value.resource_path
	return value
