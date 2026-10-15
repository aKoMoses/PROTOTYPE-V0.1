extends Node
## Park only the world completely covered by an opaque menu. Garage SubViewport,
## menus, camera poses and materials remain intact. Restore exact process modes.
var scene: Node
var parked := false
var _modes: Dictionary = {}
var _viewport: Viewport
var _original_disable_3d := false
var _scene_processing := false

func configure(owner_scene: Node) -> void:
	scene = owner_scene
	_viewport = scene.get_viewport()
	_original_disable_3d = _viewport.disable_3d
	scene.child_entered_tree.connect(_child_entered)

func set_parked(value: bool) -> void:
	if value == parked or not is_instance_valid(scene):
		return
	parked = value
	if parked:
		_scene_processing = scene.is_processing()
		scene.set_process(false)
		_viewport.disable_3d = true
		for child in scene.get_children():
			_park_branch(child)
	else:
		_restore()

func _child_entered(child: Node) -> void:
	if parked:
		# _ready may assign a process mode, so record it after initialization.
		_park_deferred_branch.call_deferred(weakref(child))

func _park_deferred_branch(reference: WeakRef) -> void:
	var child := reference.get_ref() as Node
	if is_instance_valid(child):
		_park_branch(child)

func _park_branch(child: Node) -> void:
	if not parked or not is_instance_valid(child) or child.get_parent() != scene:
		return
	if child is Control or child is CanvasLayer or child == self:
		return
	if not _modes.has(child):
		_modes[child] = child.process_mode
	child.process_mode = Node.PROCESS_MODE_DISABLED

func _restore() -> void:
	if is_instance_valid(_viewport):
		_viewport.disable_3d = _original_disable_3d
	if is_instance_valid(scene):
		scene.set_process(_scene_processing)
	for child in _modes:
		if is_instance_valid(child):
			child.process_mode = _modes[child]
	_modes.clear()

func _exit_tree() -> void:
	if parked:
		_restore()
	parked = false
