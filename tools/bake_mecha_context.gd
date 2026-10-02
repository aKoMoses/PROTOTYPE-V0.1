extends SceneTree

## Run in the isolated reviewer project: --script <absolute script> -- SOURCE OUTPUT.
## Only animation data is shipped; the existing meshes, skins and combat clips stay intact.
const CLIPS := {
	"standing_relax": 8.0, "look_around": 7.0, "wait": 6.0,
	"greet_02": 5.583334, "agree": 4.0, "frustrated_01": 3.541667,
	"cheer": 3.2, "defeat_02": 4.0,
	"hit_to_body_01": 1.291667, "hit_to_body_02": 1.708334,
	"hit_to_side": 1.25, "hit_to_stomach": 1.541667, "hit_to_head": 1.833334,
	"scratch": 8.0, "greet_01": 3.5, "greet_03": 7.0, "greet_04": 2.791667,
	"laugh_01": 5.583334, "laugh_02": 5.583334, "frustrated_02": 5.2,
	"box_01": 2.208334, "box_02": 2.791667, "box_03": 2.541667,
	"slash": 6.583334, "pitch_baseball": 3.791667, "basketball_shot": 6.583334,
	"cast_a_spell": 5.375, "flee_01": 2.666667,
}

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 2:
		quit(1)
		return
	var document := GLTFDocument.new()
	var state := GLTFState.new()
	if document.append_from_file(args[0], state) != OK:
		quit(1)
		return
	var model := document.generate_scene(state)
	var animator := model.find_children("*", "AnimationPlayer", true, false)[0] as AnimationPlayer
	var library := AnimationLibrary.new()
	for clip_name in CLIPS:
		var source := animator.get_animation(clip_name)
		if source == null:
			push_error("Missing clip: " + clip_name)
			quit(1)
			return
		var clip := Animation.new()
		clip.length = minf(source.length, float(CLIPS[clip_name]))
		clip.loop_mode = Animation.LOOP_NONE
		for track in source.get_track_count():
			var type := source.track_get_type(track)
			if type not in [Animation.TYPE_POSITION_3D, Animation.TYPE_ROTATION_3D, Animation.TYPE_SCALE_3D]:
				continue
			var destination := clip.add_track(type)
			clip.track_set_path(destination, source.track_get_path(track))
			# Uniform native interpolation is deterministic across import settings.
			var samples := ceili(clip.length * 30.0)
			for frame in samples + 1:
				var time := minf(float(frame) / 30.0, clip.length)
				var value: Variant
				match type:
					Animation.TYPE_POSITION_3D: value = source.position_track_interpolate(track, time)
					Animation.TYPE_ROTATION_3D: value = source.rotation_track_interpolate(track, time)
					Animation.TYPE_SCALE_3D: value = source.scale_track_interpolate(track, time)
				clip.track_insert_key(destination, time, value)
		library.add_animation(clip_name, clip)
	DirAccess.make_dir_recursive_absolute(args[1].get_base_dir())
	var error := ResourceSaver.save(library, args[1], ResourceSaver.FLAG_COMPRESS)
	print("MECHA_BANK clips=%d error=%s" % [library.get_animation_list().size(), error_string(error)])
	model.free()
	quit(0 if error == OK else 1)
