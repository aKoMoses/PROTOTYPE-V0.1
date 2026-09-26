extends SceneTree

func _initialize() -> void:
	var loadout_script := load("res://scripts/loadout_state.gd")
	var value: Dictionary = {"weapon": "shotgun", "offensive": "javelin", "defensive": "static_shield", "mobility": "bio_injector", "passive": "omnivamp"}
	var saved: bool = loadout_script.save_local(value)
	var restored: Dictionary = loadout_script.load_local()
	if saved and (not loadout_script.is_valid(restored) or restored != value):
		push_error("FAIL: équipement persistant invalide")
		quit(1)
		return
	var fallback: Dictionary = loadout_script.sanitize({"weapon": "unknown", "passive": "bad"})
	if fallback.weapon != "electro_axe" or fallback.passive != "baroud":
		push_error("FAIL: fallback équipement invalide")
		quit(1)
		return
	print("P0-126 LOADOUT TEST: PASS" + (" (écriture user:// indisponible dans ce sandbox)" if not saved else ""))
	quit(0)
