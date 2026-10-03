extends Node3D

const CLASSIC_ARENA_BUILDER = preload("res://scripts/arenas/classic_arena_builder.gd")
const ARENA_HAZARDS := preload("res://scripts/arena_hazards.gd")
const TEST_ARENA := preload("res://scripts/test_arena.gd")
const ARENA_TRAVERSAL := preload("res://scripts/arena_traversal.gd")
const COMPACT_ARENAS := preload("res://scripts/compact_arena_catalog.gd")
const COMPACT_STAGE := preload("res://scripts/compact_arena_stage.gd")
const COMPACT_MECHANISMS := preload("res://scripts/compact_arena_mechanisms.gd")
const HELIOSTAT_MECHANISMS := preload("res://scripts/heliostat_arena.gd")
const OPEN_MECHANISMS := preload("res://scripts/open_arena_mechanisms.gd")
const PLAYER_SCRIPT := preload("res://scripts/player.gd")
const CAMERA_RIG_SCRIPT := preload("res://scripts/camera_rig.gd")
const TARGET_SCRIPT := preload("res://scripts/target_dummy.gd")
const TOUCH_CONTROLS_SCRIPT := preload("res://scripts/touch_controls.gd")
const GAME_FLOW_SCRIPT := preload("res://scripts/game_flow.gd")
const NETWORK_MATCH_SCRIPT := preload("res://scripts/network_match.gd")
const VFX_MANAGER_SCRIPT := preload("res://scripts/vfx_manager.gd")
const BOT_BUILD_PRESETS := preload("res://scripts/bot_build_presets.gd")
const SIGHT_TRACKER_SCRIPT := preload("res://scripts/sight_tracker.gd")
const FOG_OF_WAR_SCRIPT := preload("res://scripts/fog_of_war.gd")
const REPAIR_KIT_SCENE := preload("res://scenes/repair_kit.tscn")
const ARENA_PRESENTATION: PackedScene = preload("res://scenes/environment/arena_presentation.tscn")
const REPAIR_SOCKET: PackedScene = preload("res://scenes/environment/repair_socket.tscn")

@export_enum("easy", "normal", "hard") var bot_difficulty := "normal"

var player: CharacterBody3D
var game_flow: CanvasLayer
var network_match: CanvasLayer
var target: StaticBody3D
var touch_controls: Control
var sight_tracker: CanvasLayer
var fog_of_war: Node3D
var duel_active := false
var arena_variant := "classic"
var _arena_hazards: Node3D
var _classic_arena_nodes: Array[Node3D] = []
var _test_arena: Node3D
var _classic_hazards: Node3D
var _compact_stage: Node3D
var _classic_arena_roots: Array[Node] = []
var _classic_arena_blockers: Array[StaticBody3D] = []
var _classic_environment: Environment
var _classic_light_color := Color.WHITE
var _classic_light_energy := 1.0
var _bot_build: Dictionary = {}
var _ambient_clock := 0.0
var _flicker_lights: Array[OmniLight3D] = []
var _fx_serial := 0
var _fx_budget_clock := 0.0
var _menu_showcase_active := false
var _menu_showcase_elapsed := 0.0
var _menu_showcase_clip := -1
var _classic_builder: RefCounted
var _arena_blockers: Array[StaticBody3D] = []
var _bot_build_presets := BOT_BUILD_PRESETS.new()
var _bot_build_round_key := ""
var _bot_build_current: Dictionary = {}
const FX_MAX_PARTICLES := 24
const FX_MAX_BURSTS := 42
const FX_MAX_PROJECTILES := 14
const MENU_SHOWCASE_CLIP_SECONDS := 3.0


func _process(delta: float) -> void:
	if fog_of_war != null:
		var active_player: Node = game_flow.get("player") if game_flow != null else player
		var active_target: Node = game_flow.get("target") if game_flow != null else target
		var live_round := is_instance_valid(active_player) and bool(active_player.call("is_gameplay_enabled")) and not bool(active_player.call("is_real_dead"))
		var local_or_network := duel_active or is_instance_valid(network_match)
		fog_of_war.call("set_enabled", live_round and local_or_network and is_instance_valid(active_target) and not bool(active_target.call("is_real_dead")))
	_ambient_clock += delta
	_fx_budget_clock += delta
	_update_menu_showcase(delta)
	if _fx_budget_clock >= 0.25:
		_fx_budget_clock = 0.0
		_trim_fx_budget()
	for index in range(_flicker_lights.size()):
		var light := _flicker_lights[index]
		if not is_instance_valid(light):
			continue
		var base_energy := float(light.get_meta("base_energy", 1.0))
		var phase := float(index) * 1.71
		light.light_energy = base_energy + sin(_ambient_clock * (5.0 + float(index % 3)) + phase) * 0.14 + sin(_ambient_clock * 11.0 + phase) * 0.06


func register_fx_node(node: Node, category: String = "burst") -> void:
	if node == null or not is_instance_valid(node):
		return
	# Projectile nodes own combat callbacks and may only be cleared at round reset.
	if category == "projectile":
		node.add_to_group("prototype0_gameplay_projectiles")
		return
	_fx_serial += 1
	node.add_to_group("prototype0_fx_budget")
	node.set_meta("prototype0_fx_category", category)
	node.set_meta("prototype0_fx_serial", _fx_serial)


func _trim_fx_budget() -> void:
	var counts := {"particle": 0, "burst": 0, "projectile": 0}
	var nodes_by_category := {"particle": [], "burst": [], "projectile": []}
	for node in get_tree().get_nodes_in_group("prototype0_fx_budget"):
		if node == null or not is_instance_valid(node):
			continue
		var category := str(node.get_meta("prototype0_fx_category", "burst"))
		if not nodes_by_category.has(category):
			category = "burst"
		counts[category] = int(counts[category]) + 1
		nodes_by_category[category].append(node)
	var limits := {"particle": FX_MAX_PARTICLES, "burst": FX_MAX_BURSTS, "projectile": FX_MAX_PROJECTILES}
	for category in limits.keys():
		var excess := int(counts[category]) - int(limits[category])
		if excess <= 0:
			continue
		var candidates: Array = nodes_by_category[category]
		candidates.sort_custom(func(a: Node, b: Node) -> bool:
			return int(a.get_meta("prototype0_fx_serial", 0)) < int(b.get_meta("prototype0_fx_serial", 0))
		)
		for index in range(mini(excess, candidates.size())):
			var node: Node = candidates[index]
			if is_instance_valid(node):
				node.queue_free()


func _ready() -> void:
	var remembered_arena := str(get_tree().get_meta("selected_duel_arena", "classic"))
	set_meta("camera_shake_enabled", true)
	var vfx := VFX_MANAGER_SCRIPT.new()
	vfx.name = "VFXManager"
	add_child(vfx)
	_classic_builder = CLASSIC_ARENA_BUILDER.new(self, _arena_blockers, _flicker_lights)
	_build_environment()
	var before_arena := get_children()
	_build_arena()
	for node in get_children():
		if node not in before_arena:
			_classic_arena_roots.append(node)
			if node is Node3D:
				_classic_arena_nodes.append(node)
	_classic_arena_blockers.assign(_arena_blockers)
	_build_player()
	_build_camera()
	_build_target()
	_arena_hazards = ARENA_HAZARDS.new()
	_arena_hazards.name = "ArenaHazards"
	add_child(_arena_hazards)
	_classic_hazards = _arena_hazards
	_arena_hazards.call("configure", player, target)
	_build_interface()
	var presentation := ARENA_PRESENTATION.instantiate()
	add_child(presentation)
	_classic_arena_roots.append(presentation)
	fog_of_war = FOG_OF_WAR_SCRIPT.new()
	fog_of_war.name = "FogOfWar"
	add_child(fog_of_war)
	fog_of_war.call("configure", player, get_node("CameraRig/Camera3D"))
	fog_of_war.call("set_enabled", false)
	get_node("/root/NetworkSession").match_started.connect(_on_network_match_started)
	if remembered_arena != "classic":
		game_flow.call_deferred("_select_arena", remembered_arena)


func _on_network_match_started(host_id: int, guest_id: int) -> void:
	# Online sessions currently agree on the classic arena only.
	set_arena_variant("classic")
	if _arena_hazards != null:
		_arena_hazards.call("set_enabled", false)
	if network_match != null and is_instance_valid(network_match):
		network_match.call("_cleanup_actors")
		network_match.queue_free()
	network_match = CanvasLayer.new()
	network_match.name = "NetworkMatch"
	network_match.set_script(NETWORK_MATCH_SCRIPT)
	add_child(network_match)
	network_match.call("configure", self, host_id, guest_id)


func _build_environment() -> void:
	_classic_builder.build_environment()


func _build_arena() -> void:
	_classic_builder.build()


func _create_scrap_barrier(node_name: String, position: Vector3, size: Vector3, rotation_y: float = 0.0) -> StaticBody3D:
	return _classic_builder._create_scrap_barrier(node_name, position, size, rotation_y)


func _build_player() -> void:
	player = CharacterBody3D.new()
	player.name = "Player"
	player.set_script(PLAYER_SCRIPT)
	player.position = Vector3(-3.5, 0.0, 17.0)
	add_child(player)
	if DisplayServer.get_name() != "headless":
		player.call("set_gameplay_enabled", false)
	if player.has_signal("died"):
		player.died.connect(_on_player_died)


func _build_camera() -> void:
	var rig := Node3D.new()
	rig.name = "CameraRig"
	rig.set_script(CAMERA_RIG_SCRIPT)

	var camera := Camera3D.new()
	camera.name = "Camera3D"
	# A high, slightly perspective view keeps the arena readable while preserving
	# the visible height and depth found in the visual references.
	camera.position = Vector3(0.0, 20.5, 17.5)
	camera.fov = 38.0
	camera.current = true
	rig.add_child(camera)
	# Add the complete rig only after its Camera3D child exists. Otherwise the
	# rig's _ready() runs too early and the camera never gets aimed at the player.
	add_child(rig)
	rig.call("set_target", player)


func _build_target() -> void:
	target = StaticBody3D.new()
	target.name = "TargetDummy"
	target.set_script(TARGET_SCRIPT)
	target.position = Vector3(3.5, 0.0, 15.5)
	add_child(target)
	# Match start is always clean. This is intentionally explicit even though
	# TargetDummy creates a fresh CombatState in _ready(): it protects the
	# gameplay scene from any editor/capture reuse and keeps diagnostic effects
	# (F1-F4) opt-in instead of leaking into a new round.
	target.call("reset_combat_state")
	target.call("set_duel_mode", false)
	if target.has_signal("died"):
		target.died.connect(_on_target_died)


func _build_interface() -> void:
	game_flow = CanvasLayer.new()
	# Keep the historical Interface path so existing tools and captures remain valid.
	game_flow.name = "Interface"
	game_flow.set_script(GAME_FLOW_SCRIPT)
	add_child(game_flow)
	touch_controls = Control.new()
	touch_controls.name = "TouchControls"
	touch_controls.set_script(TOUCH_CONTROLS_SCRIPT)
	touch_controls.call("set_player", player)
	game_flow.add_child(touch_controls)
	game_flow.call("configure", self, player, target, touch_controls)
	sight_tracker = SIGHT_TRACKER_SCRIPT.new()
	sight_tracker.name = "SightTracker"
	add_child(sight_tracker)
	sight_tracker.call("configure", self, player, target)


func set_menu_mode(menu_mode: bool) -> void:
	# Headless integration scripts exercise the combat actors directly without
	# navigating the visual menu. Keep their physics active for those tests.
	if DisplayServer.get_name() == "headless":
		return
	if menu_mode:
		if player != null and player.has_method("set_gameplay_enabled"):
			player.call("set_gameplay_enabled", false)
		if target != null:
			target.call("set_training_bot_enabled", false)


func set_menu_showcase_enabled(value: bool) -> void:
	if value and arena_variant == "test":
		set_arena_variant("classic")
	if DisplayServer.get_name() == "headless":
		return
	if COMPACT_ARENAS.is_compact(arena_variant):
		value = false
	if _menu_showcase_active == value:
		return
	_menu_showcase_active = value
	_menu_showcase_elapsed = 0.0
	_menu_showcase_clip = -1
	if value:
		_set_menu_showcase_clip(0)
		return
	if player != null:
		player.call("clear_touch_inputs")
		player.call("set_gameplay_enabled", false)
	if target != null:
		target.call("set_training_bot_enabled", false)
		target.call("set_duel_mode", false)
	reset_round_camera()


func _update_menu_showcase(delta: float) -> void:
	if not _menu_showcase_active or player == null or target == null:
		return
	_menu_showcase_elapsed += delta
	var clip_index := int(floor(_menu_showcase_elapsed / MENU_SHOWCASE_CLIP_SECONDS)) % 3
	if clip_index != _menu_showcase_clip:
		_set_menu_showcase_clip(clip_index)
	var clip_time := fmod(_menu_showcase_elapsed, MENU_SHOWCASE_CLIP_SECONDS)
	var aim: Vector3 = target.global_position - player.global_position
	aim.y = 0.0
	if aim.length_squared() > 0.001:
		player.call("set_touch_aim_vector", Vector2(aim.x, aim.z).normalized())
	var firing := (clip_time >= 0.62 and clip_time < 1.22) or (clip_time >= 2.04 and clip_time < 2.43)
	player.call("set_touch_attack_held", firing)


func _set_menu_showcase_clip(clip_index: int) -> void:
	_menu_showcase_clip = clip_index
	var player_positions: Array[Vector3] = [
		Vector3(-2.4, 0.0, 3.5),
		Vector3(2.2, 0.0, 4.0),
		Vector3(-1.5, 0.0, 5.3),
	]
	var target_positions: Array[Vector3] = [
		Vector3(2.1, 0.0, 0.5),
		Vector3(-0.5, 0.0, 2.0),
		Vector3(1.5, 0.0, 4.0),
	]
	var camera_positions: Array[Vector3] = [
		Vector3(-4.5, 13.0, 11.0),
		Vector3(-5.2, 13.0, 11.0),
		Vector3(-4.0, 14.0, 12.0),
	]
	var camera_fovs: Array[float] = [34.0, 36.0, 36.0]
	clear_transient_fx()
	player.global_position = player_positions[clip_index]
	target.global_position = target_positions[clip_index]
	player.call("clear_touch_inputs")
	player.call("reset_combat_state")
	player.call("set_weapon", "shotgun" if clip_index == 1 else "blaster")
	player.call("set_gameplay_enabled", true)
	target.call("set_duel_mode", false)
	target.call("reset_combat_state")
	target.call("set_training_bot_spawn_position", target_positions[clip_index])
	target.call("set_training_bot_enabled", true)
	var player_world_ui := player.get_node_or_null("WorldUIAnchor") as Node3D
	if player_world_ui != null:
		player_world_ui.visible = false
	var target_readout := target.get_node_or_null("TargetHealthReadout")
	if target_readout != null:
		target_readout.visible = false
		target_readout.call("set_cinematic_mode", true)
	var rig := get_node_or_null("CameraRig")
	if rig != null:
		rig.call("reset_focus")
		rig.call("set_target", player)
		rig.call("set_follow_offset", Vector3(-5.5 if clip_index == 1 else -6.0, 0.0, -3.0), true)
		var camera := rig.get_node_or_null("Camera3D") as Camera3D
		if camera != null:
			camera.position = camera_positions[clip_index]
			camera.fov = camera_fovs[clip_index]


func start_duel(loadout: Dictionary, rematch: bool = false) -> void:
	_bot_build_round_key = str(game_flow.match_id) if rematch and game_flow != null else ""
	prepare_round(loadout)


func prepare_round(loadout: Dictionary) -> void:
	duel_active = true
	if _arena_hazards != null:
		_arena_hazards.call("set_enabled", (arena_variant == "hazards" or COMPACT_ARENAS.is_compact(arena_variant)) and not is_instance_valid(network_match))
	if player == null or target == null:
		return
	clear_transient_fx()
	var spawns := get_arena_spawns()
	player.position = spawns[0]
	target.position = spawns[1]
	player.velocity = Vector3.ZERO
	if COMPACT_ARENAS.is_compact(arena_variant):
		player.set("aim_direction", (target.position - player.position).normalized())
	reset_round_camera()
	target.call("set_duel_mode", true)
	var round_key := str(game_flow.match_id if game_flow != null else 0)
	# Keep the opponent's identity and build for the whole match, including draws.
	if _bot_build_current.is_empty() or round_key != _bot_build_round_key:
		_bot_build_current = _bot_build_presets.next_preset()
		_bot_build_round_key = round_key
	target.set_meta("bot_build_preset", _bot_build_current.duplicate(true))
	target.set_meta("bot_build_id", str(_bot_build_current.id))
	target.set_meta("bot_build_name", str(_bot_build_current.name))
	target.set_meta("bot_personality", _bot_build_current.personality.duplicate(true))
	_bot_build = _bot_build_current.loadout.duplicate(true)
	_bot_build["title"] = str(_bot_build_current.name)
	target.call("set_duel_loadout", _bot_build)
	target.call("set_bot_difficulty", bot_difficulty)
	target.call("set_training_bot_enabled", false)
	target.call("set_training_bot_spawn_position", target.position)
	var bot_controller := target.get_node_or_null("TrainingBot")
	if bot_controller != null:
		bot_controller.set("duel_arena_limit", minf(get_arena_half_size().x, get_arena_half_size().y) - 0.6 if COMPACT_ARENAS.is_compact(arena_variant) else (TEST_ARENA.PLAYABLE_HALF_EXTENTS.x if arena_variant == "test" else 27.0))
	target.call("reset_combat_state")
	player.call("apply_loadout", loadout)
	player.call("reset_combat_state")
	player.call("set_gameplay_enabled", false)
	player.call("clear_touch_inputs")
	_reset_repair_kits(false)


func get_bot_build() -> Dictionary:
	return {} if is_instance_valid(network_match) or (target != null and bool(target.get("network_proxy"))) else _bot_build.duplicate(true)


func set_bot_build_seed(value: int) -> void:
	_bot_build_presets.set_seed(value)
	_bot_build_round_key = ""
	_bot_build_current.clear()
	_bot_build.clear()


func get_current_bot_build() -> Dictionary:
	return _bot_build_current.duplicate(true)


func activate_round() -> void:
	if not duel_active or player == null or target == null:
		return
	player.call("set_gameplay_enabled", true)
	target.call("set_training_bot_enabled", true)
	_set_repair_kits_active(true)
	if is_instance_valid(_compact_stage):
		_compact_stage.set("running", true)
	if _arena_hazards != null:
		_arena_hazards.call("start_round")


func restart_duel(loadout: Dictionary) -> void:
	start_duel(loadout)


func stop_duel(preserve_defeat: bool = false) -> void:
	duel_active = false
	if is_instance_valid(_compact_stage):
		_compact_stage.set("running", false)
	if _arena_hazards != null:
		_arena_hazards.call("stop_round")
	clear_transient_fx()
	_set_repair_kits_active(false)
	if player != null:
		player.call("set_gameplay_enabled", false)
		player.call("clear_touch_inputs")
	if target != null:
		target.call("set_training_bot_enabled", false)
		# Switching combat states here resurrects the defeated bot immediately.
		# Keep the corpse until the next round explicitly resets both actors.
		if not preserve_defeat:
			target.call("set_duel_mode", false)


func set_arena_variant(value: String) -> void:
	var selected := COMPACT_ARENAS.sanitize(value)
	if is_instance_valid(network_match):
		selected = "classic"
	if selected != arena_variant:
		_set_repair_kits_active(false)
		if _arena_hazards != null:
			_arena_hazards.call("stop_round")
		if is_instance_valid(_test_arena) and _test_arena.get_parent() == self:
			for surface in _test_arena.get("surfaces"):
				player.remove_collision_exception_with(surface)
			_set_arena_branch_active(_test_arena, false)
			remove_child(_test_arena)
		if is_instance_valid(_compact_stage):
			var old_platform := _compact_stage.get_node_or_null("GyrePlatform")
			if old_platform != null:
				for surface in old_platform.get("surfaces"):
					player.remove_collision_exception_with(surface)
			remove_child(_compact_stage)
			_compact_stage.queue_free()
			_compact_stage = null
		if _arena_hazards != _classic_hazards and is_instance_valid(_arena_hazards):
			remove_child(_arena_hazards)
			_arena_hazards.queue_free()
		remove_meta("arena_floor_rid")
		remove_meta("arena_outline")
		arena_variant = selected
		var custom := COMPACT_ARENAS.is_compact(selected) or selected == "test"
		for node in _classic_arena_roots:
			_set_arena_branch_active(node, true)
			if custom and selected != "test" and node.get_parent() == self:
				remove_child(node)
			elif (not custom or selected == "test") and node.get_parent() == null:
				add_child(node)
		if COMPACT_ARENAS.is_compact(selected):
			if _classic_hazards.get_parent() == self:
				remove_child(_classic_hazards)
			_compact_stage = COMPACT_STAGE.new()
			_compact_stage.set("arena_id", selected)
			add_child(_compact_stage)
			var platform := _compact_stage.get_node_or_null("TideglassArena" if selected == "tideglass" else "GyrePlatform")
			if platform != null:
				for surface in platform.get("surfaces"):
					player.add_collision_exception_with(surface)
			_arena_blockers.clear()
			for body in _compact_stage.find_children("*", "StaticBody3D", true, false):
				if body.is_in_group("arena_solid"):
					_arena_blockers.append(body)
			var compact_floor := _compact_stage.get_node("CompactFloor") as StaticBody3D
			set_meta("arena_floor_rid", compact_floor.get_rid())
			set_meta("arena_outline", COMPACT_ARENAS.footprint(selected))
			_arena_hazards = HELIOSTAT_MECHANISMS.new() if selected == "heliostat" else (OPEN_MECHANISMS.new() if COMPACT_ARENAS.definition(selected).get("mechanism", "") == "open" else COMPACT_MECHANISMS.new())
			_arena_hazards.set("arena_id", selected)
			_arena_hazards.name = "ArenaHazards"
			add_child(_arena_hazards)
			_arena_hazards.call("configure", player, target)
			if _arena_hazards.has_method("set_stage"):
				_arena_hazards.call("set_stage", _compact_stage)
		else:
			if _classic_hazards.get_parent() == null:
				add_child(_classic_hazards)
			_arena_hazards = _classic_hazards
			if selected == "test":
				if not is_instance_valid(_test_arena):
					_test_arena = TEST_ARENA.new()
					_test_arena.name = "TestArena"
					add_child(_test_arena)
					_test_arena.call("configure", _classic_arena_nodes, self)
				elif _test_arena.get_parent() == null:
					add_child(_test_arena)
				_set_arena_branch_active(_test_arena, true)
				_arena_blockers.clear()
				for body in _test_arena.find_children("*", "StaticBody3D", true, false):
					if body.get_meta("blocks_navigation", false):
						_arena_blockers.append(body)
				_arena_blockers.append_array(_test_arena.get("surfaces"))
				for surface in _test_arena.get("surfaces"):
					player.add_collision_exception_with(surface)
				# The older test-map API keeps the inactive courtyard accessible.
				for node in _classic_arena_roots:
					_set_arena_branch_active(node, false)
			else:
				_arena_blockers.assign(_classic_arena_blockers)
		_apply_arena_atmosphere()
		set_meta("arena_half_size", get_arena_half_size())
		if sight_tracker != null:
			sight_tracker.call("configure", self, player, target)
	if _arena_hazards != null:
		_arena_hazards.call("set_enabled", (arena_variant == "hazards" or COMPACT_ARENAS.is_compact(arena_variant)) and not is_instance_valid(network_match))
	if COMPACT_ARENAS.is_compact(arena_variant):
		set_menu_showcase_enabled(false)
		var spawns := get_arena_spawns()
		player.position = spawns[0]
		target.position = spawns[1]
	ARENA_TRAVERSAL.snap(player)
	ARENA_TRAVERSAL.snap(target)
	reset_round_camera()


func get_arena_half_size() -> Vector2:
	if arena_variant == "test":
		return TEST_ARENA.MAP_HALF_EXTENTS
	return COMPACT_ARENAS.definition(arena_variant).half_size if COMPACT_ARENAS.is_compact(arena_variant) else Vector2(29, 29)


func get_arena_spawns() -> Array:
	if arena_variant == "test":
		return [Vector3(-3.5, 0, 11.8), Vector3(3.5, 0, -11.8)]
	return COMPACT_ARENAS.definition(arena_variant).spawns if COMPACT_ARENAS.is_compact(arena_variant) else [Vector3(-3.5, 0, 17), Vector3(3.5, 0, 15.5)]


func _apply_arena_atmosphere() -> void:
	var environment: WorldEnvironment
	for child in get_children():
		if child is WorldEnvironment:
			environment = child
			break
	if environment == null:
		return
	var sun := get_node("ArenaKeyLight") as DirectionalLight3D
	if _classic_environment == null:
		_classic_environment = environment.environment.duplicate(true)
		_classic_light_color = sun.light_color
		_classic_light_energy = sun.light_energy
	if not COMPACT_ARENAS.is_compact(arena_variant):
		environment.environment = _classic_environment.duplicate(true)
		sun.light_color = _classic_light_color
		sun.light_energy = _classic_light_energy
		return
	var palette: Array = {
		"heliostat": [Color("#638c9b"), Color("#c2d7df"), Color("#ffe1b2"), 1.12, 0.42],
		"tideglass": [Color("#244e59"), Color("#a3cbc3"), Color("#e2efcd"), 1.10, 0.43],
		"clockwork": [Color("#242339"), Color("#bdbbd8"), Color("#ffe0b9"), 1.14, 0.43],
		"gyre": [Color("#18232c"), Color("#a0bac5"), Color("#ffd0a7"), 1.22, 0.45],
		"resonance": [Color("#202b42"), Color("#b6cedc"), Color("#ffe2dd"), 1.08, 0.43],
	}.get(arena_variant, [Color("#171b1e"), Color("#aab4b7"), Color("#f2d7b5"), 1.08])
	environment.environment.background_color = palette[0]
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.sky = null
	if arena_variant == "heliostat":
		var sky := Sky.new()
		var sky_material := ProceduralSkyMaterial.new()
		sky_material.sky_top_color = Color("#426d91")
		sky_material.sky_horizon_color = Color("#b8d0ce")
		sky_material.ground_horizon_color = Color("#b8d0ce")
		sky_material.ground_bottom_color = Color("#567f96")
		sky_material.sky_curve = 0.45
		sky_material.ground_curve = 0.5
		sky.sky_material = sky_material
		environment.environment.sky = sky
		environment.environment.background_mode = Environment.BG_SKY
	environment.environment.ambient_light_color = palette[1]
	environment.environment.ambient_light_energy = palette[4]
	sun.light_color = palette[2]
	sun.light_energy = palette[3]


func _exit_tree() -> void:
	# Detached classic roots stay available for instant map changes during play.
	for node in _classic_arena_roots:
		if is_instance_valid(node) and node.get_parent() == null:
			node.queue_free()
	if is_instance_valid(_test_arena) and _test_arena.get_parent() == null:
		_test_arena.queue_free()
	if is_instance_valid(_classic_hazards) and _classic_hazards.get_parent() == null:
		_classic_hazards.queue_free()


func _set_arena_branch_active(node: Node, enabled: bool) -> void:
	if node is Node3D:
		if not node.has_meta("arena_visible"):
			node.set_meta("arena_visible", node.visible)
		node.visible = node.get_meta("arena_visible") if enabled else false
	if not node.has_meta("arena_process_mode"):
		node.set_meta("arena_process_mode", node.process_mode)
	node.process_mode = node.get_meta("arena_process_mode") if enabled else Node.PROCESS_MODE_DISABLED
	if node is CollisionObject3D:
		if not node.has_meta("arena_collision_layer"):
			node.set_meta("arena_collision_layer", node.collision_layer)
			node.set_meta("arena_collision_mask", node.collision_mask)
		node.collision_layer = node.get_meta("arena_collision_layer") if enabled else 0
		node.collision_mask = node.get_meta("arena_collision_mask") if enabled else 0
	for group in ["repair_kits", "bush_placeholder"]:
		var key: String = "arena_group_" + str(group)
		if node.is_in_group(group):
			node.set_meta(key, true)
		if node.get_meta(key, false):
			if enabled:
				node.add_to_group(group)
			else:
				node.remove_from_group(group)
	for child in node.get_children():
		_set_arena_branch_active(child, enabled)


func focus_round_winner(player_won: bool) -> void:
	if player_won:
		player.call("show_round_result", true)
	var rig := get_node_or_null("CameraRig")
	var winner: Node3D = player if player_won else target
	if rig != null:
		rig.call("focus_on_winner", winner)
	var readout := winner.get_node_or_null("WorldUIAnchor/PlayerHealthReadout") if player_won else winner.get_node_or_null("TargetHealthReadout")
	if readout != null:
		readout.call("set_cinematic_mode", true)


func reset_round_camera() -> void:
	var rig := get_node_or_null("CameraRig")
	if rig != null and player != null:
		rig.call("set_target", player)
		rig.call("set_follow_offset", Vector3.ZERO, true)
	if player != null:
		var player_world_ui := player.get_node_or_null("WorldUIAnchor") as Node3D
		if player_world_ui != null:
			player_world_ui.visible = true
		var player_readout := player.get_node_or_null("WorldUIAnchor/PlayerHealthReadout")
		if player_readout != null:
			player_readout.call("set_cinematic_mode", false)
	if target != null:
		var target_readout := target.get_node_or_null("TargetHealthReadout")
		if target_readout != null:
			target_readout.visible = true
			target_readout.call("set_cinematic_mode", false)


func resolve_round() -> void:
	if game_flow == null or not duel_active:
		return
	var player_dead := bool(player.call("is_real_dead"))
	var target_dead := bool(target.call("is_real_dead"))
	if not player_dead and player.has_method("get_health"):
		player_dead = float(player.call("get_health")) <= 0.0
	if not target_dead:
		target_dead = float(target.call("get_health")) <= 0.0
	if player_dead or target_dead:
		_set_repair_kits_active(false)
		game_flow.call("resolve_round", player_dead, target_dead)


func _reset_repair_kits(collection_active: bool) -> void:
	for repair_kit in get_tree().get_nodes_in_group("repair_kits"):
		if repair_kit.has_method("reset_for_round"):
			repair_kit.call("reset_for_round", collection_active)


func _set_repair_kits_active(value: bool) -> void:
	for repair_kit in get_tree().get_nodes_in_group("repair_kits"):
		if repair_kit.has_method("set_collection_active"):
			repair_kit.call("set_collection_active", value)


func shift_pause_timers(seconds: float) -> void:
	if seconds <= 0.0:
		return
	if player != null and player.has_method("shift_pause_timers"):
		player.call("shift_pause_timers", seconds)
	if target != null and target.has_method("shift_pause_timers"):
		target.call("shift_pause_timers", seconds)


func clear_transient_fx() -> void:
	var sfx := get_node_or_null("/root/GameSfx")
	if sfx != null and sfx.has_method("clear"):
		sfx.call("clear")
	var vfx := get_node_or_null("VFXManager")
	if vfx != null:
		vfx.call("clear")
	for node in get_tree().get_nodes_in_group("prototype0_fx_budget"):
		if is_instance_valid(node):
			node.queue_free()
	for node in get_tree().get_nodes_in_group("prototype0_gameplay_projectiles"):
		if is_instance_valid(node):
			node.queue_free()


func _on_player_died() -> void:
	if game_flow != null:
		game_flow.call("on_actor_died", player)


func _on_target_died() -> void:
	if game_flow != null:
		game_flow.call("on_actor_died", target)


func _create_box(node_name: String, position: Vector3, size: Vector3, color: Color, texture: Texture2D = null) -> StaticBody3D:
	return _classic_builder.props.create_box(node_name, position, size, color, texture)


func _material(color: Color, roughness: float = 0.8, emission: Color = Color.BLACK) -> StandardMaterial3D:
	return _classic_builder.props.materials.material(color, roughness, emission)


func _textured_material(color: Color, roughness: float, emission: Color, texture: Texture2D, uv_scale: Vector3 = Vector3.ONE) -> StandardMaterial3D:
	return _classic_builder.props.materials.textured(color, roughness, emission, texture, uv_scale)
