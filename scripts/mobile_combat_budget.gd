extends Node
## Android scenery gets a shared 15 Hz clock. Combat, physics, actors, HUD,
## visibility and hazard controllers retain their own full-rate processing.
const INTERVAL := 1.0 / 15.0
const SCENERY_SCRIPTS := [
	"res://scripts/environment/organic_world_details.gd",
	"res://scripts/environment/workshop_ambience.gd",
	"res://scripts/environment/scenery_life.gd",
	"res://scripts/environment/workshop_ecosystem.gd",
	"res://scripts/combat_presentation_pass.gd",
]
var _targets: Array[Dictionary] = []
var _pending: Dictionary = {}
var _updates := 0
var _last_update_ms := 0.0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	process_priority = 125
	get_tree().node_added.connect(_node_added)
	# Installation can happen after a scene already exists in a diagnostic run.
	if get_tree().current_scene != null:
		for node in get_tree().current_scene.find_children("*", "", true, false):
			_node_added(node)

func _node_added(node: Node) -> void:
	if _is_scenery(node):
		_pending[node.get_instance_id()] = {"node": weakref(node), "frames": 0}

func _is_scenery(node: Node) -> bool:
	var script := node.get_script() as Script
	return script != null and script.resource_path in SCENERY_SCRIPTS and node.get_viewport() == get_viewport()

func register_node(node: Node) -> void:
	if not is_instance_valid(node) or not node.is_inside_tree() or not _is_scenery(node) or not node.is_processing():
		return
	for entry in _targets:
		if entry.node.get_ref() == node:
			return
	node.set_process(false)
	_targets.append({"node": weakref(node), "elapsed": 0.0, "due": INTERVAL * (1.0 + float(_targets.size() % 4) * 0.25), "was_active": true})

func _can_update(node: Node) -> bool:
	if not node.can_process() or (node is Node3D and not (node as Node3D).is_visible_in_tree()):
		return false
	if node.has_method("_is_active") and not bool(node.call("_is_active")):
		return false
	# A child's explicit PAUSABLE mode can override a disabled parent's mode.
	# Scene transitions disable that parent: never manually revive its decor.
	var ancestor := node.get_parent()
	while ancestor != null:
		if ancestor.process_mode == Node.PROCESS_MODE_DISABLED:
			return false
		ancestor = ancestor.get_parent()
	return true

func _process(delta: float) -> void:
	if get_tree().paused:
		return
	for id in _pending.keys():
		var entry: Dictionary = _pending[id]
		var node: Node = entry.node.get_ref()
		if not is_instance_valid(node) or not node.is_inside_tree():
			_pending.erase(id)
			continue
		entry.frames += 1
		# Deferred scenery builders need a few frames before enabling processing.
		if int(entry.frames) >= 3 and node.is_processing():
			register_node(node)
			_pending.erase(id)
		elif int(entry.frames) >= 30:
			_pending.erase(id)
	var started := Time.get_ticks_usec()
	for index in range(_targets.size() - 1, -1, -1):
		var entry := _targets[index]
		var node: Node = entry.node.get_ref()
		if not is_instance_valid(node) or not node.is_inside_tree():
			if is_instance_valid(node):
				node.set_process(true)
			_targets.remove_at(index)
			continue
		if not _can_update(node):
			if bool(entry.was_active):
				# Cleanup is a lifecycle event, not a cosmetic animation tick.
				if node.has_method("clear"):
					node.call("clear")
				elif node.has_method("reset_transients"):
					node.call("reset_transients")
				if node.has_method("_is_active"):
					node.set("_active", false)
			entry.was_active = false
			entry.elapsed = 0.0
			continue
		entry.was_active = true
		entry.elapsed += maxf(0.0, delta)
		if float(entry.elapsed) + 0.000001 < float(entry.due):
			continue
		var elapsed := float(entry.elapsed)
		entry.elapsed = 0.0
		entry.due = INTERVAL
		node.call("_process", elapsed)
		_updates += 1
	_last_update_ms = float(Time.get_ticks_usec() - started) / 1000.0

func get_debug_snapshot() -> Dictionary:
	return {"controllers": _targets.size(), "updates": _updates, "last_update_ms": _last_update_ms, "interval": INTERVAL}

func _exit_tree() -> void:
	for entry in _targets:
		var node: Node = entry.node.get_ref()
		if is_instance_valid(node):
			node.set_process(true)
