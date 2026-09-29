extends "res://scripts/target_dummy.gd"

const TRAINING_DATA := preload("res://scripts/combat_data.gd")

var training_kind := "fixed"
var training_size := 1.0
var training_origin := Vector3.ZERO
var training_clock := 0.0

func _ready() -> void:
	super._ready()
	scale = Vector3.ONE * training_size
	if training_size > 1.0:
		var readout := get_node_or_null("TargetHealthReadout") as Node3D
		if readout != null:
			readout.scale = Vector3.ONE / training_size
	training_origin = position
	if training_kind == "shooter":
		var bot := get_node_or_null("TrainingBot")
		if bot != null:
			bot.training_stationary = true
			bot.training_attack_interval = 1.5
			bot.training_attack_damage = float(TRAINING_DATA.WEAPON_DEFINITIONS["blaster"]["damage"])
		set_training_bot_enabled(true)

func _process(delta: float) -> void:
	super._process(delta)
	if training_kind == "moving" and get_health() > 0.0 and not is_action_locked():
		training_clock += delta
		position.x = training_origin.x + sin(training_clock * 1.25) * 4.0

func get_training_hit_radius() -> float:
	return 0.78 * training_size

func reset_training_position() -> void:
	training_clock = 0.0
	position = training_origin
	reset_combat_state()
