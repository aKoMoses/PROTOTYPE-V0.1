class_name PassiveHud
extends Control

## Presentation only; inherits the spell bar's visibility and HUD transforms.
const ICONS := preload("res://scripts/equipment_icons.gd")
const LOADOUT := preload("res://scripts/loadout_state.gd")
var player: Node
var _icons = ICONS.new()
var _box := StyleBoxFlat.new()


static func attach(bar: Control, actor: Node, controller: Node) -> Control:
	var widget := PassiveHud.new()
	widget.name = "PassiveSlot"
	widget.player = actor
	widget.position = Vector2(bar.size.x * 0.5 - 100.0, -64.0)
	widget.size = Vector2(200, 54)
	widget.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_child(widget)
	controller.call("register", "passive_slot", widget)
	return widget


func _process(_delta: float) -> void:
	if is_visible_in_tree():
		queue_redraw()


func _draw() -> void:
	if not is_instance_valid(player) or not player.has_method("get_passive_status"):
		return
	var id := str(player.call("get_passive_id"))
	if id == "":
		return
	var state: Dictionary = player.call("get_passive_status")
	var active := float(state.get("alternator", 0.0)) > 0.0 or float(state.get("inertia", 0.0)) > 0.0
	var tint := Color("#bbecdb") if active else Color("#f3ddbb")
	var pulse := float(state.get("pulse", 0.0)) / 0.25
	draw_style_box(_background(tint, pulse), Rect2(Vector2.ZERO, size))
	var icon: Texture2D = _icons.get_icon(id)
	if icon != null:
		draw_texture_rect(icon, Rect2(6, 6, 40, 40), false, Color.WHITE.lerp(Color("#bbecdb"), maxf(float(active), pulse)))
	var title: String = str({"auxiliary_reactor": "RÉACTEUR AUX.", "tracker": "TRAQUEUR", "alternator": "ALTERNATEUR", "inertia": "INERTIE"}.get(id, LOADOUT.display_name(id)))
	draw_string(ThemeDB.fallback_font, Vector2(52, 19), str(title), HORIZONTAL_ALIGNMENT_LEFT, 143, 13, tint)
	var text := "AUTOMATIQUE"
	match id:
		"auxiliary_reactor":
			text = "PRÊT" if float(state.get("reactor", 0.0)) <= 0.0 else "RECHARGE %.2f s" % float(state.reactor)
		"tracker":
			var marks := int(state.get("marks", 0))
			var segments := int(state.get("hits", 3))
			text = "SPOTTED %.1f s" % float(state.reveal) if float(state.get("reveal", 0.0)) > 0.0 else "%d / %d  ·  %.1f s" % [marks, segments, float(state.get("gap", 0.0))]
			for index in segments:
				draw_rect(Rect2(7 + index * 13, 46, 10, 3), Color("#bbecdb") if index < marks else Color("#536365"))
		"alternator":
			text = "PRÊT  ·  %.1f s" % float(state.alternator) if active else "TOUCHER AVEC LE MODULE"
		"inertia":
			text = "PRÊT  ·  %.1f s" % float(state.inertia) if active else "TERMINER UN DASH"
	draw_string(ThemeDB.fallback_font, Vector2(52, 39), text, HORIZONTAL_ALIGNMENT_LEFT, 143, 11, tint)
	# SPOTTED retains its eye cue through solid cover, without exposing a live
	# actor mesh, altering visibility admission or changing projectile collisions.
	var camera := get_viewport().get_camera_3d()
	if camera == null or not player.has_method("get_tracker_locations"):
		return
	for target: Node3D in player.call("get_tracker_locations"):
		if not is_instance_valid(target) or (target.has_method("is_real_dead") and bool(target.call("is_real_dead"))):
			continue
		var at := target.global_position + Vector3.UP * 3.3
		if camera.is_position_behind(at):
			continue
		# Keep the eye above the existing health/status stack.
		var screen := camera.unproject_position(at) - Vector2(0, 84)
		if not get_viewport_rect().has_point(screen):
			continue
		var point := get_global_transform_with_canvas().affine_inverse() * screen
		draw_circle(point, 15.0, Color("#10191bea"))
		draw_arc(point, 12.0, 0.0, TAU, 32, Color("#bbecdb"), 2.5, true)
		draw_circle(point, 4.0, Color("#ecfff7"))
		var remaining := float(target.call("get_spotted_reveal_remaining")) if target.has_method("get_spotted_reveal_remaining") else float(state.get("reveal", 0.0))
		var caption := "TRAQUÉ %.1f s" % remaining
		var font := ThemeDB.fallback_font
		var caption_width := font.get_string_size(caption, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
		var text_point := point + Vector2(-caption_width * 0.5, -20)
		draw_string_outline(font, text_point, caption, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, 5, Color("#10191b"))
		draw_string(font, text_point, caption, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color("#bbecdb"))


func _background(tint: Color, pulse: float) -> StyleBoxFlat:
	_box.bg_color = Color("#242629e8")
	_box.border_color = tint.lerp(Color.WHITE, pulse)
	_box.set_border_width_all(2 if pulse > 0.0 else 1)
	_box.set_corner_radius_all(6)
	return _box
