extends SceneTree

## Actual rendered compact arenas: authored overview + production duel view.
## Run rendered: --script res://tools/capture_compact_arenas.gd -- <directory> [id|all] [art-only|gameplay] [baseline-directory]
## Existing production images can be compared headlessly with compare-only.
const CATALOG := preload("res://scripts/compact_arena_catalog.gd")
const STAGE := preload("res://scripts/compact_arena_stage.gd")
const MECHANISMS := preload("res://scripts/compact_arena_mechanisms.gd")
var _errors: Array[String] = []
var _baseline_directory := ""
var _baseline_report: Dictionary = {}


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var compare_only := args.size() > 2 and args[2] == "compare-only"
	if args.is_empty() or (DisplayServer.get_name() == "headless" and not compare_only):
		push_error("Use a rendered Godot window and provide an output directory.")
		quit(2)
		return
	var directory: String = args[0]
	var chosen: String = args[1] if args.size() > 1 else "all"
	var art_only := args.size() > 2 and args[2] == "art-only"
	if args.size() > 3:
		_baseline_directory = args[3]
		var baseline_path := _baseline_directory.path_join("compact-arenas-art-captures.json" if art_only else "compact-arenas-captures.json")
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(baseline_path)) if FileAccess.file_exists(baseline_path) else null
		if not parsed is Dictionary:
			push_error("Cannot read baseline capture report: " + baseline_path)
			quit(2)
			return
		_baseline_report = parsed
	var ids: Array = CATALOG.IDS if chosen == "all" else [chosen]
	for identifier in ids:
		if not CATALOG.is_compact(str(identifier)):
			push_error("Unknown compact arena: " + str(identifier))
			quit(2)
			return
	if DirAccess.make_dir_recursive_absolute(directory) != OK:
		push_error("Cannot create capture directory: " + directory)
		quit(2)
		return
	# Keep diagnostics out of Godot's import scan if saved inside the project.
	var project_directory := ProjectSettings.globalize_path("res://").replace("\\", "/")
	if directory.replace("\\", "/").begins_with(project_directory):
		var ignore := FileAccess.open(directory.path_join(".gdignore"), FileAccess.WRITE)
		if ignore != null:
			ignore.close()
	var report := {"engine": Engine.get_version_info().string, "driver": RenderingServer.get_current_rendering_driver_name(), "viewport": [root.size.x, root.size.y], "art_only": art_only, "arenas": {}, "reference_directory": _baseline_directory,
		"measurement_note": "RenderingServer counts from the saved frame; captures freeze actor/arena simulation and do not constitute an FPS benchmark."}
	if compare_only:
		var saved: Variant = JSON.parse_string(FileAccess.get_file_as_string(directory.path_join("compact-arenas-captures.json")))
		if not saved is Dictionary or _baseline_report.is_empty():
			push_error("compare-only requires an existing production report and a baseline directory")
			quit(2)
			return
		_write_comparison(directory, saved, ids, false)
		for message in _errors:
			push_error(message)
		quit(0 if _errors.is_empty() else 1)
		return
	for identifier in ids:
		if art_only:
			await _capture_art(str(identifier), directory, report)
		else:
			await _capture_arena(str(identifier), directory, report)
	if not _baseline_report.is_empty():
		_write_comparison(directory, report, ids, art_only)
	var report_file := FileAccess.open(directory.path_join("compact-arenas-art-captures.json" if art_only else "compact-arenas-captures.json"), FileAccess.WRITE)
	if report_file != null:
		report_file.store_string(JSON.stringify(report, "\t", true, true) + "\n")
	else:
		_errors.append("Could not save capture report")
	for message in _errors:
		push_error(message)
	print("COMPACT ARENAS CAPTURE: %s (%d maps; %s)" % ["PASS" if _errors.is_empty() else "FAIL", ids.size(), directory])
	quit(0 if _errors.is_empty() else 1)


func _capture_arena(identifier: String, directory: String, report: Dictionary) -> void:
	var scene := load("res://scenes/main.tscn").instantiate() as Node3D
	root.add_child(scene)
	current_scene = scene
	await process_frame
	var flow := scene.get_node("Interface")
	# Bot identity is independent of geometry constructors' random-number usage.
	scene.call("set_bot_build_seed", 81738 + CATALOG.IDS.find(identifier))
	flow.call("_select_arena", identifier)
	flow.call("_start_duel")
	flow.call("_begin_live_round")
	flow.set_process(false)
	scene.set("_menu_showcase_active", false)
	scene.set_meta("camera_shake_enabled", false)
	var player := scene.get_node("Player") as Node3D
	var target := scene.get_node("TargetDummy") as Node3D
	player.set_process(false)
	player.set_physics_process(false)
	target.call("set_training_bot_enabled", false)
	target.set_physics_process(false)
	target.set_process(false)
	var stage := scene.get_node("CompactArenaStage") as Node3D
	if str(stage.get_meta("arena_id", "")) != identifier or not stage.has_meta("mesh_count"):
		_errors.append(identifier + ": visual stage construction did not finish")
	stage.set_process(false)
	var hazards := scene.get_node("ArenaHazards")
	hazards.set_physics_process(false)
	# Show the actual warning or rotor ramp while both fighters start safely.
	hazards.call("advance", 4.1)
	hazards.call("advance", 0.6)
	stage.call("_process", 4.7)
	var fog := scene.get_node_or_null("FogOfWar")
	scene.set_process(false)
	if fog != null:
		fog.call("set_enabled", false)
	var rig := scene.get_node("CameraRig") as Node3D
	rig.set_process(false)
	var gameplay_camera := rig.get_node("Camera3D") as Camera3D
	var layers: Array[CanvasLayer] = []
	for child in scene.get_children():
		if child is CanvasLayer:
			layers.append(child)
			child.visible = false
	var overview := Camera3D.new()
	overview.name = "DiagnosticCompactOverview"
	overview.position = Vector3(0.0, 34.0, 26.0)
	overview.fov = 40.0
	scene.add_child(overview)
	overview.look_at(Vector3(0.0, 0.0, -0.5))
	overview.current = true
	for frame in range(40):
		await process_frame
	await RenderingServer.frame_post_draw
	var overview_path := directory.path_join(identifier + "-overview.png")
	_save_image(overview_path)
	var arena_report := {"overview_path": overview_path, "overview_camera_position": _vector(overview.global_position), "overview_fov": overview.fov,
		"stage_snapshot": stage.call("get_snapshot"), "render_info": {"overview": _render_counts()}, "bot_seed": 81738 + CATALOG.IDS.find(identifier),
		"bot_build": scene.call("get_current_bot_build"), "player_loadout": flow.get("loadout")}
	# This extra perspective reveals facades and floor depth; the original
	# overview remains unchanged for comparison with the existing image set.
	var hidden_readouts := _hide_world_readouts(scene)
	overview.position = Vector3(23, 24, 29)
	overview.fov = 42.0
	overview.look_at(Vector3(0, 0.5, 0))
	for frame in range(20):
		await process_frame
	await RenderingServer.frame_post_draw
	var architecture_path := directory.path_join(identifier + "-architecture.png")
	_save_image(architecture_path)
	arena_report["architecture_path"] = architecture_path
	arena_report["architecture_camera_position"] = _vector(overview.global_position)
	arena_report["architecture_fov"] = overview.fov
	arena_report.render_info["architecture"] = _render_counts()
	for entry in hidden_readouts:
		(entry.node as Node3D).visible = bool(entry.visible)
	overview.queue_free()
	gameplay_camera.current = true
	scene.set_process(true)
	var reference: Dictionary = _baseline_report.get("arenas", {}).get(identifier, {})
	if reference.has("gameplay_camera_position"):
		var at: Array = reference.gameplay_camera_position
		gameplay_camera.global_position = Vector3(at[0], at[1], at[2])
		gameplay_camera.fov = float(reference.get("gameplay_fov", 40.0))
		gameplay_camera.look_at(Vector3(at[0], 0.45, float(at[2]) - 20.0))
		arena_report["camera_reference"] = "baseline production camera position and focal plane"
	else:
		# Settle the production follow routine with fixed timesteps, then keep
		# its camera still while the renderer samples identical actor positions.
		for frame in range(120):
			rig.call("_process", 1.0 / 60.0)
		arena_report["camera_reference"] = "production follow rig settled for 2 simulated seconds"
	for layer in layers:
		layer.visible = true
	flow.call("_update_countdown_overlay")
	flow.call("_update_hud")
	# The shipped camera, HUD, line-of-sight and fighter rigs render this frame.
	for frame in range(40):
		await process_frame
	var tracker := scene.get_node_or_null("SightTracker")
	if tracker != null:
		tracker.call("_process", 0.1)
	target.call("_update_visibility_presentation", 0.0)
	player.call("_update_world_ui_anchor")
	await RenderingServer.frame_post_draw
	var gameplay_path := directory.path_join(identifier + "-gameplay.png")
	_save_image(gameplay_path)
	arena_report["gameplay_path"] = gameplay_path
	arena_report["gameplay_camera_position"] = _vector(gameplay_camera.global_position)
	arena_report["gameplay_fov"] = gameplay_camera.fov
	arena_report["player_position"] = _vector(player.global_position)
	arena_report["opponent_position"] = _vector(target.global_position)
	arena_report["warning_mechanisms"] = hazards.call("get_snapshot")
	arena_report.render_info["gameplay"] = _render_counts()
	# Capture the real discharge as well as the readable advance warning.
	hazards.call("advance", _active_sample_delta(identifier))
	stage.call("_process", _active_sample_delta(identifier))
	for frame in range(10):
		await process_frame
	await RenderingServer.frame_post_draw
	var active_path := directory.path_join(identifier + "-gameplay-active.png")
	_save_image(active_path)
	arena_report["active_gameplay_path"] = active_path
	arena_report["active_mechanisms"] = hazards.call("get_snapshot")
	arena_report["active_player_position"] = _vector(player.global_position)
	arena_report["active_opponent_position"] = _vector(target.global_position)
	arena_report["active_camera_position"] = _vector(gameplay_camera.global_position)
	arena_report.render_info["active_gameplay"] = _render_counts()
	report.arenas[identifier] = arena_report
	print("COMPACT ARENA RENDERED: %s %s %s %s" % [identifier, overview_path, gameplay_path, active_path])
	scene.call("stop_duel")
	if identifier == "heliostat":
		await _capture_selection(flow, directory, arena_report)
	for sound in root.find_children("*", "AudioStreamPlayer", true, false):
		(sound as AudioStreamPlayer).stop()
	var sfx := root.get_node_or_null("GameSfx")
	if sfx != null:
		sfx.call("clear")
	current_scene = null
	scene.queue_free()
	await process_frame


func _save_image(path: String) -> void:
	var error := root.get_texture().get_image().save_png(path)
	if error != OK:
		_errors.append("Could not save %s (%d)" % [path, error])


func _render_counts() -> Dictionary:
	return {"objects_in_frame": RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME),
		"primitives_in_frame": RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME),
		"draw_calls_in_frame": RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)}


func _hide_world_readouts(scene: Node) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for node_name in ["WorldUIAnchor", "TargetHealthReadout"]:
		var node := scene.find_child(node_name, true, false) as Node3D
		if node != null:
			result.append({"node": node, "visible": node.visible})
			node.visible = false
	return result


func _write_comparison(directory: String, report: Dictionary, ids: Array, art_only: bool) -> void:
	var before_dimensions: Array = _baseline_report.get("viewport", [])
	var after_dimensions: Array = report.viewport
	var same_dimensions := before_dimensions.size() == 2 and after_dimensions.size() == 2
	if same_dimensions:
		same_dimensions = int(before_dimensions[0]) == int(after_dimensions[0]) and int(before_dimensions[1]) == int(after_dimensions[1])
	var comparison := {"baseline_directory": _baseline_directory, "after_directory": directory,
		"baseline_viewport": before_dimensions, "after_viewport": report.viewport,
		"matching_viewport": same_dimensions, "arenas": {}}
	var html := """<!doctype html><html lang="fr"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Cinq arènes — comparaison visuelle</title><style>
body{margin:0;background:#111c25;color:#e1e9ed;font:15px system-ui,sans-serif}main{max-width:1600px;margin:auto;padding:28px}
h1{font-size:28px}h2{font-size:23px;margin-top:44px;color:#f2c891}h3{font-size:15px;font-weight:500;color:#b8c9d2}
.pair{display:grid;grid-template-columns:1fr 1fr;gap:14px}figure{margin:0;background:#1d2b35;border:1px solid #354650;border-radius:7px;overflow:hidden}
img{display:block;width:100%;height:auto}figcaption{padding:9px 12px;font-size:13px}p{line-height:1.6;color:#b8c9d2}
details{margin-top:12px}pre{white-space:pre-wrap;color:#c4d4dd;font-size:12px}@media(max-width:760px){.pair{grid-template-columns:1fr}}
</style><main><h1>Cinq arènes — comparaison visuelle</h1>
<p>Les vues principales conservent le cadrage des captures de référence. Les acteurs, les mécanismes et les animations du décor sont figés à des temps de simulation définis. Les compteurs proviennent du rendu enregistré ; cette capture ne mesure pas les performances d'un duel en mouvement.</p>
"""
	for identifier in ids:
		var before: Dictionary = _baseline_report.get("arenas", {}).get(identifier, {})
		var after: Dictionary = report.arenas.get(identifier, {})
		if before.is_empty() or after.is_empty():
			continue
		var measures := {"before_render_info": before.get("render_info", {}), "after_render_info": after.get("render_info", {}),
			"baseline_has_renderer_counts": before.has("render_info"), "baseline_has_active_camera": before.has("active_camera_position")}
		if before.has("gameplay_camera_position") and after.has("gameplay_camera_position"):
			var a: Array = before.gameplay_camera_position
			var b: Array = after.gameplay_camera_position
			measures["warning_camera_position_difference_m"] = Vector3(a[0], a[1], a[2]).distance_to(Vector3(b[0], b[1], b[2]))
		for phase in ["warning_mechanisms", "active_mechanisms"]:
			if before.has(phase) and after.has(phase):
				measures[phase + "_clock_difference_s"] = absf(float(before[phase].elapsed) - float(after[phase].elapsed))
		comparison.arenas[identifier] = measures
		html += "<section><h2>" + str(CATALOG.definition(str(identifier)).title).xml_escape() + "</h2>"
		var views: Array = ["overview", "detail", "active"] if art_only else ["overview", "gameplay", "active_gameplay"]
		for view in views:
			var before_path := str(before.get("views", {}).get(view, {}).get("path", "")) if art_only else str(before.get(str(view) + "_path", ""))
			var after_path := str(after.get("views", {}).get(view, {}).get("path", "")) if art_only else str(after.get(str(view) + "_path", ""))
			if before_path.is_empty() or after_path.is_empty():
				continue
			var label: String = {"overview": "Vue d'ensemble", "gameplay": "Combat — avertissement", "active_gameplay": "Combat — mécanisme actif", "detail": "Détail", "active": "Mécanisme actif"}[view]
			html += "<h3>" + label + "</h3><div class='pair'>" + _comparison_figure(before_path, "Avant") + _comparison_figure(after_path, "Après") + "</div>"
		if after.has("architecture_path"):
			html += "<details><summary>Nouvelle vue de l'architecture</summary>" + _comparison_figure(str(after.architecture_path), "Perspective de contrôle — étiquettes de santé masquées") + "</details>"
		html += "<details><summary>Mesures du rendu et du cadrage</summary><pre>" + JSON.stringify(measures, "  ").xml_escape() + "</pre></details></section>"
	html += "</main></html>"
	var json_file := FileAccess.open(directory.path_join("compact-arenas-comparison.json"), FileAccess.WRITE)
	var html_file := FileAccess.open(directory.path_join("compact-arenas-comparison.html"), FileAccess.WRITE)
	if json_file == null or html_file == null:
		_errors.append("Could not save capture comparison")
		return
	json_file.store_string(JSON.stringify(comparison, "\t", true, true) + "\n")
	html_file.store_string(html)
	print("COMPACT ARENAS COMPARISON: " + directory.path_join("compact-arenas-comparison.html"))


func _comparison_figure(path: String, caption: String) -> String:
	var normalized := ProjectSettings.globalize_path(path).replace("\\", "/")
	var url := "file:///" + normalized.replace(" ", "%20") if not normalized.begins_with("/") else "file://" + normalized.replace(" ", "%20")
	return "<figure><img loading='lazy' src='" + url.xml_escape(true) + "'><figcaption>" + caption.xml_escape() + "</figcaption></figure>"


func _capture_selection(flow: Node, directory: String, arena_report: Dictionary) -> void:
	# Embed the actual PopupMenu so its complete arena list appears in the PNG.
	var previous_embed := root.gui_embed_subwindows
	root.gui_embed_subwindows = true
	flow.call("_open_equipment")
	for frame in range(20):
		await process_frame
	var garage := flow.get("_forge_garage") as Control
	var selector := garage.get("_arena_selector") as OptionButton if garage != null else null
	if selector == null:
		_errors.append("Cannot capture the forge arena selector")
		root.gui_embed_subwindows = previous_embed
		return
	selector.show_popup()
	for frame in range(10):
		await process_frame
	await RenderingServer.frame_post_draw
	var path := directory.path_join("heliostat-selection.png")
	_save_image(path)
	arena_report["selection_path"] = path
	arena_report["selection_choices"] = selector.item_count
	print("COMPACT ARENA SELECTOR RENDERED: " + path)
	selector.get_popup().hide()
	root.gui_embed_subwindows = previous_embed


func _vector(value: Vector3) -> Array:
	return [value.x, value.y, value.z]


func _capture_art(identifier: String, directory: String, report: Dictionary) -> void:
	# Independent visual authoring fixture; does not load main, forge or combat.
	var scene := Node3D.new()
	root.add_child(scene)
	current_scene = scene
	var palette: Array = {
		"heliostat": [Color("#638c9b"), Color("#c2d7df"), Color("#ffe1b2"), 1.12, 0.42],
		"tideglass": [Color("#244e59"), Color("#a3cbc3"), Color("#e2efcd"), 1.10, 0.43],
		"clockwork": [Color("#242339"), Color("#bdbbd8"), Color("#ffe0b9"), 1.14, 0.43],
		"gyre": [Color("#18232c"), Color("#a0bac5"), Color("#ffd0a7"), 1.22, 0.45],
		"resonance": [Color("#202b42"), Color("#b6cedc"), Color("#ffe2dd"), 1.08, 0.43],
	}[identifier]
	var settings := Environment.new()
	settings.background_mode = Environment.BG_COLOR
	settings.background_color = palette[0]
	settings.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	settings.ambient_light_color = palette[1]
	settings.ambient_light_energy = palette[4]
	if identifier == "heliostat":
		var sky := Sky.new()
		var sky_material := ProceduralSkyMaterial.new()
		sky_material.sky_top_color = Color("#426d91")
		sky_material.sky_horizon_color = Color("#b8d0ce")
		sky_material.ground_horizon_color = Color("#b8d0ce")
		sky_material.ground_bottom_color = Color("#567f96")
		sky_material.sky_curve = 0.45
		sky_material.ground_curve = 0.5
		sky.sky_material = sky_material
		settings.sky = sky
		settings.background_mode = Environment.BG_SKY
	settings.fog_enabled = false
	settings.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var environment := WorldEnvironment.new()
	environment.environment = settings
	scene.add_child(environment)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-58, -32, 0)
	key.light_color = palette[2]
	key.light_energy = palette[3]
	key.shadow_enabled = true
	scene.add_child(key)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-38, 145, 0)
	fill.light_color = Color("#91a9b6")
	fill.light_energy = 0.28
	scene.add_child(fill)
	var stage := STAGE.new()
	stage.arena_id = identifier
	scene.add_child(stage)
	if str(stage.get_meta("arena_id", "")) != identifier or not stage.has_meta("mesh_count"):
		_errors.append(identifier + ": standalone visual stage construction did not finish")
	stage.running = true
	stage.set_process(false)
	var runtime_script: Script = load("res://scripts/open_arena_mechanisms.gd") if CATALOG.definition(identifier).get("mechanism", "") == "open" else MECHANISMS
	if runtime_script == null:
		_errors.append("Missing arena mechanisms for " + identifier)
		scene.queue_free()
		await process_frame
		return
	var mechanisms: Node3D = runtime_script.new()
	mechanisms.set("arena_id", identifier)
	scene.add_child(mechanisms)
	if mechanisms.has_method("set_stage"):
		mechanisms.call("set_stage", stage)
	mechanisms.call("set_enabled", true)
	mechanisms.set_physics_process(false)
	mechanisms.call("start_round")
	mechanisms.call("advance", 4.1)
	mechanisms.call("advance", 0.6)
	stage.call("_process", 4.7)
	var camera := Camera3D.new()
	camera.fov = 40.0
	scene.add_child(camera)
	camera.current = true
	var arena_report := {"fixture": "standalone art preview; no gameplay actors or HUD", "views": {}, "stage_snapshot": stage.call("get_snapshot"), "render_info": {}}
	for view in ["overview", "detail"]:
		camera.position = Vector3(0, 34, 26) if view == "overview" else Vector3(0, 24, 20)
		camera.look_at(Vector3(0, 0, -0.5))
		for frame in range(40):
			await process_frame
		await RenderingServer.frame_post_draw
		var path := directory.path_join(identifier + "-art-" + view + ".png")
		_save_image(path)
		arena_report.views[view] = {"path": path, "camera_position": _vector(camera.global_position), "fov": camera.fov}
		arena_report.render_info[view] = _render_counts()
		print("COMPACT ARENA ART PREVIEW: " + path)
	arena_report["warning_mechanisms"] = mechanisms.call("get_snapshot")
	mechanisms.call("advance", _active_sample_delta(identifier))
	stage.call("_process", _active_sample_delta(identifier))
	for frame in range(10):
		await process_frame
	await RenderingServer.frame_post_draw
	var active_path := directory.path_join(identifier + "-art-active.png")
	_save_image(active_path)
	arena_report.views["active"] = {"path": active_path, "camera_position": _vector(camera.global_position), "fov": camera.fov}
	arena_report["active_mechanisms"] = mechanisms.call("get_snapshot")
	arena_report.render_info["active"] = _render_counts()
	print("COMPACT ARENA ART PREVIEW: " + active_path)
	report.arenas[identifier] = arena_report
	var sfx := root.get_node_or_null("GameSfx")
	if sfx != null:
		sfx.call("clear")
	current_scene = null
	scene.queue_free()
	await process_frame


func _active_sample_delta(identifier: String) -> float:
	# A grown acoustic crest and visibly displaced rings expose each new mechanic.
	if identifier == "gyre":
		return 3.0
	if identifier == "resonance":
		return 1.42
	return float(CATALOG.definition(identifier).warning) + 0.02
