class_name PassiveHud
extends Control

## Presentation only; inherits the spell bar's visibility and HUD transforms.
const ICONS := preload("res://scripts/equipment_icons.gd")
var player: Node
var _icons = ICONS.new()


static func attach(bar: Control, actor: Node, controller: Node) -> Control:
	var widget := PassiveHud.new()
	widget.name = "PassiveSlot"
	widget.player = actor
	# A smaller, separate medallion beside the active modules. The stable HUD
	# identity still lets the interface editor move and scale it independently.
	widget.size = Vector2(48, 56)
	widget.position = Vector2(-60.0, (bar.size.y - widget.size.y) * 0.5)
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
	var active := float(state.get("alternator", 0.0)) > 0.0 or float(state.get("inertia", 0.0)) > 0.0 or float(state.get("reveal", 0.0)) > 0.0
	var tint := Color("#bbecdb") if active else Color("#dcc298")
	var pulse := clampf(float(state.get("pulse", 0.0)) / 0.25, 0.0, 1.0)
	var center := Vector2(24, 22)
	draw_circle(center, 21.0, Color("#172023e8"))
	draw_arc(center, 20.0, 0.0, TAU, 48, tint.lerp(Color.WHITE, pulse), 1.5 + pulse, true)
	var icon: Texture2D = _icons.get_icon(id)
	if icon != null:
		var icon_tint := Color.WHITE.lerp(Color("#bbecdb"), maxf(float(active), pulse))
		if id == "auxiliary_reactor" and float(state.get("reactor", 0.0)) > 0.0:
			icon_tint.a = 0.6
		draw_texture_rect(icon, Rect2(9, 7, 30, 30), false, icon_tint)
	# A permanent automatic-effect seal, never a keyboard shortcut or button.
	draw_circle(Vector2(40, 8), 8.0, Color("#172023"))
	draw_arc(Vector2(40, 8), 7.0, 0.0, TAU, 24, tint, 1.0, true)
	draw_string(ThemeDB.fallback_font, Vector2(32, 12), "∞", HORIZONTAL_ALIGNMENT_CENTER, 16, 13, tint)
	draw_string(ThemeDB.fallback_font, Vector2(0, 54), "PASSIF", HORIZONTAL_ALIGNMENT_CENTER, 48, 9, tint)
	var counter := ""
	match id:
		"auxiliary_reactor":
			if float(state.get("reactor", 0.0)) > 0.0:
				counter = str(ceili(float(state.reactor)))
		"tracker":
			var marks := int(state.get("marks", 0))
			var segments := maxi(1, int(state.get("hits", 3)))
			var step := 30.0 / segments
			for index in segments:
				draw_rect(Rect2(9 + index * step, 37, maxf(1.0, step - 2.0), 2), Color("#bbecdb") if index < marks or active else Color("#536365"))
		"alternator":
			if active:
				counter = str(ceili(float(state.alternator)))
		"inertia":
			if active:
				counter = str(ceili(float(state.inertia)))
	if not counter.is_empty():
		draw_rect(Rect2(28, 28, 19, 14), Color("#172023"))
		draw_string(ThemeDB.fallback_font, Vector2(28, 39), counter, HORIZONTAL_ALIGNMENT_CENTER, 19, 10, tint)
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
