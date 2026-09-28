extends SceneTree

func _initialize() -> void:
	call_deferred("capture")

func capture() -> void:
	var stage := Node3D.new()
	root.add_child(stage)
	current_scene = stage
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("#252b36")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_energy = 0.8
	var world := WorldEnvironment.new()
	world.environment = env
	stage.add_child(world)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-35, -30, 0)
	stage.add_child(light)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 6.7
	stage.add_child(camera)
	camera.position = Vector3(0, 4.5, 10)
	camera.look_at(Vector3(0, 0.6, 0))
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	doc.append_from_file(ProjectSettings.globalize_path("res://art/enemy_droid.glb"), state)
	var sample := doc.generate_scene(state)
	var names := ["idle", "walk", "run", "fire", "fall", "turn", "wait", "look_around", "warm_up", "cast_a_spell"]
	var times := [0.0, 0.6, 0.3, 0.4, 2.9, 2.0, 2.0, 4.0, 4.0, 2.0]
	for i in names.size():
		var model := sample.duplicate()
		stage.add_child(model)
		model.position = Vector3((i % 5 - 2) * 1.3, 0, (i / 5) * 2.6 - 1.3)
		var player: AnimationPlayer = model.get_node("AnimationPlayer")
		player.play(names[i])
		player.seek(times[i], true)
		player.pause()
		var label := Label3D.new()
		label.text = names[i]
		label.font_size = 24
		label.pixel_size = 0.004
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.position = Vector3(0, 1.3, 0)
		model.add_child(label)
	sample.free()
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("res://exports/enemy-droid-review")
	root.get_texture().get_image().save_png("res://exports/enemy-droid-review/source-clips.png")
	quit()
