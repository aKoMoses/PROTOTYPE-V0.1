extends SceneTree

const VISUAL := preload("res://scripts/touch_module_visual.gd")
const ICONS := preload("res://scripts/equipment_icons.gd")
const LOADOUT := preload("res://scripts/loadout_state.gd")
var failures: Array[String] = []

class Actor extends Node:
	var offensive := "pelto_smash"
	var defensive := "projector"
	var mobility := "eclipse"
	var cooldowns: Dictionary = {}
	var pyro_charges := 2
	var recast := 0.0
	var preparing := false
	var _survival_cooldown_multipliers := {"offensive": 1.0, "defensive": 1.0, "mobility": 1.0}
	func get_offensive_module_id() -> String: return offensive
	func get_defensive_module_id() -> String: return defensive
	func get_mobility_module_id() -> String: return mobility
	func get_module_cooldown(identifier: String) -> float: return float(cooldowns.get(identifier, 0.0))
	func get_pyro_charges() -> int: return pyro_charges
	func get_javelin_recast_fraction() -> float: return recast
	func is_pelto_preparing() -> bool: return preparing

func check(ok: bool, message: String) -> void:
	if not ok: failures.append(message)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var actor := Actor.new()
	var visual := VISUAL.new()
	visual.update(actor, 0.016, true)
	check(float(visual.states.offensive.flash) == 0.0, "no ready flash on initial display")
	actor.cooldowns = {"pelto_smash": 10.0, "projector": 3.0, "eclipse": 2.5}
	visual.update(actor, 0.016, true)
	check(is_equal_approx(visual.states.offensive.fraction, 1.0), "full cooldown at activation")
	check(is_equal_approx(visual.states.defensive.fraction, 0.5), "defensive half cooldown")
	check(is_equal_approx(visual.states.mobility.fraction, 0.25), "mobility quarter cooldown")
	check(bool(visual.states.offensive.unavailable), "cooldown greys the unusable icon")
	actor._survival_cooldown_multipliers.offensive = 0.5
	actor.cooldowns.pelto_smash = 2.5
	visual.update(actor, 0.016, true)
	check(is_equal_approx(visual.states.offensive.fraction, 0.5), "survival reductions keep an accurate circle")
	actor.preparing = true
	visual.update(actor, 0.016, true)
	check(not bool(visual.states.offensive.unavailable), "preparing stays readable")
	actor.preparing = false
	actor.cooldowns.pelto_smash = 0.0
	visual.update(actor, 0.016, true)
	check(float(visual.states.offensive.flash) > 0.8, "a recovered module emits a pulse")
	visual.update(actor, 0.40, true)
	check(float(visual.states.offensive.flash) < 0.5, "pulse fades without restarting")
	visual.update(actor, 0.50, true)
	check(float(visual.states.offensive.flash) == 0.0, "pulse stops after 850 ms")
	actor.offensive = "javelin"
	actor.cooldowns.javelin = 9.0
	actor.recast = 0.7
	visual.update(actor, 0.016, true)
	check(bool(visual.states.offensive.recast) and not bool(visual.states.offensive.unavailable), "Javelin teleport remains available during cooldown")
	check(float(visual.states.offensive.flash) == 0.0, "equipment change never announces a recovery")
	actor.recast = 0.0
	visual.update(actor, 0.016, true)
	check(bool(visual.states.offensive.unavailable), "Javelin returns to cooldown when recast ends")
	actor.mobility = "pyro_boots"
	actor.pyro_charges = 0
	actor.cooldowns.pyro_boots = 4.0
	visual.update(actor, 0.016, true)
	check(bool(visual.states.mobility.unavailable), "empty Pyro Boots are grey")
	actor.pyro_charges = 1
	actor.cooldowns.pyro_boots = 2.0
	visual.update(actor, 0.016, true)
	check(not bool(visual.states.mobility.unavailable) and float(visual.states.mobility.flash) > 0.8, "first Pyro charge is usable and flashes while second recharges")
	actor.pyro_charges = 0
	visual.update(actor, 0.016, true)
	check(float(visual.states.mobility.flash) == 0.0, "spending a recovered charge cancels its old flash")
	actor.pyro_charges = 2
	actor.cooldowns.pyro_boots = 0.0
	visual.update(actor, 0.016, true)
	check(float(visual.states.mobility.flash) > 0.8, "second Pyro charge also announces its recovery")
	visual.update(actor, 0.016, false)
	check(float(visual.states.mobility.flash) == 0.0 and str(visual.states.mobility.id) == "pyro_boots", "pause clears transient effects and retains equipment")
	visual.update(actor, 0.016, true)
	check(float(visual.states.mobility.flash) == 0.0, "resume does not replay a stale recovery")
	var icons := ICONS.new()
	for identifier in LOADOUT.OFFENSIVE + LOADOUT.DEFENSIVE + LOADOUT.MOBILITY + LOADOUT.PASSIVES:
		var texture: Texture2D = icons.get_icon(identifier)
		check(texture != null, "module icon exists: " + identifier)
		if texture == null: continue
		var source := texture.get_image()
		var used := source.get_used_rect()
		check(used.size.x >= 110 and used.size.y >= 110, "icon is legible: " + identifier)
		check(used.position.x > 0 and used.position.y > 0 and used.end.x < source.get_width() and used.end.y < source.get_height(), "transparent icon does not clip: " + identifier)
		if identifier in LOADOUT.PASSIVES: continue
		var grey: Texture2D = icons.get_cooldown_icon(identifier)
		var grey_image := grey.get_image()
		check(grey.get_size() == texture.get_size(), "cooldown icon preserves dimensions: " + identifier)
		for y in range(0, grey_image.get_height(), 16):
			for x in range(0, grey_image.get_width(), 16):
				var pixel := grey_image.get_pixel(x, y)
				if pixel.a < 0.5: continue
				check(absf(pixel.r - pixel.g) < 0.01 and absf(pixel.g - pixel.b) < 0.01, "cooldown texture is desaturated: " + identifier)
	actor.free()
	for failure in failures: push_error("FAIL: " + failure)
	print("MODULE ICONS / TOUCH COOLDOWN VISUAL TEST: ", "PASS" if failures.is_empty() else "FAIL")
	quit(0 if failures.is_empty() else 1)
