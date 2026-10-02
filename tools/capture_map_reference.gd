extends SceneTree
## Real production cameras; clean hides only interface for art comparison.
## -- OUTPUT_DIR [all|classic|hazards|test|training|training-fixed|training-moving|training-shooter|survival|factory|passage] [clean] [low]
const VIEWS := {
	"classic":Vector3(0,0,17),"hazards":Vector3(0,0,2),"test":Vector3(-3.5,2.4,1.4),
	"training":Vector3(0,0,25),"training-fixed":Vector3(-24,0,-5),"training-moving":Vector3(0,0,-5),"training-shooter":Vector3(24,0,-5),
	"survival":Vector3(0,0,4),"factory":Vector3(54,0,-5),"passage":Vector3(27,0,0)
}
func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var output := args[0]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	var views: Array = VIEWS.keys() if args.size()<2 or args[1]=="all" else [args[1]]
	var report := {"renderer":RenderingServer.get_current_rendering_driver_name(),"quality":"low" if args.has("low") else "normal","arguments":Array(args),"views":{}}
	var code := 0
	for mode in views:
		var duel: bool = mode in ["classic","hazards","test"]
		var training: bool = String(mode).begins_with("training")
		var path := "res://scenes/%s.tscn" % ("main" if duel else "training_ground" if training else "survival")
		var scene := load(path).instantiate() as Node3D
		root.add_child(scene)
		current_scene = scene
		await process_frame
		await process_frame
		var player := scene.get_node("Player") as Node3D
		if duel:
			scene.call("set_menu_showcase_enabled",false)
			scene.call("set_bot_build_seed",42)
			var flow := scene.get("game_flow") as CanvasLayer
			flow.call("_select_arena",mode)
			flow.call("_start_duel")
			flow.call("_begin_live_round")
			flow.set_process(false)
			var target := scene.get("target") as Node3D
			target.call("set_training_bot_enabled",false)
			target.global_position = Vector3(3.5,2.4,-1) if mode=="test" else VIEWS[mode]+Vector3(3.5,0,-4)
		else:
			if not training:
				scene.call("_choose_weapon","blaster")
				if mode in ["factory","passage"]:
					scene.call("_open_passage")
					if mode=="factory":
						scene.call("_enter_factory")
				scene.call("_clear_enemies")
			elif scene.get("_menu").visible:
				scene.call("_toggle_menu")
		player.global_position = VIEWS[mode]
		player.call("clear_touch_inputs")
		player.call("set_gameplay_enabled",true)
		player.set("aim_direction",Vector3.FORWARD)
		player.set_physics_process(false)
		scene.set_process(false)
		scene.set_meta("camera_shake_enabled",false)
		var rig := scene.get_node("CameraRig") as Node3D
		rig.call("set_target",player)
		rig.call("set_follow_offset",Vector3.ZERO,true)
		rig.set_process(false)
		if args.has("low"):
			scene.get_node("VFXManager").set("quality",0)
			root.get_node("StylizedEnvironment").call("_update_quality")
			for details in scene.find_children("ReferenceMapDressing","Node3D",true,false):
				details.call("_sync")
			var presentation := scene.get_node_or_null("ArenaPresentation")
			if presentation!=null:
				presentation.call("set_quality",0)
		if args.has("clean"):
			for canvas in scene.find_children("*","CanvasLayer",true,false):
				canvas.visible = false
			for label in scene.find_children("*","Label3D",true,false):
				label.visible = false
			for readout in scene.find_children("*HealthReadout","Node3D",true,false):
				readout.visible = false
		for frame in range(32):
			await process_frame
		await RenderingServer.frame_post_draw
		var suffix := "-low" if args.has("low") else ""
		var image_path := output.path_join(String(mode)+suffix+".png")
		var error := root.get_texture().get_image().save_png(image_path)
		code = maxi(code,1 if error!=OK else 0)
		var camera := root.get_camera_3d()
		var lights := 0
		for light in scene.find_children("*","OmniLight3D",true,false):
			var branch: Node = light
			while branch.get_parent()!=scene:
				branch = branch.get_parent()
			if branch.get_script()!=null and not branch.name in ["TestArena","ArenaPresentation","ReferenceMapDressing"]:
				continue
			if light.get_viewport()==scene.get_viewport() and light.is_visible_in_tree():
				lights += 1
		report.views[mode] = {"image":image_path,"capture_error":error,"camera_position":str(camera.global_position),"camera_fov":camera.fov,"local_lights":lights,"draw_calls":Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)}
		print("MAP REFERENCE CAPTURE: ",mode," ",image_path)
		root.get_node("GameSfx").call("clear")
		scene.queue_free()
		await process_frame
		await process_frame
	var file := FileAccess.open(output.path_join("capture-low.json" if args.has("low") else "capture.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"\t"))
	quit(code)
