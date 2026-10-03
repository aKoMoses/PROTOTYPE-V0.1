extends SceneTree

var failures: Array[String] = []
var events: Array[String] = []
var controls_checked := 0
var application_compiles := true

func _initialize() -> void:
	call_deferred("_run")

func _check(value: bool, message: String) -> void:
	if not value:
		failures.append(message)
		push_error(message)

func _audit(node: Node) -> void:
	if node is BaseButton or node is PopupMenu or node is Slider:
		var touch := false
		var ancestor := node.get_parent()
		while ancestor != null:
			touch = touch or ancestor.name == &"TouchControls"
			ancestor = ancestor.get_parent()
		if not touch:
			controls_checked += 1
			_check(node.has_meta("_ui_sfx_bound"), "unbound actual control: " + str(node.get_path()))
	for child in node.get_children():
		_audit(child)

func _run() -> void:
	await process_frame
	var sfx := root.get_node("UiSfx")
	sfx.event_played.connect(func(family: String) -> void: events.append(family))
	_check(sfx.process_mode == Node.PROCESS_MODE_ALWAYS, "UI feedback survives pause")
	_check(sfx.get("_voice").bus == &"Effects", "uses effects volume bus")
	_check(sfx._label_family("RELANCER LES CARTES · 1 restante") == "confirmation", "reroll confirms; it does not launch a game")
	_check(sfx._label_family("CRÉER LE SALON") == "confirmation", "room creation")
	_check(sfx._label_family("LANCER LE MATCH") == "launch", "online launch")
	for family in sfx.STREAMS:
		var stream: AudioStreamWAV = sfx.STREAMS[family]
		_check(stream.data.size() > 100 and stream.get_length() < 0.6 and stream.loop_mode == AudioStreamWAV.LOOP_DISABLED, "valid imported one-shot: " + family)
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	application_compiles = scene.get_script() != null and scene.get_script().can_instantiate()
	root.add_child(scene)
	current_scene = scene
	await process_frame
	await process_frame
	var flow: Node = scene.get_node("Interface")
	for method in ["_open_menu", "_open_solo_setup", "_open_settings", "_open_equipment", "_open_lobby"]:
		flow.call(method)
		await process_frame
		await process_frame
		_audit(scene)
	var solo: Node = flow.get("_solo_setup")
	_check(sfx.family_for(solo.get("arena_title")) == "selection", "dynamic arena title selects rather than navigates")
	_check(sfx.family_for(solo.get("launch")) == "launch", "solo launch")
	var garage: Node = flow.get("_forge_garage")
	if garage != null:
		_check(sfx.family_for(garage.get("_save_button")) == "silent", "garage awaits actual save result")
	var button := Button.new()
	button.text = "RETOUR AU MENU"
	root.add_child(button)
	await process_frame
	await process_frame
	var before := events.size()
	button.pressed.emit()
	_check(events.size() == before + 1 and events.back() == "back", "dynamic button emits one event")
	button.disabled = true
	before = events.size()
	button.pressed.emit()
	_check(events.size() == before, "disabled buttons silent")
	button.queue_free()
	var refused := Button.new()
	refused.text = "CRÉER LE SALON"
	refused.pressed.connect(func() -> void: sfx.play("denied"))
	root.add_child(refused)
	await process_frame
	await process_frame
	before = events.size()
	refused.button_down.emit()
	refused.pressed.emit()
	_check(events.size() == before + 1 and events.back() == "denied", "synchronous failure is not masked by click feedback")
	refused.queue_free()
	var selector := OptionButton.new()
	selector.add_item("A")
	selector.add_item("B")
	root.add_child(selector)
	var slider := HSlider.new()
	root.add_child(slider)
	await process_frame
	await process_frame
	before = events.size()
	selector.select(1)
	slider.value = 50
	_check(events.size() == before, "programmatic refresh silent")
	selector.get_popup().id_pressed.emit(0)
	_check(events.size() == before + 1 and events.back() == "selection", "popup selection emits once")
	selector.queue_free()
	slider.queue_free()
	scene.queue_free()
	await process_frame
	for path in ["res://scenes/training_ground.tscn", "res://scenes/beginner_tutorial.tscn", "res://scenes/survival.tscn"]:
		scene = load(path).instantiate()
		root.add_child(scene)
		current_scene = scene
		await process_frame
		await process_frame
		_audit(scene)
		scene.queue_free()
		await process_frame
	_check(is_instance_valid(sfx.get("_voice")), "player survives scene destruction")
	paused = true
	before = events.size()
	sfx.play("denied")
	_check(events.size() == before + 1 and events.back() == "denied", "refusal works while paused")
	paused = false
	if failures.is_empty():
		print("UI SFX: PASS (%d actual controls audited)" % controls_checked)
		if not application_compiles:
			print("APPLICATION SCRIPT COMPILATION: FAIL (main scene dependencies)")
		quit(0 if application_compiles else 2)
	else:
		print("UI SFX: FAIL: " + str(failures))
		quit(1)
