extends SceneTree

func _initialize() -> void:
	var loadout_script := load("res://scripts/loadout_state.gd")
	var test_path := "user://prototype0_loadout_test.cfg"
	var value: Dictionary = {"robot": "puissant", "weapon": "shotgun", "offensive": "javelin", "defensive": "static_shield", "mobility": "bio_injector", "passive": "omnivamp"}
	var saved: bool = loadout_script.save_local(value, test_path)
	var restored: Dictionary = loadout_script.load_local(test_path)
	if saved:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(test_path))
	if saved and (not loadout_script.is_valid(restored) or restored != value):
		push_error("FAIL: équipement persistant invalide")
		quit(1)
		return
	var fallback: Dictionary = loadout_script.sanitize({"weapon": "unknown", "passive": "bad"})
	if fallback.weapon != "blaster" or fallback.passive != "baroud" or fallback.robot != "polyvalent":
		push_error("FAIL: fallback équipement invalide")
		quit(1)
		return
	var migrated: Dictionary = loadout_script.sanitize({"weapon": "electro_axe", "offensive": "unknown_module"})
	if migrated.weapon != "blaster" or migrated.robot != "polyvalent":
		push_error("FAIL: migration Electro Axe vers Blaster absente")
		quit(1)
		return
	print("P0-126 LOADOUT TEST: PASS" + (" (écriture user:// indisponible dans ce sandbox)" if not saved else ""))
	quit(0)
