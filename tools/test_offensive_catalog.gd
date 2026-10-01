extends SceneTree

const LOADOUT := preload("res://scripts/loadout_state.gd")
const DATA := preload("res://scripts/combat_data.gd")
const PROGRESSION := preload("res://scripts/survival_progression.gd")
const ASPECTS := preload("res://scripts/survival_aspects.gd")
const SYNERGIES := preload("res://scripts/survival_synergies.gd")
const PRESETS := preload("res://scripts/bot_build_presets.gd")
const ICONS := preload("res://scripts/equipment_icons.gd")
var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, description: String) -> void:
	if not value:
		failures.append(description)

func _run() -> void:
	var retired := "modulo" + "_drone"
	var expected: Array = LOADOUT.OFFENSIVE
	check(not expected.has(retired), "catalogue offensif sans module retiré")
	for retained in ["javelin", "fulguro_punch", "pelto_smash"]:
		check(expected.has(retained), "module conservé : " + retained)
	check(not DATA.MODULE_DEFINITIONS.has(retired), "module retiré des données de combat")
	check(not ICONS.SOURCES.has(retired) and not ICONS.REGIONS.has(retired), "aucune icône du module retiré")
	var previous := LOADOUT.defaults()
	previous.offensive = retired
	check(LOADOUT.sanitize(previous).offensive == "javelin", "ancienne configuration remplacée par Javelin")
	var config := ConfigFile.new()
	config.set_value("loadout", "offensive", retired)
	var save_path := "user://test_offensive_catalog.cfg"
	check(config.save(save_path) == OK, "ancienne sauvegarde créée pour le test")
	check(LOADOUT.load_local(save_path).offensive == "javelin", "ancienne sauvegarde chargeable avec Javelin")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path))
	for preset in PRESETS.PRESETS:
		check(preset.offensive in expected, "build bot valide : " + str(preset.id))
	check(not PROGRESSION.CATEGORY_OPTIONS.offensive.has(retired), "récompenses Survie sans module retiré")
	check(not ASPECTS.PATHS.has(retired) and not ASPECTS.DEFINITIONS.has("hunter") and not ASPECTS.DEFINITIONS.has("sentry"), "évolutions du module retirées")
	check(not SYNERGIES.DEFINITIONS.has("relay"), "synergie du module retirée")
	var progression := PROGRESSION.new()
	progression.choose_weapon("blaster")
	for wave in range(1, PROGRESSION.TOTAL_WAVES):
		for reward in progression.reward_choices(wave):
			check(str(reward.id) != retired and str(reward.id) != "relay", "récompense valide vague %d" % wave)
	var scene: Node3D = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	await physics_frame
	var player: Node = scene.get_node("Player")
	player.call("apply_loadout", previous)
	check(player.call("get_offensive_module_id") == "javelin", "joueur équipé avec le remplacement")
	var target: Node = scene.get_node("TargetDummy")
	target.call("set_training_bot_enabled", false)
	target.call("set_duel_loadout", previous)
	check(target.call("get_duel_loadout").offensive == "javelin", "bot équipé avec le remplacement")
	var flow: Node = scene.get_node("Interface")
	flow.call("_open_equipment")
	flow.call("_open_equipment_category", "offensive")
	await process_frame
	var cards: Dictionary = flow.get("_selection_buttons")["offensive"]
	check(cards.size() == expected.size() and not cards.has(retired), "forge affiche seulement les modules conservés")
	for module_id in expected:
		check(cards.has(module_id), "carte disponible : " + module_id)
	player.call("set_gameplay_enabled", true)
	for index in expected.size():
		player.call("_cycle_offensive_module")
		check(player.call("get_offensive_module_id") in expected, "cycle offensif sans ancien module")
	scene.queue_free()
	current_scene = null
	await process_frame
	for failure in failures:
		push_error(failure)
	print("OFFENSIVE CATALOG TEST: %s (%d échecs)" % ["PASS" if failures.is_empty() else "FAIL", failures.size()])
	quit(0 if failures.is_empty() else 1)
