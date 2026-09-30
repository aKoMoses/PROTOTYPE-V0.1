extends CharacterBody3D

signal bush_state_changed(in_bush: bool, bush_name: String)
signal died
signal effective_damage_taken(amount: float, source_id: String, attack_id: String)

var _external_damage_pending := false
var _received_attack_ids: Dictionary = {}

const ROBOT_CREAM_TEXTURE: Texture2D = preload("res://art/metal_cream.svg")
const ROBOT_RUST_TEXTURE: Texture2D = preload("res://art/metal_rust.svg")
const ROBOT_STEEL_TEXTURE: Texture2D = preload("res://art/steel_dark.svg")
const HEAVY_BLASTER_MODEL_PATH := "res://art/player_heavy_blaster.glb"
const SHOTGUN_SCENE := preload("res://scenes/weapons/shotgun.tscn")
const COMBAT_DATA := preload("res://scripts/combat_data.gd")
const LIVE_PROJECTILE := preload("res://scripts/live_projectile.gd")
const COMBAT_STATE := preload("res://scripts/combat_state.gd")
const ACTION_GATE := preload("res://scripts/action_gate.gd")
const PASSIVE_STATE := preload("res://scripts/passive_state.gd")
const VISIBILITY_STATE := preload("res://scripts/visibility_state.gd")
const STATUS_VFX := preload("res://scripts/status_vfx.gd")
const FULGURO := preload("res://scripts/fulguro_punch.gd")
const PELTO_SMASH := preload("res://scripts/pelto_smash.gd")
const FULGURO_RELEASE_SOUND: AudioStream = preload("res://art/audio/blaster-shot-charged-v2.wav")
const BLASTER_CHARGE_SOUND: AudioStream = preload("res://art/audio/blaster-charge-v2.wav")
const BLASTER_CHARGE_HOLD_SOUND: AudioStream = preload("res://art/audio/blaster-charge-hold-v2.wav")
const BLASTER_READY_SOUND: AudioStream = preload("res://art/audio/blaster-ready-v2.wav")
const BLASTER_SHOT_SOUND: AudioStream = preload("res://art/audio/blaster-shot-v2.wav")
const BLASTER_CHARGED_SHOT_SOUND: AudioStream = preload("res://art/audio/blaster-shot-charged-v2.wav")
const SHOTGUN_SHOT_SOUND: AudioStream = preload("res://art/audio/shotgun-shot-a.wav")
const SHOTGUN_CYCLE_SOUND: AudioStream = preload("res://art/audio/shotgun-cycle-a.wav")
const SHOTGUN_RELOAD_SOUND: AudioStream = preload("res://art/audio/shotgun-reload-a.wav")
const PLAYER_BASE_VISUAL_SCALE := 0.88
const HEALTH_READOUT_BASE_HEIGHT := 2.95
const MOUSE_AIM_HEIGHT := 1.35

@export var move_speed := 5.0
var _robot_id := COMBAT_DATA.DEFAULT_ROBOT
@export var attack_interval := 0.55
@export_category("Weapon Handling")
@export_range(0.25, 0.50, 0.01) var aim_hold_time := 0.35
@export_range(0.04, 0.30, 0.01) var aim_raise_time := 0.10
@export_range(0.08, 0.40, 0.01) var aim_lower_time := 0.18
@export_range(0.05, 0.40, 0.01) var mobile_blaster_charge_threshold := 0.20
@export_category("Debug")
@export var enable_direction_debug := false

enum WeaponPoseState { IDLE, LOCOMOTION, AIM, FIRE, AIM_HOLD }
const WEAPON_POSE_NAMES := [&"IDLE", &"LOCOMOTION", &"AIM", &"FIRE", &"AIM_HOLD"]
const SKELETAL_FIRE_POSE_DURATION := 0.17

# Blaster values are loaded from CombatData so future modules can override them
# without changing the controller.
const CRIT_MULTIPLIER := 1.5
const HIT_STOP_NORMAL := 0.045
const HIT_STOP_CRITICAL := 0.085
const LEGACY_COMBO_WINDOW := 1.20
var _blaster_damage := 20.0
var _blaster_max_damage := 50.0
var _blaster_cooldown := 0.45
var _blaster_charge_time := 1.0
var _blaster_max_range := 14.0
var _blaster_projectile_speed := 24.0
var _blaster_charge_slow_multiplier := 0.80
var _blaster_projectile_radius := 0.16
var _blaster_charge_ratio := 0.0
var _blaster_charge_started_at := -1.0
var _blaster_charge_active := false
var _blaster_attack_busy := false
var _blaster_attack_token := 0
var _blaster_action_token := 0
var _blaster_next_attack_ready_at := -10.0
var _attack_hold_last := false

var aim_direction := Vector3(0.0, 0.0, -1.0)
var move_direction := Vector3.ZERO
var weapon_pose_state: WeaponPoseState = WeaponPoseState.IDLE
var _aim_hold_remaining := 0.0
var _fire_pose_remaining := 0.0
var _last_projectile_direction := Vector3.ZERO
var _last_attack_time := -10.0
var _combo_step := 0
var _combo_expires_at := -1.0
var _next_attack_ready_at := -10.0
# Legacy fields remain unused by V0.1 and are kept only for old capture files.
# The active weapon path below is exclusively Blaster or Shotgun.
var _axe_attack_busy := false
var _axe_attack_token := 0
var _axe_action_token := 0
var _axe_attack_step := -1
var _axe_attack_origin := Vector3.ZERO
var _axe_attack_direction := Vector3.FORWARD
var _axe_attack_impact_point := Vector3.ZERO
var _axe_damage: Array = [80.0, 90.0, 150.0]
var _axe_range: Array = [3.0, 2.2, 1.2]
var _axe_preparation: Array = [0.20, 0.20, 0.35]
var _axe_active: Array = [0.10, 0.10, 0.25]
var _axe_recovery: Array = [0.25, 0.30, 0.25]
var _axe_slow_duration: Array = [0.25, 0.25, 0.50]
var _axe_slow_percent := 30.0
var _axe_stun_duration := 0.50
var _axe_estoc_width := 0.65
var _axe_sweep_half_angle := 50.0
var _axe_wave_inner_radius := 1.2
var _axe_wave_outer_radius := 3.5
var _show_debug_hitbox := false
var _weapon_id := "blaster"
var _shotgun_pellet_angles: Array = [-10.0, -6.0, -2.0, 2.0, 6.0, 10.0]
var _shotgun_pellet_speed := 22.0
var _shotgun_max_range := 7.0
var _shotgun_falloff_start := 3.0
var _shotgun_pellet_damage := 20.0
var _shotgun_minimum_damage := 8.0
var _shotgun_hitbox_radius := 0.78
var _shotgun_preparation := 0.10
var _shotgun_recovery := 0.60
var _shotgun_magazine_size := 3
var _shotgun_ammo := 3
var _shotgun_reload_duration := 1.80
var _shotgun_reloading := false
var _shotgun_reload_remaining := 0.0
var _shotgun_reload_token := 0
var _shotgun_attack_busy := false
var _shotgun_attack_token := 0
var _shotgun_action_token := 0
var _shotgun_attack_emitted := false
var _shotgun_attack_origin := Vector3.ZERO
var _shotgun_attack_direction := Vector3.FORWARD
var _module_cooldowns: Dictionary = {}
var _module_token := 0
var _action_gate = ACTION_GATE.new()
var _active_module_action_token := 0
var _active_module_id := ""
var _desktop_attack_rearm_required := false
var _desktop_blaster_tap_buffered := false
var _touch_attack_rearm_required := false
var _drone_preparation := 0.18
var _drone_max_range := 9.0
var _drone_speed := 10.0
var _drone_damage := 100.0
var _drone_burn_duration := 3.5
var _drone_spotted_duration := 5.0
var _drone_cone_half_angle := 20.0
var _drone_collision_radius := 0.15
var _javelin_preparation := 0.12
var _javelin_max_range := 8.0
var _javelin_speed := 20.0
var _javelin_damage := 140.0
var _javelin_mark_duration := 2.5
var _javelin_teleport_distance := 1.4
var _javelin_collision_radius := 0.12
var _javelin_mark_target: Node
var _javelin_launch_token := 0
var _fulguro_preparation := 0.35
var _fulguro_charge_max := 3.0
var _fulguro_range := 2.0
var _fulguro_range_max := 4.0
var _fulguro_width := 0.9
var _fulguro_active_window := 0.10
var _fulguro_recovery := 0.20
var _fulguro_damage := 200.0
var _fulguro_damage_max := 400.0
var _fulguro_wall_damage := 150.0
var _fulguro_wall_damage_max := 250.0
var _fulguro_wall_stun := 0.75
var _fulguro_phase := ""
var _fulguro_elapsed := 0.0
var _fulguro_direction := Vector3.FORWARD
var _fulguro_attack_serial := 0
var _fulguro_hit_resolved := false
var _fulguro_release_requested := false
var _fulguro_release_at := -1.0
var _fulguro_charge_ratio := 0.0
var _fulguro_strike_range := 2.0
var _fulguro_strike_damage := 200.0
var _fulguro_strike_wall_damage := 150.0
var _fulguro_flame_clock := 0.0
var _fulguro_indicator: Node3D
var _fulguro_fist_visual: MeshInstance3D
var _fulguro_fist_core: MeshInstance3D
var _fulguro_flame_tongues: Array[MeshInstance3D] = []
var _fulguro_lane_mesh: BoxMesh
var _fulguro_tip_visual: MeshInstance3D
var _fulguro_flame_light: OmniLight3D
var _fulguro_charge_audio: AudioStreamPlayer
var _fulguro_release_audio: AudioStreamPlayer
var _pelto_preparation := 0.45
var _pelto_impact_duration := 0.10
var _pelto_recovery := 0.25
var _pelto_damage_multiplier := 1.0
var _pelto_phase := ""
var _pelto_elapsed := 0.0
var _pelto_direction := Vector3.FORWARD
var _pelto_attack_serial := 0
var _pelto_indicator: Node3D
var _pelto_lane_mesh: BoxMesh
var _pelto_impact_audio: AudioStreamPlayer
var _pelto_waves: Array[Node] = []
var _pelto_weapon_hidden := false
var _pelto_weapon_restore_serial := 0
var _module_busy := false
var _offensive_module_id := "modulo_drone"
var _defensive_module_id := "magnetic_field"
var _mobility_module_id := "pyro_boots"
var survival_mode := false
var _survival_cooldown_multipliers := {"offensive": 1.0, "defensive": 1.0, "mobility": 1.0}
var _survival_dash_multiplier := 1.0
var _passive_id := "baroud"
var passive_state
var visibility_state
var _current_bush: Node3D
var _current_bush_name := ""
var _bush_transition_clock := 0.0
var _dash_active := false
var _dash_token := 0
var _dash_direction := Vector3.ZERO
var _dash_elapsed := 0.0
var _last_move_direction := Vector3.ZERO
var _fulguro_projection_active := false
var _fulguro_projection_direction := Vector3.ZERO
var _fulguro_projection_distance_remaining := 0.0
var _fulguro_projection_time_remaining := 0.0
var _fulguro_projection_speed := 0.0
var _fulguro_projection_wall_damage := 0.0
var _fulguro_projection_wall_stun := 0.0
var _fulguro_projection_source_id := ""
var _fulguro_projection_attack_id := ""
var _fulguro_wall_stun_active := false
var _pelto_pull_active := false
var _pelto_pull_direction := Vector3.ZERO
var _pelto_pull_distance_remaining := 0.0
var _pelto_pull_time_remaining := 0.0
var _pelto_pull_speed := 0.0
var _defensive_buffer: Dictionary = {}
var _bio_remaining := 0.0
var _bio_speed_multiplier := 1.40
var _bio_attack_speed_multiplier := 1.50
var _bio_other_cooldown_rate := 1.428571
var _magnetic_preparation := 0.15
var _magnetic_distance := 2.0
var _magnetic_width := 4.0
var _magnetic_height := 2.4
var _magnetic_duration := 2.5
var _static_duration := 1.5
var _stasis_remaining := 0.0
var survival_synergies: Node
var survival_evolution_effects: Node
var _magnetic_wall: Area3D
var _survival_evolutions := {"weapon": false, "offensive": false, "defensive": false, "mobility": false, "passive": false}
var _survival_trail_clock := 0.0
var _survival_magnetic_clock := 0.0
var _attack_label: Label3D
var _baroud_bar_bg: MeshInstance3D
var _baroud_bar_fill: MeshInstance3D
var _axe_pivot: Node3D
var _axe_pivot_home := Vector3(0.5, 1.0, -0.55)
var _axe_pivot_home_rotation := Vector3.ZERO
var _blaster_pivot: Node3D
var _blaster_pivot_home_transform := Transform3D.IDENTITY
var _blaster_sway_pivot: Node3D
var _blaster_recoil_pivot: Node3D
var _blaster_muzzle: Node3D
var _blaster_recoil_tweens: Array[Tween] = []
var _blaster_light: OmniLight3D
var _blaster_charge_visual: MeshInstance3D
var _blaster_charge_material: StandardMaterial3D
var _blaster_charge_audio: AudioStreamPlayer
var _blaster_charge_hold_audio: AudioStreamPlayer
var _blaster_ready_audio: AudioStreamPlayer
var _blaster_shot_audio: AudioStreamPlayer
var _blaster_charged_shot_audio: AudioStreamPlayer
var _blaster_charge_audio_fade: Tween
var _blaster_ready_cued := false
var _shotgun_pivot: Node3D
var _shotgun_pivot_home_transform := Transform3D.IDENTITY
var _shotgun_sway_pivot: Node3D
var _shotgun_recoil_pivot: Node3D
var _shotgun_muzzle: Node3D
var _shotgun_recoil_tweens: Array[Tween] = []
var _shotgun_light: OmniLight3D
var _shotgun_shot_audio: AudioStreamPlayer
var _shotgun_cycle_audio: AudioStreamPlayer
var _shotgun_reload_audio: AudioStreamPlayer
var _robot_visuals: Node3D
var _locomotion_nodes: Array[Node3D] = []
var _locomotion_clock := 0.0
var _locomotion_amount := 0.0
var _weapon_motion_clock := 0.0
var _axe_light: OmniLight3D
var _axe_tip: Node3D
var _player_body_material: StandardMaterial3D
var _player_core_material: StandardMaterial3D
const COMBAT_READOUT := preload("res://scripts/combat_readout.gd")
var _health_readout: Node3D
var _visual_rig: PlayerVisualRig
var _round_warmup_active := false
var _world_ui_anchor: Node3D
var _trail_mesh: MeshInstance3D
var _trail_material: StandardMaterial3D
var _trail_points: Array[Vector3] = []
var _trail_elapsed := 0.0
var _trail_duration := 0.0
var _trail_width := 0.1
var _trail_active := false
var combat_state
var _debug_key_latches: Dictionary = {}
var _touch_move_vector := Vector2.ZERO
var _touch_aim_vector := Vector2.ZERO
var _touch_aim_active := false
var _touch_attack_held := false
var _touch_actions: Dictionary = {}
var _touch_fire_active := false
var _touch_fire_started_at := -1.0
var _touch_fire_charge_started := false
var _touch_last_valid_aim_direction := Vector3(0.0, 0.0, -1.0)
var _touch_fire_requests: Array[Dictionary] = []
var _gameplay_enabled := true
var _direction_debug_mesh: MeshInstance3D
var _direction_debug_geometry: ImmediateMesh
var _direction_debug_material: StandardMaterial3D
var _direction_debug_enabled := false
var _direction_debug_label: Label3D
var _status_vfx: Node3D
var _stasis_visual: Node3D
var _static_pulse_token := 0
var training_invulnerable := false
var training_instant_cooldowns := false
var training_unlimited_ammo := false


func _ready() -> void:
	get_node("/root/GamePreferences").bindings_changed.connect(_refresh_control_bindings)
	collision_layer = 4
	collision_mask = 1
	combat_state = COMBAT_STATE.new(COMBAT_DATA.MAX_HEALTH)
	combat_state.health_changed.connect(_on_health_changed)
	combat_state.damage_applied.connect(_on_damage_applied)
	combat_state.healing_applied.connect(_on_healing_applied)
	combat_state.died.connect(_on_state_died)
	passive_state = PASSIVE_STATE.new()
	passive_state.configure(_passive_id)
	visibility_state = VISIBILITY_STATE.new()
	_load_weapon_definitions()
	_build_collision()
	_build_robot()
	_status_vfx = STATUS_VFX.new()
	_status_vfx.name = "StatusVFX"
	add_child(_status_vfx)
	_status_vfx.set("marker_height", 3.30 * COMBAT_DATA.CHARACTER_VISUAL_SCALE)
	_status_vfx.call("configure", self)
	_blaster_charge_audio = AudioStreamPlayer.new()
	_blaster_charge_audio.name = "BlasterChargeAudio"
	_blaster_charge_audio.stream = BLASTER_CHARGE_SOUND
	_blaster_charge_audio.volume_db = -9.0
	add_child(_blaster_charge_audio)
	_blaster_charge_hold_audio = AudioStreamPlayer.new()
	_blaster_charge_hold_audio.name = "BlasterChargeHoldAudio"
	var hold_stream := BLASTER_CHARGE_HOLD_SOUND.duplicate() as AudioStreamWAV
	hold_stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	hold_stream.loop_end = roundi(hold_stream.get_length() * hold_stream.mix_rate)
	_blaster_charge_hold_audio.stream = hold_stream
	_blaster_charge_hold_audio.volume_db = -10.0
	add_child(_blaster_charge_hold_audio)
	_blaster_ready_audio = AudioStreamPlayer.new()
	_blaster_ready_audio.name = "BlasterReadyAudio"
	_blaster_ready_audio.stream = BLASTER_READY_SOUND
	_blaster_ready_audio.volume_db = -4.0
	add_child(_blaster_ready_audio)
	_blaster_shot_audio = AudioStreamPlayer.new()
	_blaster_shot_audio.name = "BlasterShotAudio"
	_blaster_shot_audio.stream = BLASTER_SHOT_SOUND
	_blaster_shot_audio.max_polyphony = 4
	_blaster_shot_audio.volume_db = -8.0
	add_child(_blaster_shot_audio)
	_blaster_charged_shot_audio = AudioStreamPlayer.new()
	_blaster_charged_shot_audio.name = "BlasterChargedShotAudio"
	_blaster_charged_shot_audio.stream = BLASTER_CHARGED_SHOT_SOUND
	_blaster_charged_shot_audio.max_polyphony = 4
	_blaster_charged_shot_audio.volume_db = -7.0
	add_child(_blaster_charged_shot_audio)
	_shotgun_shot_audio = AudioStreamPlayer.new()
	_shotgun_shot_audio.name = "ShotgunShotAudio"
	_shotgun_shot_audio.stream = SHOTGUN_SHOT_SOUND
	_shotgun_shot_audio.volume_db = -7.0
	add_child(_shotgun_shot_audio)
	_shotgun_cycle_audio = AudioStreamPlayer.new()
	_shotgun_cycle_audio.name = "ShotgunCycleAudio"
	_shotgun_cycle_audio.stream = SHOTGUN_CYCLE_SOUND
	_shotgun_cycle_audio.volume_db = -5.0
	add_child(_shotgun_cycle_audio)
	_shotgun_reload_audio = AudioStreamPlayer.new()
	_shotgun_reload_audio.name = "ShotgunReloadAudio"
	_shotgun_reload_audio.stream = SHOTGUN_RELOAD_SOUND
	_shotgun_reload_audio.volume_db = -2.0
	add_child(_shotgun_reload_audio)
	_fulguro_charge_audio = AudioStreamPlayer.new()
	_fulguro_charge_audio.name = "FulguroChargeAudio"
	_fulguro_charge_audio.stream = BLASTER_CHARGE_SOUND
	_fulguro_charge_audio.volume_db = -10.0
	_fulguro_charge_audio.pitch_scale = 1.35
	add_child(_fulguro_charge_audio)
	_fulguro_release_audio = AudioStreamPlayer.new()
	_fulguro_release_audio.name = "FulguroReleaseAudio"
	_fulguro_release_audio.stream = FULGURO_RELEASE_SOUND
	_fulguro_release_audio.volume_db = -5.0
	_fulguro_release_audio.pitch_scale = 0.88
	add_child(_fulguro_release_audio)
	_pelto_impact_audio = AudioStreamPlayer.new()
	_pelto_impact_audio.name = "PeltoImpactAudio"
	_pelto_impact_audio.stream = SHOTGUN_SHOT_SOUND
	_pelto_impact_audio.volume_db = -7.0
	_pelto_impact_audio.pitch_scale = 0.52
	add_child(_pelto_impact_audio)


func _exit_tree() -> void:
	_blaster_attack_token += 1
	_shotgun_attack_token += 1
	_module_token += 1
	_javelin_launch_token += 1
	_static_pulse_token += 1
	_action_gate.reset()


func _load_weapon_definitions() -> void:
	var blaster_definition: Dictionary = COMBAT_DATA.WEAPON_DEFINITIONS.get("blaster", {})
	_blaster_damage = float(blaster_definition.get("damage", _blaster_damage))
	_blaster_max_damage = float(blaster_definition.get("max_damage", _blaster_max_damage))
	_blaster_cooldown = float(blaster_definition.get("cooldown", _blaster_cooldown))
	_blaster_charge_time = float(blaster_definition.get("charge_time", _blaster_charge_time))
	_blaster_max_range = float(blaster_definition.get("max_range", _blaster_max_range))
	_blaster_projectile_speed = float(blaster_definition.get("projectile_speed", _blaster_projectile_speed))
	_blaster_charge_slow_multiplier = float(blaster_definition.get("charge_slow_multiplier", _blaster_charge_slow_multiplier))
	_blaster_projectile_radius = float(blaster_definition.get("projectile_radius", _blaster_projectile_radius))
	var shotgun_definition: Dictionary = COMBAT_DATA.WEAPON_DEFINITIONS.get("shotgun", {})
	_shotgun_pellet_angles = shotgun_definition.get("pellet_angles", _shotgun_pellet_angles)
	_shotgun_pellet_speed = float(shotgun_definition.get("pellet_speed", _shotgun_pellet_speed))
	_shotgun_max_range = float(shotgun_definition.get("max_range", _shotgun_max_range))
	_shotgun_falloff_start = float(shotgun_definition.get("falloff_start", _shotgun_falloff_start))
	_shotgun_pellet_damage = float(shotgun_definition.get("pellet_damage", _shotgun_pellet_damage))
	_shotgun_minimum_damage = float(shotgun_definition.get("minimum_damage", _shotgun_minimum_damage))
	_shotgun_hitbox_radius = float(shotgun_definition.get("hitbox_radius", _shotgun_hitbox_radius))
	_shotgun_preparation = float(shotgun_definition.get("attack_preparation", _shotgun_preparation))
	_shotgun_recovery = float(shotgun_definition.get("attack_recovery", _shotgun_recovery))
	_shotgun_magazine_size = int(shotgun_definition.get("magazine_size", _shotgun_magazine_size))
	_shotgun_ammo = _shotgun_magazine_size
	_shotgun_reload_duration = float(shotgun_definition.get("reload_duration", _shotgun_reload_duration))
	var drone_definition: Dictionary = COMBAT_DATA.MODULE_DEFINITIONS.get("modulo_drone", {})
	_drone_preparation = float(drone_definition.get("preparation", _drone_preparation))
	_drone_max_range = float(drone_definition.get("max_range", _drone_max_range))
	_drone_speed = float(drone_definition.get("speed", _drone_speed))
	_drone_damage = float(drone_definition.get("damage", _drone_damage))
	_drone_burn_duration = float(drone_definition.get("burn_duration", _drone_burn_duration))
	_drone_spotted_duration = float(drone_definition.get("spotted_duration", _drone_spotted_duration))
	_drone_cone_half_angle = float(drone_definition.get("cone_half_angle", _drone_cone_half_angle))
	_drone_collision_radius = float(drone_definition.get("collision_radius", _drone_collision_radius))
	var javelin_definition: Dictionary = COMBAT_DATA.MODULE_DEFINITIONS.get("javelin", {})
	_javelin_preparation = float(javelin_definition.get("preparation", _javelin_preparation))
	_javelin_max_range = float(javelin_definition.get("max_range", _javelin_max_range))
	_javelin_speed = float(javelin_definition.get("speed", _javelin_speed))
	_javelin_damage = float(javelin_definition.get("damage", _javelin_damage))
	_javelin_mark_duration = float(javelin_definition.get("mark_duration", _javelin_mark_duration))
	_javelin_teleport_distance = float(javelin_definition.get("teleport_distance", _javelin_teleport_distance))
	_javelin_collision_radius = float(javelin_definition.get("collision_radius", _javelin_collision_radius))
	var fulguro_definition: Dictionary = COMBAT_DATA.MODULE_DEFINITIONS.get("fulguro_punch", {})
	_fulguro_preparation = float(fulguro_definition.get("charge_min", fulguro_definition.get("preparation", _fulguro_preparation)))
	_fulguro_charge_max = float(fulguro_definition.get("charge_max", _fulguro_charge_max))
	_fulguro_range = float(fulguro_definition.get("range_min", fulguro_definition.get("range", _fulguro_range)))
	_fulguro_range_max = float(fulguro_definition.get("range_max", _fulguro_range_max))
	_fulguro_width = float(fulguro_definition.get("width", _fulguro_width))
	_fulguro_active_window = float(fulguro_definition.get("active_window", _fulguro_active_window))
	_fulguro_recovery = float(fulguro_definition.get("recovery", _fulguro_recovery))
	_fulguro_damage = float(fulguro_definition.get("damage_min", fulguro_definition.get("damage", _fulguro_damage)))
	_fulguro_damage_max = float(fulguro_definition.get("damage_max", _fulguro_damage_max))
	_fulguro_wall_damage = float(fulguro_definition.get("wall_damage_min", fulguro_definition.get("wall_damage", _fulguro_wall_damage)))
	_fulguro_wall_damage_max = float(fulguro_definition.get("wall_damage_max", _fulguro_wall_damage_max))
	_fulguro_wall_stun = float(fulguro_definition.get("wall_stun", _fulguro_wall_stun))
	var pelto_definition: Dictionary = COMBAT_DATA.MODULE_DEFINITIONS.get("pelto_smash", {})
	_pelto_damage_multiplier = 1.0
	_pelto_preparation = float(pelto_definition.get("preparation", _pelto_preparation))
	_pelto_impact_duration = float(pelto_definition.get("impact_duration", _pelto_impact_duration))
	_pelto_recovery = float(pelto_definition.get("recovery", _pelto_recovery))
	var bio_definition: Dictionary = COMBAT_DATA.MODULE_DEFINITIONS.get("bio_injector", {})
	_bio_speed_multiplier = float(bio_definition.get("speed_multiplier", _bio_speed_multiplier))
	_bio_attack_speed_multiplier = float(bio_definition.get("attack_speed_multiplier", _bio_attack_speed_multiplier))
	_bio_other_cooldown_rate = float(bio_definition.get("other_cooldown_rate", _bio_other_cooldown_rate))
	var magnetic_definition: Dictionary = COMBAT_DATA.MODULE_DEFINITIONS.get("magnetic_field", {})
	_magnetic_preparation = float(magnetic_definition.get("preparation", _magnetic_preparation))
	_magnetic_distance = float(magnetic_definition.get("distance", _magnetic_distance))
	_magnetic_width = float(magnetic_definition.get("width", _magnetic_width))
	_magnetic_height = float(magnetic_definition.get("height", _magnetic_height))
	_magnetic_duration = float(magnetic_definition.get("duration", _magnetic_duration))
	var static_definition: Dictionary = COMBAT_DATA.MODULE_DEFINITIONS.get("static_shield", {})
	_static_duration = float(static_definition.get("duration", _static_duration))


func _physics_process(delta: float) -> void:
	if not _gameplay_enabled:
		velocity = Vector3.ZERO
		clear_touch_inputs()
		return
	if visibility_state != null:
		visibility_state.update(delta)
	var baroud_expired: bool = passive_state != null and bool(passive_state.process(delta))
	if baroud_expired:
		_finalize_passive_death()
	_update_baroud_presentation()
	if passive_state != null and passive_state.real_dead:
		velocity = Vector3.ZERO
		return
	var stasis_active := _stasis_remaining > 0.0
	if stasis_active:
		_stasis_remaining = maxf(0.0, _stasis_remaining - delta)
	if combat_state != null:
		combat_state.update(delta, stasis_active)
	if _fulguro_wall_stun_active and (combat_state == null or not combat_state.is_stunned()):
		_fulguro_wall_stun_active = false
	if _status_vfx != null:
		_status_vfx.call("sync", get_active_effect_types())
	_update_module_cooldowns(delta)
	if _survival_evolved("defensive") and _defensive_module_id == "magnetic_field" and _magnetic_wall != null and is_instance_valid(_magnetic_wall):
		_survival_magnetic_clock += delta
		if _survival_magnetic_clock >= 0.8:
			_survival_magnetic_clock = 0.0
			_survival_area_damage(_magnetic_wall.global_position, 3.0, 35.0, "magnetic_shock", Color("#53d9e5"))
	_update_aim()
	if combat_state != null and combat_state.is_stunned() and _dash_active:
		_cancel_dash()
	if combat_state != null and combat_state.is_stunned() and _fulguro_phase != "":
		_cancel_fulguro_attack("FULGURO PUNCH  •  INTERROMPU")
	if combat_state != null and combat_state.is_stunned() and _pelto_phase != "":
		_cancel_pelto_smash("PELTO SMASH  •  INTERROMPU")
	_try_execute_defensive_buffer()
	_update_movement(delta)
	# Sample action commands while the current cast still owns the frame. This
	# prevents a held input from slipping through on the exact recovery frame.
	_update_debug_effects()
	var cast_locked_before_action_updates := _action_gate.is_kind(ACTION_GATE.Kind.MODULE)
	_update_fulguro_attack(delta)
	_update_pelto_attack(delta)
	_update_weapon_pose_state(delta)
	_update_robot_motion(delta)
	_update_world_ui_anchor()
	_update_bush_state(delta)
	_update_javelin_mark()
	if combat_state != null and combat_state.is_stunned() and (_blaster_charge_active or _touch_fire_active):
		cancel_touch_fire("BLASTER  •  INTERROMPU")
	if combat_state != null and combat_state.is_stunned() and _blaster_attack_busy:
		_cancel_blaster_attack()
	if combat_state != null and combat_state.is_stunned() and _shotgun_attack_busy:
		_cancel_shotgun_attack()
	if combat_state != null and combat_state.is_stunned() and _active_module_action_token != 0:
		_cancel_pending_module_action("MODULE  •  INTERROMPU")
	_update_shotgun_reload_input()
	_update_shotgun_reload(delta)
	_update_attack(cast_locked_before_action_updates)
	_update_weapon_ambient_motion(delta)
	_update_shotgun_reload_visual()
	_update_blaster_charge_visual(delta)
	_sync_weapon_readout()


func _update_movement(delta: float) -> void:
	if _stasis_remaining > 0.0:
		velocity = Vector3.ZERO
		move_direction = Vector3.ZERO
		return
	if _fulguro_projection_active:
		_update_fulguro_projection(delta)
		return
	if _dash_active:
		_update_dash(delta)
		return
	if _pelto_pull_active:
		_update_pelto_pull(delta)
		return
	var input_vector := _touch_move_vector
	if input_vector.length_squared() <= 0.001:
		input_vector = Vector2.ZERO
		if Input.is_action_pressed("game_move_left"):
			input_vector.x -= 1.0
		if Input.is_action_pressed("game_move_right"):
			input_vector.x += 1.0
		if Input.is_action_pressed("game_move_up"):
			input_vector.y -= 1.0
		if Input.is_action_pressed("game_move_down"):
			input_vector.y += 1.0

	input_vector = input_vector.limit_length(1.0)
	var world_move_direction := _camera_relative_direction(input_vector)
	if world_move_direction.length_squared() > 0.001:
		_last_move_direction = world_move_direction
	if combat_state != null and combat_state.is_stunned():
		input_vector = Vector2.ZERO
		world_move_direction = Vector3.ZERO
	var slow_multiplier := 1.0
	if combat_state != null:
		slow_multiplier = 1.0 - combat_state.get_slow_percent() / 100.0
	var bio_multiplier := _bio_speed_multiplier if _bio_remaining > 0.0 else 1.0
	var charge_multiplier := _blaster_charge_slow_multiplier if _blaster_charge_active else 1.0
	var evolution_speed: float = survival_evolution_effects.movement_multiplier() if survival_mode and survival_evolution_effects != null else 1.0
	velocity = world_move_direction * move_speed * bio_multiplier * slow_multiplier * charge_multiplier * evolution_speed
	move_and_slide()
	global_position.y = 0.0


func _update_robot_motion(delta: float) -> void:
	if _robot_visuals == null:
		return
	_locomotion_clock += delta
	var visual_velocity := _get_actual_move_velocity()
	move_direction = visual_velocity.normalized() if visual_velocity.length() > 0.15 else Vector3.ZERO
	var visual_speed := visual_velocity.length()
	var desired_amount := clampf(visual_speed / maxf(move_speed, 0.01), 0.0, 1.0)
	_locomotion_amount = move_toward(_locomotion_amount, desired_amount, delta * 8.0)
	for node in _locomotion_nodes:
		if node == null or not is_instance_valid(node):
			continue
		var base_position: Vector3 = node.get_meta("locomotion_base_position", node.position)
		var base_rotation: Vector3 = node.get_meta("locomotion_base_rotation", node.rotation)
		var phase := float(node.get_meta("locomotion_phase", 0.0))
		var role := str(node.get_meta("locomotion_role", "body"))
		var stride := sin(_locomotion_clock * 9.5 + phase) * _locomotion_amount
		if role == "limb":
			node.position = base_position + Vector3(0.0, absf(stride) * 0.035, 0.0)
			node.rotation = base_rotation + Vector3(stride * 0.18, 0.0, 0.0)
		elif role == "head":
			node.position = base_position + Vector3(0.0, sin(_locomotion_clock * 9.5 + phase) * 0.035 * _locomotion_amount, 0.0)
			node.rotation = base_rotation + Vector3(0.0, sin(_locomotion_clock * 4.7 + phase) * 0.025 * _locomotion_amount, 0.0)
		else:
			node.position = base_position + Vector3(0.0, sin(_locomotion_clock * 9.5 + phase) * 0.045 * _locomotion_amount, 0.0)
			node.rotation = base_rotation
	if _visual_rig != null:
		_update_aim_pose_state()
		var visual_aim := _fulguro_direction if _fulguro_phase != "" else aim_direction
		_visual_rig.update_visual_state(move_direction, visual_aim, visual_speed, move_speed, delta, _gameplay_enabled and not is_real_dead())
	if not _has_skeletal_weapon_attachment():
		_update_player_debug_vectors()


func _get_actual_move_velocity() -> Vector3:
	if _stasis_remaining > 0.0 or (combat_state != null and combat_state.is_stunned()):
		return Vector3.ZERO
	if _fulguro_projection_active:
		return _fulguro_projection_direction * _fulguro_projection_speed
	if _dash_active and _dash_direction.length_squared() > 0.001:
		var dash_definition: Dictionary = COMBAT_DATA.MODULE_DEFINITIONS.get("pyro_boots", {})
		var dash_duration := maxf(0.001, float(dash_definition.get("dash_duration", 0.25)))
		return _dash_direction * float(dash_definition.get("dash_distance", 3.0)) / dash_duration
	var actual_velocity := get_real_velocity()
	actual_velocity.y = 0.0
	return actual_velocity


func _camera_relative_direction(input_vector: Vector2) -> Vector3:
	if input_vector.length_squared() <= 0.001:
		return Vector3.ZERO
	var camera := get_viewport().get_camera_3d() if get_viewport() != null else null
	var camera_right := Vector3.RIGHT
	var camera_forward := Vector3.FORWARD
	if camera != null:
		camera_right = camera.global_basis.x
		camera_forward = -camera.global_basis.z
		camera_right.y = 0.0
		camera_forward.y = 0.0
		if camera_right.length_squared() > 0.001:
			camera_right = camera_right.normalized()
		if camera_forward.length_squared() > 0.001:
			camera_forward = camera_forward.normalized()
	var world_direction := camera_right * input_vector.x - camera_forward * input_vector.y
	world_direction.y = 0.0
	return world_direction.normalized() if world_direction.length_squared() > 0.001 else Vector3.ZERO


func _world_offset_to_visual_local(world_offset: Vector3) -> Vector3:
	if _visual_rig == null:
		return world_offset
	return _visual_rig.global_basis.inverse() * world_offset


func _update_weapon_ambient_motion(delta: float) -> void:
	_weapon_motion_clock += delta
	if _has_skeletal_weapon_attachment():
		# Both equipped weapons follow the animated hand, including recovery.
		if _blaster_sway_pivot != null:
			_blaster_sway_pivot.transform = Transform3D.IDENTITY
		if _blaster_recoil_pivot != null:
			_blaster_recoil_pivot.transform = Transform3D.IDENTITY
		if _shotgun_sway_pivot != null:
			_shotgun_sway_pivot.transform = Transform3D.IDENTITY
		if _shotgun_recoil_pivot != null:
			_shotgun_recoil_pivot.transform = Transform3D.IDENTITY
	elif _weapon_id == "blaster" and _blaster_sway_pivot != null and not _blaster_attack_busy and not _blaster_charge_active and not _is_weapon_recoil_running(_blaster_recoil_tweens):
		var blaster_sway := sin(_weapon_motion_clock * 2.4) * 0.018
		var blaster_transform := Transform3D.IDENTITY
		blaster_transform.origin += Vector3(0.0, blaster_sway, sin(_weapon_motion_clock * 1.7) * 0.014)
		blaster_transform.basis = blaster_transform.basis * Basis.from_euler(Vector3(0.0, sin(_weapon_motion_clock * 1.9) * 0.025, sin(_weapon_motion_clock * 2.2) * 0.018))
		_blaster_sway_pivot.transform = blaster_transform
	if not _has_skeletal_weapon_attachment() and _weapon_id == "shotgun" and _shotgun_sway_pivot != null and not _shotgun_attack_busy and not _shotgun_reloading:
		var shotgun_sway := sin(_weapon_motion_clock * 2.0 + 0.8) * 0.014
		var shotgun_transform := Transform3D.IDENTITY
		shotgun_transform.origin += Vector3(0.0, shotgun_sway, sin(_weapon_motion_clock * 1.4) * 0.018)
		shotgun_transform.basis = shotgun_transform.basis * Basis.from_euler(Vector3(0.0, sin(_weapon_motion_clock * 1.8) * 0.018, sin(_weapon_motion_clock * 2.1) * 0.014))
		_shotgun_sway_pivot.transform = shotgun_transform


func _update_aim() -> void:
	if _touch_aim_active and _touch_aim_vector.length_squared() > 0.04:
		_set_aim_direction(_camera_relative_direction(_touch_aim_vector))
		return
	if OS.has_feature("mobile") or DisplayServer.is_touchscreen_available():
		if _last_move_direction.length_squared() > 0.001:
			_set_aim_direction(_last_move_direction)
		return
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	var mouse_position := get_viewport().get_mouse_position()
	_aim_at_screen_position(mouse_position, camera)


func _aim_at_screen_position(mouse_position: Vector2, camera: Camera3D) -> void:
	var ray_origin := camera.project_ray_origin(mouse_position)
	var ray_direction := camera.project_ray_normal(mouse_position)
	if absf(ray_direction.y) < 0.001:
		return
	# The isometric camera projects the torso and the floor to different pixels.
	# Aim on the combat plane so pointing at a robot's body does not turn the
	# barrel toward a point behind it, especially when it stands to either side.
	var distance_to_aim_plane := (global_position.y + MOUSE_AIM_HEIGHT - ray_origin.y) / ray_direction.y
	if distance_to_aim_plane <= 0.0:
		return
	var aim_point := ray_origin + ray_direction * distance_to_aim_plane
	var flat_direction := aim_point - global_position
	flat_direction.y = 0.0
	if flat_direction.length_squared() > 0.04:
		_set_aim_direction(flat_direction.normalized())


func _set_aim_direction(direction: Vector3) -> void:
	direction.y = 0.0
	if direction.length_squared() > 0.001:
		aim_direction = direction.normalized()
	elif _last_move_direction.length_squared() > 0.001:
		aim_direction = _last_move_direction.normalized()
	else:
		aim_direction = Vector3(0.0, 0.0, -1.0)


func _normalized_aim_direction() -> Vector3:
	var direction := aim_direction
	direction.y = 0.0
	return direction.normalized() if direction.length_squared() > 0.001 else Vector3(0.0, 0.0, -1.0)


func _weapon_pose_uses_aim() -> bool:
	return weapon_pose_state in [WeaponPoseState.AIM, WeaponPoseState.FIRE, WeaponPoseState.AIM_HOLD]


func get_weapon_pose_state_name() -> StringName:
	return WEAPON_POSE_NAMES[weapon_pose_state]


func _set_weapon_pose_state(next_state: WeaponPoseState, restart_hold: bool = false) -> void:
	weapon_pose_state = next_state
	if next_state == WeaponPoseState.FIRE:
		_fire_pose_remaining = SKELETAL_FIRE_POSE_DURATION
	if next_state == WeaponPoseState.AIM_HOLD and restart_hold:
		_aim_hold_remaining = aim_hold_time
	_update_aim_pose_state()


func _begin_weapon_aim() -> void:
	if _weapon_id not in ["blaster", "shotgun"]:
		return
	if _round_warmup_active and _gameplay_enabled:
		_play_player_animation(&"idle")
		_round_warmup_active = false
	_set_weapon_pose_state(WeaponPoseState.AIM)


func _begin_weapon_fire() -> void:
	if _weapon_id not in ["blaster", "shotgun"]:
		return
	if _round_warmup_active and _gameplay_enabled:
		_play_player_animation(&"idle")
		_round_warmup_active = false
	_set_weapon_pose_state(WeaponPoseState.FIRE)
	if _visual_rig != null:
		_visual_rig.commit_firing_pose(_normalized_aim_direction())


func _begin_aim_hold() -> void:
	if _weapon_id in ["blaster", "shotgun"] and _gameplay_enabled and not is_real_dead():
		_set_weapon_pose_state(WeaponPoseState.AIM_HOLD, true)
	else:
		_reset_weapon_pose_to_locomotion()


func _reset_weapon_pose_to_locomotion(immediate: bool = false) -> void:
	_aim_hold_remaining = 0.0
	_fire_pose_remaining = 0.0
	var moving := _get_actual_move_velocity().length() > 0.15
	weapon_pose_state = WeaponPoseState.LOCOMOTION if moving else WeaponPoseState.IDLE
	if _visual_rig != null:
		_visual_rig.set_aim_enabled(false, immediate)


func _update_weapon_pose_state(delta: float) -> void:
	if not _gameplay_enabled or is_real_dead() or _weapon_id not in ["blaster", "shotgun"]:
		_reset_weapon_pose_to_locomotion(true)
		return
	if weapon_pose_state == WeaponPoseState.AIM:
		if not _blaster_charge_active and not _shotgun_attack_busy:
			_begin_aim_hold()
		return
	if weapon_pose_state == WeaponPoseState.FIRE:
		_fire_pose_remaining = maxf(0.0, _fire_pose_remaining - delta)
		if (_visual_rig == null or not _visual_rig.is_shot_kick_active()) and _fire_pose_remaining <= 0.0:
			_begin_aim_hold()
		return
	if weapon_pose_state == WeaponPoseState.AIM_HOLD:
		_aim_hold_remaining = maxf(0.0, _aim_hold_remaining - delta)
		if _aim_hold_remaining <= 0.0:
			_reset_weapon_pose_to_locomotion()
		return
	var moving := _get_actual_move_velocity().length() > 0.15
	_set_weapon_pose_state(WeaponPoseState.LOCOMOTION if moving else WeaponPoseState.IDLE)


func _desktop_attack_input_held() -> bool:
	return Input.is_action_pressed("game_attack")


func _action_incapacitated() -> bool:
	return not _gameplay_enabled or is_real_dead() or _stasis_remaining > 0.0 or _fulguro_projection_active or (combat_state != null and combat_state.is_stunned())


func _try_begin_weapon_action(action_id: String) -> int:
	if _action_incapacitated() or _action_gate.is_kind(ACTION_GATE.Kind.MODULE):
		return 0
	return _action_gate.try_acquire(ACTION_GATE.Kind.WEAPON, action_id)


func _try_begin_module_action(module_id: String) -> int:
	if _action_incapacitated() or _action_gate.is_kind(ACTION_GATE.Kind.MODULE):
		return 0
	var action_token := 0
	if _action_gate.is_kind(ACTION_GATE.Kind.WEAPON):
		action_token = _action_gate.replace_weapon_with_module(module_id)
	else:
		action_token = _action_gate.try_acquire(ACTION_GATE.Kind.MODULE, module_id)
	if action_token == 0:
		return 0
	_active_module_action_token = action_token
	_active_module_id = module_id
	_interrupt_weapon_for_module()
	return action_token


func _interrupt_weapon_for_module() -> void:
	_desktop_attack_rearm_required = _desktop_attack_rearm_required or _desktop_attack_input_held()
	_desktop_blaster_tap_buffered = false
	_touch_attack_rearm_required = _touch_attack_rearm_required or _touch_fire_active or _touch_attack_held
	_touch_fire_requests.clear()
	if _blaster_charge_active or _touch_fire_active or _touch_attack_held:
		cancel_touch_fire()
	if _blaster_attack_busy:
		_cancel_blaster_attack()
	if _shotgun_attack_busy:
		_cancel_shotgun_attack()
	if _axe_attack_busy:
		_cancel_axe_attack()
	_attack_hold_last = _desktop_attack_input_held()


func _module_action_can_execute(action_token: int, module_id: String) -> bool:
	return _action_gate.owns(action_token, ACTION_GATE.Kind.MODULE, module_id) and not _action_incapacitated()


func _end_module_action(action_token: int, module_id: String) -> bool:
	if not _action_gate.owns(action_token, ACTION_GATE.Kind.MODULE, module_id):
		return false
	_action_gate.release(action_token)
	if _active_module_action_token == action_token:
		_active_module_action_token = 0
		_active_module_id = ""
	_module_busy = false
	return true


func _cancel_pending_module_action(reason: String = "") -> void:
	if _active_module_action_token == 0:
		return
	var module_id := _active_module_id
	var action_token := _active_module_action_token
	_module_token += 1
	_javelin_launch_token += 1
	_end_module_action(action_token, module_id)
	if reason != "" and _attack_label != null:
		_attack_label.text = reason


func _reset_action_ownership() -> void:
	_action_gate.reset()
	_active_module_action_token = 0
	_active_module_id = ""
	_blaster_action_token = 0
	_shotgun_action_token = 0
	_axe_action_token = 0
	_desktop_attack_rearm_required = _desktop_attack_input_held()
	_desktop_blaster_tap_buffered = false
	_touch_attack_rearm_required = false


func get_action_owner() -> String:
	return _action_gate.get_owner_id()


func _update_attack(force_action_blocked: bool = false) -> void:
	var desktop_wants_attack := _desktop_attack_input_held()
	if force_action_blocked or _action_gate.is_kind(ACTION_GATE.Kind.MODULE) or _action_incapacitated():
		_desktop_blaster_tap_buffered = false
		if desktop_wants_attack:
			_desktop_attack_rearm_required = true
		if _touch_fire_active or _touch_attack_held:
			_touch_attack_rearm_required = true
			cancel_touch_fire()
		_touch_fire_requests.clear()
		_attack_hold_last = desktop_wants_attack
		return
	if _desktop_attack_rearm_required:
		if desktop_wants_attack:
			_attack_hold_last = true
			desktop_wants_attack = false
		else:
			_desktop_attack_rearm_required = false
			_attack_hold_last = false
	var wants_to_attack := _touch_attack_held or desktop_wants_attack
	if _weapon_id == "shotgun":
		_update_shotgun_attack(wants_to_attack)
		_attack_hold_last = wants_to_attack
		return
	var now := Time.get_ticks_msec() / 1000.0
	var processed_touch_request := false
	if not _touch_fire_requests.is_empty():
		_process_touch_fire_request()
		processed_touch_request = true
	if _touch_fire_active:
		_update_mobile_blaster_contact(now)
		# Le flux tactile possède sa propre machine d'état. Il ne doit jamais être
		# interprété une seconde fois comme le maintien PC historique.
		_attack_hold_last = wants_to_attack
		return
	if processed_touch_request:
		_attack_hold_last = wants_to_attack
		return
	if _desktop_blaster_tap_buffered:
		if wants_to_attack:
			# Un nouveau maintien remplace le tap en attente et suit le chemin de charge.
			_desktop_blaster_tap_buffered = false
		elif now >= _blaster_next_attack_ready_at:
			_desktop_blaster_tap_buffered = false
			_fire_blaster_projectile(_blaster_damage, 0.0, aim_direction.normalized())
			_attack_hold_last = false
			return
	var just_released := not wants_to_attack and _attack_hold_last
	# Un appui PC peut commencer pendant le cooldown du tir précédent. Dans ce
	# cas, la première tentative est refusée mais le maintien doit amorcer la
	# charge dès que l'arme redevient disponible. Le réarmement post-cast a déjà
	# forcé `desktop_wants_attack` à false plus haut tant qu'aucun relâchement
	# réel n'a eu lieu, donc cette relance ne mémorise jamais une entrée interdite.
	if wants_to_attack and not _blaster_charge_active:
		_begin_blaster_charge(now)
	_update_active_blaster_charge(now)
	if just_released:
		if _blaster_charge_active:
			_release_blaster_charge()
		elif now < _blaster_next_attack_ready_at:
			# Un tap bref pendant la cadence conserve uniquement un tir normal. Les
			# entrées de cast passent par la branche bloquée plus haut et effacent ce
			# tampon, elles ne peuvent donc jamais être rejouées après l'incantation.
			_desktop_blaster_tap_buffered = true
	_attack_hold_last = wants_to_attack


func _update_active_blaster_charge(now: float) -> void:
	if not _blaster_charge_active:
		return
	_blaster_charge_ratio = clampf((now - _blaster_charge_started_at) / maxf(0.001, _blaster_charge_time), 0.0, 1.0)
	if _blaster_charge_ratio >= 1.0:
		_play_blaster_ready_sound()


func _update_mobile_blaster_contact(now: float) -> void:
	if not _touch_fire_active or _weapon_id != "blaster":
		return
	var held_for := maxf(0.0, now - _touch_fire_started_at)
	if not _touch_fire_charge_started and held_for >= mobile_blaster_charge_threshold and now >= _blaster_next_attack_ready_at:
		# Le délai de distinction ne rallonge pas la charge existante : une charge
		# commencée à 0,20 s conserve l'instant du toucher comme origine.
		var charge_origin := maxf(_touch_fire_started_at, _blaster_next_attack_ready_at)
		_begin_blaster_charge(charge_origin)
		_touch_fire_charge_started = _blaster_charge_active
	_update_active_blaster_charge(now)


func _process_touch_fire_request() -> void:
	if _touch_fire_requests.is_empty():
		return
	var request: Dictionary = _touch_fire_requests.pop_front()
	if not _gameplay_enabled or is_real_dead() or _weapon_id != "blaster":
		return
	var direction: Vector3 = request.get("direction", _normalized_aim_direction())
	var charge_ratio := clampf(float(request.get("charge_ratio", 0.0)), 0.0, 1.0)
	var damage := lerpf(_blaster_damage, _blaster_max_damage, charge_ratio)
	_fire_blaster_projectile(damage, charge_ratio, direction)


func _update_debug_effects() -> void:
	if _pressed_once(KEY_F8):
		_direction_debug_enabled = not _direction_debug_enabled
		if _direction_debug_mesh != null:
			_direction_debug_mesh.visible = _direction_debug_enabled
		if _direction_debug_label != null:
			_direction_debug_label.visible = _direction_debug_enabled
		if _attack_label != null:
			_attack_label.text = "DEBUG DIRECTIONS : %s (F8)" % ("ON" if _direction_debug_enabled else "OFF")
	# Temporary PC-only mannequin probes for P0-102. They do not replace the
	# future module bindings and are intentionally explicit in the HUD/README.
	var active_scene := get_tree().current_scene
	if active_scene == null:
		return
	# Debug mannequin shortcuts only exist in the duel scene. Gameplay module
	# inputs continue in Survival and Training Ground as well.
	var target := active_scene.get_node_or_null("TargetDummy") if not active_scene.has_method("get_training_targets") else null
	if target != null:
		if _pressed_once(KEY_F1):
			target.call("apply_burn", COMBAT_DATA.BURN_DURATION, COMBAT_DATA.BURN_DAMAGE_PER_SECOND, "debug")
		if _pressed_once(KEY_F2):
			target.call("apply_slow", 1.5, 30.0, "debug")
		if _pressed_once(KEY_F3):
			target.call("apply_stun", 1.5, "debug")
		if _pressed_once(KEY_F4):
			target.call("apply_spotted", 5.0, "debug")
		if _pressed_once(KEY_F5):
			target.call("reset_combat_state")
		if _pressed_once(KEY_F6):
			_show_debug_hitbox = not _show_debug_hitbox
			_attack_label.text = "DIAGNOSTIC HITBOX : %s" % ("ON" if _show_debug_hitbox else "OFF")
		if _pressed_once(KEY_F7):
			var bot_enabled := bool(target.call("toggle_training_bot"))
			_attack_label.text = "BOT D'ENTRAÎNEMENT : %s" % ("ON" if bot_enabled else "OFF")
	if not survival_mode and _pressed_action_once("weapon"):
		set_weapon("shotgun" if _weapon_id == "blaster" else "blaster")
	var offensive_down := Input.is_action_pressed("game_offensive")
	var offensive_was_down := bool(_debug_key_latches.get("game_offensive", false))
	_debug_key_latches["game_offensive"] = offensive_down
	if _offensive_module_id == "fulguro_punch":
		if offensive_down and not offensive_was_down:
			_begin_fulguro_charge()
		elif not offensive_down and offensive_was_down:
			_release_fulguro_charge()
	elif offensive_down and not offensive_was_down:
		_perform_offensive_module()
	if _pressed_action_once("defensive"):
		_activate_defensive_module()
	if _pressed_action_once("mobility"):
		_activate_mobility_module()
	if not survival_mode and _consume_touch_action("weapon"):
		set_weapon("shotgun" if _weapon_id == "blaster" else "blaster")
	if _consume_touch_action("offensive"):
		_perform_offensive_module()
	if _consume_touch_action("defensive"):
		_activate_defensive_module()
	if _consume_touch_action("mobility"):
		_activate_mobility_module()


func _refresh_control_bindings() -> void:
	_debug_key_latches.clear()
	cancel_touch_fire()


func _pressed_action_once(action: String) -> bool:
	var mapped := StringName("game_" + action)
	var is_down := Input.is_action_pressed(mapped)
	var was_down := bool(_debug_key_latches.get(mapped, false))
	_debug_key_latches[mapped] = is_down
	return is_down and not was_down


func _pressed_once(keycode: Key) -> bool:
	var is_down := Input.is_key_pressed(keycode)
	var was_down := bool(_debug_key_latches.get(keycode, false))
	_debug_key_latches[keycode] = is_down
	return is_down and not was_down


func set_touch_move_vector(value: Vector2) -> void:
	set_move_input(value)


func set_touch_aim_vector(value: Vector2) -> void:
	set_aim_input(value)


func set_move_input(value: Vector2) -> void:
	_touch_move_vector = value.limit_length(1.0)


func set_aim_input(value: Vector2) -> void:
	_touch_aim_vector = value.limit_length(1.0)
	_touch_aim_active = _touch_aim_vector.length_squared() > 0.04
	if _touch_aim_active:
		var direction := _camera_relative_direction(_touch_aim_vector)
		if direction.length_squared() > 0.001:
			_touch_last_valid_aim_direction = direction.normalized()
			# Mettre à jour immédiatement évite de perdre le dernier drag lorsqu'un
			# relâchement arrive entre deux frames physiques.
			_set_aim_direction(_touch_last_valid_aim_direction)


func set_touch_attack_held(value: bool) -> void:
	if value and (_action_gate.is_kind(ACTION_GATE.Kind.MODULE) or _action_gate.was_claimed_this_frame() or _action_incapacitated()):
		_touch_attack_rearm_required = true
		_touch_attack_held = false
		return
	if not value:
		_touch_attack_rearm_required = false
	_touch_attack_held = value


func begin_touch_fire() -> void:
	if _touch_fire_active or not _gameplay_enabled or is_real_dead():
		return
	if _touch_attack_rearm_required or _action_gate.is_kind(ACTION_GATE.Kind.MODULE) or _action_gate.was_claimed_this_frame() or _action_incapacitated():
		_touch_attack_rearm_required = true
		return
	_touch_fire_active = true
	_touch_fire_started_at = Time.get_ticks_msec() / 1000.0
	_touch_fire_charge_started = false
	_touch_last_valid_aim_direction = _normalized_aim_direction()
	if _weapon_id == "shotgun":
		# Le Shotgun conserve exactement son chemin pressé/maintenu existant.
		_touch_attack_held = true


func end_touch_fire(final_aim: Vector2 = Vector2.ZERO) -> bool:
	if final_aim.length_squared() > 0.04:
		set_aim_input(final_aim)
	if _touch_attack_rearm_required:
		_touch_attack_rearm_required = false
		_touch_fire_active = false
		_touch_attack_held = false
		_touch_fire_requests.clear()
		return false
	if not _touch_fire_active:
		return false
	var released_weapon := _weapon_id
	var now := Time.get_ticks_msec() / 1000.0
	var held_for := maxf(0.0, now - _touch_fire_started_at)
	var direction_snapshot := _touch_last_valid_aim_direction
	if direction_snapshot.length_squared() <= 0.001:
		direction_snapshot = _normalized_aim_direction()
	_touch_fire_active = false
	_touch_attack_held = false
	_touch_fire_started_at = -1.0
	_touch_fire_charge_started = false
	if released_weapon != "blaster":
		return false
	var ratio := mobile_blaster_release_ratio(held_for, mobile_blaster_charge_threshold, _blaster_charge_time)
	if _blaster_charge_active:
		ratio = maxf(ratio, _blaster_charge_ratio)
	_touch_fire_requests.append({
		"direction": direction_snapshot.normalized(),
		"charge_ratio": ratio,
	})
	_cancel_blaster_charge()
	return true


func cancel_touch_fire(reason: String = "") -> void:
	_touch_fire_active = false
	_touch_fire_started_at = -1.0
	_touch_fire_charge_started = false
	_touch_attack_held = false
	_touch_fire_requests.clear()
	if _blaster_charge_active:
		_cancel_blaster_charge(reason)


static func mobile_blaster_release_ratio(hold_seconds: float, charge_threshold: float, charge_time: float) -> float:
	if hold_seconds < maxf(0.0, charge_threshold):
		return 0.0
	return clampf(hold_seconds / maxf(0.001, charge_time), 0.0, 1.0)


func get_mobile_blaster_input_state() -> StringName:
	if _weapon_id != "blaster" or not _touch_fire_active:
		return &"aim"
	if not _blaster_charge_active:
		return &"aim"
	return &"ready" if _blaster_charge_ratio >= 1.0 else &"charging"


func trigger_touch_action(action: String) -> bool:
	if _action_gate.is_kind(ACTION_GATE.Kind.MODULE) or _action_gate.was_claimed_this_frame():
		return false
	_touch_actions[action] = true
	return true


func begin_touch_action(action: String) -> bool:
	if _action_gate.is_kind(ACTION_GATE.Kind.MODULE) or _action_gate.was_claimed_this_frame():
		return false
	if action == "offensive" and _offensive_module_id == "fulguro_punch":
		_begin_fulguro_charge()
		return _action_gate.is_kind(ACTION_GATE.Kind.MODULE) and _active_module_id == "fulguro_punch"
	return trigger_touch_action(action)


func end_touch_action(action: String) -> void:
	if action == "offensive" and _offensive_module_id == "fulguro_punch":
		_release_fulguro_charge()


func clear_touch_inputs() -> void:
	var touch_owned_charge := _touch_fire_charge_started
	_touch_move_vector = Vector2.ZERO
	_touch_aim_vector = Vector2.ZERO
	_touch_aim_active = false
	_touch_actions.clear()
	_attack_hold_last = false
	_touch_fire_active = false
	_touch_fire_started_at = -1.0
	_touch_fire_charge_started = false
	_touch_attack_held = false
	_touch_fire_requests.clear()
	_touch_attack_rearm_required = false
	# A hidden/inactive touch overlay must not cancel a charge started from the
	# desktop input path. It only owns a charge it started after a touch hold.
	if touch_owned_charge and _blaster_charge_active:
		_cancel_blaster_charge()


func set_gameplay_enabled(value: bool) -> void:
	_gameplay_enabled = value
	if not value:
		_static_pulse_token += 1
		_reset_weapon_pose_to_locomotion(true)
		clear_touch_inputs()
		_cancel_fulguro_attack()
		_cancel_pelto_smash()
		_cancel_pending_module_action()
		_cancel_blaster_charge()
		_cancel_shotgun_attack()
		_cancel_axe_attack()
		_reset_action_ownership()
		velocity = Vector3.ZERO
		if not _round_warmup_active and not is_real_dead():
			_play_player_animation(&"idle")
	else:
		if _round_warmup_active:
			# The countdown can end before the 18 s source warmup clip. Release
			# the rig's full-body action lock before the first combat shot.
			_play_player_animation(&"idle")
		_round_warmup_active = false
		_reset_weapon_pose_to_locomotion(true)
		_update_player_animation()


func is_gameplay_enabled() -> bool:
	return _gameplay_enabled


func _consume_touch_action(action: String) -> bool:
	if not bool(_touch_actions.get(action, false)):
		return false
	_touch_actions[action] = false
	return true


func _mark_combat_event() -> void:
	if visibility_state != null:
		visibility_state.mark_combat_event()


func get_combat_reveal_remaining() -> float:
	return visibility_state.combat_remaining if visibility_state != null else 0.0


func get_spotted_reveal_remaining() -> float:
	return visibility_state.spotted_remaining if visibility_state != null else 0.0


func is_revealed() -> bool:
	return visibility_state != null and visibility_state.is_revealed()


func is_attack_committed() -> bool:
	return _action_gate.is_busy()


func is_in_bush() -> bool:
	_sync_bush_state()
	return _current_bush != null and is_instance_valid(_current_bush)


func get_current_bush_name() -> String:
	return _current_bush_name if is_in_bush() else ""


func get_bush_transition_clock() -> float:
	return _bush_transition_clock


func is_visible_to(observer: Node3D) -> bool:
	if observer == null or not is_instance_valid(observer):
		return true
	if observer == self:
		return true
	var world := get_world_3d()
	if world == null:
		return VISIBILITY_STATE.visible_to_observer(is_revealed(), is_in_bush(), true)
	var query := PhysicsRayQueryParameters3D.create(observer.global_position + Vector3.UP * 0.72, global_position + Vector3.UP * 0.72)
	query.collision_mask = 1
	query.collide_with_areas = false
	query.collide_with_bodies = true
	query.exclude = [observer.get_rid(), get_rid()]
	var line_of_sight := world.direct_space_state.intersect_ray(query).is_empty()
	return VISIBILITY_STATE.visible_to_observer(is_revealed(), is_in_bush(), line_of_sight)


func _update_bush_state(delta: float) -> void:
	_sync_bush_state()
	_bush_transition_clock = maxf(0.0, _bush_transition_clock - delta)


func _sync_bush_state() -> void:
	var next_bush := _find_bush_at_position()
	var changed := next_bush != _current_bush
	_current_bush = next_bush
	_current_bush_name = str(next_bush.name) if next_bush != null else ""
	if changed:
		_bush_transition_clock = 0.22
		bush_state_changed.emit(_current_bush != null, _current_bush_name)


func _find_bush_at_position() -> Node3D:
	var space := get_tree()
	if space == null:
		return null
	for bush in space.get_nodes_in_group("bush_placeholder"):
		if not is_instance_valid(bush):
			continue
		var radius := float(bush.get_meta("bush_radius", 0.0))
		if radius <= 0.0:
			continue
		if Vector2(global_position.x - bush.global_position.x, global_position.z - bush.global_position.z).length() <= radius:
			return bush as Node3D
	return null


func take_damage(amount: float, source_id: String = "", attack_id: String = "") -> float:
	if training_invulnerable:
		return 0.0
	if _stasis_remaining > 0.0:
		return 0.0
	if combat_state == null or passive_state == null:
		return 0.0
	if survival_mode and survival_evolution_effects != null:
		amount = survival_evolution_effects.receive_damage(amount, attack_id)
		if amount <= 0.0:
			return 0.0
	if amount <= 0.0 or (attack_id != "" and _received_attack_ids.has(attack_id)):
		return 0.0
	if attack_id != "":
		_received_attack_ids[attack_id] = true
	if amount > 0.0 and visibility_state != null:
		visibility_state.mark_combat_event()
	var result: Dictionary = passive_state.intercept_damage(amount, combat_state.health)
	if bool(result["triggered_baroud"]):
		if survival_mode and survival_evolution_effects != null:
			combat_state.health = 1.0
			combat_state.health_changed.emit(combat_state.health, combat_state.max_health)
			survival_evolution_effects.start_baroud()
		if _survival_evolved("passive") and _passive_id == "baroud":
			_survival_area_damage(global_position, 4.0, 90.0, "baroud_pulse", Color("#f17285"))
		if _attack_label != null and not survival_mode:
			_attack_label.text = "BAROUD D'HONNEUR  •  2.5s"
		return 0.0
	var effective := float(result["effective"])
	if effective <= 0.0:
		return 0.0
	get_node("/root/GameSfx").play_event("damage_received")
	effective_damage_taken.emit(effective, source_id, attack_id)
	_external_damage_pending = true
	if bool(result["real_death"]):
		combat_state.apply_damage(combat_state.health, source_id, attack_id)
	else:
		# Baroud damage is kept on its temporary gauge, not normal PV.
		if passive_state.baroud_active:
			if _attack_label != null:
				_attack_label.text = "BAROUD  •  %d PV" % int(round(passive_state.baroud_health))
		else:
			combat_state.apply_damage(effective, source_id, attack_id)
	_external_damage_pending = false
	flash_impact(bool(result["real_death"]))
	return effective


func flash_impact(critical: bool = false) -> void:
	if _robot_visuals == null:
		return
	var vfx := _vfx_manager()
	if vfx != null:
		vfx.call("hit_flash", _robot_visuals, critical)
	_camera_impulse(0.09 if critical else 0.045, 0.065 if critical else 0.025)


func _clear_player_impact_material(_unused: float = 0.0) -> void:
	if _player_body_material != null:
		_player_body_material.emission_enabled = false


func _vfx_manager() -> Node:
	var scene := get_tree().current_scene if get_tree() != null else null
	return scene.get_node_or_null("VFXManager") if scene != null else null


func _camera_impulse(duration: float, strength: float) -> void:
	var scene := get_tree().current_scene if get_tree() != null else null
	var rig := scene.get_node_or_null("CameraRig") if scene != null else null
	if rig != null and rig.has_method("shake"):
		rig.call("shake", duration, strength)


func _create_muzzle_burst(_origin: Vector3, _direction: Vector3, _color: Color, scale: float = 1.0, muzzle_anchor: Node3D = null) -> void:
	var socket := muzzle_anchor if muzzle_anchor != null else _active_muzzle()
	var vfx := _vfx_manager()
	if vfx != null and socket != null:
		vfx.call("muzzle", socket, "shotgun" if socket == _shotgun_muzzle else "blaster", clampf((scale - 1.0) / 0.65, 0.0, 1.0))


func _active_muzzle() -> Node3D:
	return _shotgun_muzzle if _weapon_id == "shotgun" else _blaster_muzzle


func _visual_contact(start: Vector3, end: Vector3, target: Node = null) -> Dictionary:
	var delta := end - start
	if delta.length_squared() < 0.0001 or get_world_3d() == null:
		return {}
	# This query only positions VFX. Assisted combat ranges and hit tests stay unchanged.
	var query := PhysicsRayQueryParameters3D.create(start, end + delta.normalized() * 0.08, 9)
	if target is CollisionObject3D:
		query.collision_mask |= target.collision_layer
	query.exclude = [get_rid()]
	query.collide_with_areas = true
	return get_world_3d().direct_space_state.intersect_ray(query)


func _contact_fx(contact: Dictionary, color: Color, power: float = 1.0) -> void:
	var vfx := _vfx_manager()
	if vfx == null or contact.is_empty():
		return
	var collider := contact.get("collider") as Node
	if not is_instance_valid(collider):
		collider = null
	var surface: String = vfx.call("surface_for", collider)
	vfx.call("impact", contact["position"], contact["normal"], surface, power, color)
	if surface == "shield" and collider != null and collider.name == "MagneticField":
		get_node("/root/GameSfx").play_event("magnetic_absorb")
	elif surface != "robot" and surface != "shield":
		get_node("/root/GameSfx").play_event("impact_decor")


func _create_surface_impact_fx(origin: Vector3, direction: Vector3, color: Color = Color("#ff9c52")) -> void:
	var normal := direction.normalized() if direction.length_squared() > 0.001 else Vector3.UP
	_contact_fx(_visual_contact(origin + normal * 0.15, origin - normal * 0.15), color)


func _finalize_passive_death() -> void:
	if combat_state == null or combat_state.is_dead():
		return
	combat_state.apply_damage(combat_state.health, "baroud", "baroud:expiry")
	if _attack_label != null:
		_attack_label.text = "ÉLIMINÉ"


func _on_state_died() -> void:
	if not _gameplay_enabled:
		return
	if _status_vfx != null:
		_status_vfx.call("clear")
	_round_warmup_active = false
	_play_player_animation(&"fall", 0.10)
	_gameplay_enabled = false
	_update_aim_pose_state()
	clear_touch_inputs()
	_clear_defensive_buffer()
	_cancel_fulguro_projection()
	_cancel_fulguro_attack()
	_cancel_pelto_smash()
	_cancel_pelto_pull()
	_cancel_blaster_charge()
	_cancel_shotgun_attack()
	_cancel_axe_attack()
	_cancel_pending_module_action()
	_static_pulse_token += 1
	_reset_action_ownership()
	died.emit()


func is_real_dead() -> bool:
	return (passive_state != null and passive_state.real_dead) or (combat_state != null and combat_state.is_dead())


func apply_loadout(next_loadout: Dictionary) -> void:
	if survival_evolution_effects != null:
		survival_evolution_effects.clear_transients()
		survival_evolution_effects.queue_free()
		survival_evolution_effects = null
	if survival_synergies != null:
		survival_synergies.configure({})
	survival_mode = false
	_survival_evolutions = {"weapon": false, "offensive": false, "defensive": false, "mobility": false, "passive": false}
	set_robot(str(next_loadout.get("robot", COMBAT_DATA.DEFAULT_ROBOT)))
	_survival_cooldown_multipliers = {"offensive": 1.0, "defensive": 1.0, "mobility": 1.0}
	_survival_dash_multiplier = 1.0
	_load_weapon_definitions()
	if passive_state != null:
		passive_state.baroud_max_health = PASSIVE_STATE.BAROUD_MAX_HEALTH
		passive_state.baroud_duration = PASSIVE_STATE.BAROUD_DURATION
		passive_state.omnivamp_rate = PASSIVE_STATE.OMNIVAMP_RATE
	var weapon_id := str(next_loadout.get("weapon", "blaster"))
	var offensive_id := str(next_loadout.get("offensive", "modulo_drone"))
	var defensive_id := str(next_loadout.get("defensive", "magnetic_field"))
	var mobility_id := str(next_loadout.get("mobility", "pyro_boots"))
	var passive_id := str(next_loadout.get("passive", "baroud"))
	_offensive_module_id = offensive_id if offensive_id in ["modulo_drone", "javelin", "fulguro_punch", "pelto_smash"] else "modulo_drone"
	_defensive_module_id = defensive_id if defensive_id in ["magnetic_field", "static_shield"] else "magnetic_field"
	_mobility_module_id = mobility_id if mobility_id in ["pyro_boots", "bio_injector"] else "pyro_boots"
	set_passive(passive_id)
	cancel_touch_fire()
	reset_shotgun_state()
	_weapon_id = "shotgun" if weapon_id == "shotgun" else "blaster"
	_update_weapon_visuals()
	_sync_weapon_readout()

func set_robot(identifier: String) -> void:
	_robot_id = identifier if COMBAT_DATA.ROBOT_DEFINITIONS.has(identifier) else COMBAT_DATA.DEFAULT_ROBOT
	if _visual_rig != null:
		_visual_rig.set_chassis_appearance(_robot_id)
	var definition: Dictionary = COMBAT_DATA.ROBOT_DEFINITIONS[_robot_id]
	move_speed = float(definition.move_speed)
	if combat_state != null:
		var health_ratio: float = combat_state.health / maxf(1.0, combat_state.max_health)
		combat_state.max_health = float(definition.max_health)
		combat_state.health = clampf(health_ratio, 0.0, 1.0) * combat_state.max_health
		combat_state.health_changed.emit(combat_state.health, combat_state.max_health)

func get_robot_id() -> String:
	return _robot_id

func configure_survival_build(build: Dictionary) -> void:
	if survival_synergies == null:
		survival_synergies = preload("res://scripts/survival_synergies.gd").new()
		survival_synergies.player = self
		add_child(survival_synergies)
	survival_synergies.configure(build)
	_load_weapon_definitions()
	survival_mode = true
	_survival_evolutions = build.get("evolutions", {}).duplicate(true)
	_weapon_id = str(build.get("weapon", "blaster"))
	_offensive_module_id = str(build.get("offensive", ""))
	_defensive_module_id = str(build.get("defensive", ""))
	_mobility_module_id = str(build.get("mobility", ""))
	set_passive(str(build.get("passive", "")))
	var ranks: Dictionary = build.get("upgrades", {})
	var weapon_ranks: Dictionary = ranks.get("weapon", {})
	var weapon_power := 0.65 + 0.60 * int(weapon_ranks.get("power", 0))
	var weapon_tempo := 1.20 * pow(0.72, int(weapon_ranks.get("tempo", 0)))
	_blaster_damage *= weapon_power
	_blaster_max_damage *= weapon_power
	_blaster_cooldown *= weapon_tempo
	# Survival needs a reliable ranged opening alongside the close-range shotgun.
	_blaster_damage *= 1.6
	_blaster_max_damage *= 2.0
	_blaster_cooldown *= 0.82
	_blaster_charge_time *= 0.70
	_blaster_charge_slow_multiplier = 1.0
	_blaster_projectile_speed *= 1.35
	_shotgun_pellet_damage *= weapon_power
	_shotgun_minimum_damage *= weapon_power
	_shotgun_recovery *= weapon_tempo
	_shotgun_reload_duration *= weapon_tempo
	if int(build.get("aspects", {}).get("weapon", {}).get("rank", 0)) == 0 and bool(_survival_evolutions.get("weapon", false)) and _weapon_id == "shotgun":
		_shotgun_pellet_angles = [-16.0, -12.0, -8.0, -4.0, 4.0, 8.0, 12.0, 16.0]
	var offensive_ranks: Dictionary = ranks.get("offensive", {})
	var offensive_power := 0.65 + 0.60 * int(offensive_ranks.get("power", 0))
	_drone_damage *= offensive_power
	_javelin_damage *= offensive_power
	_fulguro_damage *= offensive_power
	_fulguro_wall_damage *= offensive_power
	_pelto_damage_multiplier = offensive_power
	_drone_burn_duration *= offensive_power
	var defensive_ranks: Dictionary = ranks.get("defensive", {})
	var defensive_power := 0.70 + 0.55 * int(defensive_ranks.get("power", 0))
	_magnetic_duration *= defensive_power
	_static_duration *= defensive_power
	var mobility_ranks: Dictionary = ranks.get("mobility", {})
	var mobility_power := 0.70 + 0.55 * int(mobility_ranks.get("power", 0))
	_survival_dash_multiplier = mobility_power
	_bio_speed_multiplier = 1.0 + 0.40 * mobility_power
	_bio_attack_speed_multiplier = 1.0 + 0.50 * mobility_power
	var passive_ranks: Dictionary = ranks.get("passive", {})
	var passive_power := 0.65 + 0.60 * int(passive_ranks.get("power", 0))
	if combat_state != null:
		combat_state.max_health = float(COMBAT_DATA.ROBOT_DEFINITIONS[_robot_id].max_health) + 250.0 * int(passive_ranks.get("tempo", 0))
		combat_state.health_changed.emit(combat_state.health, combat_state.max_health)
	if passive_state != null:
		passive_state.baroud_max_health = PASSIVE_STATE.BAROUD_MAX_HEALTH * passive_power
		passive_state.baroud_duration = PASSIVE_STATE.BAROUD_DURATION * passive_power
		passive_state.omnivamp_rate = PASSIVE_STATE.OMNIVAMP_RATE * passive_power
	_survival_cooldown_multipliers = {
		"offensive": 1.25 * pow(0.65, int(offensive_ranks.get("tempo", 0))),
		"defensive": 1.25 * pow(0.65, int(defensive_ranks.get("tempo", 0))),
		"mobility": 1.25 * pow(0.65, int(mobility_ranks.get("tempo", 0))),
	}
	reset_blaster_state()
	reset_shotgun_state()
	reset_module_state()
	_reset_action_ownership()
	_update_weapon_visuals()
	if survival_evolution_effects == null:
		survival_evolution_effects = preload("res://scripts/survival_evolution_effects.gd").new()
		survival_evolution_effects.player = self
		add_child(survival_evolution_effects)
	survival_evolution_effects.configure(build)
	_sync_weapon_readout()

func set_training_options(invulnerable: bool, instant_cooldowns: bool, unlimited_ammo: bool) -> void:
	training_invulnerable = invulnerable
	training_instant_cooldowns = instant_cooldowns
	training_unlimited_ammo = unlimited_ammo
	if instant_cooldowns:
		_module_cooldowns.clear()
		_blaster_next_attack_ready_at = -10.0
	if unlimited_ammo:
		_shotgun_ammo = _shotgun_magazine_size
		_shotgun_reloading = false
		_shotgun_reload_remaining = 0.0
		if _shotgun_reload_audio != null:
			_shotgun_reload_audio.stop()

func set_training_health_ratio(ratio: float) -> void:
	if combat_state == null:
		return
	reset_combat_state()
	combat_state.health = clampf(ratio, 0.01, 1.0) * combat_state.max_health
	combat_state.health_changed.emit(combat_state.health, combat_state.max_health)


func shift_pause_timers(seconds: float) -> void:
	if seconds <= 0.0:
		return
	_last_attack_time += seconds
	_blaster_next_attack_ready_at += seconds
	if _combo_expires_at > 0.0:
		_combo_expires_at += seconds
	if _next_attack_ready_at > 0.0:
		_next_attack_ready_at += seconds
	if _javelin_mark_target != null and is_instance_valid(_javelin_mark_target):
		if _javelin_mark_target.has_method("shift_pause_timers"):
			_javelin_mark_target.call("shift_pause_timers", seconds)


func _update_baroud_presentation() -> void:
	if _baroud_bar_bg == null or _baroud_bar_fill == null or passive_state == null:
		return
	var visible: bool = bool(passive_state.baroud_active)
	_baroud_bar_bg.visible = visible
	_baroud_bar_fill.visible = visible
	if not visible:
		return
	var fraction: float = clampf(float(passive_state.baroud_health) / maxf(1.0, float(passive_state.baroud_max_health)), 0.0, 1.0)
	var width: float = 1.8 * fraction
	_baroud_bar_fill.scale = Vector3(width, 1.0, 1.0)
	_baroud_bar_fill.position.x = -0.9 + width * 0.5


func _update_world_ui_anchor() -> void:
	if _world_ui_anchor != null:
		# Keep the world-space UI above the robot while ignoring the player's aim
		# yaw, recoil and attack animation transforms.
		_world_ui_anchor.global_position = global_position


func set_passive(passive_id: String) -> void:
	_passive_id = passive_id if passive_id in ["baroud", "omnivamp"] else ""
	if passive_state != null:
		passive_state.configure(_passive_id)


func get_passive_id() -> String:
	return _passive_id


func get_baroud_remaining() -> float:
	return passive_state.baroud_remaining if passive_state != null else 0.0


func get_baroud_health() -> float:
	return passive_state.baroud_health if passive_state != null else 0.0


func _on_damage_dealt(effective_damage: float, target: Node3D = null) -> void:
	if passive_state == null:
		return
	if survival_mode and survival_evolution_effects != null:
		survival_evolution_effects.dealt_damage(effective_damage, target)
	var amount: float = float(passive_state.omnivamp_heal_for(effective_damage))
	if amount > 0.0:
		var actual := heal(amount, "omnivamp")
		if survival_mode and survival_evolution_effects != null:
			survival_evolution_effects.overflow_heal(amount - actual)


func get_health() -> float:
	return combat_state.health if combat_state != null else 0.0


func get_max_health() -> float:
	return combat_state.max_health if combat_state != null else COMBAT_DATA.MAX_HEALTH


func get_active_effect_types() -> Array[String]:
	return combat_state.get_active_effect_types() if combat_state != null else []


func _on_health_changed(current: float, maximum: float) -> void:
	if _health_readout != null:
		_health_readout.call("set_health", current, maximum)


func _on_damage_applied(amount: float, _source_id: String, _attack_id: String) -> void:
	if not _external_damage_pending:
		effective_damage_taken.emit(amount, _source_id, _attack_id)
	if _health_readout != null:
		_health_readout.call("show_damage", amount)


func _on_healing_applied(amount: float, _source_id: String) -> void:
	if _health_readout != null and _health_readout.has_method("show_healing"):
		_health_readout.call("show_healing", amount)
	if _attack_label != null:
		_attack_label.text = "SOIN  •  +%d PV" % roundi(amount)
	_spawn_particle_burst(global_position + Vector3.UP * 1.05, Color("#72f0a5"), 10, 0.32, 2.2, 0.10, Vector3.UP, 58.0)


func heal(amount: float, source_id: String = "") -> float:
	if _stasis_remaining > 0.0 or passive_state == null or not passive_state.can_heal():
		return 0.0
	return combat_state.heal(amount, source_id) if combat_state != null else 0.0


func apply_burn(duration: float = COMBAT_DATA.BURN_DURATION, damage_per_second: float = COMBAT_DATA.BURN_DAMAGE_PER_SECOND, source_id: String = "") -> void:
	if combat_state != null:
		combat_state.apply_burn(duration, damage_per_second, source_id)


func apply_slow(duration: float, percent: float, source_id: String = "") -> void:
	if combat_state != null:
		combat_state.apply_slow(duration, percent, source_id)


func apply_stun(duration: float, source_id: String = "") -> void:
	if duration > 0.0 and _fulguro_phase != "":
		_cancel_fulguro_attack("FULGURO PUNCH  •  INTERROMPU")
	if duration > 0.0 and _pelto_phase != "":
		_cancel_pelto_smash("PELTO SMASH  •  INTERROMPU")
	if duration > 0.0:
		_cancel_pelto_pull()
		_cancel_pending_module_action("MODULE  •  INTERROMPU")
		_cancel_blaster_charge()
		_cancel_blaster_attack()
		_cancel_shotgun_attack()
		_cancel_axe_attack()
	if combat_state != null:
		combat_state.apply_stun(duration, source_id)


func apply_spotted(duration: float, source_id: String = "") -> void:
	if combat_state != null:
		combat_state.apply_spotted(duration, source_id)
	if visibility_state != null:
		visibility_state.mark_spotted(duration)


func reset_combat_state() -> void:
	_received_attack_ids.clear()
	clear_touch_inputs()
	_clear_defensive_buffer()
	_cancel_fulguro_projection()
	_cancel_fulguro_attack()
	_cancel_pelto_smash()
	_cancel_pelto_pull()
	if _status_vfx != null:
		_status_vfx.call("clear")
	if _health_readout != null:
		_health_readout.call("clear_damage_numbers")
	if combat_state != null:
		combat_state.reset()
	if passive_state != null:
		passive_state.configure(_passive_id)
		passive_state.reset()
	if visibility_state != null:
		visibility_state.reset()
	_current_bush = _find_bush_at_position()
	_current_bush_name = str(_current_bush.name) if _current_bush != null else ""
	_bush_transition_clock = 0.0
	reset_blaster_state()
	reset_shotgun_state()
	reset_module_state()
	_reset_action_ownership()
	_on_health_changed(get_health(), get_max_health())
	_start_round_warmup_animation()


func reset_blaster_state() -> void:
	_blaster_attack_token += 1
	_blaster_attack_busy = false
	_blaster_next_attack_ready_at = -10.0
	_attack_hold_last = false
	_desktop_blaster_tap_buffered = false
	cancel_touch_fire()
	_action_gate.release(_blaster_action_token)
	_blaster_action_token = 0


func set_weapon(weapon_id: String) -> void:
	if survival_mode:
		return
	if weapon_id != "blaster" and weapon_id != "shotgun":
		return
	if _weapon_id == weapon_id:
		return
	reset_blaster_state()
	reset_shotgun_state()
	_weapon_id = weapon_id
	_reset_weapon_pose_to_locomotion(true)
	_update_weapon_visuals()
	_sync_weapon_readout()
	if _attack_label != null:
		_attack_label.text = "ARME : BLASTER" if _weapon_id == "blaster" else ""


func get_offensive_module_id() -> String:
	return _offensive_module_id


func _cycle_offensive_module() -> void:
	var choices := ["modulo_drone", "javelin", "fulguro_punch", "pelto_smash"]
	_offensive_module_id = choices[(choices.find(_offensive_module_id) + 1) % choices.size()]
	if _attack_label != null:
		_attack_label.text = "OFFENSIF : %s" % _offensive_module_id.replace("_", " ").to_upper()


func _perform_offensive_module() -> void:
	if _offensive_module_id == "" or _action_gate.is_kind(ACTION_GATE.Kind.MODULE):
		return
	if _offensive_module_id == "javelin" and _can_buffer_defensive_action() and _has_live_javelin_mark():
		_buffer_javelin_recast()
		return
	if _offensive_module_id == "javelin":
		_perform_javelin()
	elif _offensive_module_id == "fulguro_punch":
		_perform_fulguro_punch()
	elif _offensive_module_id == "pelto_smash":
		_perform_pelto_smash()
	else:
		_perform_modulo_drone()


func _activate_defensive_module() -> void:
	if _action_gate.is_kind(ACTION_GATE.Kind.MODULE):
		return
	_perform_defensive_module()


func _activate_mobility_module() -> void:
	if _action_gate.is_kind(ACTION_GATE.Kind.MODULE):
		return
	if _can_buffer_defensive_action() and _mobility_module_id == "pyro_boots":
		_buffer_dash()
		return
	_perform_mobility_module()


func get_weapon_id() -> String:
	return _weapon_id


func get_shotgun_ammo() -> int:
	return _shotgun_ammo


func get_shotgun_magazine_size() -> int:
	return _shotgun_magazine_size


func get_shotgun_reload_progress() -> float:
	if not _shotgun_reloading:
		return 0.0
	return 1.0 - _shotgun_reload_remaining / maxf(0.001, _shotgun_reload_duration)


func is_shotgun_reloading() -> bool:
	return _shotgun_reloading


func reset_shotgun_state() -> void:
	_shotgun_attack_token += 1
	_shotgun_reload_token += 1
	_shotgun_attack_busy = false
	_shotgun_attack_emitted = false
	_action_gate.release(_shotgun_action_token)
	_shotgun_action_token = 0
	_shotgun_reloading = false
	_shotgun_reload_remaining = 0.0
	_shotgun_ammo = _shotgun_magazine_size
	_kill_weapon_recoil_tweens(_shotgun_recoil_tweens)
	if _shotgun_recoil_pivot != null:
		_shotgun_recoil_pivot.transform = Transform3D.IDENTITY
	if _shotgun_light != null:
		_shotgun_light.light_energy = 0.0
	if _shotgun_shot_audio != null:
		_shotgun_shot_audio.stop()
	if _shotgun_cycle_audio != null:
		_shotgun_cycle_audio.stop()
	if _shotgun_reload_audio != null:
		_shotgun_reload_audio.stop()
		_shotgun_reload_audio.stream_paused = false


func reset_module_state() -> void:
	_module_token += 1
	_javelin_launch_token += 1
	_static_pulse_token += 1
	_module_cooldowns.clear()
	_module_busy = false
	_cancel_fulguro_attack()
	_cancel_pelto_smash()
	_cancel_fulguro_projection()
	_cancel_pelto_pull()
	_clear_defensive_buffer()
	for wave in _pelto_waves:
		if wave != null and is_instance_valid(wave):
			wave.queue_free()
	_pelto_waves.clear()
	_javelin_mark_target = null
	_dash_token += 1
	_dash_active = false
	_dash_direction = Vector3.ZERO
	_dash_elapsed = 0.0
	_bio_remaining = 0.0
	_stasis_remaining = 0.0
	if is_instance_valid(_stasis_visual):
		_stasis_visual.queue_free()
	_stasis_visual = null
	if _magnetic_wall != null and is_instance_valid(_magnetic_wall):
		_magnetic_wall.queue_free()
	_magnetic_wall = null
	if _active_module_action_token != 0:
		_end_module_action(_active_module_action_token, _active_module_id)


func _update_shotgun_reload_input() -> void:
	if _weapon_id == "shotgun" and _pressed_action_once("reload"):
		_start_shotgun_reload()


func _update_shotgun_attack(wants_to_attack: bool) -> void:
	if _shotgun_reloading or _shotgun_attack_busy:
		return
	if _shotgun_ammo <= 0:
		_start_shotgun_reload()
		return
	if wants_to_attack:
		_perform_shotgun_attack()


func _perform_shotgun_attack() -> void:
	if _shotgun_reloading or _shotgun_attack_busy:
		return
	if _shotgun_ammo <= 0:
		_start_shotgun_reload()
		return
	var action_token := _try_begin_weapon_action("shotgun")
	if action_token == 0:
		return
	_shotgun_action_token = action_token
	_shotgun_attack_emitted = false
	_mark_combat_event()
	_begin_weapon_aim()
	_shotgun_attack_token += 1
	var token := _shotgun_attack_token
	_shotgun_attack_busy = true
	if not training_unlimited_ammo:
		_shotgun_ammo -= 1
	_shotgun_attack_origin = global_position
	_shotgun_attack_direction = aim_direction.normalized()
	var attack_speed := get_attack_speed_multiplier()
	# Preparation keeps the live aim pose; kick/flash start with pellet emission.
	_attack_label.text = "SHOTGUN  •  %d/%d CARTOUCHES" % [_shotgun_ammo, _shotgun_magazine_size]
	var salvo := {
		"id": token,
		"action_token": action_token,
		"hits_by_target": {},
		"credited": {},
	}
	var emission_timer := get_tree().create_timer(_shotgun_preparation / attack_speed, false, false, false)
	emission_timer.timeout.connect(func() -> void: _emit_shotgun_salvo(token, salvo))
	var finish_timer := get_tree().create_timer((_shotgun_preparation + (0.01 if training_instant_cooldowns else _shotgun_recovery)) / attack_speed, false, false, false)
	finish_timer.timeout.connect(func() -> void: _finish_shotgun_attack(token))


func _play_shotgun_animation(speed_scale: float) -> void:
	_kill_weapon_recoil_tweens(_shotgun_recoil_tweens)
	if _shotgun_recoil_pivot != null:
		_shotgun_recoil_pivot.transform = Transform3D.IDENTITY
	if _has_skeletal_weapon_attachment():
		_update_aim_pose_state()
		# The same shoulder/arm impulse as a charged blaster, with both hands attached.
		_visual_rig.play_shot_kick(1.0)
	elif _shotgun_recoil_pivot != null:
		var duration_scale := maxf(0.5, speed_scale)
		var kick := create_tween().set_parallel(true)
		kick.tween_property(_shotgun_recoil_pivot, "position", Vector3(0.0, 0.0, 0.07), 0.05 / duration_scale)
		kick.tween_property(_shotgun_recoil_pivot, "rotation", Vector3(deg_to_rad(2.0), 0.0, 0.0), 0.05 / duration_scale)
		kick.chain().tween_property(_shotgun_recoil_pivot, "position", Vector3.ZERO, 0.12 / duration_scale)
		kick.parallel().tween_property(_shotgun_recoil_pivot, "rotation", Vector3.ZERO, 0.12 / duration_scale)
		_shotgun_recoil_tweens.append(kick)
	if _shotgun_light != null:
		_shotgun_light.light_energy = 0.0
	_camera_impulse(0.105, 0.085)


func _emit_shotgun_salvo(token: int, salvo: Dictionary) -> void:
	var echo := bool(salvo.get("echo", false))
	var action_token := int(salvo.get("action_token", 0))
	if not _gameplay_enabled or (not echo and (token != _shotgun_attack_token or not _shotgun_attack_busy)):
		return
	if not _action_gate.owns(action_token, ACTION_GATE.Kind.WEAPON, "shotgun"):
		return
	if echo and (survival_synergies == null or int(salvo.get("generation", -1)) != survival_synergies.generation):
		return
	if combat_state != null and combat_state.is_stunned():
		_cancel_shotgun_attack()
		return
	# Commit every input scheme from the same live source of truth at emission.
	_shotgun_attack_origin = global_position
	_shotgun_attack_direction = _normalized_aim_direction()
	_shotgun_attack_emitted = true
	_last_projectile_direction = _shotgun_attack_direction
	_begin_weapon_fire()
	if _has_skeletal_weapon_attachment():
		# The preparation timer runs after physics. Read the next final skeletal
		# pose, not the lowered attachment left by the preceding tick.
		await _visual_rig.skeleton.skeleton_updated
		if not _gameplay_enabled or not _action_gate.owns(action_token, ACTION_GATE.Kind.WEAPON, "shotgun") or (not echo and token != _shotgun_attack_token):
			return
		_shotgun_attack_direction = _visual_rig.get_aim_forward_direction()
		_last_projectile_direction = _shotgun_attack_direction
	_shotgun_shot_audio.play()
	var cycle_timer := get_tree().create_timer(0.26 / get_attack_speed_multiplier(), true, false, false)
	cycle_timer.timeout.connect(func() -> void: _play_shotgun_cycle_audio(token))
	var visual_start := _shotgun_muzzle.global_position if _shotgun_muzzle != null else _shotgun_attack_origin + Vector3.UP * 0.85 + _shotgun_attack_direction * 0.45
	visual_start = _safe_projectile_origin(visual_start)
	_create_muzzle_burst(visual_start, _shotgun_attack_direction, Color("#ff9d4e"), 1.35, _shotgun_muzzle)
	# Spread is symmetric around the evaluated barrel/aim axis, at every range.
	var center_direction := _shotgun_attack_direction
	for index in range(_shotgun_pellet_angles.size()):
		var angle := deg_to_rad(float(_shotgun_pellet_angles[index]))
		var direction := center_direction.rotated(Vector3.UP, angle).normalized()
		var endpoint := visual_start + direction * _shotgun_max_range
		if _show_debug_hitbox:
			_create_lightning_arc(visual_start, endpoint, Color("#ffc56e"), 0.025, 0.45)
		_spawn_shotgun_projectile(visual_start, endpoint, salvo, index)
	if not echo and survival_mode and survival_evolution_effects != null:
		survival_evolution_effects.shotgun_salvo(visual_start, _shotgun_attack_direction)
	_play_shotgun_animation(get_attack_speed_multiplier())
	if not echo and survival_synergies != null and survival_synergies.consume_double():
		var second := {"id": token, "action_token": action_token, "hits_by_target": {}, "credited": {}, "echo": true, "generation": survival_synergies.generation, "source": "double", "damage_scale": 0.65 if bool(survival_synergies.evolved.get("mobility", false)) else 0.45}
		get_tree().create_timer(0.16, false).timeout.connect(func() -> void: _emit_shotgun_salvo(token, second))


func _play_shotgun_cycle_audio(token: int) -> void:
	if token == _shotgun_attack_token and _weapon_id == "shotgun":
		_shotgun_cycle_audio.play()


func _spawn_shotgun_projectile(start: Vector3, endpoint: Vector3, salvo: Dictionary, index: int) -> void:
	var projectile := LIVE_PROJECTILE.new()
	projectile.name = "ShotgunPellet"
	projectile.process_mode = Node.PROCESS_MODE_PAUSABLE
	get_tree().current_scene.add_child(projectile)
	projectile.add_to_group("prototype0_gameplay_projectiles")
	projectile.global_position = start
	var direction := endpoint - start
	direction = direction.normalized() if direction.length_squared() > 0.001 else _shotgun_attack_direction
	projectile.look_at(start + direction, Vector3.UP)
	var excluded: Array[RID] = [get_rid()]
	if survival_mode and survival_evolution_effects != null:
		excluded.append_array(survival_evolution_effects.own_wall_exclusions())
	projectile.configure(direction, _shotgun_pellet_speed, _shotgun_max_range, 1 | 2 | 8, excluded)
	projectile.finished.connect(_on_shotgun_pellet_finished.bind(salvo, index))
	var vfx := _vfx_manager()
	if vfx != null:
		vfx.call("projectile_visual", projectile, "shotgun", 0.0)
		if index % 2 == 0:
			vfx.call("tracer", start, start + direction * 2.2, 0.055, Color("#ffc077"), 0.11)


func _on_shotgun_pellet_finished(hit: Dictionary, distance: float, salvo: Dictionary, index: int) -> void:
	if hit.is_empty():
		return
	var target := hit.get("collider") as Node
	if target != null and target.has_method("take_damage") and target.has_method("get_health"):
		_resolve_shotgun_projectile(salvo, index, true, target, distance)
	# Three readable impact clusters communicate the six-pellet spread.
	if index % 2 == 0:
		_contact_fx(hit, Color("#e39a54"), 0.72)

func _resolve_shotgun_projectile(salvo: Dictionary, index: int, did_hit: bool, target: Node, distance: float) -> void:
	if not did_hit or target == null or not is_instance_valid(target):
		return
	var projectile_id := "%s:%d:%d" % [str(salvo.get("source", "shotgun")), int(salvo["id"]), index]
	var credited: Dictionary = salvo["credited"]
	if credited.has(projectile_id):
		return
	credited[projectile_id] = true
	var damage := _shotgun_damage_at_distance(distance) * float(salvo.get("damage_scale", 1.0))
	var effective_damage := float(target.call("take_damage", damage, "player", projectile_id))
	if effective_damage <= 0.0:
		return
	if survival_mode and survival_evolution_effects != null:
		survival_evolution_effects.shotgun_hit(target, salvo)
	var hits_by_target: Dictionary = salvo["hits_by_target"]
	var target_id := target.get_instance_id()
	var tally: Dictionary = hits_by_target.get(target_id, {"valid_hits": 0, "base_damage_sum": 0.0, "critical_applied": false})
	tally["valid_hits"] = int(tally["valid_hits"]) + 1
	tally["base_damage_sum"] = float(tally["base_damage_sum"]) + damage
	hits_by_target[target_id] = tally
	_create_target_hit_fx(target.global_position, false)
	target.call("flash_impact", false)
	if int(tally["valid_hits"]) == _shotgun_pellet_angles.size() and not bool(tally["critical_applied"]):
		tally["critical_applied"] = true
		var bonus := float(tally["base_damage_sum"]) * (CRIT_MULTIPLIER - 1.0)
		var bonus_id := "%s:%d:critical:%d" % [str(salvo.get("source", "shotgun")), int(salvo["id"]), target_id]
		target.call("take_damage", bonus, "player", bonus_id)
		target.call("apply_burn", COMBAT_DATA.BURN_DURATION, COMBAT_DATA.BURN_DAMAGE_PER_SECOND * float(salvo.get("damage_scale", 1.0)), "player:" + str(salvo.get("source", "shotgun")))
		target.call("flash_impact", true)


func _shotgun_damage_at_distance(distance: float) -> float:
	if distance <= _shotgun_falloff_start:
		return _shotgun_pellet_damage
	var ratio := clampf((distance - _shotgun_falloff_start) / maxf(0.001, _shotgun_max_range - _shotgun_falloff_start), 0.0, 1.0)
	return lerpf(_shotgun_pellet_damage, _shotgun_minimum_damage, ratio)


func _finish_shotgun_attack(token: int) -> void:
	if token != _shotgun_attack_token or not _shotgun_attack_busy:
		return
	_shotgun_attack_busy = false
	_shotgun_attack_emitted = false
	_action_gate.release(_shotgun_action_token)
	_shotgun_action_token = 0
	_begin_aim_hold()
	if _shotgun_ammo <= 0:
		_start_shotgun_reload()


func _cancel_shotgun_attack() -> void:
	if not _shotgun_attack_busy:
		_action_gate.release(_shotgun_action_token)
		_shotgun_action_token = 0
		return
	_shotgun_attack_token += 1
	if not _shotgun_attack_emitted and not training_unlimited_ammo:
		_shotgun_ammo = mini(_shotgun_magazine_size, _shotgun_ammo + 1)
	_shotgun_attack_busy = false
	_shotgun_attack_emitted = false
	_action_gate.release(_shotgun_action_token)
	_shotgun_action_token = 0
	_shotgun_cycle_audio.stop()
	_attack_label.text = ""


func _start_shotgun_reload() -> void:
	if _shotgun_reloading or _shotgun_ammo >= _shotgun_magazine_size:
		return
	_shotgun_reloading = true
	_shotgun_reload_token += 1
	_shotgun_reload_remaining = _shotgun_reload_duration
	_shotgun_reload_audio.stream_paused = false
	_shotgun_reload_audio.play()
	_attack_label.text = ""


func _update_shotgun_reload(delta: float) -> void:
	if not _shotgun_reloading:
		return
	_shotgun_reload_audio.stream_paused = _stasis_remaining > 0.0
	if _stasis_remaining > 0.0:
		return
	_shotgun_reload_remaining = maxf(0.0, _shotgun_reload_remaining - delta * (get_attack_speed_multiplier() if survival_mode else 1.0))
	if _shotgun_reload_remaining > 0.0:
		return
	_shotgun_ammo = _shotgun_magazine_size
	_shotgun_reloading = false
	_attack_label.text = ""


func _update_shotgun_reload_visual() -> void:
	if not _shotgun_reloading or _shotgun_pivot == null or _weapon_id != "shotgun":
		return
	var phase := get_shotgun_reload_progress()
	var lift := sin(phase * PI)
	_shotgun_pivot.position = Vector3(0.58, 0.88 + 0.14 * lift, -0.36 + 0.12 * lift)
	_shotgun_pivot.rotation = Vector3(-0.22 * lift, 0.0, 0.12 * lift)


func _sync_weapon_readout() -> void:
	if _health_readout == null:
		return
	_health_readout.call("set_shotgun_ammo", _weapon_id == "shotgun", _shotgun_ammo, _shotgun_magazine_size, _shotgun_reloading, get_shotgun_reload_progress())
	_health_readout.call("set_blaster_charge", _weapon_id == "blaster", _blaster_charge_active, get_blaster_charge_ratio())


func _update_javelin_mark() -> void:
	if _javelin_mark_target == null or not is_instance_valid(_javelin_mark_target):
		_javelin_mark_target = null
		return
	if not bool(_javelin_mark_target.call("has_javelin_mark")):
		_javelin_mark_target = null


func get_javelin_recast_fraction() -> float:
	if survival_mode and survival_evolution_effects != null:
		return survival_evolution_effects.javelin_fraction()
	if _javelin_mark_target == null or not is_instance_valid(_javelin_mark_target):
		return 0.0
	if not _javelin_mark_target.has_method("get_javelin_mark_remaining"):
		return 0.0
	var remaining := float(_javelin_mark_target.call("get_javelin_mark_remaining"))
	return clampf(remaining / maxf(0.001, _javelin_mark_duration), 0.0, 1.0)


func _update_module_cooldowns(delta: float) -> void:
	var bio_active := _bio_remaining > 0.0
	if bio_active:
		_bio_remaining = maxf(0.0, _bio_remaining - delta)
	for module_id in _module_cooldowns.keys():
		var rate := _bio_other_cooldown_rate if bio_active and module_id != "bio_injector" else 1.0
		_module_cooldowns[module_id] = maxf(0.0, float(_module_cooldowns[module_id]) - delta * rate)


func get_module_cooldown(module_id: String) -> float:
	if training_instant_cooldowns:
		return 0.0
	return maxf(0.0, float(_module_cooldowns.get(module_id, 0.0)))


func is_module_busy() -> bool:
	return _action_gate.is_kind(ACTION_GATE.Kind.MODULE)


func _module_ready(module_id: String) -> bool:
	return get_module_cooldown(module_id) <= 0.0


func _start_module_cooldown(module_id: String, duration: float) -> void:
	var category := "offensive" if module_id in ["modulo_drone", "javelin", "fulguro_punch", "pelto_smash"] else "defensive" if module_id in ["magnetic_field", "static_shield"] else "mobility"
	_module_cooldowns[module_id] = 0.0 if training_instant_cooldowns else maxf(0.0, duration * float(_survival_cooldown_multipliers.get(category, 1.0)))


func get_mobility_module_id() -> String:
	return _mobility_module_id


func get_defensive_module_id() -> String:
	return _defensive_module_id


func get_stasis_remaining() -> float:
	return _stasis_remaining


func _perform_defensive_module() -> void:
	if _defensive_module_id == "":
		return
	if _defensive_module_id == "static_shield":
		_perform_static_shield()
	else:
		_perform_magnetic_field()


func _perform_magnetic_field() -> void:
	if survival_mode and survival_evolution_effects != null and _stasis_remaining <= 0.0 and (combat_state == null or not combat_state.is_stunned()) and survival_evolution_effects.release_wall():
		return
	if _stasis_remaining > 0.0 or _fulguro_projection_active or not _module_ready("magnetic_field") or (combat_state != null and combat_state.is_stunned()):
		return
	var direction := aim_direction.normalized()
	var origin := global_position
	var center := origin + direction * _magnetic_distance
	if not _magnetic_placement_valid(origin, center):
		if _attack_label != null:
			_attack_label.text = "MAGNETIC FIELD  •  PLACEMENT REFUSÉ"
		return
	var action_token := _try_begin_module_action("magnetic_field")
	if action_token == 0:
		return
	_mark_combat_event()
	_module_busy = true
	_module_token += 1
	var token := _module_token
	_start_module_cooldown("magnetic_field", float(COMBAT_DATA.MODULE_DEFINITIONS["magnetic_field"]["cooldown"]))
	if _attack_label != null:
		_attack_label.text = "MAGNETIC FIELD  •  PRÉPARATION"
	var timer := get_tree().create_timer(_magnetic_preparation, true, false, false)
	timer.timeout.connect(func() -> void: _create_magnetic_wall(token, action_token, center, direction))


func _magnetic_placement_valid(origin: Vector3, center: Vector3) -> bool:
	if absf(center.x) > 23.0 or absf(center.z) > 23.0:
		return false
	var world := get_world_3d()
	if world == null:
		return true
	var query := PhysicsRayQueryParameters3D.create(origin + Vector3.UP * 0.72, center + Vector3.UP * 0.72)
	query.collision_mask = 1
	query.collide_with_areas = false
	query.collide_with_bodies = true
	query.exclude = [get_rid()]
	return world.direct_space_state.intersect_ray(query).is_empty()


func _create_magnetic_wall(token: int, action_token: int, center: Vector3, direction: Vector3) -> void:
	if token != _module_token or not _module_action_can_execute(action_token, "magnetic_field"):
		return
	var wall := Area3D.new()
	wall.name = "MagneticField"
	wall.collision_layer = 8
	wall.collision_mask = 0
	wall.monitoring = false
	wall.monitorable = true
	var collision := CollisionShape3D.new()
	collision.name = "CollisionShape3D"
	var shape := BoxShape3D.new()
	shape.size = Vector3(_magnetic_width, _magnetic_height, 0.14)
	collision.shape = shape
	collision.position.y = _magnetic_height * 0.5
	wall.add_child(collision)
	var visual := MeshInstance3D.new()
	var visual_mesh := BoxMesh.new()
	visual_mesh.size = Vector3(_magnetic_width, _magnetic_height, 0.10)
	visual.mesh = visual_mesh
	visual.position.y = _magnetic_height * 0.5
	visual.material_override = _create_fx_material(Color("#53d9e5"), 0.38)
	wall.add_child(visual)
	get_tree().current_scene.add_child(wall)
	wall.global_position = center
	wall.rotation.y = atan2(direction.x, direction.z)
	_magnetic_wall = wall
	if survival_mode and survival_evolution_effects != null:
		survival_evolution_effects.wall_created(wall, direction)
	_survival_magnetic_clock = 0.0
	_end_module_action(action_token, "magnetic_field")
	if _attack_label != null:
		_attack_label.text = "MAGNETIC FIELD  •  2.5s"
	var lifetime_timer := get_tree().create_timer(_magnetic_duration, true, false, false)
	var wall_reference: WeakRef = weakref(wall)
	lifetime_timer.timeout.connect(func() -> void:
		var surviving_wall: Area3D = wall_reference.get_ref()
		if is_instance_valid(surviving_wall):
			surviving_wall.queue_free()
		if _magnetic_wall == surviving_wall:
			_magnetic_wall = null
	)


func _perform_static_shield() -> void:
	if _stasis_remaining > 0.0 or _fulguro_projection_active or not _module_ready("static_shield") or (combat_state != null and combat_state.is_stunned()):
		return
	var action_token := _try_begin_module_action("static_shield")
	if action_token == 0:
		return
	_cancel_pelto_pull()
	_mark_combat_event()
	_start_module_cooldown("static_shield", float(COMBAT_DATA.MODULE_DEFINITIONS["static_shield"]["cooldown"]))
	if survival_mode and survival_evolution_effects != null:
		survival_evolution_effects.activate_shield()
		_end_module_action(action_token, "static_shield")
		return
	_static_pulse_token += 1
	var pulse_token := _static_pulse_token
	_stasis_remaining = _static_duration
	if _blaster_charge_active or _touch_fire_active:
		cancel_touch_fire("BLASTER  •  INTERROMPU")
	if _shotgun_attack_busy:
		_cancel_shotgun_attack()
	if _dash_active:
		_cancel_dash()
	if _attack_label != null:
		_attack_label.text = "STATIC SHIELD  •  %.1fs" % _stasis_remaining
	_create_stasis_fx()
	_end_module_action(action_token, "static_shield")
	if _survival_evolved("defensive"):
		var pulse_timer := get_tree().create_timer(_static_duration, false)
		pulse_timer.timeout.connect(func() -> void:
			if pulse_token == _static_pulse_token and is_inside_tree() and not is_real_dead() and survival_mode and _defensive_module_id == "static_shield":
				_survival_area_damage(global_position, 4.0, 70.0, "static_pulse", Color("#ba97ff"))
		)


func _create_stasis_fx() -> void:
	if is_instance_valid(_stasis_visual):
		_stasis_visual.queue_free()
	var shield := MeshInstance3D.new()
	var shield_mesh := SphereMesh.new()
	shield_mesh.radius = 1.12
	shield_mesh.height = 2.05
	shield.mesh = shield_mesh
	shield.material_override = _create_fx_material(Color("#b18dff"), 0.22)
	add_child(shield)
	shield.position = Vector3(0.0, 0.95, 0.0)
	_stasis_visual = shield
	var tween := shield.create_tween()
	tween.set_parallel(true)
	tween.tween_property(shield, "scale", Vector3.ONE * 1.12, 0.20)
	tween.tween_method(Callable(self, "_set_material_alpha").bind(shield.material_override), 0.22, 0.0, _static_duration)
	tween.set_parallel(false)
	tween.tween_callback(func() -> void:
		if _stasis_visual == shield:
			_stasis_visual = null
		shield.queue_free()
	)


func get_bio_remaining() -> float:
	return _bio_remaining


func get_current_move_speed() -> float:
	var slow_multiplier := 1.0
	if combat_state != null:
		slow_multiplier = 1.0 - combat_state.get_slow_percent() / 100.0
	var charge_multiplier := _blaster_charge_slow_multiplier if _blaster_charge_active else 1.0
	var evolution_speed: float = survival_evolution_effects.movement_multiplier() if survival_mode and survival_evolution_effects != null else 1.0
	return move_speed * (_bio_speed_multiplier if _bio_remaining > 0.0 else 1.0) * slow_multiplier * charge_multiplier * evolution_speed


func get_attack_speed_multiplier() -> float:
	var boost: float = survival_evolution_effects.attack_multiplier() if survival_mode and survival_evolution_effects != null else 1.0
	return (_bio_attack_speed_multiplier if _bio_remaining > 0.0 else 1.0) * boost


func is_dash_active() -> bool:
	return _dash_active


func _perform_mobility_module() -> void:
	if _mobility_module_id == "":
		return
	if _mobility_module_id == "bio_injector":
		_perform_bio_injector()
	else:
		_perform_pyro_boots()


func _perform_pyro_boots(direction_override: Vector3 = Vector3.ZERO) -> void:
	if _stasis_remaining > 0.0 or _fulguro_projection_active or _dash_active or (combat_state != null and combat_state.is_stunned()):
		return
	if not (survival_mode and survival_evolution_effects != null) and not _module_ready("pyro_boots"):
		return
	var direction := direction_override if direction_override.length_squared() > 0.001 else _last_move_direction if _last_move_direction.length_squared() > 0.001 else aim_direction.normalized()
	if direction.length_squared() <= 0.001:
		return
	var action_token := _try_begin_module_action("pyro_boots")
	if action_token == 0:
		return
	if survival_mode and survival_evolution_effects != null and not survival_evolution_effects.prepare_dash():
		_end_module_action(action_token, "pyro_boots")
		return
	_cancel_pelto_pull()
	_mark_combat_event()
	_dash_token += 1
	_dash_active = true
	_dash_direction = direction.normalized()
	_dash_elapsed = 0.0
	_start_module_cooldown("pyro_boots", float(COMBAT_DATA.MODULE_DEFINITIONS["pyro_boots"]["cooldown"]))
	if _attack_label != null:
		_attack_label.text = "PYRO BOOTS  •  DASH"
	_create_dash_fx(global_position)
	if survival_mode and survival_evolution_effects != null:
		survival_evolution_effects.dash_started()
	get_node("/root/GameSfx").play_event("pyro_dash")
	_end_module_action(action_token, "pyro_boots")


func _perform_bio_injector() -> void:
	if _stasis_remaining > 0.0 or _fulguro_projection_active or _bio_remaining > 0.0 or not _module_ready("bio_injector") or (combat_state != null and combat_state.is_stunned()):
		return
	var action_token := _try_begin_module_action("bio_injector")
	if action_token == 0:
		return
	_mark_combat_event()
	_start_module_cooldown("bio_injector", float(COMBAT_DATA.MODULE_DEFINITIONS["bio_injector"]["cooldown"]))
	_bio_remaining = float(COMBAT_DATA.MODULE_DEFINITIONS["bio_injector"]["duration"])
	if survival_mode and survival_evolution_effects != null:
		survival_evolution_effects.bio_started()
	if _attack_label != null:
		_attack_label.text = "BIO INJECTOR  •  %.1fs" % _bio_remaining
	_create_bio_fx()
	if survival_synergies != null:
		survival_synergies.arm_double()
	if _survival_evolved("mobility"):
		_survival_area_damage(global_position, 4.0, 70.0, "bio_pulse", Color("#73f0bb"))
	_end_module_action(action_token, "bio_injector")


func _update_dash(delta: float) -> void:
	if not _dash_active:
		return
	_dash_elapsed += delta
	var dash_distance := float(COMBAT_DATA.MODULE_DEFINITIONS["pyro_boots"]["dash_distance"]) * _survival_dash_multiplier
	var dash_duration := float(COMBAT_DATA.MODULE_DEFINITIONS["pyro_boots"]["dash_duration"])
	var step := dash_distance * delta / maxf(0.001, dash_duration)
	var collision := move_and_collide(_dash_direction * step)
	global_position.y = 0.0
	if survival_synergies != null:
		survival_synergies.pyro_step(global_position)
	if survival_mode and survival_evolution_effects != null:
		survival_evolution_effects.pyro_step(global_position)
	if _survival_evolved("mobility"):
		_survival_trail_clock += delta
		if _survival_trail_clock >= 0.12:
			_survival_trail_clock = 0.0
			_survival_area_damage(global_position, 1.5, 24.0, "pyro_trail", Color("#ff8a45"))
	if collision != null or _dash_elapsed >= dash_duration:
		_finish_dash()


func _finish_dash() -> void:
	_dash_active = false
	_dash_direction = Vector3.ZERO
	if _attack_label != null:
		_attack_label.text = "MOBILITÉ : PYRO BOOTS"


func _cancel_dash() -> void:
	if not _dash_active:
		return
	_dash_token += 1
	_dash_active = false
	_dash_direction = Vector3.ZERO
	if _attack_label != null:
		_attack_label.text = "DASH  •  INTERROMPU"


func get_fulguro_hit_radius() -> float:
	return 0.55


func is_fulguro_projected() -> bool:
	return _fulguro_projection_active


func is_action_locked() -> bool:
	return is_real_dead() or _stasis_remaining > 0.0 or _fulguro_projection_active or _action_gate.is_kind(ACTION_GATE.Kind.MODULE) or (combat_state != null and combat_state.is_stunned())


func start_fulguro_projection(direction: Vector3, max_distance: float, max_duration: float, wall_damage: float, wall_stun: float, source_id: String, attack_id: String) -> void:
	if is_real_dead() or max_distance <= 0.0 or max_duration <= 0.0:
		return
	_cancel_pelto_pull()
	_cancel_fulguro_attack("FULGURO PUNCH  •  PROJETÉ")
	_cancel_pelto_smash("PELTO SMASH  •  PROJETÉ")
	if _dash_active:
		_cancel_dash()
	if _blaster_charge_active or _touch_fire_active:
		cancel_touch_fire("FULGURO PUNCH  •  PROJETÉ")
	if _blaster_attack_busy:
		_cancel_blaster_attack()
	if _shotgun_attack_busy:
		_cancel_shotgun_attack()
	_cancel_pending_module_action()
	_fulguro_projection_active = true
	_fulguro_projection_direction = FULGURO.flat_direction(direction)
	_fulguro_projection_distance_remaining = maxf(0.0, max_distance)
	_fulguro_projection_time_remaining = maxf(0.001, max_duration)
	_fulguro_projection_speed = _fulguro_projection_distance_remaining / _fulguro_projection_time_remaining
	_fulguro_projection_wall_damage = maxf(0.0, wall_damage)
	_fulguro_projection_wall_stun = maxf(0.0, wall_stun)
	_fulguro_projection_source_id = source_id
	_fulguro_projection_attack_id = attack_id
	velocity = Vector3.ZERO
	_spawn_particle_burst(global_position + Vector3.UP * 0.82, Color("#65e9ff"), 8, 0.22, 3.0, 0.09, _fulguro_projection_direction, 24.0)


func _update_fulguro_projection(delta: float) -> void:
	if not _fulguro_projection_active:
		return
	var available_time := minf(maxf(delta, 0.0), _fulguro_projection_time_remaining)
	var step_distance := minf(_fulguro_projection_distance_remaining, _fulguro_projection_speed * available_time)
	if step_distance <= 0.0001:
		_finish_fulguro_projection(false)
		return
	var collision := move_and_collide(_fulguro_projection_direction * step_distance)
	global_position.y = 0.0
	var travelled := step_distance
	if collision != null:
		travelled = collision.get_travel().length()
	_fulguro_projection_distance_remaining = maxf(0.0, _fulguro_projection_distance_remaining - travelled)
	_fulguro_projection_time_remaining = maxf(0.0, _fulguro_projection_time_remaining - available_time)
	if collision != null:
		var crushing := FULGURO.is_crushing_wall(collision.get_collider(), collision.get_normal(), _fulguro_projection_direction)
		_finish_fulguro_projection(crushing, collision.get_position(), collision.get_normal())
		return
	if _fulguro_projection_distance_remaining <= 0.001 or _fulguro_projection_time_remaining <= 0.001:
		_finish_fulguro_projection(false)


func _finish_fulguro_projection(crushed_wall: bool, impact_position: Vector3 = Vector3.ZERO, impact_normal: Vector3 = Vector3.ZERO) -> void:
	if not _fulguro_projection_active:
		return
	_fulguro_projection_active = false
	_fulguro_projection_distance_remaining = 0.0
	_fulguro_projection_time_remaining = 0.0
	_fulguro_projection_speed = 0.0
	velocity = Vector3.ZERO
	if crushed_wall and not is_real_dead():
		var wall_attack_id := "%s:wall" % _fulguro_projection_attack_id
		var applied := take_damage(_fulguro_projection_wall_damage, _fulguro_projection_source_id, wall_attack_id)
		if applied > 0.0 and not is_real_dead():
			_fulguro_wall_stun_active = true
			apply_stun(_fulguro_projection_wall_stun, "fulguro_wall")
			_spawn_fulguro_wall_impact(impact_position, impact_normal)
	_try_execute_defensive_buffer()


func _cancel_fulguro_projection() -> void:
	_fulguro_projection_active = false
	_fulguro_projection_direction = Vector3.ZERO
	_fulguro_projection_distance_remaining = 0.0
	_fulguro_projection_time_remaining = 0.0
	_fulguro_projection_speed = 0.0
	_fulguro_wall_stun_active = false


func start_pelto_pull(pull_direction: Vector3, distance: float, duration: float, _source_id: String = "", _attack_id: String = "") -> void:
	if is_real_dead() or _stasis_remaining > 0.0 or _fulguro_projection_active or _dash_active or (combat_state != null and combat_state.is_stunned()) or distance <= 0.0 or duration <= 0.0:
		return
	_pelto_pull_active = true
	_pelto_pull_direction = PELTO_SMASH.flat_direction(pull_direction)
	_pelto_pull_distance_remaining = maxf(0.0, distance)
	_pelto_pull_time_remaining = maxf(0.001, duration)
	_pelto_pull_speed = _pelto_pull_distance_remaining / _pelto_pull_time_remaining


func _update_pelto_pull(delta: float) -> void:
	if not _pelto_pull_active:
		return
	if is_real_dead() or _stasis_remaining > 0.0 or _fulguro_projection_active or (combat_state != null and combat_state.is_stunned()):
		_cancel_pelto_pull()
		return
	var available_time := minf(maxf(delta, 0.0), _pelto_pull_time_remaining)
	var step_distance := minf(_pelto_pull_distance_remaining, _pelto_pull_speed * available_time)
	if step_distance <= 0.0001:
		_cancel_pelto_pull()
		return
	var collision := move_and_collide(_pelto_pull_direction * step_distance)
	global_position.y = 0.0
	var travelled := collision.get_travel().length() if collision != null else step_distance
	_pelto_pull_distance_remaining = maxf(0.0, _pelto_pull_distance_remaining - travelled)
	_pelto_pull_time_remaining = maxf(0.0, _pelto_pull_time_remaining - available_time)
	if collision != null or _pelto_pull_distance_remaining <= 0.001 or _pelto_pull_time_remaining <= 0.001:
		_cancel_pelto_pull()


func _cancel_pelto_pull() -> void:
	_pelto_pull_active = false
	_pelto_pull_direction = Vector3.ZERO
	_pelto_pull_distance_remaining = 0.0
	_pelto_pull_time_remaining = 0.0
	_pelto_pull_speed = 0.0


func is_pelto_pulled() -> bool:
	return _pelto_pull_active


func _spawn_fulguro_wall_impact(impact_position: Vector3, impact_normal: Vector3) -> void:
	var position := impact_position if impact_position != Vector3.ZERO else global_position + Vector3.UP * 0.85
	var normal := impact_normal if impact_normal.length_squared() > 0.001 else -_fulguro_projection_direction
	var vfx := _vfx_manager()
	if vfx != null:
		vfx.call("impact", position, normal, "environment", 1.65, Color("#ffb34f"))
	_spawn_particle_burst(position, Color("#ffca63"), 16, 0.34, 5.2, 0.13, normal, 48.0)
	_camera_impulse(0.14, 0.11)


func _can_buffer_defensive_action() -> bool:
	return not is_real_dead() and (_fulguro_projection_active or _fulguro_wall_stun_active)


func _buffer_dash() -> void:
	var direction := _last_move_direction if _last_move_direction.length_squared() > 0.001 else aim_direction
	_defensive_buffer = {"type": "dash", "direction": FULGURO.flat_direction(direction)}
	if _attack_label != null:
		_attack_label.text = "BUFFER  •  DASH"


func _has_live_javelin_mark() -> bool:
	return _javelin_mark_target != null and is_instance_valid(_javelin_mark_target) and _javelin_mark_target.has_method("has_javelin_mark") and bool(_javelin_mark_target.call("has_javelin_mark"))


func _buffer_javelin_recast() -> void:
	if not _has_live_javelin_mark():
		return
	var destination := _find_javelin_destination(_javelin_mark_target)
	_defensive_buffer = {"type": "teleport", "target": _javelin_mark_target, "destination": destination}
	if _attack_label != null:
		_attack_label.text = "BUFFER  •  TÉLÉPORTATION"


func _try_execute_defensive_buffer() -> void:
	if _defensive_buffer.is_empty() or is_action_locked():
		return
	var command := _defensive_buffer.duplicate()
	_defensive_buffer.clear()
	match str(command.get("type", "")):
		"dash":
			if _mobility_module_id == "pyro_boots" and _module_ready("pyro_boots"):
				var direction: Vector3 = command.get("direction", Vector3.ZERO)
				if direction.length_squared() > 0.001:
					_perform_pyro_boots(direction)
		"teleport":
			var target := command.get("target") as Node
			var destination: Vector3 = command.get("destination", Vector3.INF)
			if _offensive_module_id == "javelin" and target == _javelin_mark_target and _has_live_javelin_mark() and destination.is_finite() and _javelin_destination_valid(target, destination):
				_recast_javelin(destination)


func _clear_defensive_buffer() -> void:
	_defensive_buffer.clear()


func get_buffered_defensive_action() -> String:
	return str(_defensive_buffer.get("type", ""))


func _create_dash_fx(origin: Vector3) -> void:
	var direction := -_dash_direction if _dash_direction.length_squared() > 0.001 else -aim_direction
	_spawn_particle_burst(origin + Vector3.UP * 0.15, Color("#d99562"), 10, 0.24, 3.8, 0.10, direction + Vector3.UP * 0.28, 28.0)

func _create_bio_fx() -> void:
	_spawn_particle_burst(global_position + Vector3.UP * 0.85, Color("#85bfa5"), 7, 0.30, 1.2, 0.09, Vector3.UP, 24.0)

func _survival_evolved(category: String) -> bool:
	return survival_mode and bool(_survival_evolutions.get(category, false)) and (survival_evolution_effects == null or survival_evolution_effects.rank(category) == 0)


func _survival_targets() -> Array:
	var scene := get_tree().current_scene
	return scene.call("get_training_targets") if scene != null and scene.has_method("get_training_targets") else []


func _survival_area_damage(center: Vector3, radius: float, damage: float, attack_name: String, color: Color, excluded: Node = null) -> void:
	if not survival_mode:
		return
	_survival_pulse_fx(center, radius, color)
	var attack_id := "%s:%d" % [attack_name, Time.get_ticks_usec()]
	for enemy in _survival_targets():
		if enemy == excluded or not is_instance_valid(enemy) or float(enemy.call("get_health")) <= 0.0:
			continue
		if center.distance_to(enemy.global_position) <= radius:
			var applied := float(enemy.call("take_damage", damage, "player", attack_id))
			if applied > 0.0:
				enemy.call("flash_impact", false)


func _survival_secondary_hit(primary: Node, damage: float, radius: float, attack_name: String, aligned: bool, direction: Vector3 = Vector3.ZERO) -> void:
	var candidate: Node = null
	var best_distance := INF
	for enemy in _survival_targets():
		if enemy == primary or not is_instance_valid(enemy) or float(enemy.call("get_health")) <= 0.0:
			continue
		var offset: Vector3 = enemy.global_position - primary.global_position
		offset.y = 0.0
		var distance := offset.length()
		if distance > radius or distance >= best_distance:
			continue
		if aligned and (direction.dot(offset) <= 0.0 or absf(direction.cross(offset.normalized()).y) > 0.24):
			continue
		if not _solid_path_clear(primary.global_position, enemy.global_position, [primary.get_rid(), enemy.get_rid()]):
			continue
		candidate = enemy
		best_distance = distance
	if candidate != null:
		var applied := float(candidate.call("take_damage", damage, "player", "%s:%d" % [attack_name, Time.get_ticks_usec()]))
		if applied > 0.0:
			candidate.call("flash_impact", false)
			_create_lightning_arc(primary.global_position + Vector3.UP, candidate.global_position + Vector3.UP, Color("#8feaff"), 0.04, 0.25)


func _survival_pulse_fx(center: Vector3, radius: float, color: Color) -> void:
	var scene := get_tree().current_scene
	if scene == null:
		return
	var ring := MeshInstance3D.new()
	ring.name = "SurvivalEvolutionPulse"
	var mesh := TorusMesh.new()
	mesh.inner_radius = 0.90
	mesh.outer_radius = 1.0
	ring.mesh = mesh
	ring.rotation_degrees.x = 90
	ring.material_override = _create_fx_material(color, 0.85)
	scene.add_child(ring)
	ring.global_position = center + Vector3.UP * 0.08
	var tween := ring.create_tween()
	tween.tween_property(ring, "scale", Vector3.ONE * radius, 0.32)
	tween.tween_callback(ring.queue_free)


func _module_target() -> Node:
	var active_scene := get_tree().current_scene
	if active_scene != null and active_scene.has_method("get_training_targets"):
		return _best_training_target(global_position, aim_direction, 20.0, 1.0)
	return active_scene.get_node_or_null("TargetDummy") if active_scene != null else null

func _best_training_target(origin: Vector3, direction: Vector3, max_range: float, radius_scale: float) -> Node:
	var scene := get_tree().current_scene
	if scene == null or not scene.has_method("get_training_targets"):
		return null
	var best: Node = null
	var best_along := INF
	var flat_direction := Vector3(direction.x, 0.0, direction.z).normalized()
	for candidate in scene.call("get_training_targets"):
		if not is_instance_valid(candidate) or not candidate.has_method("get_health") or float(candidate.call("get_health")) <= 0.0:
			continue
		var offset: Vector3 = candidate.global_position - origin
		offset.y = 0.0
		var along := flat_direction.dot(offset)
		if along <= 0.0 or along > max_range or along >= best_along:
			continue
		var lateral := (offset - flat_direction * along).length()
		var hit_radius := float(candidate.call("get_training_hit_radius")) if candidate.has_method("get_training_hit_radius") else 0.8
		if lateral <= hit_radius * radius_scale and _solid_path_clear(origin, candidate.global_position, [candidate.get_rid()]):
			best = candidate
			best_along = along
	return best


func _module_visual_start(direction: Vector3) -> Vector3:
	var muzzle := _active_muzzle()
	return muzzle.global_position if muzzle != null else global_position + Vector3.UP * 0.85 + direction * 0.45


func _module_obstacle_endpoint(start: Vector3, end: Vector3, excluded: Array[RID] = []) -> Vector3:
	var world := get_world_3d()
	if world == null:
		return end
	var query := PhysicsRayQueryParameters3D.create(start + Vector3.UP * 0.72, end + Vector3.UP * 0.72)
	query.collision_mask = 9
	query.collide_with_areas = true
	query.collide_with_bodies = true
	query.exclude = [get_rid()] + excluded
	var result := world.direct_space_state.intersect_ray(query)
	return result["position"] if not result.is_empty() else end


func _module_path_clear(from_position: Vector3, to_position: Vector3, excluded: Array[RID] = []) -> bool:
	var world := get_world_3d()
	if world == null:
		return true
	var query := PhysicsRayQueryParameters3D.create(from_position + Vector3.UP * 0.72, to_position + Vector3.UP * 0.72)
	query.collision_mask = 9
	query.collide_with_areas = true
	query.collide_with_bodies = true
	query.exclude = [get_rid()] + excluded
	return world.direct_space_state.intersect_ray(query).is_empty()


func _solid_path_clear(from_position: Vector3, to_position: Vector3, excluded: Array[RID] = []) -> bool:
	var world := get_world_3d()
	if world == null:
		return true
	var query := PhysicsRayQueryParameters3D.create(from_position + Vector3.UP * 0.72, to_position + Vector3.UP * 0.72)
	query.collision_mask = 1
	query.collide_with_areas = false
	query.collide_with_bodies = true
	query.exclude = [get_rid()] + excluded
	return world.direct_space_state.intersect_ray(query).is_empty()


func _select_drone_target(origin: Vector3, direction: Vector3) -> Node:
	var target := _module_target()
	if target == null or not is_instance_valid(target) or float(target.call("get_health")) <= 0.0:
		return null
	var offset: Vector3 = target.global_position - origin
	offset.y = 0.0
	var distance: float = offset.length()
	if distance <= 0.001 or distance > _drone_max_range:
		return null
	var angle := rad_to_deg(acos(clampf(direction.dot(offset.normalized()), -1.0, 1.0)))
	if angle > _drone_cone_half_angle or not _solid_path_clear(origin, target.global_position, [target.get_rid()]):
		return null
	return target


func _fulguro_targets() -> Array:
	var scene := get_tree().current_scene if get_tree() != null else null
	if scene == null:
		return []
	if scene.has_method("get_training_targets"):
		return scene.call("get_training_targets")
	var target := scene.get_node_or_null("TargetDummy")
	return [target] if target != null else []


func _perform_fulguro_punch() -> void:
	_begin_fulguro_charge()
	_release_fulguro_charge()


func _begin_fulguro_charge() -> void:
	if _stasis_remaining > 0.0 or _fulguro_projection_active or not _module_ready("fulguro_punch") or is_real_dead() or (combat_state != null and combat_state.is_stunned()):
		return
	var action_token := _try_begin_module_action("fulguro_punch")
	if action_token == 0:
		return
	_mark_combat_event()
	_module_busy = true
	_module_token += 1
	_fulguro_attack_serial += 1
	_fulguro_phase = "preparation"
	_fulguro_elapsed = 0.0
	_fulguro_direction = FULGURO.flat_direction(aim_direction)
	_fulguro_hit_resolved = false
	_fulguro_release_requested = false
	_fulguro_release_at = -1.0
	_fulguro_charge_ratio = 0.0
	_fulguro_strike_range = _fulguro_range
	_fulguro_strike_damage = _fulguro_damage
	_fulguro_strike_wall_damage = _fulguro_wall_damage
	_fulguro_flame_clock = 0.0
	_start_module_cooldown("fulguro_punch", float(COMBAT_DATA.MODULE_DEFINITIONS["fulguro_punch"]["cooldown"]))
	_create_fulguro_telegraph()
	if _fulguro_charge_audio != null:
		_fulguro_charge_audio.play()
	if _attack_label != null:
		_attack_label.text = "FULGURO PUNCH  •  CHARGE 0.00 / %.1f s" % _fulguro_charge_max
	_update_fulguro_pose()


func _release_fulguro_charge() -> void:
	if _fulguro_phase != "preparation" or _fulguro_release_requested:
		return
	_fulguro_release_requested = true
	_fulguro_release_at = clampf(maxf(_fulguro_elapsed, _fulguro_preparation), _fulguro_preparation, _fulguro_charge_max)


func get_fulguro_charge_fraction() -> float:
	if _fulguro_phase != "preparation":
		return 0.0
	return clampf(_fulguro_elapsed / maxf(0.001, _fulguro_charge_max), 0.0, 1.0)


func is_fulguro_charging() -> bool:
	return _fulguro_phase == "preparation"


func _update_fulguro_attack(delta: float) -> void:
	if _fulguro_phase == "":
		return
	if not _module_action_can_execute(_active_module_action_token, "fulguro_punch"):
		_cancel_fulguro_attack()
		return
	if is_real_dead() or _stasis_remaining > 0.0 or _fulguro_projection_active or (combat_state != null and combat_state.is_stunned()):
		_cancel_fulguro_attack("FULGURO PUNCH  •  INTERROMPU")
		return
	if _fulguro_phase == "preparation":
		var release_time := _fulguro_release_at if _fulguro_release_requested else _fulguro_charge_max
		_fulguro_elapsed = minf(_fulguro_elapsed + maxf(0.0, delta), release_time)
		_update_fulguro_telegraph(delta)
		_update_fulguro_pose()
		if _attack_label != null:
			var percent := int(round(_fulguro_power_ratio() * 100.0))
			_attack_label.text = "FULGURO PUNCH  •  CHARGE %.2f / %.1f s  •  %d%%" % [_fulguro_elapsed, _fulguro_charge_max, percent]
		if _fulguro_elapsed >= release_time - 0.000001:
			_commit_fulguro_strike()
		return
	var phase_duration := _fulguro_active_window if _fulguro_phase == "active" else _fulguro_recovery
	_fulguro_elapsed += maxf(0.0, delta)
	if _fulguro_elapsed >= phase_duration:
		_fulguro_elapsed = 0.0
		if _fulguro_phase == "active":
			_fulguro_phase = "recovery"
			if _attack_label != null:
				_attack_label.text = "FULGURO PUNCH  •  RÉCUPÉRATION"
		else:
			_finish_fulguro_attack()
			return
	_update_fulguro_pose()


func _fulguro_power_ratio() -> float:
	return clampf(inverse_lerp(_fulguro_preparation, _fulguro_charge_max, _fulguro_elapsed), 0.0, 1.0)


func _commit_fulguro_strike() -> void:
	if not _module_action_can_execute(_active_module_action_token, "fulguro_punch"):
		_cancel_fulguro_attack()
		return
	_fulguro_charge_ratio = _fulguro_power_ratio()
	_fulguro_strike_range = lerpf(_fulguro_range, _fulguro_range_max, _fulguro_charge_ratio)
	_fulguro_strike_damage = lerpf(_fulguro_damage, _fulguro_damage_max, _fulguro_charge_ratio)
	_fulguro_strike_wall_damage = lerpf(_fulguro_wall_damage, _fulguro_wall_damage_max, _fulguro_charge_ratio)
	_fulguro_phase = "active"
	_fulguro_elapsed = 0.0
	if _fulguro_charge_audio != null:
		_fulguro_charge_audio.stop()
	if _fulguro_release_audio != null:
		_fulguro_release_audio.pitch_scale = lerpf(1.03, 0.78, _fulguro_charge_ratio)
		_fulguro_release_audio.play()
	_clear_fulguro_telegraph()
	_resolve_fulguro_strike()
	_spawn_fulguro_strike_fx()
	if _attack_label != null:
		_attack_label.text = "FULGURO PUNCH  •  DÉCHARGE INCANDESCENTE  •  %d%%" % int(round(_fulguro_charge_ratio * 100.0))
	_update_fulguro_pose()


func _resolve_fulguro_strike() -> void:
	if _fulguro_hit_resolved:
		return
	_fulguro_hit_resolved = true
	var attack_id := "fulguro:%d" % _fulguro_attack_serial
	var target := FULGURO.resolve_strike(self, _fulguro_targets(), _fulguro_direction, _fulguro_strike_damage, _fulguro_strike_wall_damage, _fulguro_wall_stun, "player", attack_id, _fulguro_strike_range, _fulguro_width)
	if target != null:
		var impact_position := (target as Node3D).global_position + Vector3.UP * 0.82
		_create_target_hit_fx(impact_position, false)
		var vfx := _vfx_manager()
		if vfx != null:
			vfx.call("impact", impact_position, -_fulguro_direction, "robot", lerpf(1.15, 1.85, _fulguro_charge_ratio), Color("#ff7a24"))
		_spawn_particle_burst(impact_position, Color("#fff0a3"), 10 + int(_fulguro_charge_ratio * 10.0), 0.34, 5.0, 0.16, -_fulguro_direction + Vector3.UP * 0.25, 52.0)
		if _survival_evolved("offensive"):
			_survival_area_damage((target as Node3D).global_position, 2.25, 45.0, "fulguro_incandescent_wave", Color("#ff8a32"), target)


func _create_fulguro_telegraph() -> void:
	_clear_fulguro_telegraph()
	var root := Node3D.new()
	root.name = "FulguroTelegraph"
	var lane := MeshInstance3D.new()
	var lane_mesh := BoxMesh.new()
	lane_mesh.size = Vector3(_fulguro_width, 0.025, _fulguro_range)
	lane.mesh = lane_mesh
	lane.position = Vector3(0.0, 0.0, -_fulguro_range * 0.5)
	lane.material_override = _create_fx_material(Color("#ff7a24"), 0.46)
	root.add_child(lane)
	_fulguro_lane_mesh = lane_mesh
	var tip := MeshInstance3D.new()
	var tip_mesh := BoxMesh.new()
	tip_mesh.size = Vector3(_fulguro_width * 0.72, 0.035, 0.24)
	tip.mesh = tip_mesh
	tip.position = Vector3(0.0, 0.012, -_fulguro_range + 0.10)
	tip.rotation.y = PI * 0.25
	tip.material_override = _create_fx_material(Color("#ffd36a"), 0.82)
	root.add_child(tip)
	_fulguro_tip_visual = tip
	var fist := MeshInstance3D.new()
	var fist_mesh := SphereMesh.new()
	fist_mesh.radius = 0.22
	fist_mesh.height = 0.38
	fist.mesh = fist_mesh
	fist.material_override = _create_fx_material(Color("#ff5a16"), 0.78)
	root.add_child(fist)
	_fulguro_fist_visual = fist
	var core := MeshInstance3D.new()
	var core_mesh := SphereMesh.new()
	core_mesh.radius = 0.13
	core_mesh.height = 0.24
	core.mesh = core_mesh
	core.material_override = _create_fx_material(Color("#fff2af"), 0.92)
	root.add_child(core)
	_fulguro_fist_core = core
	_fulguro_flame_tongues.clear()
	for index in range(3):
		var flame := MeshInstance3D.new()
		var flame_mesh := SphereMesh.new()
		flame_mesh.radius = 0.085
		flame_mesh.height = 0.34
		flame.mesh = flame_mesh
		flame.material_override = _create_fx_material(Color("#ff6a1f") if index != 1 else Color("#ffd66b"), 0.68)
		root.add_child(flame)
		_fulguro_flame_tongues.append(flame)
	var light := OmniLight3D.new()
	light.light_color = Color("#ff7b2f")
	light.light_energy = 1.2
	light.omni_range = 2.2
	light.shadow_enabled = false
	root.add_child(light)
	_fulguro_flame_light = light
	get_tree().current_scene.add_child(root)
	_fulguro_indicator = root
	_update_fulguro_telegraph(0.0)


func _update_fulguro_telegraph(delta: float = 0.0) -> void:
	if _fulguro_indicator == null or not is_instance_valid(_fulguro_indicator):
		return
	_fulguro_indicator.global_position = global_position + Vector3.UP * 0.055
	_fulguro_indicator.global_basis = Basis.looking_at(_fulguro_direction, Vector3.UP)
	var armed := clampf(_fulguro_elapsed / maxf(0.001, _fulguro_preparation), 0.0, 1.0)
	var power := _fulguro_power_ratio()
	var live_range := lerpf(_fulguro_range, _fulguro_range_max, power)
	if _fulguro_lane_mesh != null:
		_fulguro_lane_mesh.size = Vector3(_fulguro_width, 0.025 + power * 0.018, live_range)
	var lane := _fulguro_indicator.get_child(0) as MeshInstance3D
	if lane != null:
		lane.position = Vector3(0.0, 0.0, -live_range * 0.5)
	if _fulguro_tip_visual != null:
		_fulguro_tip_visual.position = Vector3(0.0, 0.012, -live_range + 0.10)
		_fulguro_tip_visual.scale = Vector3.ONE * (1.0 + power * 0.32 + sin(_fulguro_elapsed * 18.0) * 0.05)
	if _fulguro_fist_visual != null:
		var fist_position := Vector3(0.36, 0.88, 0.24 + armed * 0.18)
		var pulse := sin(_fulguro_elapsed * lerpf(22.0, 48.0, power)) * (0.05 + power * 0.08)
		_fulguro_fist_visual.position = fist_position
		_fulguro_fist_visual.scale = Vector3.ONE * (0.74 + armed * 0.34 + power * 0.58 + pulse)
		var material := _fulguro_fist_visual.material_override as StandardMaterial3D
		if material != null:
			material.emission = Color("#ff641c").lerp(Color("#fff1a6"), power * 0.72)
			material.emission_energy_multiplier = lerpf(1.8, 6.5, power)
		if _fulguro_fist_core != null:
			_fulguro_fist_core.position = fist_position + Vector3(0.0, 0.01, -0.025)
			_fulguro_fist_core.scale = Vector3.ONE * (0.52 + power * 0.46 + sin(_fulguro_elapsed * 55.0) * 0.06)
		for index in range(_fulguro_flame_tongues.size()):
			var flame := _fulguro_flame_tongues[index]
			var angle := _fulguro_elapsed * lerpf(5.0, 9.0, power) + TAU * float(index) / float(_fulguro_flame_tongues.size())
			flame.position = fist_position + Vector3(cos(angle) * (0.10 + power * 0.07), 0.13 + sin(angle * 1.7) * 0.05, sin(angle) * (0.08 + power * 0.05))
			flame.scale = Vector3(0.72 + power * 0.35, 1.05 + power * 0.85 + sin(angle * 2.0) * 0.16, 0.72 + power * 0.35)
		if _fulguro_flame_light != null:
			_fulguro_flame_light.position = fist_position
			_fulguro_flame_light.light_energy = lerpf(1.2, 4.8, power) + sin(_fulguro_elapsed * 36.0) * 0.25
			_fulguro_flame_light.omni_range = lerpf(2.2, 4.1, power)
		_fulguro_flame_clock -= delta
		if delta > 0.0 and _fulguro_flame_clock <= 0.0:
			_fulguro_flame_clock = lerpf(0.16, 0.065, power)
			var flame_origin := _fulguro_fist_visual.global_position
			_spawn_particle_burst(flame_origin, Color("#ff7628").lerp(Color("#fff0a0"), power * 0.65), 5 + int(power * 7.0), 0.28, lerpf(1.4, 3.5, power), 0.12, Vector3.UP - _fulguro_direction * 0.20, 42.0)


func _clear_fulguro_telegraph() -> void:
	if _fulguro_indicator != null and is_instance_valid(_fulguro_indicator):
		_fulguro_indicator.queue_free()
	_fulguro_indicator = null
	_fulguro_fist_visual = null
	_fulguro_fist_core = null
	_fulguro_flame_tongues.clear()
	_fulguro_lane_mesh = null
	_fulguro_tip_visual = null
	_fulguro_flame_light = null


func _spawn_fulguro_strike_fx() -> void:
	var trail := MeshInstance3D.new()
	trail.name = "FulguroPunchTrail"
	var mesh := BoxMesh.new()
	mesh.size = Vector3(_fulguro_width * lerpf(0.62, 0.88, _fulguro_charge_ratio), lerpf(0.28, 0.46, _fulguro_charge_ratio), _fulguro_strike_range)
	trail.mesh = mesh
	trail.material_override = _create_fx_material(Color("#ff5a18"), 0.64)
	get_tree().current_scene.add_child(trail)
	trail.global_position = global_position + _fulguro_direction * (_fulguro_strike_range * 0.5) + Vector3.UP * 0.92
	trail.global_basis = Basis.looking_at(_fulguro_direction, Vector3.UP)
	_register_fx_budget(trail, "burst")
	var core := MeshInstance3D.new()
	core.name = "FulguroIncandescentCore"
	var core_mesh := BoxMesh.new()
	core_mesh.size = Vector3(_fulguro_width * 0.28, 0.13, _fulguro_strike_range * 0.98)
	core.mesh = core_mesh
	core.material_override = _create_fx_material(Color("#fff0a0"), 0.90)
	get_tree().current_scene.add_child(core)
	core.global_position = trail.global_position
	core.global_basis = trail.global_basis
	_register_fx_budget(core, "burst")
	var discharge_end := global_position + _fulguro_direction * _fulguro_strike_range + Vector3.UP * 0.90
	_spawn_particle_burst(discharge_end, Color("#ff7928"), 12, 0.36, 5.0, 0.18, _fulguro_direction, 28.0)
	_spawn_particle_burst(discharge_end, Color("#fff3b0"), 8, 0.24, 4.2, 0.11, _fulguro_direction, 20.0)
	for index in range(3 + int(_fulguro_charge_ratio * 3.0)):
		var side := Vector3(-_fulguro_direction.z, 0.0, _fulguro_direction.x) * (float(index) - 2.0) * 0.055
		_create_lightning_arc(global_position + Vector3.UP * 0.92 + side, discharge_end + side * 0.35, Color("#ffb044") if index % 2 == 0 else Color("#fff0a3"), 0.035 + _fulguro_charge_ratio * 0.025, 0.18)
	var material := trail.material_override as StandardMaterial3D
	var core_material := core.material_override as StandardMaterial3D
	var tween := trail.create_tween()
	tween.set_parallel(true)
	tween.tween_property(trail, "scale", Vector3(0.55, 0.55, 1.08), _fulguro_active_window)
	tween.tween_method(Callable(self, "_set_material_alpha").bind(material), 0.72, 0.0, _fulguro_active_window + 0.08)
	tween.tween_property(core, "scale", Vector3(0.48, 0.48, 1.12), _fulguro_active_window)
	tween.tween_method(Callable(self, "_set_material_alpha").bind(core_material), 0.90, 0.0, _fulguro_active_window + 0.10)
	tween.set_parallel(false)
	tween.tween_callback(func() -> void:
		if is_instance_valid(trail):
			trail.queue_free()
		if is_instance_valid(core):
			core.queue_free()
	)


func _update_fulguro_pose() -> void:
	if _visual_rig == null or not _visual_rig.has_method("set_fulguro_pose"):
		return
	var duration := _fulguro_active_window if _fulguro_phase == "active" else _fulguro_recovery
	var progress := clampf(_fulguro_elapsed / maxf(0.001, duration), 0.0, 1.0)
	if _fulguro_phase == "preparation":
		progress = clampf(_fulguro_elapsed / maxf(0.001, _fulguro_preparation), 0.0, 1.0)
	_visual_rig.call("set_fulguro_pose", _fulguro_phase, progress)


func _finish_fulguro_attack() -> void:
	var action_token := _active_module_action_token if _active_module_id == "fulguro_punch" else 0
	_clear_fulguro_telegraph()
	if _fulguro_charge_audio != null:
		_fulguro_charge_audio.stop()
	if _visual_rig != null and _visual_rig.has_method("clear_fulguro_pose"):
		_visual_rig.call("clear_fulguro_pose")
	_fulguro_phase = ""
	_fulguro_elapsed = 0.0
	_fulguro_hit_resolved = false
	_fulguro_release_requested = false
	_fulguro_release_at = -1.0
	_end_module_action(action_token, "fulguro_punch")
	_update_aim_pose_state()
	if _attack_label != null:
		_attack_label.text = "FULGURO PUNCH  •  CD 8s"


func _cancel_fulguro_attack(reason: String = "") -> void:
	var action_token := _active_module_action_token if _active_module_id == "fulguro_punch" else 0
	if _fulguro_phase == "" and action_token == 0:
		_clear_fulguro_telegraph()
		return
	_clear_fulguro_telegraph()
	if _fulguro_charge_audio != null:
		_fulguro_charge_audio.stop()
	if _visual_rig != null and _visual_rig.has_method("clear_fulguro_pose"):
		_visual_rig.call("clear_fulguro_pose")
	_fulguro_phase = ""
	_fulguro_elapsed = 0.0
	_fulguro_hit_resolved = false
	_fulguro_release_requested = false
	_fulguro_release_at = -1.0
	_end_module_action(action_token, "fulguro_punch")
	_update_aim_pose_state()
	if reason != "" and _attack_label != null:
		_attack_label.text = reason


func _perform_pelto_smash() -> void:
	if _stasis_remaining > 0.0 or _fulguro_projection_active or not _module_ready("pelto_smash") or is_real_dead() or (combat_state != null and combat_state.is_stunned()):
		return
	var action_token := _try_begin_module_action("pelto_smash")
	if action_token == 0:
		return
	_mark_combat_event()
	_module_busy = true
	_module_token += 1
	_pelto_attack_serial += 1
	_pelto_phase = "preparation"
	_pelto_elapsed = 0.0
	_pelto_direction = PELTO_SMASH.flat_direction(aim_direction)
	_pelto_weapon_restore_serial += 1
	_start_module_cooldown("pelto_smash", float(COMBAT_DATA.MODULE_DEFINITIONS["pelto_smash"].cooldown))
	_create_pelto_telegraph()
	_set_pelto_weapon_hidden(true)
	_update_pelto_pose()
	_update_aim_pose_state()
	if _attack_label != null:
		_attack_label.text = "PELTO SMASH  •  PRÉPARATION"


func is_pelto_preparing() -> bool:
	return _pelto_phase == "preparation"


func get_pelto_preparation_fraction() -> float:
	return clampf(_pelto_elapsed / maxf(0.001, _pelto_preparation), 0.0, 1.0) if _pelto_phase == "preparation" else 0.0


func _update_pelto_attack(delta: float) -> void:
	if _pelto_phase == "":
		return
	if not _module_action_can_execute(_active_module_action_token, "pelto_smash"):
		_cancel_pelto_smash()
		return
	if is_real_dead() or _stasis_remaining > 0.0 or _fulguro_projection_active or (combat_state != null and combat_state.is_stunned()):
		_cancel_pelto_smash("PELTO SMASH  •  INTERROMPU")
		return
	_pelto_elapsed += maxf(0.0, delta)
	if _pelto_phase == "preparation":
		_update_pelto_telegraph()
		_update_pelto_pose()
		if _pelto_elapsed >= _pelto_preparation:
			_commit_pelto_impact()
		return
	var duration := _pelto_impact_duration if _pelto_phase == "impact" else _pelto_recovery
	if _pelto_elapsed >= duration:
		_pelto_elapsed = 0.0
		if _pelto_phase == "impact":
			_pelto_phase = "recovery"
			if _attack_label != null:
				_attack_label.text = "PELTO SMASH  •  REPRISE"
		else:
			_finish_pelto_smash()
			return
	_update_pelto_pose()


func _commit_pelto_impact() -> void:
	if not _module_action_can_execute(_active_module_action_token, "pelto_smash"):
		_cancel_pelto_smash()
		return
	_pelto_phase = "impact"
	_pelto_elapsed = 0.0
	_clear_pelto_telegraph()
	if _pelto_impact_audio != null:
		_pelto_impact_audio.play()
	_camera_impulse(0.12, 0.085)
	_spawn_particle_burst(global_position + Vector3.UP * 0.08, Color("#c47b43"), 14, 0.30, 3.5, 0.13, _pelto_direction + Vector3.UP * 0.22, 45.0)
	var scene := get_tree().current_scene if get_tree() != null else null
	if scene != null:
		var wave := PELTO_SMASH.new()
		wave.name = "PeltoSmashWave_%d" % _pelto_attack_serial
		scene.add_child(wave)
		wave.call("configure", self, global_position, _pelto_direction, "player", "pelto:%d" % _pelto_attack_serial, _pelto_damage_multiplier)
		_pelto_waves.append(wave)
		wave.finished.connect(Callable(self, "_on_pelto_wave_finished").bind(wave), CONNECT_ONE_SHOT)
		_register_fx_budget(wave, "projectile")
	if _attack_label != null:
		_attack_label.text = "PELTO SMASH  •  IMPACT"
	_update_pelto_pose()


func _on_pelto_wave_finished(wave: Node) -> void:
	_pelto_waves.erase(wave)


func _on_pelto_hit(target: Node, returning: bool, applied_damage: float) -> void:
	if not returning or not _survival_evolved("offensive") or target == null or not target is Node3D:
		return
	_survival_area_damage((target as Node3D).global_position, 2.5, applied_damage * 0.35, "pelto_aftershock", Color("#d99a5b"), target)


func _create_pelto_telegraph() -> void:
	_clear_pelto_telegraph()
	var values: Dictionary = COMBAT_DATA.MODULE_DEFINITIONS["pelto_smash"]
	var root := Node3D.new()
	root.name = "PeltoSmashTelegraph"
	var lane := MeshInstance3D.new()
	_pelto_lane_mesh = BoxMesh.new()
	_pelto_lane_mesh.size = Vector3(float(values.width), 0.022, float(values.max_range))
	lane.mesh = _pelto_lane_mesh
	lane.position = Vector3(0.0, 0.0, -float(values.max_range) * 0.5)
	lane.material_override = _pelto_ground_material(Color("#8b593b"), 0.30)
	root.add_child(lane)
	for segment in range(1, 7):
		var ridge := MeshInstance3D.new()
		var ridge_mesh := BoxMesh.new()
		ridge_mesh.size = Vector3(float(values.width) * 0.94, 0.035, 0.045)
		ridge.mesh = ridge_mesh
		ridge.position = Vector3(0.0, 0.018, -float(values.max_range) * float(segment) / 7.0)
		ridge.material_override = _pelto_ground_material(Color("#d39a5c"), 0.62)
		root.add_child(ridge)
	var strike := MeshInstance3D.new()
	var strike_mesh := CylinderMesh.new()
	strike_mesh.top_radius = 0.34
	strike_mesh.bottom_radius = 0.42
	strike_mesh.height = 0.035
	strike_mesh.radial_segments = 16
	strike.mesh = strike_mesh
	strike.position = Vector3(0.0, 0.025, -0.28)
	strike.material_override = _pelto_ground_material(Color("#f0ba6a"), 0.82)
	root.add_child(strike)
	_scene_add_child(root)
	_pelto_indicator = root
	_update_pelto_telegraph()


func _scene_add_child(node: Node) -> void:
	var scene := get_tree().current_scene if get_tree() != null else null
	if scene != null:
		scene.add_child(node)
	else:
		add_child(node)


func _update_pelto_telegraph() -> void:
	if _pelto_indicator == null or not is_instance_valid(_pelto_indicator):
		return
	_pelto_indicator.global_position = global_position + Vector3.UP * 0.045
	_pelto_indicator.global_basis = Basis.looking_at(_pelto_direction, Vector3.UP)
	var progress := clampf(_pelto_elapsed / maxf(0.001, _pelto_preparation), 0.0, 1.0)
	_pelto_indicator.scale.y = 1.0 + sin(_pelto_elapsed * 22.0) * 0.18 * progress


func _clear_pelto_telegraph() -> void:
	if _pelto_indicator != null and is_instance_valid(_pelto_indicator):
		_pelto_indicator.queue_free()
	_pelto_indicator = null
	_pelto_lane_mesh = null


func _update_pelto_pose() -> void:
	if _visual_rig == null or not _visual_rig.has_method("set_pelto_pose"):
		return
	var duration := _pelto_preparation if _pelto_phase == "preparation" else _pelto_impact_duration if _pelto_phase == "impact" else _pelto_recovery
	_visual_rig.call("set_pelto_pose", _pelto_phase, clampf(_pelto_elapsed / maxf(0.001, duration), 0.0, 1.0))


func _finish_pelto_smash() -> void:
	var action_token := _active_module_action_token if _active_module_id == "pelto_smash" else 0
	_clear_pelto_telegraph()
	if _visual_rig != null and _visual_rig.has_method("clear_pelto_pose"):
		_visual_rig.call("clear_pelto_pose")
	_pelto_phase = ""
	_pelto_elapsed = 0.0
	_end_module_action(action_token, "pelto_smash")
	_update_aim_pose_state(true)
	_queue_pelto_weapon_restore()
	if _attack_label != null:
		_attack_label.text = "PELTO SMASH  •  CD 10s"


func _cancel_pelto_smash(reason: String = "") -> void:
	var action_token := _active_module_action_token if _active_module_id == "pelto_smash" else 0
	_clear_pelto_telegraph()
	if _visual_rig != null and _visual_rig.has_method("clear_pelto_pose"):
		_visual_rig.call("clear_pelto_pose")
	_pelto_phase = ""
	_pelto_elapsed = 0.0
	_end_module_action(action_token, "pelto_smash")
	_update_aim_pose_state(true)
	_queue_pelto_weapon_restore()
	if reason != "" and _attack_label != null:
		_attack_label.text = reason


func _set_pelto_weapon_hidden(hidden: bool) -> void:
	_pelto_weapon_hidden = hidden
	if hidden:
		if _blaster_pivot != null:
			_blaster_pivot.visible = false
		if _shotgun_pivot != null:
			_shotgun_pivot.visible = false
	else:
		_update_weapon_visuals()


func _queue_pelto_weapon_restore() -> void:
	_pelto_weapon_restore_serial += 1
	_restore_pelto_weapon_after_skeleton(_pelto_weapon_restore_serial)


func _restore_pelto_weapon_after_skeleton(restore_serial: int) -> void:
	# BoneAttachment3D is refreshed after animation and SkeletonModifier3D. Keep
	# the weapon hidden until two complete frames have replaced the last Pelto
	# pose; revealing it earlier exposes the attachment at its stale world pose.
	var scene_tree := get_tree()
	if scene_tree == null:
		return
	for _frame in range(2):
		await scene_tree.process_frame
	if restore_serial != _pelto_weapon_restore_serial or _pelto_phase != "" or not is_inside_tree():
		return
	if _visual_rig != null and _visual_rig.has_method("settle_weapon_attachment_after_transient_pose"):
		_visual_rig.call("settle_weapon_attachment_after_transient_pose")
	_set_pelto_weapon_hidden(false)


func _pelto_ground_material(color: Color, alpha: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(color.r, color.g, color.b, alpha)
	material.roughness = 0.95
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.emission_enabled = true
	material.emission = color.darkened(0.62)
	material.emission_energy_multiplier = 0.16
	return material


func _perform_modulo_drone() -> void:
	if _stasis_remaining > 0.0 or _fulguro_projection_active or not _module_ready("modulo_drone") or (combat_state != null and combat_state.is_stunned()):
		return
	var action_token := _try_begin_module_action("modulo_drone")
	if action_token == 0:
		return
	_mark_combat_event()
	_module_busy = true
	_module_token += 1
	var token := _module_token
	_start_module_cooldown("modulo_drone", float(COMBAT_DATA.MODULE_DEFINITIONS["modulo_drone"]["cooldown"]))
	var direction := aim_direction.normalized()
	_attack_label.text = "MODULO DRONE  •  CD 10s"
	var timer := get_tree().create_timer(_drone_preparation, true, false, false)
	timer.timeout.connect(func() -> void: _emit_modulo_drone(token, action_token, global_position, direction))


func _emit_modulo_drone(token: int, action_token: int, origin: Vector3, direction: Vector3) -> void:
	if token != _module_token or not _module_action_can_execute(action_token, "modulo_drone"):
		return
	if survival_mode and survival_evolution_effects != null and survival_evolution_effects.launch_sentry(origin, direction):
		_end_module_action(action_token, "modulo_drone")
		return
	var target := _select_drone_target(origin, direction)
	var visual_start := _module_visual_start(direction)
	visual_start.y = maxf(visual_start.y, global_position.y + 0.85)
	visual_start = _safe_projectile_origin(visual_start)
	var flight_direction := direction
	if target != null and is_instance_valid(target):
		flight_direction = (target.global_position + Vector3.UP * 0.9 - visual_start).normalized()
	var excluded: Array[RID] = [get_rid()]
	if survival_synergies != null:
		excluded.append_array(survival_synergies.drone_exclusions())
	if survival_mode and survival_evolution_effects != null:
		excluded.append_array(survival_evolution_effects.own_wall_exclusions())
	var projectile := LIVE_PROJECTILE.new()
	projectile.name = "ModuloDroneProjectile"
	projectile.process_mode = Node.PROCESS_MODE_PAUSABLE
	get_tree().current_scene.add_child(projectile)
	_register_fx_budget(projectile, "projectile")
	projectile.global_position = visual_start
	projectile.look_at(visual_start + flight_direction, Vector3.UP)
	projectile.configure(flight_direction, _drone_speed, _drone_max_range, 1 | 2 | 8, excluded)
	var drone := MeshInstance3D.new()
	drone.name = "DroneBody"
	var drone_mesh := SphereMesh.new()
	drone_mesh.radius = _drone_collision_radius
	drone_mesh.height = _drone_collision_radius * 2.0
	drone.mesh = drone_mesh
	drone.material_override = _create_fx_material(Color("#45ddff"), 0.96)
	projectile.add_child(drone)
	var flight: Dictionary = survival_synergies.track_drone(drone) if survival_synergies != null else {"charged": false}
	_decorate_drone_projectile(drone)
	_create_muzzle_burst(visual_start, flight_direction, Color("#45ddff"), 0.82)
	projectile.finished.connect(_on_modulo_drone_finished.bind(token, flight))

	_end_module_action(action_token, "modulo_drone")


func _on_modulo_drone_finished(hit: Dictionary, _distance: float, token: int, flight: Dictionary) -> void:
	if token != _module_token:
		return
	if survival_synergies != null:
		survival_synergies.update_flight(flight)
	if not hit.is_empty():
		var target := hit.get("collider") as Node
		if target != null and target.has_method("take_damage") and target.has_method("get_health"):
			var applied := float(target.call("take_damage", _drone_damage, "player", "modulo_drone:%d" % token))
			if applied > 0.0:
				if bool(flight.charged) and survival_synergies != null:
					survival_synergies.drone_hit(target, _drone_damage)
				if survival_mode and survival_evolution_effects != null:
					survival_evolution_effects.drone_hit(target)
				if _survival_evolved("offensive"):
					_survival_secondary_hit(target, _drone_damage * 0.5, 5.0, "drone_chain", false)
				target.call("apply_burn", _drone_burn_duration, COMBAT_DATA.BURN_DAMAGE_PER_SECOND, "player:modulo_drone")
				target.call("apply_spotted", _drone_spotted_duration, "modulo_drone")
				_create_target_hit_fx(target.global_position, false)
				target.call("flash_impact", false)
			_create_hit_flash(hit["position"], Color("#8ff7ff"), 0.50)
		else:
			_contact_fx(hit, Color("#45ddff"))
	_module_busy = false


func _decorate_drone_projectile(drone: Node3D) -> void:
	var core := MeshInstance3D.new()
	var core_mesh := SphereMesh.new()
	core_mesh.radius = _drone_collision_radius * 0.55
	core_mesh.height = _drone_collision_radius * 1.1
	core.mesh = core_mesh
	core.material_override = _create_fx_material(Color("#d8ffff"), 1.0)
	drone.add_child(core)
	var orbit := MeshInstance3D.new()
	var orbit_mesh := TorusMesh.new()
	orbit_mesh.inner_radius = 0.17
	orbit_mesh.outer_radius = 0.22
	orbit_mesh.rings = 8
	orbit_mesh.ring_segments = 14
	orbit.mesh = orbit_mesh
	orbit.rotation_degrees.x = 90.0
	orbit.material_override = _create_fx_material(Color("#7cf4ff"), 0.90)
	drone.add_child(orbit)
	var trail := MeshInstance3D.new()
	var trail_mesh := CylinderMesh.new()
	trail_mesh.top_radius = 0.018
	trail_mesh.bottom_radius = 0.09
	trail_mesh.height = 0.65
	trail.mesh = trail_mesh
	trail.rotation_degrees.x = -90.0
	trail.position.z = 0.34
	trail.material_override = _create_fx_material(Color("#2fa6d8"), 0.34)
	drone.add_child(trail)
	var pulse := drone.create_tween().set_loops()
	pulse.tween_property(orbit, "rotation_degrees", Vector3(90.0, 0.0, 180.0), 0.16).set_trans(Tween.TRANS_SINE)
	pulse.tween_property(orbit, "rotation_degrees", Vector3(90.0, 0.0, 360.0), 0.16).set_trans(Tween.TRANS_SINE)
	pulse.tween_property(drone, "scale", Vector3.ONE * 1.18, 0.10)
	pulse.tween_property(drone, "scale", Vector3.ONE, 0.10)


func _select_javelin_target(origin: Vector3, direction: Vector3) -> Node:
	var target := _module_target()
	if target == null or not is_instance_valid(target) or float(target.call("get_health")) <= 0.0:
		return null
	var offset: Vector3 = target.global_position - origin
	offset.y = 0.0
	var along := direction.dot(offset)
	var closest := origin + direction * along
	var lateral := Vector3(target.global_position.x - closest.x, 0.0, target.global_position.z - closest.z).length()
	if along <= 0.0 or along > _javelin_max_range or lateral > 0.70:
		return null
	if not _solid_path_clear(origin, target.global_position, [target.get_rid()]):
		return null
	return target


func _perform_javelin() -> void:
	if _stasis_remaining > 0.0 or _fulguro_projection_active or (combat_state != null and combat_state.is_stunned()):
		return
	if survival_mode and survival_evolution_effects != null and survival_evolution_effects.has_javelin_anchor():
		_recast_javelin()
		return
	if not survival_mode and _javelin_mark_target != null and is_instance_valid(_javelin_mark_target) and bool(_javelin_mark_target.call("has_javelin_mark")):
		_mark_combat_event()
		_recast_javelin()
		return
	_javelin_mark_target = null
	if not _module_ready("javelin"):
		return
	var action_token := _try_begin_module_action("javelin")
	if action_token == 0:
		return
	_mark_combat_event()
	_module_busy = true
	_module_token += 1
	_javelin_launch_token += 1
	var token := _javelin_launch_token
	_start_module_cooldown("javelin", float(COMBAT_DATA.MODULE_DEFINITIONS["javelin"]["cooldown"]))
	var direction := aim_direction.normalized()
	_attack_label.text = "JAVELIN  •  CD 12s"
	var timer := get_tree().create_timer(_javelin_preparation, true, false, false)
	timer.timeout.connect(func() -> void: _emit_javelin(token, action_token, global_position, direction))


func _emit_javelin(token: int, action_token: int, origin: Vector3, direction: Vector3) -> void:
	if token != _javelin_launch_token or not _module_action_can_execute(action_token, "javelin"):
		return
	if survival_mode and survival_evolution_effects != null and survival_evolution_effects.launch_beacon(origin, direction):
		_end_module_action(action_token, "javelin")
		return
	var target := _select_javelin_target(origin, direction)
	var visual_start := _module_visual_start(direction)
	visual_start.y = maxf(visual_start.y, global_position.y + 0.85)
	visual_start = _safe_projectile_origin(visual_start)
	var flight_direction := direction
	if target != null and is_instance_valid(target):
		flight_direction = (target.global_position + Vector3.UP * 0.9 - visual_start).normalized()
	var projectile := LIVE_PROJECTILE.new()
	projectile.name = "JavelinProjectile"
	projectile.process_mode = Node.PROCESS_MODE_PAUSABLE
	get_tree().current_scene.add_child(projectile)
	_register_fx_budget(projectile, "projectile")
	projectile.global_position = visual_start
	projectile.look_at(visual_start + flight_direction, Vector3.UP)
	var excluded: Array[RID] = [get_rid()]
	if survival_mode and survival_evolution_effects != null:
		excluded.append_array(survival_evolution_effects.own_wall_exclusions())
	projectile.configure(flight_direction, _javelin_speed, _javelin_max_range, 1 | 2 | 8, excluded)
	var spear := MeshInstance3D.new()
	spear.name = "JavelinBody"
	var spear_mesh := CylinderMesh.new()
	spear_mesh.top_radius = 0.025
	spear_mesh.bottom_radius = 0.11
	spear_mesh.height = 0.58
	spear.mesh = spear_mesh
	spear.material_override = _create_fx_material(Color("#ffe48b"), 0.96)
	projectile.add_child(spear)
	_decorate_javelin_projectile(spear)
	_create_muzzle_burst(visual_start, flight_direction, Color("#ffe48b"), 0.90)
	projectile.finished.connect(_on_javelin_finished.bind(token))

	_end_module_action(action_token, "javelin")


func _on_javelin_finished(hit: Dictionary, _distance: float, token: int) -> void:
	if token != _javelin_launch_token:
		return
	if not hit.is_empty():
		var target := hit.get("collider") as Node
		if target != null and target.has_method("take_damage") and target.has_method("apply_javelin_mark"):
			var applied := float(target.call("take_damage", _javelin_damage, "player", "javelin:%d" % token))
			if applied > 0.0:
				if survival_mode and survival_evolution_effects != null:
					survival_evolution_effects.javelin_hit(target, target.global_position)
				if _survival_evolved("offensive"):
					_survival_area_damage(target.global_position, 3.0, _javelin_damage * 0.45, "javelin_splash", Color("#ffe48b"), target)
				target.call("apply_javelin_mark", _javelin_mark_duration, "javelin")
				_javelin_mark_target = target
				_create_target_hit_fx(target.global_position, true)
				target.call("flash_impact", true)
				_create_hit_flash(hit["position"], Color("#fff0a1"), 0.65)
		else:
			_contact_fx(hit, Color("#ffcf6a"))
	_module_busy = false


func _decorate_javelin_projectile(spear: Node3D) -> void:
	var core := MeshInstance3D.new()
	var core_mesh := CylinderMesh.new()
	core_mesh.top_radius = 0.012
	core_mesh.bottom_radius = 0.035
	core_mesh.height = 0.48
	core.mesh = core_mesh
	core.rotation_degrees.x = -90.0
	core.position.z = -0.03
	core.material_override = _create_fx_material(Color("#fff4c2"), 1.0)
	spear.add_child(core)
	var trail := MeshInstance3D.new()
	var trail_mesh := CylinderMesh.new()
	trail_mesh.top_radius = 0.012
	trail_mesh.bottom_radius = 0.07
	trail_mesh.height = 0.86
	trail.mesh = trail_mesh
	trail.rotation_degrees.x = -90.0
	trail.position.z = 0.48
	trail.material_override = _create_fx_material(Color("#ff9e45"), 0.30)
	spear.add_child(trail)
	var pulse := spear.create_tween().set_loops()
	pulse.tween_property(spear, "scale", Vector3(1.14, 1.0, 1.14), 0.10)
	pulse.tween_property(spear, "scale", Vector3.ONE, 0.14)


func _recast_javelin(preferred_destination: Vector3 = Vector3.INF) -> void:
	if survival_mode and survival_evolution_effects != null:
		survival_evolution_effects.recall_javelin()
		return
	var target := _javelin_mark_target
	if target == null or not is_instance_valid(target) or not bool(target.call("has_javelin_mark")):
		_javelin_mark_target = null
		return
	if float(target.call("get_health")) <= 0.0 or global_position.distance_to(target.global_position) > _javelin_max_range or not _solid_path_clear(global_position, target.global_position, [target.get_rid()]):
		_attack_label.text = "JAVELIN  •  REACTIVATION REFUSÉE"
		return
	var destination := preferred_destination if preferred_destination.is_finite() else _find_javelin_destination(target)
	if preferred_destination.is_finite() and not _javelin_destination_valid(target, preferred_destination):
		destination = Vector3.INF
	if destination == Vector3.INF:
		_attack_label.text = "JAVELIN  •  DESTINATION BLOQUÉE"
		return
	var action_token := _try_begin_module_action("javelin_recast")
	if action_token == 0:
		return
	_mark_combat_event()
	var teleport_origin := global_position
	_cancel_pelto_pull()
	global_position = destination
	if survival_synergies != null:
		survival_synergies.teleport_trail(teleport_origin, destination)
	target.call("clear_javelin_mark")
	_javelin_mark_target = null
	_create_teleport_fx(destination)
	get_node("/root/GameSfx").play_event("javelin_teleport")
	_attack_label.text = "JAVELIN  •  TÉLÉPORTÉ"
	_end_module_action(action_token, "javelin_recast")


func _find_javelin_destination(target: Node) -> Vector3:
	var behind: Vector3 = target.global_transform.basis.z
	behind.y = 0.0
	behind = behind.normalized() if behind.length_squared() > 0.001 else Vector3(0.0, 0.0, 1.0)
	var base: Vector3 = target.global_position + behind * _javelin_teleport_distance
	var candidates: Array[Vector3] = [base, target.global_position + behind.rotated(Vector3.UP, deg_to_rad(30.0)) * _javelin_teleport_distance, target.global_position + behind.rotated(Vector3.UP, deg_to_rad(-30.0)) * _javelin_teleport_distance]
	for candidate in candidates:
		candidate.y = 0.0
		if _javelin_destination_valid(target, candidate):
			return candidate
	return Vector3.INF


func _javelin_destination_valid(target: Node, candidate: Vector3) -> bool:
	if target == null or not is_instance_valid(target) or not target is CollisionObject3D or not candidate.is_finite():
		return false
	if absf(candidate.x) > 23.0 or absf(candidate.z) > 23.0:
		return false
	if not _solid_path_clear(global_position, candidate):
		return false
	var world := get_world_3d()
	if world == null:
		return true
	var query := PhysicsPointQueryParameters3D.new()
	query.position = candidate + Vector3.UP * 0.72
	query.collision_mask = 1
	query.collide_with_bodies = true
	query.exclude = [get_rid(), (target as CollisionObject3D).get_rid()]
	return world.direct_space_state.intersect_point(query, 8).is_empty()


func _begin_blaster_charge(now: float = -1.0) -> void:
	if _weapon_id != "blaster" or _blaster_charge_active or _blaster_attack_busy:
		return
	if now < 0.0:
		now = Time.get_ticks_msec() / 1000.0
	if now < _blaster_next_attack_ready_at:
		return
	var action_token := _try_begin_weapon_action("blaster")
	if action_token == 0:
		return
	_blaster_action_token = action_token
	_blaster_charge_active = true
	_begin_weapon_aim()
	_blaster_charge_started_at = now
	_blaster_charge_ratio = 0.0
	_blaster_ready_cued = false
	if _blaster_charge_audio_fade != null and _blaster_charge_audio_fade.is_running():
		_blaster_charge_audio_fade.kill()
	_blaster_charge_audio.stop()
	_blaster_charge_hold_audio.stop()
	_blaster_ready_audio.stop()
	_blaster_charge_audio.volume_db = -9.0
	_blaster_charge_hold_audio.volume_db = -10.0
	_blaster_charge_audio.play()
	_mark_combat_event()
	if _attack_label != null:
		_attack_label.text = ""
	_update_blaster_charge_visual(0.0)


func _play_blaster_ready_sound() -> void:
	if _blaster_ready_cued or not _blaster_charge_active:
		return
	_blaster_ready_cued = true
	_blaster_charge_audio.stop()
	_blaster_charge_hold_audio.play()
	_blaster_ready_audio.play()


func _stop_blaster_charge_audio() -> void:
	if _blaster_charge_audio == null:
		return
	_blaster_ready_audio.stop()
	if _blaster_charge_audio_fade != null and _blaster_charge_audio_fade.is_running():
		_blaster_charge_audio_fade.kill()
	if not _blaster_charge_audio.playing and not _blaster_charge_hold_audio.playing:
		return
	_blaster_charge_audio_fade = create_tween().set_parallel(true)
	if _blaster_charge_audio.playing:
		_blaster_charge_audio_fade.tween_property(_blaster_charge_audio, "volume_db", -60.0, 0.02)
	if _blaster_charge_hold_audio.playing:
		_blaster_charge_audio_fade.tween_property(_blaster_charge_hold_audio, "volume_db", -60.0, 0.02)
	_blaster_charge_audio_fade.chain().tween_callback(_finish_blaster_charge_audio_stop)


func _finish_blaster_charge_audio_stop() -> void:
	_blaster_charge_audio.stop()
	_blaster_charge_hold_audio.stop()
	_blaster_charge_audio.volume_db = -9.0
	_blaster_charge_hold_audio.volume_db = -10.0


func _cancel_blaster_charge(reason: String = "", release_action: bool = true) -> void:
	_stop_blaster_charge_audio()
	_blaster_charge_active = false
	_blaster_charge_started_at = -1.0
	_blaster_charge_ratio = 0.0
	_blaster_ready_cued = false
	if _blaster_charge_visual != null:
		_blaster_charge_visual.visible = false
	if _blaster_light != null:
		_blaster_light.light_energy = 0.0
	if release_action:
		_action_gate.release(_blaster_action_token)
		_blaster_action_token = 0
	if reason != "" and _attack_label != null:
		_attack_label.text = reason


func _cancel_blaster_attack() -> void:
	if _blaster_attack_busy:
		_blaster_attack_token += 1
		_blaster_attack_busy = false
	_action_gate.release(_blaster_action_token)
	_blaster_action_token = 0


func _release_blaster_charge() -> void:
	if not _blaster_charge_active:
		return
	var ratio := clampf(_blaster_charge_ratio, 0.0, 1.0)
	var damage := lerpf(_blaster_damage, _blaster_max_damage, ratio)
	var direction := aim_direction.normalized()
	var action_token := _blaster_action_token
	_cancel_blaster_charge("", false)
	_fire_blaster_projectile(damage, ratio, direction, action_token)


func _fire_blaster_projectile(damage: float, charge_ratio: float, direction: Vector3, reserved_action_token: int = 0) -> void:
	if _weapon_id != "blaster" or _blaster_attack_busy:
		if reserved_action_token != 0:
			_action_gate.release(reserved_action_token)
			if _blaster_action_token == reserved_action_token:
				_blaster_action_token = 0
		return
	var now := Time.get_ticks_msec() / 1000.0
	if now < _blaster_next_attack_ready_at:
		if reserved_action_token != 0:
			_action_gate.release(reserved_action_token)
			if _blaster_action_token == reserved_action_token:
				_blaster_action_token = 0
		return
	var action_token := reserved_action_token
	if action_token == 0:
		action_token = _try_begin_weapon_action("blaster")
	if not _action_gate.owns(action_token, ACTION_GATE.Kind.WEAPON, "blaster"):
		return
	_blaster_action_token = action_token
	_mark_combat_event()
	var shot_audio := _blaster_charged_shot_audio if charge_ratio >= 0.85 else _blaster_shot_audio
	shot_audio.pitch_scale = lerpf(1.05, 0.94, charge_ratio)
	shot_audio.play()
	_set_aim_direction(direction)
	var shot_direction := _normalized_aim_direction()
	_last_projectile_direction = shot_direction
	var wait_for_firing_pose := _visual_rig != null and not _visual_rig.is_aim_pose_committed()
	_begin_weapon_fire()
	_blaster_attack_token += 1
	var token := _blaster_attack_token
	_blaster_attack_busy = true
	_blaster_next_attack_ready_at = now + (0.01 if training_instant_cooldowns else _blaster_cooldown)
	_play_blaster_recoil(charge_ratio)
	_camera_impulse(0.045 + charge_ratio * 0.035, 0.018 + charge_ratio * 0.034)
	if wait_for_firing_pose and _visual_rig != null and _visual_rig.skeleton != null:
		# Bone attachments update with the final skeleton pass. Delay only a tap that
		# began below full aim; charged/held fire emits immediately from the muzzle.
		await _visual_rig.skeleton.skeleton_updated
		if token != _blaster_attack_token or _weapon_id != "blaster" or not _action_gate.owns(action_token, ACTION_GATE.Kind.WEAPON, "blaster"):
			return
	var origin := _blaster_muzzle.global_position if _blaster_muzzle != null else global_position + Vector3.UP * 0.90 + shot_direction * 0.62
	origin = _safe_projectile_origin(origin)
	_create_muzzle_burst(origin, shot_direction, Color("#64e9ff"), 1.0 + charge_ratio * 0.65, _blaster_muzzle)
	_spawn_blaster_projectile(origin, damage, charge_ratio, token, shot_direction)
	_action_gate.release(action_token)
	if _blaster_action_token == action_token:
		_blaster_action_token = 0
	# The fire lock is governed solely by the 0.45 s cooldown. Projectile travel
	# may continue visually beyond that window without blocking the next shot.
	_blaster_attack_busy = false
	if _attack_label != null:
		_attack_label.text = "BLASTER  •  TIR %d DÉGÂTS" % roundi(damage)
	if _blaster_light != null:
		_blaster_light.light_energy = 0.0


func _play_blaster_recoil(charge_ratio: float) -> void:
	_kill_weapon_recoil_tweens(_blaster_recoil_tweens)
	if _blaster_sway_pivot != null:
		_blaster_sway_pivot.transform = Transform3D.IDENTITY
	if _blaster_recoil_pivot != null:
		_blaster_recoil_pivot.transform = Transform3D.IDENTITY
	if _has_skeletal_weapon_attachment():
		_update_aim_pose_state()
		_visual_rig.play_shot_kick(charge_ratio)
		return
	# The procedural fallback has no bones to absorb the impulse.
	if _blaster_recoil_pivot == null:
		return
	_blaster_recoil_pivot.transform = Transform3D.IDENTITY
	var recoil_distance := 0.07 + charge_ratio * 0.10
	var position_tween := create_tween()
	position_tween.tween_property(_blaster_recoil_pivot, "position", Vector3(0.0, 0.0, recoil_distance), 0.045).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	position_tween.tween_property(_blaster_recoil_pivot, "position", Vector3(0.0, 0.0, -0.025), 0.06).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	position_tween.tween_property(_blaster_recoil_pivot, "position", Vector3.ZERO, 0.15).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_blaster_recoil_tweens.append(position_tween)
	var rotation_tween := create_tween()
	rotation_tween.tween_property(_blaster_recoil_pivot, "rotation", Vector3(0.0, 0.0, deg_to_rad(-2.4 - charge_ratio * 2.0)), 0.045).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	rotation_tween.tween_property(_blaster_recoil_pivot, "rotation", Vector3(0.0, 0.0, deg_to_rad(0.7)), 0.06).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	rotation_tween.tween_property(_blaster_recoil_pivot, "rotation", Vector3.ZERO, 0.15).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_blaster_recoil_tweens.append(rotation_tween)


func _kill_weapon_recoil_tweens(tweens: Array[Tween]) -> void:
	for tween in tweens:
		if tween != null and tween.is_running():
			tween.kill()
	tweens.clear()


func _is_weapon_recoil_running(tweens: Array[Tween]) -> bool:
	for tween in tweens:
		if tween != null and tween.is_running():
			return true
	return false


func _safe_projectile_origin(muzzle: Vector3) -> Vector3:
	var origin := global_position + Vector3.UP * 0.9
	var query := PhysicsRayQueryParameters3D.create(origin, muzzle)
	query.collision_mask = 1 | 2 | 4 | 8
	query.collide_with_areas = true
	# A contact overlap can put the reference point inside the target. Without
	# inside hits this segment ignores it and emits beyond the far side.
	query.hit_from_inside = true
	query.exclude = [get_rid()]
	return origin if not get_world_3d().direct_space_state.intersect_ray(query).is_empty() else muzzle


func _spawn_blaster_projectile(start: Vector3, damage: float, charge_ratio: float, token: int, shot_direction: Vector3) -> void:
	var projectile := LIVE_PROJECTILE.new()
	projectile.name = "BlasterProjectile"
	projectile.process_mode = Node.PROCESS_MODE_PAUSABLE
	get_tree().current_scene.add_child(projectile)
	projectile.add_to_group("prototype0_gameplay_projectiles")
	projectile.global_position = start
	projectile.look_at(start + shot_direction, Vector3.UP)
	var excluded: Array[RID] = [get_rid()]
	if survival_mode and survival_evolution_effects != null:
		excluded.append_array(survival_evolution_effects.own_wall_exclusions())
	projectile.configure(shot_direction, _blaster_projectile_speed, _blaster_max_range, 1 | 2 | 8, excluded)
	projectile.finished.connect(_on_blaster_projectile_finished.bind(damage, charge_ratio, token, shot_direction))
	var vfx := _vfx_manager()
	if vfx != null:
		var shot_color := Color("#52dff4").lerp(Color("#718cff"), charge_ratio * charge_ratio * 0.78)
		vfx.call("projectile_visual", projectile, "blaster", charge_ratio)
		var tracer_end := _blaster_obstacle_endpoint(start, start + shot_direction * (1.15 + charge_ratio * 0.55))
		vfx.call("tracer", start, tracer_end, 0.036 + charge_ratio * 0.034, shot_color, 0.058 + charge_ratio * 0.014)


func _on_blaster_projectile_finished(hit: Dictionary, _distance: float, damage: float, charge_ratio: float, token: int, shot_direction: Vector3) -> void:
	if hit.is_empty():
		return
	var target := hit.get("collider") as Node
	if target != null and target.has_method("take_damage") and target.has_method("get_health"):
		var applied := float(target.call("take_damage", damage, "player", "blaster:%d" % token))
		if applied > 0.0:
			if survival_synergies != null:
				survival_synergies.blaster_hit(target, charge_ratio)
			if survival_mode and survival_evolution_effects != null:
				survival_evolution_effects.blaster_hit(target, damage, charge_ratio, shot_direction)
			if _survival_evolved("weapon"):
				_survival_secondary_hit(target, damage * 0.6, 9.0, "blaster_pierce", true, shot_direction)
			target.call("flash_impact", charge_ratio >= 0.99)
	var impact_color := Color("#52dff4").lerp(Color("#718cff"), charge_ratio * charge_ratio * 0.78)
	_contact_fx(hit, impact_color, 0.8 + charge_ratio * 0.95)

func _blaster_obstacle_endpoint(start: Vector3, end: Vector3) -> Vector3:
	var world := get_world_3d()
	if world == null:
		return end
	var query := PhysicsRayQueryParameters3D.create(start, end)
	query.collision_mask = 9
	query.collide_with_areas = true
	query.collide_with_bodies = true
	query.exclude = [get_rid()]
	var result := world.direct_space_state.intersect_ray(query)
	return result["position"] if not result.is_empty() else end


func _blaster_path_clear(target: Node, from_position: Vector3, to_position: Vector3) -> bool:
	return _module_path_clear(from_position, to_position, [target.get_rid()]) if target != null and is_instance_valid(target) else true


func _update_blaster_charge_visual(_delta: float) -> void:
	if _blaster_charge_visual == null:
		return
	if not _blaster_charge_active:
		_blaster_charge_visual.visible = false
		return
	_blaster_charge_visual.visible = true
	var ratio := clampf(_blaster_charge_ratio, 0.0, 1.0)
	var charge_curve := ratio * ratio
	var pulse := sin(float(Time.get_ticks_msec()) * 0.018) * (0.018 + charge_curve * 0.055)
	_blaster_charge_visual.scale = Vector3.ONE * (0.28 + ratio * 0.25 + charge_curve * 0.28 + pulse)
	if _blaster_charge_material != null:
		_blaster_charge_material.emission_energy_multiplier = 1.15 + ratio * 1.25 + charge_curve * 1.25
		_blaster_charge_material.albedo_color = Color(0.30 + ratio * 0.13, 0.76 + ratio * 0.05, 0.92 + ratio * 0.06, 0.20 + ratio * 0.16 + charge_curve * 0.16)
	if _blaster_light != null:
		_blaster_light.light_energy = 0.0
	if _attack_label != null:
		_attack_label.text = "BLASTER  •  CHARGE %d%%" % roundi(ratio * 100.0)


func get_blaster_charge_ratio() -> float:
	return _blaster_charge_ratio if _blaster_charge_active else 0.0


func is_blaster_charging() -> bool:
	return _blaster_charge_active


func _create_teleport_fx(origin: Vector3) -> void:
	_spawn_particle_burst(origin + Vector3.UP * 0.45, Color("#dac99a"), 10, 0.25, 2.8, 0.12, Vector3.UP, 48.0)

func _perform_axe_attack() -> void:
	var action_token := _try_begin_weapon_action("legacy_axe")
	if action_token == 0:
		return
	_axe_action_token = action_token
	_mark_combat_event()
	var step := _combo_step
	_combo_step = (_combo_step + 1) % 3
	_axe_attack_token += 1
	var token := _axe_attack_token
	_axe_attack_busy = true
	_axe_attack_step = step
	_axe_attack_origin = global_position
	_axe_attack_direction = aim_direction.normalized()
	_axe_attack_impact_point = _axe_attack_origin + _axe_attack_direction * float(_axe_wave_outer_radius)
	_combo_expires_at = -1.0
	_attack_label.text = "LEGACY ATTACK  •  COUP %d/3" % (step + 1)
	var attack_speed := get_attack_speed_multiplier()
	_play_axe_animation(step, attack_speed)
	_begin_axe_trail(step, attack_speed)
	var total := (float(_axe_preparation[step]) + float(_axe_active[step]) + float(_axe_recovery[step])) / attack_speed
	if step < 2:
		var strike_timer := get_tree().create_timer((float(_axe_preparation[step]) + float(_axe_active[step]) * 0.5) / attack_speed, true, false, false)
		strike_timer.timeout.connect(func() -> void: _resolve_axe_strike(token, step))
	else:
		var center_timer := get_tree().create_timer(float(_axe_preparation[step]) / attack_speed, true, false, false)
		center_timer.timeout.connect(func() -> void: _resolve_axe_center(token))
		var wave_timer := get_tree().create_timer((float(_axe_preparation[step]) + float(_axe_active[step])) / attack_speed, true, false, false)
		wave_timer.timeout.connect(func() -> void: _resolve_axe_wave(token))
	var finish_timer := get_tree().create_timer(total, true, false, false)
	finish_timer.timeout.connect(func() -> void: _finish_axe_attack(token))


func _attack_token_valid(token: int) -> bool:
	return is_inside_tree() and _axe_attack_busy and token == _axe_attack_token and _action_gate.owns(_axe_action_token, ACTION_GATE.Kind.WEAPON, "legacy_axe") and not (combat_state != null and combat_state.is_stunned())


func _resolve_axe_strike(token: int, step: int) -> void:
	if not _attack_token_valid(token):
		return
	var target := get_tree().current_scene.get_node_or_null("TargetDummy")
	var did_hit := target != null and _axe_target_in_shape(target, step)
	var impact_point: Vector3 = target.global_position if did_hit else _axe_attack_origin + _axe_attack_direction * float(_axe_range[step])
	var tip_position := _axe_tip.global_position if _axe_tip != null else global_position + Vector3.UP * 0.96 + _axe_attack_direction * 1.68
	_show_attack_hitbox(step, impact_point, did_hit, tip_position, _get_axe_forward())
	if not did_hit:
		return
	_apply_axe_hit(target, impact_point, float(_axe_damage[step]), _axe_slow_duration[step], false, token, step)


func _resolve_axe_center(token: int) -> void:
	if not _attack_token_valid(token):
		return
	var target := get_tree().current_scene.get_node_or_null("TargetDummy")
	var did_hit := target != null and _axe_target_in_radius(target, _axe_wave_inner_radius)
	var impact_point := _axe_attack_origin
	_show_attack_hitbox(2, impact_point, did_hit, _axe_tip.global_position if _axe_tip != null else impact_point, _get_axe_forward(), "center")
	if not did_hit:
		return
	_apply_axe_hit(target, impact_point, float(_axe_damage[2]), 0.0, true, token, 20)


func _resolve_axe_wave(token: int) -> void:
	if not _attack_token_valid(token):
		return
	var target := get_tree().current_scene.get_node_or_null("TargetDummy")
	var did_hit := target != null and _axe_target_in_wave(target)
	var impact_point := _axe_attack_origin
	_show_attack_hitbox(2, impact_point, did_hit, _axe_tip.global_position if _axe_tip != null else impact_point, _get_axe_forward(), "wave")
	if not did_hit:
		return
	_apply_axe_hit(target, impact_point, 45.0, _axe_slow_duration[2], false, token, 21)


func _apply_axe_hit(target: Node, impact_point: Vector3, damage: float, slow_duration: float, critical_hit: bool, token: int, phase: int) -> void:
	if target == null or not is_instance_valid(target):
		return
	var attack_id := "legacy_attack:%d:%d%s" % [token, phase, ":critical" if critical_hit else ""]
	var effective_damage := float(target.call("take_damage", damage, "player", attack_id))
	if critical_hit:
		target.call("apply_stun", _axe_stun_duration, "legacy_attack")
	elif slow_duration > 0.0:
		target.call("apply_slow", slow_duration, _axe_slow_percent, "legacy_attack")
	target.call("flash_impact", critical_hit)
	_create_target_hit_fx(impact_point, critical_hit)
	if effective_damage > 0.0:
		_trigger_hit_stop(HIT_STOP_CRITICAL if critical_hit else HIT_STOP_NORMAL)


func _finish_axe_attack(token: int) -> void:
	if token != _axe_attack_token or not _axe_attack_busy:
		return
	_axe_attack_busy = false
	_axe_attack_step = -1
	_action_gate.release(_axe_action_token)
	_axe_action_token = 0
	var now := Time.get_ticks_msec() / 1000.0
	_combo_expires_at = now + LEGACY_COMBO_WINDOW
	_next_attack_ready_at = now


func _cancel_axe_attack() -> void:
	if not _axe_attack_busy:
		_action_gate.release(_axe_action_token)
		_axe_action_token = 0
		return
	_axe_attack_token += 1
	_axe_attack_busy = false
	_axe_attack_step = -1
	_action_gate.release(_axe_action_token)
	_axe_action_token = 0
	_combo_step = 0
	var now := Time.get_ticks_msec() / 1000.0
	_combo_expires_at = now + LEGACY_COMBO_WINDOW
	_next_attack_ready_at = now
	_finish_axe_trail(0.10)
	_attack_label.text = "LEGACY ATTACK  •  INTERROMPU"
	if _axe_pivot != null:
		var tween := create_tween()
		tween.tween_property(_axe_pivot, "position", _axe_pivot_home, 0.12)
		tween.tween_property(_axe_pivot, "rotation", _axe_pivot_home_rotation, 0.12)


func _axe_target_in_shape(target: Node, step: int) -> bool:
	var flat_offset: Vector3 = target.global_position - _axe_attack_origin
	flat_offset.y = 0.0
	var distance: float = flat_offset.length()
	if distance <= 0.01 or not _axe_path_clear(target, _axe_attack_origin, target.global_position):
		return false
	var along := _axe_attack_direction.dot(flat_offset)
	if step == 0:
		var lateral := absf(_axe_attack_direction.cross(flat_offset).y)
		return along > 0.0 and along <= float(_axe_range[0]) and lateral <= _axe_estoc_width * 0.5
	var facing_dot := _axe_attack_direction.dot(flat_offset.normalized())
	return distance <= float(_axe_range[1]) and facing_dot >= cos(deg_to_rad(_axe_sweep_half_angle))


func _axe_target_in_radius(target: Node, radius: float) -> bool:
	var flat_offset: Vector3 = target.global_position - _axe_attack_origin
	flat_offset.y = 0.0
	return flat_offset.length() > 0.01 and flat_offset.length() <= radius and _axe_path_clear(target, _axe_attack_origin, target.global_position)


func _axe_target_in_wave(target: Node) -> bool:
	var flat_offset: Vector3 = target.global_position - _axe_attack_origin
	flat_offset.y = 0.0
	var distance: float = flat_offset.length()
	return distance > _axe_wave_inner_radius and distance <= _axe_wave_outer_radius and _axe_path_clear(target, _axe_attack_origin, target.global_position)


func _axe_path_clear(target: Node, from_position: Vector3, to_position: Vector3) -> bool:
	var world := get_world_3d()
	if world == null:
		return true
	var query := PhysicsRayQueryParameters3D.create(from_position + Vector3.UP * 0.72, to_position + Vector3.UP * 0.72)
	query.collision_mask = 1
	query.collide_with_areas = false
	query.collide_with_bodies = true
	query.exclude = [get_rid(), target.get_rid()]
	return world.direct_space_state.intersect_ray(query).is_empty()


func _play_axe_animation(step: int, speed_multiplier: float = 1.0) -> void:
	if _axe_pivot == null:
		return
	var speed_scale := 1.0 / maxf(0.01, speed_multiplier)
	var tween := create_tween()
	tween.set_parallel(false)
	tween.tween_property(_axe_pivot, "position", _axe_pivot_home, 0.01 * speed_scale)
	tween.tween_property(_axe_pivot, "rotation", _axe_pivot_home_rotation, 0.01 * speed_scale)
	if step == 0:
		# A readable thrust: the weapon lunges toward the target and snaps back.
		tween.tween_property(_axe_pivot, "position", Vector3(0.5, 1.0, -0.20), 0.20 * speed_scale)
		tween.tween_property(_axe_pivot, "position", Vector3(0.5, 1.0, -1.65), 0.10 * speed_scale)
		tween.tween_property(_axe_pivot, "position", _axe_pivot_home, 0.25 * speed_scale)
	elif step == 1:
		# A lateral sweep, with a brief anticipation in the opposite direction.
		tween.tween_property(_axe_pivot, "rotation", Vector3(0.0, deg_to_rad(-65.0), deg_to_rad(-12.0)), 0.20 * speed_scale)
		tween.tween_property(_axe_pivot, "rotation", Vector3(0.0, deg_to_rad(78.0), deg_to_rad(14.0)), 0.10 * speed_scale)
		tween.tween_property(_axe_pivot, "rotation", _axe_pivot_home_rotation, 0.30 * speed_scale)
	else:
		# Overhead slam: weapon rises, pauses, then drives down into the floor.
		tween.tween_property(_axe_pivot, "rotation", Vector3(deg_to_rad(-72.0), 0.0, 0.0), 0.35 * speed_scale)
		tween.tween_property(_axe_pivot, "rotation", Vector3(deg_to_rad(78.0), 0.0, 0.0), 0.25 * speed_scale)
		tween.tween_property(_axe_pivot, "rotation", _axe_pivot_home_rotation, 0.25 * speed_scale)
	if _robot_visuals != null:
		var recoil := create_tween()
		recoil.tween_property(_robot_visuals, "position", _world_offset_to_visual_local(-aim_direction * (0.10 if step < 2 else 0.18)), 0.06)
		recoil.tween_property(_robot_visuals, "position", Vector3.ZERO, 0.18 if step < 2 else 0.28)
		recoil.tween_property(_robot_visuals, "rotation", Vector3(0.0, 0.0, deg_to_rad(-7.0 if step == 1 else 0.0)), 0.05)
		recoil.tween_property(_robot_visuals, "rotation", Vector3.ZERO, 0.16)
	if _axe_light != null:
		_axe_light.light_energy = 8.0 if step == 2 else 5.0
		var light_tween := create_tween()
		light_tween.tween_property(_axe_light, "light_energy", 0.0, 0.24 if step < 2 else 0.42)
	var rig := get_tree().current_scene.get_node_or_null("CameraRig")
	if rig != null and rig.has_method("shake"):
		rig.call("shake", 0.05 if step < 2 else 0.13)


func _begin_axe_trail(step: int, speed_multiplier: float = 1.0) -> void:
	_finish_axe_trail(0.08)
	_trail_points.clear()
	_trail_elapsed = 0.0
	_trail_duration = (float(_axe_preparation[step]) + float(_axe_active[step]) + float(_axe_recovery[step])) / maxf(0.01, speed_multiplier)
	_trail_width = [0.07, 0.24, 0.13][step]
	_trail_active = true
	_trail_mesh = MeshInstance3D.new()
	_trail_mesh.name = "AxeEnergyTrail"
	_trail_material = _create_fx_material(Color("#7befff") if step < 2 else Color("#d8fcff"), 0.78)
	get_tree().current_scene.add_child(_trail_mesh)


func _update_axe_trail(delta: float) -> void:
	if not _trail_active or _axe_tip == null or _trail_mesh == null:
		return
	_trail_elapsed += delta
	var tip_position := _axe_tip.global_position
	if _trail_points.is_empty() or _trail_points[-1].distance_to(tip_position) >= 0.025:
		_trail_points.append(tip_position)
		if _trail_points.size() > 18:
			_trail_points.pop_front()
		_rebuild_axe_trail()
	if _trail_elapsed >= _trail_duration:
		_finish_axe_trail(0.22)


func _rebuild_axe_trail() -> void:
	if _trail_mesh == null or _trail_points.size() < 2:
		return
	var mesh := ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES, _trail_material)
	for index in range(1, _trail_points.size()):
		var previous := _trail_points[index - 1]
		var current := _trail_points[index]
		var movement := current - previous
		var side := movement.cross(Vector3.UP).normalized()
		if side.length_squared() < 0.001:
			side = Vector3(-aim_direction.z, 0.0, aim_direction.x).normalized()
		var age_ratio := float(index) / float(_trail_points.size() - 1)
		var segment_width := _trail_width * lerpf(0.20, 1.0, age_ratio)
		var previous_left := previous - side * segment_width
		var previous_right := previous + side * segment_width
		var current_left := current - side * segment_width
		var current_right := current + side * segment_width
		mesh.surface_add_vertex(previous_left)
		mesh.surface_add_vertex(previous_right)
		mesh.surface_add_vertex(current_right)
		mesh.surface_add_vertex(previous_left)
		mesh.surface_add_vertex(current_right)
		mesh.surface_add_vertex(current_left)
	mesh.surface_end()
	_trail_mesh.mesh = mesh


func _finish_axe_trail(fade_duration: float) -> void:
	if not _trail_active:
		return
	_trail_active = false
	var finished_mesh := _trail_mesh
	var finished_material := _trail_material
	_trail_mesh = null
	_trail_material = null
	if finished_mesh == null:
		return
	var tween := create_tween()
	if finished_material != null:
		tween.tween_method(Callable(self, "_set_material_alpha").bind(finished_material), finished_material.albedo_color.a, 0.0, fade_duration)
	tween.tween_callback(finished_mesh.queue_free)


func _trigger_hit_stop(duration: float) -> void:
	if Engine.time_scale < 1.0:
		return
	Engine.time_scale = 0.08
	var timer := get_tree().create_timer(duration, true, false, true)
	timer.timeout.connect(func() -> void:
		Engine.time_scale = 1.0
	)


func _create_fx_material(color: Color, alpha: float = 0.9) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(color.r, color.g, color.b, alpha)
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = 1.6
	return material


func _register_fx_budget(node: Node, category: String = "burst") -> void:
	var scene := get_tree().current_scene if get_tree() != null else null
	if scene != null and scene.has_method("register_fx_node"):
		scene.call("register_fx_node", node, category)


func _set_material_alpha(alpha: float, material: StandardMaterial3D) -> void:
	if material == null:
		return
	var color := material.albedo_color
	color.a = alpha
	material.albedo_color = color


func _create_lightning_arc(start: Vector3, end: Vector3, color: Color, width: float = 0.045, lifetime: float = 0.24) -> void:
	var vfx := _vfx_manager()
	if vfx != null:
		vfx.call("tracer", start, end, width, color, lifetime)

func _create_axe_lightning(step: int, tip_position: Vector3) -> void:
	var blade_origin := tip_position
	var forward := _get_axe_forward()
	var blade_end := tip_position + forward * (0.75 if step == 0 else 0.45)
	var bolt_color := Color("#8ff7ff")
	for index in range(3 if step < 2 else 6):
		var side := Vector3.UP * randf_range(-0.20, 0.30) + Vector3(-forward.z, 0.0, forward.x) * randf_range(-0.45, 0.45)
		_create_lightning_arc(blade_origin + side, blade_end + side * 0.3, bolt_color, 0.04, 0.26 if step < 2 else 0.42)


func _get_axe_forward() -> Vector3:
	if _axe_tip != null:
		var forward := -_axe_tip.global_transform.basis.z
		forward.y = 0.0
		if forward.length_squared() > 0.001:
			return forward.normalized()
	return aim_direction


func _spawn_particle_burst(origin: Vector3, color: Color, amount: int, lifetime: float, speed: float, particle_scale: float, emission_direction: Vector3 = Vector3.UP, emission_spread: float = 180.0) -> void:
	var vfx := _vfx_manager()
	if vfx != null:
		vfx.call("burst", origin, emission_direction, color, mini(amount, 12), minf(speed, 5.0), minf(lifetime, 0.4), minf(particle_scale * 0.45, 0.06), minf(emission_spread, 75.0))

func _play_impact_fx(step: int, impact_point: Vector3, did_hit: bool, tip_position: Vector3, tip_forward: Vector3, phase: String = "") -> void:
	_create_axe_lightning(step, tip_position)
	if step == 0:
		var start := tip_position
		var end := impact_point + Vector3.UP * 0.92 if did_hit else tip_position + tip_forward * 1.0
		for index in range(3):
			_create_lightning_arc(start + Vector3.UP * (float(index) - 1.0) * 0.08, end + Vector3.UP * (float(index) - 1.0) * 0.08, Color("#67eaff") if index < 2 else Color("#d2fcff"), 0.05, 0.30)
		_spawn_particle_burst(tip_position, Color("#a9f5ff"), 16 if did_hit else 8, 0.32, 5.0, 0.16, tip_forward, 42.0)
		if did_hit:
			_create_hit_flash(impact_point, Color("#a9f5ff"), 0.65)
		else:
			_create_surface_impact_fx(impact_point, -tip_forward, Color("#62e7ff"))
	elif step == 1:
		var center := tip_position
		var forward := tip_forward
		var side := Vector3(-forward.z, 0.0, forward.x)
		var reach := float(_axe_range[1]) if not did_hit else maxf(0.5, (impact_point - _axe_attack_origin).length())
		_create_cleave_arc(center, forward, side, reach, 0.0, Color("#52e7ff"), 0.32)
		_create_cleave_arc(center + Vector3.UP * 0.10, forward, side, reach * 0.92, 0.12, Color("#d5fcff"), 0.38)
		_spawn_particle_burst(tip_position, Color("#55e9ff"), 22 if did_hit else 12, 0.42, 4.0, 0.14, tip_forward, 70.0)
		if did_hit:
			_create_hit_flash(impact_point, Color("#72edff"), 0.8)
		else:
			_create_surface_impact_fx(impact_point, -forward, Color("#52d9ef"))
	else:
		if phase == "center":
			_create_hit_flash(impact_point, Color("#fff0a1"), 0.90)
			_spawn_particle_burst(impact_point + Vector3.UP * 0.72, Color("#eaffff"), 22, 0.42, 5.0, 0.14)
			return
		_create_shockwave_fx(impact_point)


func _create_hit_flash(origin: Vector3, color: Color, radius: float) -> void:
	_spawn_particle_burst(origin, color, 6, 0.18, 2.4, minf(radius * 0.10, 0.11), Vector3.UP, 65.0)

func _create_target_hit_fx(origin: Vector3, critical: bool) -> void:
	var color := Color("#efd099") if critical else Color("#dca579")
	_spawn_particle_burst(origin + Vector3.UP * 0.85, color, 9 if critical else 5, 0.23, 3.2, 0.10, -aim_direction, 55.0)

func _create_slash_fan(radius: float, half_angle: float) -> MeshInstance3D:
	var slash := MeshInstance3D.new()
	var mesh := ImmediateMesh.new()
	var material := _create_fx_material(Color("#56dcff"), 0.72)
	mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES, material)
	var segments := 10
	for index in range(segments):
		var a0 := -half_angle + (2.0 * half_angle) * float(index) / float(segments)
		var a1 := -half_angle + (2.0 * half_angle) * float(index + 1) / float(segments)
		mesh.surface_add_vertex(Vector3.ZERO)
		mesh.surface_add_vertex(Vector3(sin(a0) * radius, 0.0, -cos(a0) * radius))
		mesh.surface_add_vertex(Vector3(sin(a1) * radius, 0.0, -cos(a1) * radius))
	mesh.surface_end()
	slash.mesh = mesh
	return slash


func _create_slash_outline(radius: float, half_angle: float, color: Color) -> MeshInstance3D:
	var outline := MeshInstance3D.new()
	var mesh := ImmediateMesh.new()
	var material := _create_fx_material(color, 0.95)
	mesh.surface_begin(Mesh.PRIMITIVE_LINES, material)
	var segments := 14
	for index in range(segments):
		var a0 := -half_angle + (2.0 * half_angle) * float(index) / float(segments)
		var a1 := -half_angle + (2.0 * half_angle) * float(index + 1) / float(segments)
		mesh.surface_add_vertex(Vector3(sin(a0) * radius, 0.03, -cos(a0) * radius))
		mesh.surface_add_vertex(Vector3(sin(a1) * radius, 0.03, -cos(a1) * radius))
	mesh.surface_end()
	outline.mesh = mesh
	return outline


func _create_cleave_arc(center: Vector3, forward: Vector3, side: Vector3, reach: float, height_offset: float, color: Color, lifetime: float) -> void:
	var arc := MeshInstance3D.new()
	var mesh := ImmediateMesh.new()
	var material := _create_fx_material(color, 0.95)
	mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP, material)
	var radius := reach * 0.72
	var half_angle := deg_to_rad(68.0)
	for index in range(15):
		var angle := lerpf(-half_angle, half_angle, float(index) / 14.0)
		var jitter := Vector3(randf_range(-0.06, 0.06), randf_range(-0.03, 0.03), randf_range(-0.06, 0.06))
		var point := center + forward * (cos(angle) * radius) + side * (sin(angle) * radius) + Vector3.UP * height_offset + jitter
		mesh.surface_add_vertex(point)
	mesh.surface_end()
	arc.mesh = mesh
	get_tree().current_scene.add_child(arc)
	_register_fx_budget(arc, "burst")
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(arc, "scale", Vector3(1.18, 1.0, 1.18), lifetime * 0.45)
	tween.tween_method(Callable(self, "_set_material_alpha").bind(material), 0.95, 0.0, lifetime)
	tween.set_parallel(false)
	tween.tween_callback(arc.queue_free)


func _create_shockwave_fx(impact_point: Vector3) -> void:
	_create_shockwave_wave(impact_point, 0.55, Color("#8ff7ff"), 0.58)
	_create_shockwave_wave(impact_point + Vector3.UP * 0.04, 0.34, Color("#e7ffff"), 0.42)
	var crater := MeshInstance3D.new()
	var crater_mesh := ImmediateMesh.new()
	var crater_material := _create_fx_material(Color("#1d2730"), 0.96)
	crater_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES, crater_material)
	var crater_points: Array[Vector3] = []
	var core_points: Array[Vector3] = []
	for index in range(12):
		var angle := TAU * float(index) / 12.0
		var outer_radius := 0.78 + randf_range(-0.12, 0.18)
		var inner_radius := 0.30 + randf_range(-0.06, 0.06)
		crater_points.append(Vector3(cos(angle) * outer_radius, 0.06, sin(angle) * outer_radius))
		core_points.append(Vector3(cos(angle) * inner_radius, 0.09, sin(angle) * inner_radius))
	for index in range(12):
		var next_index := (index + 1) % 12
		crater_mesh.surface_add_vertex(core_points[index])
		crater_mesh.surface_add_vertex(crater_points[index])
		crater_mesh.surface_add_vertex(crater_points[next_index])
		crater_mesh.surface_add_vertex(core_points[index])
		crater_mesh.surface_add_vertex(crater_points[next_index])
		crater_mesh.surface_add_vertex(core_points[next_index])
	crater_mesh.surface_end()
	crater.mesh = crater_mesh
	crater.material_override = crater_material
	get_tree().current_scene.add_child(crater)
	_register_fx_budget(crater, "burst")
	crater.global_position = impact_point
	var core := MeshInstance3D.new()
	var core_mesh := SphereMesh.new()
	core_mesh.radius = 0.28
	core_mesh.height = 0.32
	core.mesh = core_mesh
	var core_material := _create_fx_material(Color("#07131e"), 0.98)
	core.material_override = core_material
	get_tree().current_scene.add_child(core)
	_register_fx_budget(core, "burst")
	core.global_position = impact_point + Vector3.UP * 0.08
	var crust := MeshInstance3D.new()
	var crust_mesh := ImmediateMesh.new()
	var crust_material := _create_fx_material(Color("#65ecff"), 0.95)
	crust_mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP, crust_material)
	for point in crater_points:
		crust_mesh.surface_add_vertex(point + Vector3.UP * 0.13)
	crust_mesh.surface_end()
	crust.mesh = crust_mesh
	get_tree().current_scene.add_child(crust)
	_register_fx_budget(crust, "burst")
	crust.global_position = impact_point
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(crater, "scale", Vector3(1.30, 1.0, 1.30), 0.70)
	tween.tween_property(core, "scale", Vector3(1.15, 0.75, 1.15), 0.55)
	tween.tween_property(crust, "scale", Vector3(1.55, 1.0, 1.55), 0.85)
	tween.tween_method(Callable(self, "_set_material_alpha").bind(crater_material), 0.94, 0.0, 1.55)
	tween.tween_method(Callable(self, "_set_material_alpha").bind(core_material), 0.98, 0.0, 1.15)
	tween.tween_method(Callable(self, "_set_material_alpha").bind(crust_material), 0.95, 0.0, 1.38)
	tween.set_parallel(false)
	tween.tween_interval(0.90)
	tween.tween_callback(crater.queue_free)
	tween.tween_callback(core.queue_free)
	tween.tween_callback(crust.queue_free)
	for index in range(8):
		_create_lightning_spark(impact_point, index)
	_create_crater_fractures(impact_point)
	for index in range(6):
		var direction := Vector3(cos(TAU * float(index) / 6.0), 0.0, sin(TAU * float(index) / 6.0))
		_create_lightning_arc(impact_point + Vector3.UP * 0.16, impact_point + direction * randf_range(1.2, 1.9) + Vector3.UP * 0.16, Color("#3de6ff"), 0.05, 0.60)
	_spawn_particle_burst(impact_point + Vector3.UP * 0.18, Color("#a8f8ff"), 34, 0.75, 7.0, 0.19)
	_spawn_particle_burst(impact_point + Vector3.UP * 0.12, Color("#ffb13b"), 16, 0.52, 5.0, 0.14)
	_spawn_particle_burst(impact_point + Vector3.UP * 0.2, Color("#d19b70"), 22, 0.80, 4.0, 0.18)


func _create_shockwave_wave(origin: Vector3, radius: float, color: Color, lifetime: float) -> void:
	var wave := MeshInstance3D.new()
	var mesh := ImmediateMesh.new()
	var material := _create_fx_material(color, 0.92)
	mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP, material)
	var points := 20
	for index in range(points + 1):
		var angle := TAU * float(index) / float(points)
		var irregular_radius := radius + randf_range(-0.10, 0.10)
		mesh.surface_add_vertex(Vector3(cos(angle) * irregular_radius, 0.12, sin(angle) * irregular_radius))
	mesh.surface_end()
	wave.mesh = mesh
	get_tree().current_scene.add_child(wave)
	_register_fx_budget(wave, "burst")
	wave.global_position = origin
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(wave, "scale", Vector3(3.0, 1.0, 3.0), lifetime)
	tween.tween_method(Callable(self, "_set_material_alpha").bind(material), 0.92, 0.0, lifetime)
	tween.set_parallel(false)
	tween.tween_callback(wave.queue_free)


func _create_crater_fractures(origin: Vector3) -> void:
	for index in range(7):
		var crack := MeshInstance3D.new()
		var mesh := ImmediateMesh.new()
		var material := _create_fx_material(Color("#8cf4ff"), 0.96)
		mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP, material)
		var angle := (TAU / 7.0) * float(index) + 0.18
		var direction := Vector3(cos(angle), 0.0, sin(angle))
		for point_index in range(5):
			var distance := 0.28 + float(point_index) * 0.26
			var jitter := Vector3(-direction.z, 0.0, direction.x) * (0.06 if point_index % 2 == 0 else -0.04)
			mesh.surface_add_vertex(direction * distance + jitter + Vector3.UP * 0.17)
		mesh.surface_end()
		crack.mesh = mesh
		get_tree().current_scene.add_child(crack)
		_register_fx_budget(crack, "burst")
		crack.global_position = origin
		var tween := create_tween()
		tween.tween_method(Callable(self, "_set_material_alpha").bind(material), 0.96, 0.0, 1.35)
		tween.tween_callback(crack.queue_free)


func _create_lightning_spark(origin: Vector3, index: int) -> void:
	var spark := MeshInstance3D.new()
	var spark_mesh := BoxMesh.new()
	spark_mesh.size = Vector3(0.055, 0.08, 1.2 + float(index % 3) * 0.35)
	spark.mesh = spark_mesh
	var spark_material := _create_fx_material(Color("#b7f8ff"), 0.95)
	spark.material_override = spark_material
	get_tree().current_scene.add_child(spark)
	_register_fx_budget(spark, "burst")
	var angle := (TAU / 8.0) * float(index)
	var direction := Vector3(cos(angle), 0.0, sin(angle))
	spark.global_position = origin + direction * 0.45 + Vector3.UP * (0.10 + float(index % 2) * 0.08)
	spark.look_at(spark.global_position + direction, Vector3.UP)
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(spark, "scale", Vector3(1.0, 1.0, 0.1), 0.48)
	tween.tween_method(Callable(self, "_set_material_alpha").bind(spark_material), 0.95, 0.0, 0.52)
	tween.set_parallel(false)
	tween.tween_callback(spark.queue_free)


func _show_attack_hitbox(step: int, impact_point: Vector3 = Vector3.ZERO, did_hit: bool = false, tip_position: Vector3 = Vector3.ZERO, tip_forward: Vector3 = Vector3.ZERO, phase: String = "") -> void:
	if _show_debug_hitbox:
		var hitbox := MeshInstance3D.new()
		hitbox.name = "AxeHitbox"
		var material := StandardMaterial3D.new()
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.albedo_color = Color(0.25, 0.85, 1.0, 0.42)
		material.emission_enabled = true
		material.emission = Color("#2ad9ff")
		material.emission_energy_multiplier = 2.0
		if step == 0:
			var estoc_mesh := BoxMesh.new()
			estoc_mesh.size = Vector3(_axe_estoc_width, 0.06, float(_axe_range[0]))
			hitbox.mesh = estoc_mesh
			hitbox.position = _axe_attack_origin + _axe_attack_direction * float(_axe_range[0]) * 0.5
			hitbox.position.y = 0.04
			hitbox.look_at(hitbox.global_position + _axe_attack_direction, Vector3.UP)
		elif step == 1:
			hitbox = _create_slash_fan(float(_axe_range[1]), deg_to_rad(_axe_sweep_half_angle))
			hitbox.name = "AxeHitbox"
			hitbox.global_position = _axe_attack_origin + Vector3.UP * 0.05
			hitbox.look_at(hitbox.global_position + _axe_attack_direction, Vector3.UP)
		else:
			var ring_mesh := TorusMesh.new()
			if phase == "center":
				ring_mesh.inner_radius = 0.02
				ring_mesh.outer_radius = _axe_wave_inner_radius
			else:
				ring_mesh.inner_radius = _axe_wave_inner_radius
				ring_mesh.outer_radius = _axe_wave_outer_radius
			ring_mesh.rings = 16
			ring_mesh.ring_segments = 32
			hitbox.mesh = ring_mesh
			hitbox.position = _axe_attack_origin + Vector3.UP * 0.06
			hitbox.rotation_degrees.x = 90.0
		hitbox.material_override = material
		get_tree().current_scene.add_child(hitbox)
		if hitbox.material_override == null:
			hitbox.material_override = material
		var tween := create_tween()
		tween.tween_property(hitbox, "scale", Vector3.ONE * 1.12, 0.12)
		tween.tween_callback(hitbox.queue_free)
	if impact_point == Vector3.ZERO:
		impact_point = global_position + aim_direction * float(_axe_range[step])
	if tip_position == Vector3.ZERO:
		tip_position = _axe_tip.global_position if _axe_tip != null else global_position + Vector3.UP * 0.96 + aim_direction * 1.68
	if tip_forward == Vector3.ZERO:
		tip_forward = _get_axe_forward()
	_play_impact_fx(step, impact_point, did_hit, tip_position, tip_forward, phase)


func _build_collision() -> void:
	var collision := CollisionShape3D.new()
	var shape := CapsuleShape3D.new()
	shape.radius = 0.55
	shape.height = 1.7
	collision.shape = shape
	collision.position.y = 0.85
	add_child(collision)


func _register_locomotion_node(node: Node3D, role: String, phase: float = 0.0) -> void:
	if node == null:
		return
	node.set_meta("locomotion_role", role)
	node.set_meta("locomotion_phase", phase)
	node.set_meta("locomotion_base_position", node.position)
	node.set_meta("locomotion_base_rotation", node.rotation)
	_locomotion_nodes.append(node)


func _play_player_animation(animation_name: StringName, blend_time: float = 0.16, speed_scale: float = 1.0) -> bool:
	if _visual_rig == null:
		return false
	return _visual_rig.play_action(animation_name, blend_time, speed_scale)


func _has_skeletal_weapon_attachment() -> bool:
	return _visual_rig != null and _visual_rig.skeleton != null and _visual_rig.right_hand_attachment != null


func _update_aim_pose_state(immediate: bool = false) -> void:
	if _visual_rig != null:
		var punch_pose := _fulguro_phase != "" or _pelto_phase != ""
		_visual_rig.set_aim_enabled(_gameplay_enabled and not is_real_dead() and (punch_pose or (_weapon_id in ["blaster", "shotgun"] and _weapon_pose_uses_aim())), immediate)


func _start_round_warmup_animation() -> void:
	_round_warmup_active = _play_player_animation(&"warm_up", 0.18)
	if not _round_warmup_active:
		_update_player_animation()


func _update_player_animation() -> void:
	if _visual_rig == null or not _gameplay_enabled or is_real_dead():
		return
	if _round_warmup_active:
		return
	_visual_rig.update_locomotion_state(_get_actual_move_velocity().length(), move_speed)


func _on_player_animation_finished(animation_name: StringName) -> void:
	if animation_name == &"fire" and weapon_pose_state == WeaponPoseState.FIRE:
		_begin_aim_hold()
	if animation_name == &"warm_up":
		_round_warmup_active = false
	if animation_name == &"warm_up":
		_update_player_animation()


func _attach_weapon_pivot_to_hand(pivot: Node3D, weapon_id: StringName, desired_position: Vector3, desired_rotation: Vector3, carry_pitch_degrees: float = 0.0) -> Transform3D:
	if pivot == null:
		return Transform3D.IDENTITY
	if _visual_rig == null or _visual_rig.skeleton == null or _visual_rig.right_hand_attachment == null:
		_robot_visuals.add_child(pivot)
		pivot.position = desired_position
		pivot.rotation = desired_rotation
		return pivot.transform
	_visual_rig.equip_weapon(weapon_id, pivot, {
		"position": desired_position,
		"rotation": desired_rotation,
		"scale": Vector3.ONE,
		"carry_pitch_degrees": carry_pitch_degrees,
	})
	return pivot.transform


func _build_robot() -> void:
	_visual_rig = PlayerVisualRig.new()
	_visual_rig.name = "VisualRoot"
	# Apply the shared presentation multiplier exactly once at the visual root so
	# the skeleton, weapon attachments, accessories and muzzle markers stay one rig.
	_visual_rig.scale = Vector3.ONE * PLAYER_BASE_VISUAL_SCALE * COMBAT_DATA.CHARACTER_VISUAL_SCALE
	add_child(_visual_rig)
	_visual_rig.configure_aim_transition(aim_raise_time, aim_lower_time)
	var visuals := _visual_rig.setup_visual_motion()
	_robot_visuals = visuals
	_world_ui_anchor = Node3D.new()
	_world_ui_anchor.name = "WorldUIAnchor"
	_world_ui_anchor.top_level = true
	add_child(_world_ui_anchor)
	_update_world_ui_anchor()

	_attack_label = Label3D.new()
	_attack_label.position = Vector3(0.0, 4.15 * COMBAT_DATA.CHARACTER_VISUAL_SCALE, 0.0)
	_attack_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_attack_label.font_size = 26
	_attack_label.outline_size = 6
	_attack_label.modulate = Color("#8beaff")
	_world_ui_anchor.add_child(_attack_label)

	_health_readout = Node3D.new()
	_health_readout.name = "PlayerHealthReadout"
	_health_readout.set_script(COMBAT_READOUT)
	_world_ui_anchor.add_child(_health_readout)
	# The plaque keeps its original size; only its anchor rises with the model.
	_health_readout.position.y = HEALTH_READOUT_BASE_HEIGHT * (COMBAT_DATA.CHARACTER_VISUAL_SCALE - 1.0)
	_health_readout.call("configure", Color("#42d9e5"), "JOUEUR", -1.0)
	_on_health_changed(get_health(), get_max_health())
	_sync_weapon_readout()

	_baroud_bar_bg = MeshInstance3D.new()
	var baroud_bg_mesh := BoxMesh.new()
	baroud_bg_mesh.size = Vector3(1.8, 0.14, 0.06)
	_baroud_bar_bg.mesh = baroud_bg_mesh
	_baroud_bar_bg.position = Vector3(0.0, 2.52 * COMBAT_DATA.CHARACTER_VISUAL_SCALE, 0.0)
	_baroud_bar_bg.material_override = _material(Color("#2a1820"), 0.2, Color("#3a1824"))
	_world_ui_anchor.add_child(_baroud_bar_bg)
	_baroud_bar_fill = MeshInstance3D.new()
	var baroud_fill_mesh := BoxMesh.new()
	baroud_fill_mesh.size = Vector3(1.0, 0.10, 0.07)
	_baroud_bar_fill.mesh = baroud_fill_mesh
	_baroud_bar_fill.position = Vector3(-0.45, 2.52 * COMBAT_DATA.CHARACTER_VISUAL_SCALE, -0.01)
	_baroud_bar_fill.material_override = _material(Color("#ef5a6f"), 0.1, Color("#ff4e7a"))
	_world_ui_anchor.add_child(_baroud_bar_fill)
	_baroud_bar_bg.visible = false
	_baroud_bar_fill.visible = false

	var selection_ring := MeshInstance3D.new()
	var ring_mesh := TorusMesh.new()
	ring_mesh.inner_radius = 0.78
	ring_mesh.outer_radius = 0.93
	selection_ring.mesh = ring_mesh
	selection_ring.position.y = 0.045
	selection_ring.material_override = _material(Color("#bdefff"), 0.3, Color("#56dfff"))
	visuals.add_child(selection_ring)
	var procedural_body := Node3D.new()
	procedural_body.name = "ProceduralRobot"
	visuals.add_child(procedural_body)

	var body := MeshInstance3D.new()
	var body_mesh := CapsuleMesh.new()
	body_mesh.radius = 0.58
	body_mesh.height = 1.25
	body.mesh = body_mesh
	body.position.y = 0.8
	body.material_override = _robot_textured_material(Color.WHITE, 0.78, ROBOT_CREAM_TEXTURE)
	_player_body_material = body.material_override as StandardMaterial3D
	procedural_body.add_child(body)
	_register_locomotion_node(body, "body")

	var head := MeshInstance3D.new()
	var head_mesh := SphereMesh.new()
	head_mesh.radius = 0.48
	head_mesh.height = 0.85
	head.mesh = head_mesh
	head.position = Vector3(0.0, 1.55, 0.0)
	head.material_override = _robot_textured_material(Color.WHITE, 0.72, ROBOT_CREAM_TEXTURE)
	procedural_body.add_child(head)
	_register_locomotion_node(head, "head")

	var eye := MeshInstance3D.new()
	var eye_mesh := SphereMesh.new()
	eye_mesh.radius = 0.18
	eye_mesh.height = 0.26
	eye.mesh = eye_mesh
	eye.position = Vector3(0.0, 1.58, -0.42)
	eye.scale = Vector3(1.2, 0.75, 0.45)
	eye.material_override = _material(Color("#4ee8ff"), 0.25, Color("#21cfff"))
	procedural_body.add_child(eye)

	var chest_plate := MeshInstance3D.new()
	var chest_mesh := BoxMesh.new()
	chest_mesh.size = Vector3(0.72, 0.48, 0.14)
	chest_plate.mesh = chest_mesh
	chest_plate.position = Vector3(0.0, 0.88, -0.52)
	chest_plate.rotation_degrees.x = -7.0
	chest_plate.material_override = _robot_textured_material(Color.WHITE, 0.70, ROBOT_RUST_TEXTURE)
	procedural_body.add_child(chest_plate)
	_register_locomotion_node(chest_plate, "body")
	var core := MeshInstance3D.new()
	var core_mesh := SphereMesh.new()
	core_mesh.radius = 0.19
	core_mesh.height = 0.28
	core.mesh = core_mesh
	core.position = Vector3(0.0, 0.90, -0.61)
	core.scale = Vector3(1.35, 0.72, 0.48)
	core.material_override = _material(Color("#49e8f1"), 0.16, Color("#22d8e8"))
	_player_core_material = core.material_override as StandardMaterial3D
	procedural_body.add_child(core)
	_register_locomotion_node(core, "body")
	_add_robot_arm(procedural_body, -1.0)
	_add_robot_arm(procedural_body, 1.0)
	_add_robot_leg(procedural_body, -1.0)
	_add_robot_leg(procedural_body, 1.0)
	_add_robot_backpack(procedural_body)
	if _visual_rig.install_animated_model(procedural_body, 2.0):
		_player_body_material = null
		_visual_rig.action_finished.connect(_on_player_animation_finished)
	_blaster_pivot = Node3D.new()
	_blaster_pivot.name = "BlasterPivot"
	_blaster_sway_pivot = Node3D.new()
	_blaster_sway_pivot.name = "WeaponSway"
	_blaster_pivot.add_child(_blaster_sway_pivot)
	_blaster_recoil_pivot = Node3D.new()
	_blaster_recoil_pivot.name = "WeaponRecoil"
	_blaster_sway_pivot.add_child(_blaster_recoil_pivot)
	var procedural_blaster_visual := Node3D.new()
	procedural_blaster_visual.name = "ProceduralBlasterFallback"
	_blaster_recoil_pivot.add_child(procedural_blaster_visual)
	var blaster_grip := MeshInstance3D.new()
	var blaster_grip_mesh := BoxMesh.new()
	blaster_grip_mesh.size = Vector3(0.30, 0.34, 0.55)
	blaster_grip.mesh = blaster_grip_mesh
	blaster_grip.position = Vector3(0.0, -0.12, 0.22)
	blaster_grip.rotation_degrees.x = -12.0
	blaster_grip.material_override = _robot_textured_material(Color.WHITE, 0.82, ROBOT_STEEL_TEXTURE)
	procedural_blaster_visual.add_child(blaster_grip)
	var blaster_receiver := MeshInstance3D.new()
	var blaster_receiver_mesh := BoxMesh.new()
	blaster_receiver_mesh.size = Vector3(0.52, 0.42, 0.72)
	blaster_receiver.mesh = blaster_receiver_mesh
	blaster_receiver.position = Vector3(0.0, 0.06, -0.16)
	blaster_receiver.material_override = _robot_textured_material(Color.WHITE, 0.74, ROBOT_RUST_TEXTURE)
	procedural_blaster_visual.add_child(blaster_receiver)
	var blaster_barrel := MeshInstance3D.new()
	var blaster_barrel_mesh := CylinderMesh.new()
	blaster_barrel_mesh.top_radius = 0.10
	blaster_barrel_mesh.bottom_radius = 0.14
	blaster_barrel_mesh.height = 1.15
	blaster_barrel.mesh = blaster_barrel_mesh
	blaster_barrel.rotation_degrees.x = -90.0
	blaster_barrel.position = Vector3(0.0, 0.09, -0.92)
	blaster_barrel.material_override = _robot_textured_material(Color.WHITE, 0.68, ROBOT_STEEL_TEXTURE)
	procedural_blaster_visual.add_child(blaster_barrel)
	var blaster_muzzle := MeshInstance3D.new()
	var blaster_muzzle_mesh := CylinderMesh.new()
	blaster_muzzle_mesh.top_radius = 0.18
	blaster_muzzle_mesh.bottom_radius = 0.11
	blaster_muzzle_mesh.height = 0.34
	blaster_muzzle.mesh = blaster_muzzle_mesh
	blaster_muzzle.rotation_degrees.x = -90.0
	blaster_muzzle.position = Vector3(0.0, 0.09, -1.58)
	blaster_muzzle.material_override = _material(Color("#2f3a45"), 0.52, Color("#2ad9ff"))
	procedural_blaster_visual.add_child(blaster_muzzle)
	var blaster_muzzle_ring := MeshInstance3D.new()
	var blaster_muzzle_ring_mesh := TorusMesh.new()
	blaster_muzzle_ring_mesh.inner_radius = 0.12
	blaster_muzzle_ring_mesh.outer_radius = 0.19
	blaster_muzzle_ring.mesh = blaster_muzzle_ring_mesh
	blaster_muzzle_ring.rotation_degrees.x = 90.0
	blaster_muzzle_ring.position = Vector3(0.0, 0.09, -1.78)
	blaster_muzzle_ring.material_override = _material(Color("#7cf0ff"), 0.22, Color("#2fe1ff"))
	procedural_blaster_visual.add_child(blaster_muzzle_ring)
	_blaster_muzzle = Node3D.new()
	_blaster_muzzle.name = "Muzzle"
	_blaster_muzzle.set_meta("weapon_forward_axis", Vector3.FORWARD)
	_blaster_muzzle.position = Vector3(0.0, 0.09, -1.86)
	_blaster_recoil_pivot.add_child(_blaster_muzzle)
	var blaster_left_hand_grip := Marker3D.new()
	blaster_left_hand_grip.name = "LeftHandGrip"
	blaster_left_hand_grip.position = Vector3(0.0, 0.06, -0.48)
	_blaster_recoil_pivot.add_child(blaster_left_hand_grip)
	var blaster_right_hand_grip := Marker3D.new()
	blaster_right_hand_grip.name = "RightHandGrip"
	# This is the rear handle contact point, expressed in weapon-root space.
	# Keeping it explicit lets the socket seat the grip on the animated wrist.
	blaster_right_hand_grip.position = Vector3(0.0, -0.08, 0.08)
	_blaster_recoil_pivot.add_child(blaster_right_hand_grip)
	_blaster_charge_visual = MeshInstance3D.new()
	_blaster_charge_visual.name = "BlasterChargeGlow"
	var blaster_charge_mesh := SphereMesh.new()
	blaster_charge_mesh.radius = 0.22
	blaster_charge_mesh.height = 0.44
	_blaster_charge_visual.mesh = blaster_charge_mesh
	_blaster_charge_material = _create_fx_material(Color("#49dfff"), 0.30)
	_blaster_charge_visual.material_override = _blaster_charge_material
	_blaster_charge_visual.position = Vector3(0.0, 0.09, -1.42)
	_blaster_charge_visual.visible = false
	_blaster_recoil_pivot.add_child(_blaster_charge_visual)
	_blaster_light = OmniLight3D.new()
	_blaster_light.name = "BlasterMuzzleLight"
	_blaster_light.light_color = Color("#55eaff")
	_blaster_light.light_energy = 0.0
	_blaster_light.omni_range = 3.5
	_blaster_light.position = Vector3(0.0, 0.09, -1.62)
	_blaster_recoil_pivot.add_child(_blaster_light)
	if ResourceLoader.exists(HEAVY_BLASTER_MODEL_PATH):
		var heavy_blaster_scene := load(HEAVY_BLASTER_MODEL_PATH) as PackedScene
		if heavy_blaster_scene != null:
			var heavy_blaster_model := heavy_blaster_scene.instantiate() as Node3D
			if heavy_blaster_model != null:
				procedural_blaster_visual.visible = false
				var heavy_blaster_mount := Node3D.new()
				heavy_blaster_mount.name = "ImportedHeavyBlasterMount"
				heavy_blaster_mount.rotation.y = PI * 0.5
				heavy_blaster_mount.scale = Vector3.ONE * 1.35
				heavy_blaster_mount.position = Vector3(0.0, -0.14, -0.20)
				_blaster_recoil_pivot.add_child(heavy_blaster_mount)
				heavy_blaster_model.name = "ImportedHeavyBlaster"
				heavy_blaster_mount.add_child(heavy_blaster_model)
				_blaster_muzzle.position = Vector3(0.0, 0.08, -0.88)
				blaster_left_hand_grip.position = Vector3(-0.10, -0.04, -0.20)
				_blaster_charge_visual.position = Vector3(0.0, 0.08, -0.64)
				_blaster_light.position = Vector3(0.0, 0.08, -0.86)
	_blaster_pivot_home_transform = _attach_weapon_pivot_to_hand(
		_blaster_pivot,
		&"blaster",
		Vector3(0.58, 0.93, -0.42),
		Vector3.ZERO,
		-22.0
	)
	if _has_skeletal_weapon_attachment():
		_visual_rig.configure_left_hand_support(&"blaster")

	_shotgun_pivot = Node3D.new()
	_shotgun_pivot.name = "ShotgunPivot"
	_shotgun_sway_pivot = Node3D.new()
	_shotgun_sway_pivot.name = "WeaponSway"
	_shotgun_pivot.add_child(_shotgun_sway_pivot)
	_shotgun_recoil_pivot = Node3D.new()
	_shotgun_recoil_pivot.name = "WeaponRecoil"
	_shotgun_sway_pivot.add_child(_shotgun_recoil_pivot)
	var shotgun := SHOTGUN_SCENE.instantiate() as Node3D
	_shotgun_recoil_pivot.add_child(shotgun)
	_shotgun_muzzle = shotgun.get_node("Muzzle") as Node3D
	_shotgun_light = shotgun.get_node("Muzzle/ShotgunMuzzleLight") as OmniLight3D
	_shotgun_pivot_home_transform = _attach_weapon_pivot_to_hand(
		_shotgun_pivot,
		&"shotgun",
		Vector3(0.58, 0.88, -0.36),
		Vector3.ZERO,
		-22.0
	)
	_update_weapon_visuals()

	var scarf := MeshInstance3D.new()
	var scarf_mesh := BoxMesh.new()
	scarf_mesh.size = Vector3(0.6, 0.08, 1.15)
	scarf.mesh = scarf_mesh
	scarf.position = Vector3(0.0, 1.2, 0.65)
	scarf.rotation_degrees.x = -18.0
	scarf.material_override = _material(Color("#a62f25"), 0.9)
	procedural_body.add_child(scarf)
	_create_player_direction_debug()
	_visual_rig.set_chassis_appearance(_robot_id)


func _update_weapon_visuals() -> void:
	if _axe_pivot != null:
		_axe_pivot.visible = false
	if _blaster_pivot != null:
		_blaster_pivot.visible = _weapon_id == "blaster" and not _pelto_weapon_hidden
	if _shotgun_pivot != null:
		_shotgun_pivot.visible = _weapon_id == "shotgun" and not _pelto_weapon_hidden
	if _has_skeletal_weapon_attachment():
		_visual_rig._cancel_shot_kick()
		_visual_rig.configure_left_hand_support(StringName(_weapon_id))
	_update_aim_pose_state()


func _create_player_direction_debug() -> void:
	_direction_debug_enabled = _direction_debug_enabled or enable_direction_debug
	_direction_debug_geometry = ImmediateMesh.new()
	_direction_debug_material = StandardMaterial3D.new()
	_direction_debug_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_direction_debug_material.vertex_color_use_as_albedo = true
	_direction_debug_material.albedo_color = Color.WHITE
	_direction_debug_mesh = MeshInstance3D.new()
	_direction_debug_mesh.name = "PlayerDirectionDebug"
	_direction_debug_mesh.mesh = _direction_debug_geometry
	_direction_debug_mesh.material_override = _direction_debug_material
	_direction_debug_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_direction_debug_mesh.visible = _direction_debug_enabled
	add_child(_direction_debug_mesh)
	_direction_debug_label = Label3D.new()
	_direction_debug_label.name = "MuzzleAimAngleDebug"
	_direction_debug_label.position = Vector3(0.0, 2.8, 0.0)
	_direction_debug_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_direction_debug_label.font_size = 28
	_direction_debug_label.outline_size = 6
	_direction_debug_label.no_depth_test = true
	_direction_debug_label.visible = _direction_debug_enabled
	add_child(_direction_debug_label)
	if _has_skeletal_weapon_attachment():
		# Read final modified bones/attachments, after aim support and ShotKick.
		_visual_rig.skeleton.skeleton_updated.connect(_update_player_debug_vectors)
	_update_player_debug_vectors()


func _update_player_debug_vectors() -> void:
	if _direction_debug_geometry == null or not _direction_debug_enabled:
		return
	_direction_debug_geometry.clear_surfaces()
	_direction_debug_geometry.surface_begin(Mesh.PRIMITIVE_LINES, _direction_debug_material)
	_add_debug_direction_line(move_direction, Color("#38a8ff"), 1.8)
	_add_debug_direction_line(aim_direction, Color("#ff4b45"), 2.0)
	_add_debug_direction_line(_last_projectile_direction, Color("#d05cff"), 2.25)
	if _visual_rig != null:
		_add_debug_direction_line(_visual_rig.get_aim_forward_direction(), Color("#64e572"), 1.65)
		if _visual_rig.right_hand_attachment != null:
			var hand_transform := _visual_rig.right_hand_attachment.global_transform
			var hand_forward := -hand_transform.basis.z.normalized()
			_add_debug_segment(hand_transform.origin, hand_transform.origin + hand_forward * 0.8, Color("#ffdc58"))
	var weapon := _blaster_pivot if _weapon_id == "blaster" else _shotgun_pivot
	if weapon != null:
		var weapon_forward := -weapon.global_basis.z.normalized()
		_add_debug_segment(weapon.global_position, weapon.global_position + weapon_forward * 1.2, Color.WHITE)
	var muzzle := _blaster_muzzle if _weapon_id == "blaster" else _shotgun_muzzle
	if muzzle != null:
		var muzzle_forward := _visual_rig.get_weapon_forward_direction(StringName(_weapon_id)) if _visual_rig != null else -muzzle.global_basis.z.normalized()
		_add_debug_segment(muzzle.global_position, muzzle.global_position + muzzle_forward * 1.0, Color("#48f3ed"))
		if aim_direction.length_squared() > 0.001:
			var angle := rad_to_deg(acos(clampf(muzzle_forward.dot(aim_direction.normalized()), -1.0, 1.0)))
			var projectile_angle := rad_to_deg(acos(clampf(_last_projectile_direction.normalized().dot(aim_direction.normalized()), -1.0, 1.0))) if _last_projectile_direction.length_squared() > 0.001 else 0.0
			_direction_debug_label.text = "%s  •  Muzzle/Aim %.2f°  •  Projectile/Aim %.2f°" % [get_weapon_pose_state_name(), angle, projectile_angle]
		else:
			_direction_debug_label.text = "Muzzle/Aim angle = —"
	_direction_debug_geometry.surface_end()


func _add_debug_direction_line(direction: Vector3, color: Color, length: float) -> void:
	if direction.length_squared() <= 0.001:
		return
	_add_debug_segment(global_position + Vector3.UP * 0.12, global_position + direction.normalized() * length + Vector3.UP * 0.12, color)


func _add_debug_segment(from_world: Vector3, to_world: Vector3, color: Color) -> void:
	_direction_debug_geometry.surface_set_color(color)
	_direction_debug_geometry.surface_add_vertex(to_local(from_world))
	_direction_debug_geometry.surface_add_vertex(to_local(to_world))


func _add_robot_arm(parent: Node3D, side: float) -> void:
	var shoulder := MeshInstance3D.new()
	var shoulder_mesh := SphereMesh.new()
	shoulder_mesh.radius = 0.25
	shoulder_mesh.height = 0.42
	shoulder.mesh = shoulder_mesh
	shoulder.position = Vector3(side * 0.68, 1.05, 0.0)
	shoulder.material_override = _robot_textured_material(Color.WHITE, 0.82, ROBOT_STEEL_TEXTURE)
	parent.add_child(shoulder)
	_register_locomotion_node(shoulder, "body", 0.0 if side < 0.0 else PI)
	var upper := MeshInstance3D.new()
	var upper_mesh := CylinderMesh.new()
	upper_mesh.top_radius = 0.16
	upper_mesh.bottom_radius = 0.20
	upper_mesh.height = 0.58
	upper.mesh = upper_mesh
	upper.position = Vector3(side * 0.78, 0.78, 0.0)
	upper.rotation_degrees.z = side * -11.0
	upper.material_override = _robot_textured_material(Color.WHITE, 0.82, ROBOT_CREAM_TEXTURE)
	parent.add_child(upper)
	_register_locomotion_node(upper, "limb", 0.0 if side < 0.0 else PI)
	var forearm := MeshInstance3D.new()
	var forearm_mesh := BoxMesh.new()
	forearm_mesh.size = Vector3(0.30, 0.48, 0.34)
	forearm.mesh = forearm_mesh
	forearm.position = Vector3(side * 0.82, 0.43, -0.03)
	forearm.rotation_degrees.z = side * -18.0
	forearm.material_override = _robot_textured_material(Color.WHITE, 0.84, ROBOT_RUST_TEXTURE)
	parent.add_child(forearm)
	_register_locomotion_node(forearm, "limb", 0.0 if side < 0.0 else PI)
	var hand := MeshInstance3D.new()
	var hand_mesh := SphereMesh.new()
	hand_mesh.radius = 0.17
	hand_mesh.height = 0.25
	hand.mesh = hand_mesh
	hand.position = Vector3(side * 0.84, 0.16, -0.08)
	hand.material_override = _robot_textured_material(Color.WHITE, 0.90, ROBOT_STEEL_TEXTURE)
	parent.add_child(hand)
	_register_locomotion_node(hand, "limb", 0.0 if side < 0.0 else PI)


func _add_robot_leg(parent: Node3D, side: float) -> void:
	var thigh := MeshInstance3D.new()
	var thigh_mesh := CapsuleMesh.new()
	thigh_mesh.radius = 0.20
	thigh_mesh.height = 0.62
	thigh.mesh = thigh_mesh
	thigh.position = Vector3(side * 0.31, 0.36, 0.02)
	thigh.rotation_degrees.z = side * 7.0
	thigh.material_override = _robot_textured_material(Color.WHITE, 0.84, ROBOT_STEEL_TEXTURE)
	parent.add_child(thigh)
	_register_locomotion_node(thigh, "limb", 0.0 if side < 0.0 else PI)
	var shin := MeshInstance3D.new()
	var shin_mesh := BoxMesh.new()
	shin_mesh.size = Vector3(0.28, 0.48, 0.34)
	shin.mesh = shin_mesh
	shin.position = Vector3(side * 0.33, 0.05, -0.04)
	shin.rotation_degrees.z = side * -4.0
	shin.material_override = _robot_textured_material(Color.WHITE, 0.78, ROBOT_CREAM_TEXTURE)
	parent.add_child(shin)
	_register_locomotion_node(shin, "limb", 0.0 if side < 0.0 else PI)
	var foot := MeshInstance3D.new()
	var foot_mesh := BoxMesh.new()
	foot_mesh.size = Vector3(0.40, 0.18, 0.62)
	foot.mesh = foot_mesh
	foot.position = Vector3(side * 0.33, -0.17, -0.17)
	foot.material_override = _robot_textured_material(Color.WHITE, 0.90, ROBOT_RUST_TEXTURE)
	parent.add_child(foot)
	_register_locomotion_node(foot, "limb", 0.0 if side < 0.0 else PI)


func _add_robot_backpack(parent: Node3D) -> void:
	var pack := MeshInstance3D.new()
	var pack_mesh := BoxMesh.new()
	pack_mesh.size = Vector3(0.66, 0.78, 0.34)
	pack.mesh = pack_mesh
	pack.position = Vector3(0.0, 1.02, 0.55)
	pack.rotation_degrees.x = -8.0
	pack.material_override = _robot_textured_material(Color.WHITE, 0.86, ROBOT_RUST_TEXTURE)
	parent.add_child(pack)
	var coil := MeshInstance3D.new()
	var coil_mesh := TorusMesh.new()
	coil_mesh.inner_radius = 0.14
	coil_mesh.outer_radius = 0.20
	coil.mesh = coil_mesh
	coil.position = Vector3(0.0, 1.18, 0.76)
	coil.rotation_degrees.x = 90.0
	coil.material_override = _material(Color("#52e5ed"), 0.30, Color("#2bd4df"))
	parent.add_child(coil)


func _material(color: Color, roughness: float, emission: Color = Color.BLACK) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	if emission != Color.BLACK:
		material.emission_enabled = true
		material.emission = emission
		material.emission_energy_multiplier = 3.0
	return material


func _robot_textured_material(color: Color, roughness: float, texture: Texture2D) -> StandardMaterial3D:
	var material := _material(color, roughness)
	material.albedo_texture = texture
	material.uv1_scale = Vector3(1.1, 1.1, 1.1)
	material.metallic = 0.18 if texture == ROBOT_RUST_TEXTURE else (0.38 if texture == ROBOT_STEEL_TEXTURE else 0.04)
	return material
