extends SceneTree

const BUILDS := preload("res://scripts/bot_build_presets.gd")
const LOADOUT := preload("res://scripts/loadout_state.gd")
const COMBAT_DATA := preload("res://scripts/combat_data.gd")
# These player modules have no AI activation/destination policy yet.
const PLAYER_ONLY_MODULES := ["eclipse", "projector"]
var _failures: Array[String] = []
var _integration_completed := false


func _initialize() -> void:
	_test_draws()
	if not OS.get_cmdline_user_args().has("--catalog-only"):
		await _test_round_integration()
		if not _integration_completed:
			_failures.append("round integration aborted before completing its assertions")
	if _failures.is_empty():
		print("BOT BUILD PRESETS TEST: PASS")
		quit(0)
	else:
		for failure in _failures:
			push_error("FAIL: " + failure)
		quit(1)


func _test_draws() -> void:
	var first := BUILDS.new()
	var replay := BUILDS.new()
	first.set_seed(984761)
	replay.set_seed(984761)
	var previous_id := ""
	var equipment_seen: Dictionary = {}
	var varied_loadouts: Dictionary = {}
	for _bag_number in range(64):
		var ids: Dictionary = {}
		for _entry in range(BUILDS.PRESETS.size()):
			var preset := first.next_preset()
			if preset != replay.next_preset():
				_failures.append("seed does not reproduce opponent choices")
			if previous_id == str(preset.id) or ids.has(str(preset.id)):
				_failures.append("archetype repeated before the shuffled bag was exhausted")
			previous_id = str(preset.id)
			ids[preset.id] = true
			if not LOADOUT.is_valid(preset.loadout):
				_failures.append("unsupported equipment in %s" % preset.id)
			if str(preset.loadout.robot) != "polyvalent":
				_failures.append("preset changed unsupported bot chassis statistics")
			for slot in ["weapon", "offensive", "defensive", "mobility", "passive"]:
				equipment_seen[str(preset.loadout[slot])] = true
			var personality: Dictionary = preset.personality
			for trait_name in ["aggression", "caution", "flank_bias", "heal_threshold"]:
				if float(personality[trait_name]) < 0.0 or float(personality[trait_name]) > 1.0:
					_failures.append("personality ratio outside normal limits")
			var weapon_range: float = COMBAT_DATA.WEAPON_DEFINITIONS[preset.loadout.weapon].max_range
			if float(personality.ideal_range) >= weapon_range or float(personality.ideal_range) < 1.0:
				_failures.append("preferred distance outside weapon reach")
			if float(personality.strafe_period) < 0.5:
				_failures.append("unreadable strafe cadence")
			var equipment_key := "%s:%s:%s:%s" % [preset.id, preset.loadout.defensive, preset.loadout.mobility, preset.loadout.passive]
			varied_loadouts[equipment_key] = true
	for weapon_id in COMBAT_DATA.WEAPON_DEFINITIONS:
		if not equipment_seen.has(weapon_id):
			_failures.append("weapon missing from generated opponents: %s" % weapon_id)
	for module_id in COMBAT_DATA.MODULE_DEFINITIONS:
		if module_id in PLAYER_ONLY_MODULES:
			if equipment_seen.has(module_id):
				_failures.append("opponent drew a module without AI support: %s" % module_id)
			continue
		if not equipment_seen.has(module_id):
			_failures.append("module missing from generated opponents: %s" % module_id)
	if varied_loadouts.size() <= BUILDS.PRESETS.size():
		_failures.append("utility slots never generated any coherent variation")
	var detached := BUILDS.definitions()
	detached[0].name = "changed"
	if str(BUILDS.definitions()[0].name) == "changed":
		_failures.append("external metadata mutation changed catalog definitions")


func _test_round_integration() -> void:
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	await process_frame
	scene.call("set_menu_mode", false)
	scene.call("set_bot_build_seed", 91834)
	var flow: Node = scene.get_node_or_null("Interface")
	var target: Node = scene.get_node_or_null("TargetDummy")
	if flow == null or target == null or target.get_node_or_null("TrainingBot") == null:
		_failures.append("round actors failed to initialise")
		scene.queue_free()
		await process_frame
		return
	flow.set("match_id", 1)
	flow.set("round_number", 1)
	scene.call("prepare_round", LOADOUT.defaults())
	var initial: Dictionary = scene.call("get_current_bot_build")
	scene.call("prepare_round", LOADOUT.defaults())
	if initial != scene.call("get_current_bot_build"):
		_failures.append("countdown preparation redrew the same round")
	if not target.has_meta("bot_personality") or not target.has_meta("bot_build_name"):
		_failures.append("bot personality / display identity missing from target")
	if target.get_meta("bot_personality", {}) != initial.personality:
		_failures.append("target received another preset's personality")
	var identity := target.get_node_or_null("TargetHealthReadout/HealthBarViewport/HealthBarUI/ActorName") as Label
	if identity == null or identity.text != str(initial.name):
		_failures.append("generated opponent identity is absent from its health readout")
	var equipped: Dictionary = target.call("get_duel_loadout")
	for slot in ["weapon", "offensive", "defensive", "mobility", "passive"]:
		if str(equipped.get(slot, "")) != str(initial.loadout[slot]):
			_failures.append("round did not equip generated %s" % slot)
	if not is_equal_approx(float(target.call("get_max_health")), COMBAT_DATA.MAX_HEALTH):
		_failures.append("generated loadout changed base health")
	flow.set("round_number", 2)
	scene.call("prepare_round", LOADOUT.defaults())
	var second: Dictionary = scene.call("get_current_bot_build")
	if second != initial:
		_failures.append("next round changed the opponent before the match ended")
	flow.set("match_id", 2)
	flow.set("round_number", 1)
	scene.call("prepare_round", LOADOUT.defaults())
	var restarted: Dictionary = scene.call("get_current_bot_build")
	if str(restarted.id) == str(second.id):
		_failures.append("new match repeated the previous round's archetype")
	scene.call("stop_duel")
	_integration_completed = true
	scene.queue_free()
	await process_frame
