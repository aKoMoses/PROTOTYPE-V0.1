class_name PrototypeHudLayout
extends RefCounted

## Stable HUD identities and versioned, local layouts. Coordinates are offsets
## from a safe-area anchor, measured in safe-area heights (not screen pixels).
const VERSION := 1
const SAVE_PATH := "user://prototype0_hud_layout.json"
const BACKUP_PATH := "user://prototype0_hud_layout.backup.json"
const TEMP_PATH := "user://prototype0_hud_layout.tmp.json"
const TOUCH_IDS := ["move", "aim", "offensive_button", "defensive_button", "mobility_button", "weapon_button"]
const MODULE_IDS := ["offensive_slot", "defensive_slot", "mobility_slot"]

static func family() -> String:
	return "mobile" if OS.has_feature("mobile") or DisplayServer.is_touchscreen_available() else "desktop"

static func names() -> Dictionary:
	return {
		"move": "Déplacement", "aim": "Visée et tir",
		"offensive_button": "Action offensive", "defensive_button": "Action défensive",
		"mobility_button": "Mobilité", "weapon_button": "Changer d'arme",
		"match_summary": "Score et manche", "pause": "Pause",
		"player_vitals": "Vie et arme",
		"spell_bar": "Barre de modules", "offensive_slot": "Module offensif",
		"defensive_slot": "Module défensif", "mobility_slot": "Module mobilité",
		"wave": "Vague", "arrival": "Annonce de vague",
		"training_status": "État de l'entraînement", "training_meter": "Mesures de tir",
		"training_meter_chip": "Mesures réduites",
		"training_reset": "Nouvel essai", "training_menu": "Menu entraînement",
	}

static func is_required(identifier: String) -> bool:
	return identifier in ["pause", "training_menu"]

static func size_limits(identifier: String) -> Vector2:
	if identifier in ["move", "aim"]:
		return Vector2(0.70, 1.65)
	if identifier.ends_with("_button"):
		return Vector2(0.75, 1.70)
	if identifier.ends_with("_slot") or identifier == "spell_bar":
		return Vector2(0.70, 1.45)
	return Vector2(0.65, 1.60)

static func _item(ax: float, ay: float, dx: float, dy: float) -> Dictionary:
	return {"a": [ax, ay], "d": [dx, dy], "s": 1.0, "o": 1.0, "v": true, "l": false, "z": 0}

static func standard() -> Dictionary:
	return {
		"move": _item(0.0, 1.0, 0.156, -0.156),
		"aim": _item(1.0, 1.0, -0.156, -0.156),
		"offensive_button": _item(0.0, 1.0, 0.139, -0.382),
		"defensive_button": _item(0.0, 1.0, 0.296, -0.335),
		"mobility_button": _item(0.0, 1.0, 0.380, -0.197),
		"weapon_button": _item(1.0, 0.0, -0.067, 0.078),
		"match_summary": _item(0.5, 0.0, 0.0, 0.058),
		"pause": _item(1.0, 0.0, -0.078, 0.056),
		"player_vitals": _item(0.0, 0.0, 0.22, 0.205),
		"spell_bar": _item(0.5, 1.0, 0.0, -0.064),
		"offensive_slot": _item(0.0, 0.0, 0.0, 0.0),
		"defensive_slot": _item(0.0, 0.0, 0.0, 0.0),
		"mobility_slot": _item(0.0, 0.0, 0.0, 0.0),
		"wave": _item(0.0, 0.0, 0.156, 0.046),
		"arrival": _item(0.5, 0.0, 0.0, 0.264),
		"training_status": _item(0.0, 0.0, 0.55, 0.03),
		"training_meter": _item(1.0, 0.0, -0.24, 0.22),
		"training_meter_chip": _item(1.0, 0.0, -0.17, 0.12),
		"training_reset": _item(1.0, 0.0, -0.60, 0.03),
		"training_menu": _item(1.0, 0.0, -0.39, 0.03),
	}

static func left_handed() -> Dictionary:
	var result := standard()
	for identifier in TOUCH_IDS:
		var entry: Dictionary = result[identifier]
		entry["a"][0] = 1.0 - float(entry["a"][0])
		entry["d"][0] = -float(entry["d"][0])
	return result

static func sanitize(raw: Variant) -> Dictionary:
	var result := standard()
	if not raw is Dictionary:
		return result
	for identifier in result.keys():
		if not raw.has(identifier) or not raw[identifier] is Dictionary:
			continue
		var input: Dictionary = raw[identifier]
		var item: Dictionary = result[identifier]
		for key in ["a", "d"]:
			if input.has(key) and input[key] is Array and input[key].size() == 2:
				var pair: Array = input[key]
				if (pair[0] is float or pair[0] is int) and (pair[1] is float or pair[1] is int):
					var limit := 1.0 if key == "a" else 3.0
					item[key] = [clampf(float(pair[0]), -limit if key == "d" else 0.0, limit), clampf(float(pair[1]), -limit if key == "d" else 0.0, limit)]
		if input.get("s") is float or input.get("s") is int:
			var limits := size_limits(identifier)
			item.s = clampf(float(input.s), limits.x, limits.y)
		if input.get("o") is float or input.get("o") is int:
			item.o = clampf(float(input.o), 0.35, 1.0)
		if input.get("v") is bool and not is_required(identifier):
			item.v = input.v
		if input.get("l") is bool:
			item.l = input.l
		if input.get("z") is int:
			item.z = clampi(input.z, -50, 50)
		result[identifier] = item
	# Keep records for temporarily unavailable widgets. They become active again
	# when a later build registers the same stable ID.
	var retained := 0
	for identifier in raw.keys():
		if result.has(identifier) or not identifier is String or not raw[identifier] is Dictionary:
			continue
		result[identifier] = raw[identifier].duplicate(true)
		retained += 1
		if retained >= 32:
			break
	return result

static func safe_rect(viewport: Viewport) -> Rect2:
	var rect := Rect2(Vector2.ZERO, viewport.get_visible_rect().size)
	var display_safe := DisplayServer.get_display_safe_area()
	var window_size := DisplayServer.window_get_size()
	if display_safe.size.x > 0 and display_safe.size.y > 0 and window_size.x > 0 and window_size.y > 0:
		var scaled := Rect2(Vector2(display_safe.position) * rect.size / Vector2(window_size), Vector2(display_safe.size) * rect.size / Vector2(window_size))
		rect = rect.intersection(scaled)
	var inset := maxf(12.0, rect.size.y * 0.025)
	return rect.grow(-inset)

static func center(item: Dictionary, safe: Rect2) -> Vector2:
	var anchor: Array = item.a
	var offset: Array = item.d
	return safe.position + Vector2(float(anchor[0]) * safe.size.x, float(anchor[1]) * safe.size.y) + Vector2(float(offset[0]), float(offset[1])) * safe.size.y

static func set_center(item: Dictionary, desired: Vector2, safe: Rect2, extent: Vector2) -> void:
	var half := Vector2(minf(extent.x * 0.5, safe.size.x * 0.5), minf(extent.y * 0.5, safe.size.y * 0.5))
	var pos := Vector2(clampf(desired.x, safe.position.x + half.x, safe.end.x - half.x), clampf(desired.y, safe.position.y + half.y, safe.end.y - half.y))
	var anchor: Array = item.a
	item.d = [(pos.x - safe.position.x - float(anchor[0]) * safe.size.x) / safe.size.y, (pos.y - safe.position.y - float(anchor[1]) * safe.size.y) / safe.size.y]

static func load_all() -> Dictionary:
	return load_from_paths(SAVE_PATH, BACKUP_PATH)

static func load_from_paths(primary: String, backup: String) -> Dictionary:
	for path in [primary, backup]:
		if not FileAccess.file_exists(path):
			continue
		var parser := JSON.new()
		if parser.parse(FileAccess.get_file_as_string(path)) != OK:
			continue
		var parsed: Variant = parser.data
		if not parsed is Dictionary:
			continue
		var version: Variant = parsed.get("version")
		if not (version is int or version is float):
			continue
		if int(version) == 0 and parsed.get("layout") is Dictionary:
			return {"version": VERSION, "families": {"mobile": {"saved": sanitize(parsed.layout)}}}
		if int(version) == VERSION and parsed.get("families") is Dictionary:
			var families := {}
			for input_family in ["mobile", "desktop"]:
				var raw_record: Variant = parsed.families.get(input_family, {})
				if not raw_record is Dictionary:
					continue
				var record := {"saved": sanitize(raw_record.get("saved", {}))}
				for slot in ["personal_1", "personal_2"]:
					if raw_record.get(slot) is Dictionary:
						record[slot] = sanitize(raw_record[slot])
				var active_slot: Variant = raw_record.get("active_slot", "standard")
				record["active_slot"] = active_slot if active_slot in ["standard", "gaucher", "personal_1", "personal_2"] else "standard"
				families[input_family] = record
			return {"version": VERSION, "families": families}
	return {"version": VERSION, "families": {}}

static func load_active(input_family: String = family()) -> Dictionary:
	var all := load_all()
	var families: Dictionary = all.families
	var record: Dictionary = families.get(input_family, {})
	return sanitize(record.get("saved", {}))

static func save_active(layout: Dictionary, input_family: String = family(), slot: String = "") -> bool:
	var all := load_all()
	var families: Dictionary = all.families
	var record: Dictionary = families.get(input_family, {})
	var clean := sanitize(layout)
	if slot in ["personal_1", "personal_2"]:
		record[slot] = clean.duplicate(true)
		record["active_slot"] = slot
	else:
		record["active_slot"] = "gaucher" if slot == "gaucher" else "standard"
	record["saved"] = clean
	families[input_family] = record
	all["families"] = families
	return save_document(all, SAVE_PATH, BACKUP_PATH, TEMP_PATH)

static func save_document(all: Dictionary, primary: String, backup: String, temporary: String) -> bool:
	var text := JSON.stringify(all)
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(text)
	file.flush()
	file.close()
	var temp_absolute := ProjectSettings.globalize_path(temporary)
	var active_absolute := ProjectSettings.globalize_path(primary)
	var backup_absolute := ProjectSettings.globalize_path(backup)
	if FileAccess.file_exists(primary):
		var previous := JSON.new()
		if previous.parse(FileAccess.get_file_as_string(primary)) == OK and previous.data is Dictionary and (previous.data.get("version") is float or previous.data.get("version") is int) and int(previous.data.version) == VERSION:
			if DirAccess.copy_absolute(active_absolute, backup_absolute) != OK:
				return false
		if DirAccess.remove_absolute(active_absolute) != OK:
			return false
	return DirAccess.rename_absolute(temp_absolute, active_absolute) == OK

static func preset(name: String, input_family: String = family()) -> Dictionary:
	if name == "gaucher":
		return left_handed()
	if name in ["personal_1", "personal_2"]:
		var families: Dictionary = load_all().families
		var record: Dictionary = families.get(input_family, {})
		return sanitize(record.get(name, standard()))
	return standard()
