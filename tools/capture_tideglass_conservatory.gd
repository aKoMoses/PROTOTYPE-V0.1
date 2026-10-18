extends "res://tools/capture_compact_arena_presentation.gd"
## Same production cameras as the shared arena comparison, without the profiler.
var _conservatory_snapshot: Dictionary = {}

func _run() -> void:
	root.get_node("FramePacing").visible = false
	await super._run()

func _freeze(node: Node) -> void:
	super._freeze(node)
	if OS.get_cmdline_user_args().has("decor-only"):
		if node is CanvasLayer or node is Label3D:
			node.visible = false
	if str(node.name) == "TideglassConservatory":
		_conservatory_snapshot = node.call("get_snapshot")
		# Round time stays frozen; the reflection view must still follow each of
		# the comparison camera positions used by the capture harness.
		node.set_process(true)

func _capture(id: String, directory: String, report: Dictionary) -> void:
	await super._capture(id, directory, report)
	for frame in 4:
		await process_frame
		await RenderingServer.frame_post_draw
	report["decor_only"] = OS.get_cmdline_user_args().has("decor-only")
	report["conservatory"] = _conservatory_snapshot

func _save(path: String) -> void:
	if path.ends_with("-active.png") and OS.get_cmdline_user_args().has("reflection-debug"):
		var art := current_scene.get_node("CompactArenaStage/TideglassArena/TideglassConservatory")
		var view: SubViewport = art.get("_planar")
		view.get_texture().get_image().save_png(path.get_basename() + "-reflection.png")
	super._save(path)
