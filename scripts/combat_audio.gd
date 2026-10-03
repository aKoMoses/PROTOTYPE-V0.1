extends RefCounted

## Stable Audio combat cues. Playback never changes gameplay state.
const STREAMS := {
	"javelin_charge": preload("res://art/audio/combat-sfx/javelin-charge.wav"),
	"javelin_launch": preload("res://art/audio/combat-sfx/javelin-launch.wav"),
	"javelin_impact": preload("res://art/audio/combat-sfx/javelin-impact.wav"),
	"javelin_mark_end": preload("res://art/audio/combat-sfx/javelin-mark-end.wav"),
	"fulguro_charge": preload("res://art/audio/combat-sfx/fulguro-charge.wav"),
	"fulguro_impact": preload("res://art/audio/combat-sfx/fulguro-impact.wav"),
	"fulguro_wall": preload("res://art/audio/combat-sfx/fulguro-wall.wav"),
	"pelto_outbound": preload("res://art/audio/combat-sfx/pelto-outbound.wav"),
	"pelto_return": preload("res://art/audio/combat-sfx/pelto-return.wav"),
	"pelto_hit": preload("res://art/audio/combat-sfx/pelto-hit.wav"),
	"bio_inject": preload("res://art/audio/combat-sfx/bio-inject.wav"),
	"bio_boost": preload("res://art/audio/combat-sfx/bio-boost.wav"),
	"bio_end": preload("res://art/audio/combat-sfx/bio-end.wav"),
	"static_on": preload("res://art/audio/combat-sfx/static-on.wav"),
	"static_block": preload("res://art/audio/combat-sfx/static-block.wav"),
	"static_off": preload("res://art/audio/combat-sfx/static-off.wav"),
	"magnetic_place": preload("res://art/audio/combat-sfx/magnetic-place.wav"),
	"magnetic_block": preload("res://art/audio/combat-sfx/magnetic-block.wav"),
	"magnetic_end": preload("res://art/audio/combat-sfx/magnetic-end.wav"),
	"eclipse_depart": preload("res://art/audio/combat-sfx/eclipse-depart.wav"),
	"eclipse_arrival": preload("res://art/audio/combat-sfx/eclipse-arrival.wav"),
	"eclipse_shield": preload("res://art/audio/combat-sfx/eclipse-shield.wav"),
	"tracker_mark": preload("res://art/audio/combat-sfx/tracker-mark.wav"),
	"alternator_ready": preload("res://art/audio/combat-sfx/alternator-ready.wav"),
	"inertia_trigger": preload("res://art/audio/combat-sfx/inertia-trigger.wav"),
	"reactor_refresh": preload("res://art/audio/combat-sfx/reactor-refresh.wav"),
	"omnivamp_heal": preload("res://art/audio/combat-sfx/omnivamp-heal.wav"),
}
const INTERVALS := {"omnivamp_heal": 700, "reactor_refresh": 650, "tracker_mark": 500,
	"inertia_trigger": 250, "static_block": 120, "magnetic_block": 100,
	"pelto_hit": 100, "alternator_ready": 300, "javelin_mark_end": 500}
const OUTCOMES := ["javelin_impact", "javelin_mark_end", "fulguro_impact", "fulguro_wall", "pelto_hit", "magnetic_block",
	"eclipse_shield", "static_block", "tracker_mark", "alternator_ready",
	"inertia_trigger", "reactor_refresh", "omnivamp_heal"]

static func play(actor: Node3D, cue: String, at: Vector3 = Vector3.INF) -> AudioStreamPlayer3D:
	if not is_instance_valid(actor) or not actor.is_inside_tree():
		return null
	if actor.has_method("is_real_dead") and actor.call("is_real_dead"):
		return null
	var sfx := actor.get_node_or_null("/root/GameSfx")
	if sfx == null:
		return null
	var position := at if at.is_finite() else actor.global_position + Vector3.UP
	var voice: AudioStreamPlayer3D = sfx.call("play_combat_event", cue, position, actor.get_instance_id())
	# Outcomes originate on the host; input/charge/release cues already replay
	# through accepted actions. Clients cannot request audio as combat actions.
	if voice != null and cue in OUTCOMES and actor.has_method("receive_action") and actor.get("authoritative") == true:
		actor.call("_notify", "combat_sfx", {"cue": cue, "center": position})
	return voice

static func charge(actor: Node3D, cue: String) -> void:
	stop_charge(actor, cue)
	var voice := play(actor, cue)
	if voice != null:
		actor.set_meta("combat_charge_" + cue, weakref(voice))

static func stop_charge(actor: Node3D, cue: String) -> void:
	if not is_instance_valid(actor):
		return
	var key := "combat_charge_" + cue
	if not actor.has_meta(key):
		return
	var ref: WeakRef = actor.get_meta(key)
	if ref != null:
		var voice := ref.get_ref() as AudioStreamPlayer3D
		var sfx := actor.get_node_or_null("/root/GameSfx")
		if is_instance_valid(voice) and sfx != null:
			sfx.call("stop_module_voice", voice)
		actor.remove_meta(key)

static func bind_passive(actor: Node3D, state: RefCounted) -> void:
	if not is_instance_valid(actor) or state == null:
		return
	var callback := _passive_sound.bind(weakref(actor))
	# Compare actor identity rather than newly created WeakRefs.
	for connection in state.get_signal_connection_list("sound_requested"):
		var existing: Callable = connection.callable
		if existing.get_method() == callback.get_method():
			var args := existing.get_bound_arguments()
			if not args.is_empty() and args[0] is WeakRef and args[0].get_ref() == actor:
				return
	state.connect("sound_requested", callback)

static func _passive_sound(cue: String, actor_ref: WeakRef) -> void:
	var actor := actor_ref.get_ref() as Node3D
	if is_instance_valid(actor):
		play(actor, cue)
