extends RefCounted

## Presentation only: the player remains authoritative for casts and timers.
const EQUIPMENT_ICONS := preload("res://scripts/equipment_icons.gd")
const COMBAT_DATA := preload("res://scripts/combat_data.gd")
const JAVELIN_RECAST_ICON := preload("res://art/ui/icons/javelin-recast.svg")
const READY_FLASH_DURATION := 0.85
const ACTIONS := ["offensive", "defensive", "mobility"]
var states: Dictionary = {}
var _icons := EQUIPMENT_ICONS.new()
var _active := false

func reset() -> void:
	states.clear()
	_active = false

func update(actor: Node, delta: float, active: bool) -> void:
	if actor == null or not is_instance_valid(actor):
		reset()
		return
	var was_active := _active
	_active = active
	for action in ACTIONS:
		var getter := "get_%s_module_id" % action
		if not actor.has_method(getter):
			continue
		var identifier := str(actor.call(getter))
		var remaining := float(actor.call("get_module_cooldown", identifier))
		var charges := int(actor.call("get_pyro_charges")) if identifier == "pyro_boots" else -1
		var previous: Dictionary = states.get(action, {})
		var same_module := str(previous.get("id", "")) == identifier
		var flash := maxf(0.0, float(previous.get("flash", 0.0)) - delta) if same_module and active else 0.0
		if same_module and charges >= 0 and charges < int(previous.get("charges", charges)):
			flash = 0.0
		# Initial display, equipment changes and round resets do not announce a recharge.
		if same_module and active and was_active:
			var recovered := charges > int(previous.get("charges", charges)) if charges >= 0 else remaining <= 0.0 and float(previous.get("remaining", 0.0)) > 0.0
			if recovered:
				flash = READY_FLASH_DURATION
		var recast := identifier == "javelin" and actor.has_method("get_javelin_recast_fraction") and float(actor.call("get_javelin_recast_fraction")) > 0.0
		if identifier == "static_shield" and actor.has_method("get_stasis_remaining"):
			var stasis := float(actor.call("get_stasis_remaining"))
			var survival_shield: Node = actor.get("survival_evolution_effects") if bool(actor.get("survival_mode")) else null
			recast = stasis > 0.0 or (survival_shield != null and survival_shield.shield_remaining > 0.0)
		var preparing := false
		for method in ["is_fulguro_charging", "is_pelto_preparing", "is_javelin_charging", "is_eclipse_aiming"]:
			if actor.has_method(method) and bool(actor.call(method)):
				if (action == "offensive" and method != "is_eclipse_aiming") or (action == "mobility" and method == "is_eclipse_aiming"):
					preparing = true
		var definition: Dictionary = COMBAT_DATA.MODULE_DEFINITIONS.get(identifier, {})
		var duration := float(definition.get("cooldown", 1.0))
		var multipliers: Variant = actor.get("_survival_cooldown_multipliers")
		if multipliers is Dictionary:
			duration *= float(multipliers.get(action, 1.0))
		var unavailable := remaining > 0.0 and charges != 1 and charges != 2 and not recast and not preparing
		if unavailable:
			flash = 0.0
		states[action] = {"id": identifier, "remaining": remaining, "fraction": clampf(remaining / maxf(duration, remaining), 0.0, 1.0) if remaining > 0.0 else 0.0, "charges": charges, "recast": recast, "preparing": preparing, "unavailable": unavailable, "flash": flash}

func draw_button(canvas: Control, action: String, center: Vector2, radius: float, accent: Color, opacity: float, scale: float) -> void:
	var state: Dictionary = states.get(action, {})
	var identifier := str(state.get("id", ""))
	var texture: Texture2D = _icons.get_icon(identifier)
	if identifier == "javelin" and bool(state.get("recast", false)):
		texture = JAVELIN_RECAST_ICON
	var unavailable := bool(state.get("unavailable", false))
	var edge := Color("#687780") if unavailable else accent
	canvas.draw_circle(center, radius, _alpha(Color("#111e26"), 0.88 * opacity))
	canvas.draw_arc(center, radius - 1.0, 0.0, TAU, 64, _alpha(edge, 0.9 * opacity), 2.5 * scale, true)
	if texture != null:
		var extent := Vector2.ONE * radius * 1.58
		var tint := _alpha(Color("#aaaeb3") if unavailable else Color.WHITE, opacity)
		canvas.draw_texture_rect(_icons.get_cooldown_icon(identifier) if unavailable else texture, Rect2(center - extent * 0.5, extent), false, tint)
	else:
		_draw_text(canvas, action.left(1).to_upper(), center + Vector2(0, 5 * scale), 16 * scale, _alpha(Color.WHITE, opacity))
	var fraction := float(state.get("fraction", 0.0))
	if fraction > 0.0 and not bool(state.get("recast", false)) and not bool(state.get("preparing", false)):
		var wedge := PackedVector2Array([center])
		var segments := maxi(2, ceili(64 * fraction))
		for index in range(segments + 1):
			var angle := -PI * 0.5 + TAU * fraction * float(index) / float(segments)
			wedge.append(center + Vector2.from_angle(angle) * (radius - 3.0 * scale))
		canvas.draw_colored_polygon(wedge, _alpha(Color("#78828d"), (0.32 if unavailable else 0.16) * opacity))
		canvas.draw_arc(center, radius - 1.0, -PI * 0.5 + TAU * fraction, PI * 1.5, 64, _alpha(accent, opacity), 3.5 * scale, true)
		var text := "%.1f" % float(state.get("remaining", 0.0))
		var baseline := center + Vector2(0, radius * 0.47)
		canvas.draw_rect(Rect2(baseline + Vector2(-16, -12) * scale, Vector2(32, 16) * scale), _alpha(Color("#101921"), 0.86 * opacity))
		_draw_text(canvas, text, baseline, 12 * scale, _alpha(Color("#eef1f2"), opacity))
	var charges := int(state.get("charges", -1))
	if identifier == "static_shield" and bool(state.get("recast", false)):
		_draw_text(canvas, "SORTIR", center + Vector2(0, radius * 0.55), 11 * scale, _alpha(Color.WHITE, opacity))
	if charges >= 0:
		for index in range(2):
			canvas.draw_circle(center + Vector2((float(index) - 0.5) * 13 * scale, radius * 0.75), 3.5 * scale, _alpha(accent if index < charges else Color("#56616b"), opacity))
	var flash := float(state.get("flash", 0.0))
	if flash > 0.0:
		var progress := 1.0 - flash / READY_FLASH_DURATION
		var fade := (1.0 - progress) * opacity
		canvas.draw_circle(center, radius * 0.92, _alpha(Color("#fff0c7"), maxf(0.0, 1.0 - progress * 4.0) * 0.30 * opacity))
		canvas.draw_arc(center, radius + progress * 19.0 * scale, 0.0, TAU, 64, _alpha(accent.lerp(Color.WHITE, 0.65), fade), 4.0 * scale, true)
		canvas.draw_arc(center, radius - 1.0, 0.0, TAU, 64, _alpha(Color("#fff0c7"), fade), 4.0 * scale, true)
		for index in range(6):
			var direction := Vector2.from_angle(TAU * float(index) / 6.0 - PI * 0.5)
			canvas.draw_line(center + direction * (radius + (5.0 + progress * 11.0) * scale), center + direction * (radius + (10.0 + progress * 17.0) * scale), _alpha(accent, fade * 0.75), 2.0 * scale, true)

func _alpha(color: Color, opacity: float) -> Color:
	return Color(color.r, color.g, color.b, opacity)

func _draw_text(canvas: Control, text: String, baseline: Vector2, font_size: float, color: Color) -> void:
	var font := ThemeDB.fallback_font
	var size := maxi(9, roundi(font_size))
	var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, size).x
	canvas.draw_string(font, baseline - Vector2(width * 0.5, 0), text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, size, color)
