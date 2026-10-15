extends Node
## One overlay shared by cached menus, startup and real scene changes.
## Keeps navigation state synchronous; scene resources use the threaded loader.

signal transition_started(destination: String)
signal transition_finished

const OVERLAY_PATH := "res://scenes/startup.tscn"
var _overlay: CanvasLayer

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

func is_busy() -> bool:
	return is_instance_valid(_overlay) and _overlay.is_inside_tree()

func register_overlay(overlay: CanvasLayer) -> void:
	_overlay = overlay
	overlay.tree_exited.connect(_on_overlay_exited.bind(overlay.get_instance_id()), CONNECT_ONE_SHOT)

func _on_overlay_exited(id: int) -> void:
	if is_instance_valid(_overlay) and _overlay.get_instance_id() == id:
		_overlay = null
		transition_finished.emit()

func present(destination: String) -> void:
	if is_busy():
		# Initial loading already covers the first menu and garage restoration.
		if bool(_overlay.get("presentation_only")):
			_overlay.call("set_transition_message", destination)
		return
	var overlay := _create_overlay()
	if overlay == null:
		return
	overlay.set("presentation_only", true)
	overlay.set("loading_message", destination)
	get_tree().root.add_child(overlay)
	transition_started.emit(destination)
	_finish_menu.call_deferred(overlay)

func _finish_menu(overlay: CanvasLayer) -> void:
	# Wait for navigation layouts and the first frame of the destination menu.
	for frame in 3:
		await get_tree().process_frame
	if is_instance_valid(overlay) and _overlay == overlay and not overlay.is_queued_for_deletion():
		overlay.call("complete_transition")

func change_scene(path: String, destination: String) -> void:
	if is_busy():
		if not bool(_overlay.get("presentation_only")) and str(_overlay.get("next_scene_path")) == path:
			return
		_overlay.queue_free()
		_overlay = null
	var overlay := _create_overlay()
	if overlay == null:
		return
	overlay.set("next_scene_path", path)
	overlay.set("loading_message", destination)
	overlay.set("minimum_presentation", 0.35)
	var previous := get_tree().current_scene
	if is_instance_valid(previous) and previous != overlay:
		overlay.set("origin_scene", previous)
		overlay.set("origin_process_mode", previous.process_mode)
		overlay.set("origin_tree_paused", get_tree().paused)
		previous.process_mode = Node.PROCESS_MODE_DISABLED
	get_tree().paused = false
	get_tree().root.add_child(overlay)
	transition_started.emit(destination)

func _create_overlay() -> CanvasLayer:
	var packed := load(OVERLAY_PATH) as PackedScene
	if packed == null:
		push_error("MenuTransition: loading screen is unavailable")
		return null
	var overlay := packed.instantiate() as CanvasLayer
	overlay.name = "MenuLoading"
	return overlay
