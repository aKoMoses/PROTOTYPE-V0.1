extends RefCounted

## Named builds and the active combat loadout are committed together.
const LOADOUT := preload("res://scripts/loadout_state.gd")
const SAVE_PATH := "user://prototype0_builds.cfg"


static func normalize_name(value: String) -> String:
	var result := value.strip_edges().replace("\n", " ").replace("\r", " ").left(28)
	return result if not result.is_empty() else "DUELLISTE"


static func load_local(path: String = SAVE_PATH, legacy_path: String = LOADOUT.SAVE_PATH) -> Dictionary:
	var config := ConfigFile.new()
	var builds: Array[Dictionary] = []
	var active := "build_1"
	var next_id := 2
	if config.load(path) == OK:
		active = str(config.get_value("garage", "active", active))
		next_id = maxi(2, int(config.get_value("garage", "next_id", next_id)))
		var raw: Variant = config.get_value("garage", "builds", [])
		if raw is Array:
			var ids: Array[String] = []
			for entry in raw:
				if not entry is Dictionary or not entry.get("loadout") is Dictionary:
					continue
				var id := str(entry.get("id", ""))
				if id.is_empty() or ids.has(id):
					continue
				ids.append(id)
				builds.append({"id": id, "name": normalize_name(str(entry.get("name", "DUELLISTE"))), "loadout": LOADOUT.sanitize(entry.loadout)})
	if builds.is_empty():
		builds.append({"id": "build_1", "name": "DUELLISTE", "loadout": LOADOUT.load_local(legacy_path)})
	if not builds.any(func(entry: Dictionary) -> bool: return entry.id == active):
		active = builds[0].id
	return {"active": active, "next_id": next_id, "builds": builds}


static func with_build(library: Dictionary, id: String, title: String, equipment: Dictionary) -> Dictionary:
	var result: Dictionary = library.duplicate(true)
	if id.is_empty():
		id = "build_%d" % int(result.next_id)
		while result.builds.any(func(existing: Dictionary) -> bool: return str(existing.id) == id):
			result.next_id = int(result.next_id) + 1
			id = "build_%d" % int(result.next_id)
		result.next_id = int(result.next_id) + 1
	var entry := {"id": id, "name": normalize_name(title), "loadout": LOADOUT.sanitize(equipment)}
	var replaced := false
	for index in result.builds.size():
		if str(result.builds[index].id) == id:
			result.builds[index] = entry
			replaced = true
			break
	if not replaced:
		result.builds.append(entry)
	result.active = id
	return result


static func save_local(library: Dictionary, path: String = SAVE_PATH, legacy_path: String = LOADOUT.SAVE_PATH) -> bool:
	var active: Dictionary = {}
	for entry in library.builds:
		if str(entry.id) == str(library.active):
			active = entry.loadout
	if active.is_empty():
		return false
	var config := ConfigFile.new()
	config.set_value("garage", "active", library.active)
	config.set_value("garage", "next_id", library.next_id)
	config.set_value("garage", "builds", library.builds)
	var temporary := path + ".tmp"
	if config.save(temporary) != OK:
		return false
	var legacy_existed := FileAccess.file_exists(legacy_path)
	var legacy_bytes := FileAccess.get_file_as_bytes(legacy_path) if legacy_existed else PackedByteArray()
	if not LOADOUT.save_local(active, legacy_path):
		DirAccess.remove_absolute(temporary)
		return false
	var backup := path + ".previous"
	var existed := FileAccess.file_exists(path)
	if existed and DirAccess.rename_absolute(path, backup) != OK:
		_restore(legacy_path, legacy_existed, legacy_bytes)
		DirAccess.remove_absolute(temporary)
		return false
	if DirAccess.rename_absolute(temporary, path) != OK:
		if existed:
			DirAccess.rename_absolute(backup, path)
		_restore(legacy_path, legacy_existed, legacy_bytes)
		return false
	if existed:
		DirAccess.remove_absolute(backup)
	return true


static func _restore(path: String, existed: bool, bytes: PackedByteArray) -> void:
	if not existed:
		DirAccess.remove_absolute(path)
		return
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file != null:
		file.store_buffer(bytes)
