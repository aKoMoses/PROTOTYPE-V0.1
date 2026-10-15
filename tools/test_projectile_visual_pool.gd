extends SceneTree
const PROJECTILE := preload("res://scripts/live_projectile.gd")
const VFX := preload("res://scripts/vfx_manager.gd")
const PELTO := preload("res://scripts/pelto_smash.gd")
var failures: Array[String] = []
var world: Node3D
var manager: VFX

func _initialize() -> void:
	_run.call_deferred()

func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error(message)

func shot(weapon: String, charge: float = 0.0) -> Node3D:
	var projectile := PROJECTILE.new()
	world.add_child(projectile)
	projectile.set_physics_process(false)
	manager.projectile_visual(projectile, weapon, charge)
	return projectile

func _run() -> void:
	world = Node3D.new()
	root.add_child(world)
	current_scene = world
	manager = VFX.new()
	world.add_child(manager)
	_test_pelto_resources()
	check(manager._idle_projectile_mesh_count() == 16, "Two salvos and plasma visuals are prepared before combat")
	var first := shot("blaster")
	var original_meshes: Array[Node] = [first.get_node("ProjectileCore"), first.get_node("ProjectileSheath")]
	var original_materials: Array[Material] = []
	for mesh in original_meshes:
		original_materials.append(mesh.material_override)
	var finishes := [0]
	first.finished.connect(func(_hit: Dictionary, _distance: float) -> void: finishes[0] += 1)
	first.call("_finish", {})
	check(finishes[0] == 1 and first.is_queued_for_deletion(), "Visual recycling preserves projectile completion and owner lifetime")
	for mesh in original_meshes:
		check(mesh.get_parent() == manager and not mesh.visible, "Completed visuals return hidden to their scene manager")
	await process_frame
	var charged := shot("blaster", 1.0)
	for label in ["ProjectileCore", "ProjectileSheath"]:
		var mesh := charged.get_node(label) as MeshInstance3D
		check(mesh in original_meshes and mesh.material_override in original_materials, "A subsequent shot reuses existing meshes and materials")
	var sheath := charged.get_node("ProjectileSheath") as MeshInstance3D
	var material := sheath.material_override as StandardMaterial3D
	check(is_equal_approx(material.albedo_color.a, 0.38) and material.emission.is_equal_approx(Color("#52dff4").lerp(Color("#718cff"), 0.74)), "Reuse retains exact charged colour and opacity")
	check(sheath.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "Visuals keep their original shadow policy")
	var simultaneous := shot("blaster")
	check(simultaneous.get_node("ProjectileCore") != charged.get_node("ProjectileCore") and simultaneous.get_node("ProjectileCore").material_override != charged.get_node("ProjectileCore").material_override, "Simultaneous shots cannot mutate each other's visual state")
	var pellets: Array[Node3D] = []
	for index in 50:
		var pellet := shot("shotgun")
		pellets.append(pellet)
		var core := pellet.get_node("ProjectileCore") as MeshInstance3D
		check(core != null and core.visible and is_equal_approx(core.position.z, 0.12) and core.scale.is_equal_approx(Vector3(0.085, 0.07, 0.24)), "Pool pressure never removes a live pellet or changes its geometry")
	for pellet in pellets:
		pellet.call("_finish", {})
	charged.call("_finish", {})
	simultaneous.call("_finish", {})
	await process_frame
	check(manager._idle_projectile_mesh_count() <= VFX.MAX_IDLE_PROJECTILE_MESHES, "Idle memory remains bounded after a large burst")
	var interrupted := shot("blaster")
	var interrupted_core: WeakRef = weakref(interrupted.get_node("ProjectileCore"))
	interrupted.queue_free()
	await process_frame
	check(interrupted_core.get_ref() == null, "Round cleanup releases visuals of shots deleted without impact")
	var surviving := shot("shotgun")
	manager.clear()
	check(is_instance_valid(surviving) and surviving.get_node("ProjectileCore").visible, "Disposable effect cleanup cannot reclaim gameplay projectiles")
	surviving.call("_finish", {})
	current_scene = null
	world.queue_free()
	await process_frame
	print("PROJECTILE VISUAL POOL: %s (%d failures)" % ["PASS" if failures.is_empty() else "FAIL", failures.size()])
	quit(0 if failures.is_empty() else 1)

func _test_pelto_resources() -> void:
	var first := PELTO.new()
	var second := PELTO.new()
	world.add_child(first)
	world.add_child(second)
	first.configure(world, Vector3.ZERO, Vector3.FORWARD, "test", "one")
	second.configure(world, Vector3.RIGHT, Vector3.RIGHT, "test", "two")
	check(first._plates[0].mesh == second._plates[0].mesh and first._plates[0].material_override == second._plates[0].material_override, "PELTO waves reuse immutable geometry and materials")
	check(first._plates[0] != second._plates[0] and first._front_root != second._front_root, "Simultaneous waves keep independent transforms")
	first.travel_distance = 1.0
	first._previous_distance = 1.0
	second.travel_distance = 3.0
	second._previous_distance = 3.0
	first._update_visuals()
	second._update_visuals()
	var width := float(PELTO.definition().width) * 0.92
	check(first._trace_mesh == second._trace_mesh and first._trace_mesh.size == Vector3.ONE, "Trace geometry stays immutable during animation")
	check(first._trace.global_basis.get_scale().is_equal_approx(Vector3(width, 0.025, 1.0)) and second._trace.global_basis.get_scale().is_equal_approx(Vector3(width, 0.025, 3.0)), "Each trace retains its exact independent width, height and animated length")
	check(is_equal_approx(first._plates[0].mesh.radius, float(PELTO.definition().width) / 9.0 * 0.56) and is_equal_approx(first._plates[2].mesh.height, 0.31), "Cached rock geometry retains the original proportions")
	var dust_one := PELTO._earth_material(Color("#b98a68"), 0.30)
	var dust_two := PELTO._earth_material(Color("#b98a68"), 0.30)
	dust_one.albedo_color.a = 0.0
	check(is_equal_approx(dust_two.albedo_color.a, 0.30), "Detached dust fade materials remain independent")
	first.free()
	second.free()
