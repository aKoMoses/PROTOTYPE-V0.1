extends SceneTree

## Integration: ground effects must never reveal an actor or flash as a square.
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error(message)

func _run() -> void:
	var main_script := load("res://scripts/main.gd") as Script
	if main_script == null or not main_script.can_instantiate():
		quit(2)
		return
	var scene := load("res://scenes/main.tscn").instantiate() as Node3D
	root.add_child(scene)
	current_scene = scene
	await process_frame
	await process_frame
	scene.call("set_menu_showcase_enabled", false)
	var target := scene.get_node("TargetDummy") as Node3D
	var rig := target.get_node("VisualRoot") as Node3D
	var contact := rig.get_node("CombatContactShadow") as MeshInstance3D
	var material := contact.material_override as ShaderMaterial
	var health: float = target.call("get_health")
	var actor_transform := target.transform
	var collision: Shape3D = target.find_children("*", "CollisionShape3D", true, false)[0].shape
	scene.get_node("VFXManager").call("hit_flash", rig, true)
	_check(contact.material_overlay == null, "critical hit must not light the ground shadow")
	var fade := target.get("_visibility_fade") as Node
	fade.call("apply_presentation", 0.35, 0.6, 0.0)
	_check(is_equal_approx(float(material.get_shader_parameter("visibility_opacity")), 0.35), "contact shadow must fade with its observed actor")
	_check(is_equal_approx(float(material.get_shader_parameter("visibility_silhouette")), 0.6), "contact shadow must follow silhouette presentation")
	fade.call("restore")
	_check(is_equal_approx(float(material.get_shader_parameter("visibility_opacity")), 1.0), "fade restoration must recover the original shadow")
	rig.hide()
	_check(not contact.is_visible_in_tree(), "fully concealed actor must hide its contact shadow")
	rig.show()
	_check(target.transform == actor_transform and float(target.call("get_health")) == health and target.find_children("*", "CollisionShape3D", true, false)[0].shape == collision, "visual effects must retain actor transform, health and collision")
	var player := scene.get_node("Player") as Node3D
	var player_rig := player.get_node("VisualRoot") as Node3D
	for chassis in ["agile", "puissant", "polyvalent"]:
		player.call("set_robot", chassis)
		_check(player_rig.find_child("CombatContactShadow", true, false) != null, "contact shadow must survive chassis switch")
	scene.call("set_arena_variant", "test")
	await process_frame
	await process_frame
	var deck := scene.get_node_or_null("TestArena/BridgePresentation/SteelPlatesAndHardware") as MeshInstance3D
	_check(deck != null, "platform deck art must exist")
	if deck != null:
		var finish := deck.get_active_material(0)
		var roughness: float = finish.roughness if finish is StandardMaterial3D else float(finish.get_shader_parameter("surface_roughness")) if finish is ShaderMaterial else -1.0
		_check(roughness > 0.40 and roughness < 0.55, "late-created steel deck must retain its satin finish with either material pipeline")
	for bush in get_nodes_in_group("bush_placeholder"):
		var foliage: Node3D = bush.get_node("GroundedVegetation")
		_check(is_equal_approx(float(bush.get_meta("bush_radius")), float(foliage.get_meta("foliage_radius"))), "foliage footprint must match camouflage on platforms map")
	scene.queue_free()
	await process_frame
	for path in ["res://scenes/training_ground.tscn", "res://scenes/survival.tscn"]:
		var mode := load(path).instantiate() as Node3D
		root.add_child(mode)
		current_scene = mode
		await process_frame
		await process_frame
		_check(mode.has_node("CombatVisualPolish"), "training and survival must install the same polish pass")
		var mode_player: Node3D = mode.get("player")
		_check(mode_player.find_child("CombatContactShadow", true, false) != null, "training and survival must ground the player")
		mode.queue_free()
		await process_frame
	root.get_node("GameSfx").call("clear")
	print("COMBAT POLISH TEST: ", "PASS" if failures.is_empty() else "FAIL", " (", failures.size(), " failures)")
	quit(0 if failures.is_empty() else 1)
