extends RefCounted

const RECORDS_PATH := "user://survival_records.json"
const LABELS := {"thermal": "Détonation thermique", "relay": "Relais électrique", "double": "Double détente", "trail": "Sillage incandescent", "javelin_splash": "Javelin · explosion", "blaster_pierce": "Blaster · perforation", "drone_chain": "Drone · rebond", "pyro_trail": "Pyro Boots · traînée", "magnetic_shock": "Champ magnétique", "bio_pulse": "Bio Injector · onde", "static_pulse": "Static Shield · onde", "baroud_pulse": "Baroud · onde", "wave_reward": "Réparation de palier", "repair_pickup": "Réparation ramassée", "omnivamp_kill": "Omnivamp · élimination"}
var elapsed := 0.0
var kills := 0
var damage: Dictionary = {}
var healing: Dictionary = {}
var received := 0.0
var frozen := false

func record_damage(amount: float, source: String, attack: String) -> void:
	if frozen or not source.begins_with("player") or amount <= 0:
		return
	var category := source.trim_prefix("player:") if source.begins_with("player:") else attack.get_slice(":", 0)
	if category == "":
		category = "Autres"
	damage[category] = float(damage.get(category, 0.0)) + amount

func record_heal(amount: float, source: String) -> void:
	if not frozen:
		healing[source] = float(healing.get(source, 0.0)) + amount

func record_received(amount: float, _source: String, _attack: String) -> void:
	if not frozen:
		received += amount

func snapshot(won: bool, wave: int, build: Dictionary) -> Dictionary:
	frozen = true
	return {"won": won, "wave": wave, "completed_waves": wave if won else maxi(0, wave - 1), "elapsed": elapsed, "kills": kills, "damage": damage.duplicate(), "healing": healing.duplicate(), "received": received, "build": build.duplicate(true)}

static func read_records(path: String = RECORDS_PATH) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}

static func save_records(records: Dictionary, path: String = RECORDS_PATH) -> Error:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify(records, "\t"))
	return file.get_error()

static func label_for(id: String) -> String:
	var aspects := {"rail": "Lance plasma", "arc": "Arc électrique", "heavy_slug": "Briseur · projectile lourd", "battering_ram": "Bélier · onde frontale", "hunter": "Drone chasseur", "sentry": "Drone sentinelle", "javelin_recall": "Javelin · rappel", "shield_counter": "Bouclier · riposte", "magnetic_discharge": "Condensateur · décharge", "metabolism": "Métabolisme", "harvest": "Moisson vitale", "baroud_rescue": "Baroud · sauvetage"}
	return aspects.get(id, LABELS.get(id, preload("res://scripts/loadout_state.gd").display_name(id)))
