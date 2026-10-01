extends CharacterBody3D

# Shared Player fields, exported settings and signals retain their original names.
# Components preload this state-only base to avoid cyclic Player dependencies.

var gameplay_arena_center := Vector3.ZERO

signal bush_state_changed(in_bush: bool, bush_name: String)
signal died
signal effective_damage_taken(amount: float, source_id: String, attack_id: String)

var _external_damage_pending := false
var _received_attack_ids: Dictionary = {}

const ROBOT_CREAM_TEXTURE: Texture2D = preload("res://art/metal_cream.svg")
const ROBOT_RUST_TEXTURE: Texture2D = preload("res://art/metal_rust.svg")
const ROBOT_STEEL_TEXTURE: Texture2D = preload("res://art/steel_dark.svg")
const HEAVY_BLASTER_MODEL_PATH := "res://art/player_heavy_blaster.glb"
const BLASTER_CHARGE_VISUAL := preload("res://scripts/blaster_charge_visual.gd")
const SHOTGUN_SCENE := preload("res://scenes/weapons/shotgun.tscn")
const MEKATANA_SCENE := preload("res://scenes/weapons/mekatana.tscn")
const MEKATANA_ATTACK := preload("res://scripts/mekatana_attack.gd")
var _mekatana_attack = MEKATANA_ATTACK.new()
var _mekatana_action_token := 0
var _mekatana_pivot: Node3D
var _mekatana_velocity := Vector3.ZERO
var _mekatana_movement_owned := false
const COMBAT_DATA := preload("res://scripts/combat_data.gd")
const PYRO_BOOTS := preload("res://scripts/pyro_boots.gd")
const COUNTER := preload("res://scripts/counter.gd")
var _counter: CounterGuard
const PROJECTOR := preload("res://scripts/projector.gd")
const KNOCKBACK := preload("res://scripts/knockback_motion.gd")
var _projector_below_threshold := false
var _projector_passive_remaining := 0.0
var _projector_cast_remaining := 0.0
var _projector_cast_token := 0
var _projector_cast_visual: Node3D
const LIVE_PROJECTILE := preload("res://scripts/live_projectile.gd")
const ROCKET_BASKET := preload("res://scripts/rocket_basket.gd")
var _rocket_damage_multiplier := 1.0
const WEAPON_AIM_GUIDE := preload("res://scripts/weapon_aim_guide.gd")
const PERMUTATION := preload("res://scripts/permutation.gd")
const ECLIPSE := preload("res://scripts/eclipse.gd")
var _eclipse := ECLIPSE.new()
var _permutation_mark: Node3D
var _permutation_speed_remaining := 0.0
const JAVELIN_VISUAL := preload("res://scripts/javelin_visual.gd")
const MAGNETIC_WALL := preload("res://scripts/magnetic_wall.gd")
const LONGSHOT_STATE := preload("res://scripts/longshot_state.gd")
const LONGSHOT_PROJECTILE := preload("res://scripts/longshot_projectile.gd")
var _longshot_state = LONGSHOT_STATE.new()
var _longshot_definition: Dictionary = COMBAT_DATA.WEAPON_DEFINITIONS["longshot"].duplicate(true)
var _longshot_attack_token := 0
var _longshot_action_token := 0
var _longshot_attack_busy := false
var _longshot_next_attack_ready_at := -10.0
var _longshot_pivot: Node3D
var _longshot_muzzle: Node3D
var _longshot_visual: Node3D
var _longshot_shot_audio: AudioStreamPlayer
var _longshot_enhanced_audio: AudioStreamPlayer
const COMBAT_STATE := preload("res://scripts/combat_state.gd")
const ACTION_GATE := preload("res://scripts/action_gate.gd")
const PASSIVE_STATE := preload("res://scripts/passive_state.gd")
const VISIBILITY_STATE := preload("res://scripts/visibility_state.gd")
const BUSH_STATE := preload("res://scripts/bush_state.gd")
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
@export_category("Vision")
@export_range(1.0, 60.0, 0.5) var vision_radius := VISIBILITY_STATE.DEFAULT_VISION_RADIUS
@export_range(0.0, 20.0, 0.5) var vision_fade_width := VISIBILITY_STATE.DEFAULT_VISION_FADE_WIDTH
var _visibility_epoch := 0
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
var _blaster_projectile_speed := 40.0
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
# Active weapon paths: Blaster, Shotgun, Mekatana and LONGSHOT.
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
var _desktop_mouse_attack_held := false
var _desktop_fulguro_charge_held := false
var _touch_attack_rearm_required := false
var _javelin_preparation := 0.35
var _javelin_charging := false
var _javelin_elapsed := 0.0
var _javelin_release_at := -1.0
var _javelin_release_direction := Vector3.FORWARD
var _javelin_charge_action_token := 0
var _javelin_charge_visual: Node3D
var _javelin_module_aim := Vector3.ZERO
var _desktop_javelin_charge_held := false
var _javelin_active_mark_duration := 2.5
var _javelin_active_recast_range := 8.0
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
var _pelto_aim_held := false
var _pelto_release_requested := false
var _pelto_module_aim := Vector3.ZERO
var _desktop_pelto_aim_held := false
var _pelto_attack_serial := 0
var _pelto_indicator: Node3D
var _pelto_lane_mesh: BoxMesh
var _pelto_impact_audio: AudioStreamPlayer
var _pelto_waves: Array[Node] = []
var _pelto_weapon_hidden := false
var _pelto_weapon_restore_serial := 0
var _module_busy := false
var _offensive_module_id := "javelin"
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
var _low_health_sound_armed := true
var _bush_status_label: Label3D
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
var _blaster_charge_visual: Node3D
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
