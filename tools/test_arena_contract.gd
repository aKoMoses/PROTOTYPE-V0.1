extends SceneTree

# Captures and verifies the gameplay-facing arena contract. The environment art
# pass may change children and materials, but not these transforms or shapes.

const CONTRACT_PATH := "res://docs/arena_gameplay_contract.json"


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	await process_frame
	var current := _collect_contract(scene)
	var arguments := OS.get_cmdline_user_args()
	if not arguments.is_empty() and arguments[0] == "capture":
		var file := FileAccess.open(CONTRACT_PATH, FileAccess.WRITE)
		if file == null:
			push_error("Cannot write arena contract: %s" % FileAccess.get_open_error())
			quit(1)
			return
		file.store_string(JSON.stringify(current, "\t") + "\n")
		file.close()
		print("ARENA CONTRACT: CAPTURED %s" % ProjectSettings.globalize_path(CONTRACT_PATH))
		quit(0)
		return
	if not FileAccess.file_exists(CONTRACT_PATH):
		push_error("Arena contract is missing: %s" % CONTRACT_PATH)
		quit(1)
		return
	var baseline = JSON.parse_string(FileAccess.get_file_as_string(CONTRACT_PATH))
	if baseline == null:
		push_error("Arena contract is invalid JSON")
		quit(1)
		return
	if JSON.stringify(current) != JSON.stringify(baseline):
		push_error("ARENA CONTRACT: FAIL — collision, spawn, camera, pad or bush contract changed")
		_print_contract_diff(baseline, current)
		quit(1)
		return
	print("ARENA CONTRACT: PASS (%d blockers, %d health pads, %d bushes)" % [
		current.static_bodies.size(),
		current.health_pads.size(),
		current.bushes.size(),
	])
	quit(0)


func _collect_contract(scene: Node) -> Dictionary:
	var contract := {
		"static_bodies": [],
		"spawns": {},
		"camera": {},
		"health_pads": [],
		"bushes": [],
	}
	for child in scene.get_children():
		if child is StaticBody3D and (child as StaticBody3D).collision_layer == 1:
			var body := child as StaticBody3D
			var entry := {
				"name": str(body.name),
				"position": _vec3(body.position),
				"rotation_degrees": _vec3(body.rotation_degrees),
				"collision_layer": float(body.collision_layer),
				"collision_mask": float(body.collision_mask),
				"shapes": [],
			}
			for shape_node in body.get_children():
				if shape_node is CollisionShape3D:
					var collision := shape_node as CollisionShape3D
					var shape_entry := {
						"position": _vec3(collision.position),
						"rotation_degrees": _vec3(collision.rotation_degrees),
						"type": collision.shape.get_class() if collision.shape != null else "",
					}
					if collision.shape is BoxShape3D:
						shape_entry["size"] = _vec3((collision.shape as BoxShape3D).size)
					entry.shapes.append(shape_entry)
			contract.static_bodies.append(entry)
	contract.static_bodies.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.name < b.name)
	var player := scene.get_node_or_null("Player") as Node3D
	var target := scene.get_node_or_null("TargetDummy") as Node3D
	if player != null:
		contract.spawns["player"] = _vec3(player.position)
	if target != null:
		contract.spawns["target"] = _vec3(target.position)
	var camera := scene.get_node_or_null("CameraRig/Camera3D") as Camera3D
	if camera != null:
		contract.camera = {
			"position": _vec3(camera.position),
			"rotation_degrees": _vec3(camera.rotation_degrees),
			"fov": _rounded(camera.fov),
		}
	for pad_node in get_nodes_in_group("health_kit_placeholder"):
		var pad := pad_node as Node3D
		contract.health_pads.append({"name": str(pad.name), "position": _vec3(pad.position)})
	contract.health_pads.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.name < b.name)
	for bush_node in get_nodes_in_group("bush_placeholder"):
		var bush := bush_node as Node3D
		contract.bushes.append({
			"name": str(bush.name),
			"position": _vec3(bush.position),
			"scale": _vec3(bush.scale),
			"radius": _rounded(float(bush.get_meta("bush_radius", 0.0))),
			"height": _rounded(float(bush.get_meta("bush_height", 0.0))),
		})
	contract.bushes.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.name < b.name)
	return contract


func _vec3(value: Vector3) -> Array[float]:
	return [_rounded(value.x), _rounded(value.y), _rounded(value.z)]


func _rounded(value: float) -> float:
	return snappedf(value, 0.0001)


func _print_contract_diff(baseline: Dictionary, current: Dictionary) -> void:
	for key in baseline.keys():
		if JSON.stringify(baseline[key]) != JSON.stringify(current.get(key)):
			print("ARENA CONTRACT DIFF [%s] expected=%s" % [key, JSON.stringify(baseline[key])])
			print("ARENA CONTRACT DIFF [%s] current=%s" % [key, JSON.stringify(current.get(key))])
