extends Node
## Reduce duel GPU work without changing the menu, garage previews or HUD.
## The original viewport and shadow settings are restored when leaving combat.
const SCALE_3D := 0.5
const COMBAT_SCREEN := 3 # PrototypeGameFlow.Screen.COMBAT, including network duels.
var _active := false
var _combat_scene: Node
var _targets: Dictionary = {}

static func enabled() -> bool:
	return OS.has_feature("mobile") or OS.get_cmdline_user_args().has("mobile-gpu-budget")

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_priority = 1000
	set_process(false)
	if enabled():
		activate()

func activate() -> void:
	if _active:
		return
	_active = true
	get_tree().node_added.connect(_node_added)
	set_process(true)
	_process(0.0)

func _current_combat_scene() -> Node:
	var scene := get_tree().current_scene
	if not is_instance_valid(scene):
		return null
	var flow := scene.get_node_or_null("Interface")
	if flow == null or flow.get_script() == null:
		return null
	if flow.get_script().resource_path != "res://scripts/game_flow.gd":
		return null
	return scene if int(flow.get("current_screen")) == COMBAT_SCREEN else null

func _node_added(node: Node) -> void:
	# Constructors, _ready and quality adapters configure new lights first.
	if node is Light3D:
		_register_added.call_deferred(weakref(node))

func _register_added(reference: WeakRef) -> void:
	var node: Node = reference.get_ref()
	if is_instance_valid(node):
		_register(node)

func _register(node: Node) -> void:
	if not is_instance_valid(_combat_scene) or _targets.has(node.get_instance_id()):
		return
	if node == get_tree().root:
		_targets[node.get_instance_id()] = {"node": weakref(node), "scale": node.scaling_3d_scale, "msaa": node.msaa_3d}
	elif node is Light3D and _combat_scene.is_ancestor_of(node) and node.get_viewport() == get_tree().root:
		_targets[node.get_instance_id()] = {"node": weakref(node), "shadow": node.shadow_enabled}

func _process(_delta: float) -> void:
	var scene := _current_combat_scene()
	if scene != _combat_scene:
		_restore_all()
		_combat_scene = scene
		if is_instance_valid(scene):
			_register(get_tree().root)
			for light in scene.find_children("*", "Light3D", true, false):
				_register(light)
	if not is_instance_valid(_combat_scene):
		return
	for id in _targets.keys():
		var entry: Dictionary = _targets[id]
		var node: Node = entry.node.get_ref()
		if not is_instance_valid(node) or not node.is_inside_tree() or (node is Light3D and not _combat_scene.is_ancestor_of(node)):
			_restore(entry)
			_targets.erase(id)
			continue
		if node is Light3D:
			node.shadow_enabled = false
		elif node is Viewport:
			if node.scaling_3d_scale > SCALE_3D:
				node.scaling_3d_scale = SCALE_3D
			node.msaa_3d = Viewport.MSAA_DISABLED

func _restore(entry: Dictionary) -> void:
	var node: Node = entry.node.get_ref()
	if not is_instance_valid(node):
		return
	if node is Light3D:
		node.shadow_enabled = bool(entry.shadow)
	elif node is Viewport:
		node.scaling_3d_scale = float(entry.scale)
		node.msaa_3d = int(entry.msaa)

func _restore_all() -> void:
	for entry in _targets.values():
		_restore(entry)
	_targets.clear()
	_combat_scene = null

func deactivate() -> void:
	_active = false
	set_process(false)
	if get_tree() != null and get_tree().node_added.is_connected(_node_added):
		get_tree().node_added.disconnect(_node_added)
	_restore_all()

func _exit_tree() -> void:
	deactivate()
