extends Node
## GPU budget only: native 2D/HUD, lights, visibility and physics are retained.
## Keep late scene/quality adapters from restoring costly MSAA or shadow passes.
const SCALE_3D := 0.5
var _active := false
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
	get_tree().node_added.connect(_register)
	_register(get_tree().root)
	# A diagnostic can activate the profile after scenes already exist.
	for node in get_tree().root.find_children("*", "", true, false):
		_register(node)
	_enforce()
	set_process(true)

func _register(node: Node) -> void:
	if not _active or _targets.has(node.get_instance_id()):
		return
	if node is Light3D:
		_targets[node.get_instance_id()] = {"node": weakref(node), "shadow": node.shadow_enabled}
	elif node is Viewport:
		_targets[node.get_instance_id()] = {"node": weakref(node), "scale": node.scaling_3d_scale, "msaa": node.msaa_3d}
	else:
		return
	# Constructors and _ready may configure the node after node_added fires.
	# The final process priority also covers deferred scenery/quality adapters.

func _process(_delta: float) -> void:
	_enforce()

func _enforce() -> void:
	for id in _targets.keys():
		var entry: Dictionary = _targets[id]
		var node: Node = entry.node.get_ref()
		if not is_instance_valid(node) or not node.is_inside_tree():
			if is_instance_valid(node):
				_restore(entry)
			_targets.erase(id)
			continue
		if node is Light3D:
			if node.shadow_enabled:
				node.shadow_enabled = false
		elif node is Viewport:
			# Respect any intentionally stricter quality setting.
			if node.scaling_3d_scale > SCALE_3D:
				node.scaling_3d_scale = SCALE_3D
			if node.msaa_3d != Viewport.MSAA_DISABLED:
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

func deactivate() -> void:
	if not _active:
		return
	_active = false
	set_process(false)
	if get_tree() != null and get_tree().node_added.is_connected(_register):
		get_tree().node_added.disconnect(_register)
	for entry in _targets.values():
		_restore(entry)
	_targets.clear()

func _exit_tree() -> void:
	deactivate()
