extends Node

## One bounded, local presentation director for duel, training and survival.
const PRESENCE := preload("res://scripts/mecha_presence.gd")
var manager: Node
var observer: Node3D
var _scan_clock := 0.0
var _props: Array[Dictionary] = []
var _prop_ids: Dictionary = {}
var _gusts: Array[Dictionary] = []
var _actors: Array[Node3D] = []
var _clarified: Dictionary = {}
var _scan_pending := true
var _bootstrap_remaining := 2.0

static func install(scene: Node, vfx: Node) -> void:
	if not is_instance_valid(scene) or scene.has_node("CombatPresentationPass") or not scene.has_node("CameraRig"):
		return
	var director := load("res://scripts/combat_presentation_pass.gd").new() as Node
	director.name = "CombatPresentationPass"
	director.set("manager", vfx)
	scene.add_child(director)

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	manager.connect("surface_contact", _contact)
	manager.connect("presentation_cleared", clear)
	get_tree().node_added.connect(_node_added)
	_scan()

func _node_added(node: Node) -> void:
	if not is_inside_tree() or not get_parent().is_ancestor_of(node):
		return
	# Garage previews and transient weapon FX cannot introduce scenery props.
	var ancestor := node.get_parent()
	while ancestor != null and ancestor != get_parent():
		if ancestor is Viewport or ancestor is Control:
			return
		ancestor = ancestor.get_parent()
	if node is CollisionObject3D and node.has_method("get_health"):
		_scan_pending = true
	elif node is MeshInstance3D:
		_check_added_mesh(node)
		# Presentation adapters may replace its material after node_added.
		_check_deferred_mesh.call_deferred(weakref(node))

func _check_deferred_mesh(reference: WeakRef) -> void:
	var mesh := reference.get_ref() as MeshInstance3D
	if is_instance_valid(mesh):
		_check_added_mesh(mesh)

func _check_added_mesh(node: MeshInstance3D) -> void:
	if not is_instance_valid(node) or not is_inside_tree() or not node.is_inside_tree():
		return
	var material := node.material_override as ShaderMaterial
	if material != null and material.shader != null and material.shader.resource_path in ["res://scripts/environment/yard_cloth.gdshader", "res://scripts/bush_foliage.gdshader", "res://shaders/stylized_courtyard.gdshader"]:
		_scan_pending = true

func _scan() -> void:
	_scan_pending = false
	var scene := get_parent()
	var camera_rig := scene.get_node_or_null("CameraRig")
	observer = camera_rig.get("_target") as Node3D if camera_rig != null else null
	for mesh in scene.find_children("*", "MeshInstance3D", true, false):
		var source := mesh.material_override as ShaderMaterial
		if source != null and source.shader != null and source.shader.resource_path == "res://shaders/stylized_courtyard.gdshader" and not _clarified.has(source.get_instance_id()):
			var finish := source.duplicate() as ShaderMaterial
			finish.set_shader_parameter("combat_clarity", 0.35)
			mesh.material_override = finish
			_clarified[finish.get_instance_id()] = true
		if source == null or source.shader == null or source.shader.resource_path not in ["res://scripts/environment/yard_cloth.gdshader", "res://scripts/bush_foliage.gdshader"]:
			continue
		var mesh_id: int = mesh.get_instance_id()
		if _prop_ids.has(mesh_id) and _prop_ids[mesh_id].material == source:
			continue
		# Each leaf/cloth responds locally even when its authored finish is shared.
		var response := source.duplicate() as ShaderMaterial
		mesh.material_override = response
		var source_strength: Variant = response.get_shader_parameter("wind_strength")
		var prop := {"id": mesh_id, "mesh": weakref(mesh), "material": response, "base": float(source_strength) if source_strength != null else 0.65, "reacting": false}
		if _prop_ids.has(mesh_id):
			_props.erase(_prop_ids[mesh_id])
		_prop_ids[mesh_id] = prop
		_props.append(prop)
	for body in scene.find_children("*", "CollisionObject3D", true, false):
		if not body.has_method("get_health") or not "_visual_rig" in body or body.has_node("CombatPresence"):
			continue
		var presentation := PRESENCE.new()
		presentation.name = "CombatPresence"
		presentation.actor = body
		presentation.observer = observer
		presentation.manager = manager
		body.add_child(presentation)
		_actors.append(body)

func _process(delta: float) -> void:
	_bootstrap_remaining = maxf(0.0, _bootstrap_remaining - delta)
	_scan_clock -= delta
	if _scan_clock <= 0.0:
		_scan_clock = 0.5
		# Deferred initial finishers can replace materials for a few frames.
		# Afterwards, rediscover only when relevant world nodes are introduced.
		if _scan_pending or _bootstrap_remaining > 0.0:
			_scan()
		else:
			var camera_rig := get_parent().get_node_or_null("CameraRig")
			observer = camera_rig.get("_target") as Node3D if camera_rig != null else null
		for index in range(_actors.size() - 1, -1, -1):
			var actor := _actors[index]
			if not is_instance_valid(actor):
				_actors.remove_at(index)
			elif actor.has_node("CombatPresence"):
				actor.get_node("CombatPresence").set("observer", observer)
	for index in range(_gusts.size() - 1, -1, -1):
		_gusts[index].life -= delta
		if _gusts[index].life <= 0.0:
			_gusts.remove_at(index)
	for index in range(_props.size() - 1, -1, -1):
		var prop := _props[index]
		var mesh: MeshInstance3D = prop.mesh.get_ref()
		if not is_instance_valid(mesh):
			_prop_ids.erase(prop.id)
			_props.remove_at(index)
			continue
		if mesh.material_override != prop.material:
			_scan_pending = true
		var strength := 0.0
		for gust in _gusts:
			strength = maxf(strength, maxf(0.0, 1.0 - mesh.global_position.distance_to(gust.at) / 3.0) * gust.life * gust.power)
		if strength > 0.0:
			prop.material.set_shader_parameter("wind_strength", minf(1.3, prop.base + strength))
		elif bool(prop.get("reacting", false)):
			prop.material.set_shader_parameter("wind_strength", prop.base)
		else:
			var current: Variant = prop.material.get_shader_parameter("wind_strength")
			if current != null:
				prop.base = float(current)
		prop["reacting"] = strength > 0.0

func can_present(at: Vector3) -> bool:
	if not is_instance_valid(observer) or not observer.has_method("is_gameplay_enabled") or not bool(observer.call("is_gameplay_enabled")):
		return false
	var camera := get_viewport().get_camera_3d()
	if camera == null or camera.is_position_behind(at) or not Rect2(Vector2.ZERO, get_viewport().get_visible_rect().size).has_point(camera.unproject_position(at)):
		return false
	var query := PhysicsRayQueryParameters3D.create(observer.global_position + Vector3.UP * 1.0, at)
	query.collision_mask = 1
	query.hit_from_inside = false
	var hit := observer.get_world_3d().direct_space_state.intersect_ray(query)
	# A visible impact lies on the first solid face, which the ray may hit at
	# its endpoint. A nearer wall still blocks anything behind that face.
	return hit.is_empty() or (hit.position as Vector3).distance_to(at) < 0.08

func _contact(at: Vector3, surface: String, power: float) -> void:
	if not can_present(at):
		return
	if surface in ["metal", "concrete", "sand", "environment"]:
		get_node("/root/GameSfx").call("play_surface_contact", surface, at, power)
	react_at(at, minf(power, 1.0) * 0.6)

func react_at(at: Vector3, power: float) -> void:
	if _gusts.size() >= 6:
		_gusts.pop_front()
	_gusts.append({"at": at, "power": power, "life": 0.55})

func clear() -> void:
	_gusts.clear()
	for prop in _props:
		if is_instance_valid(prop.mesh.get_ref()):
			prop.material.set_shader_parameter("wind_strength", prop.base)
		prop["reacting"] = false
	for actor in _actors:
		if is_instance_valid(actor) and actor.has_node("CombatPresence"):
			actor.get_node("CombatPresence").call("reset")
