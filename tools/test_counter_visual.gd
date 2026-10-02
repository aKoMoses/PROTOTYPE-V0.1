extends "res://tools/test_counter.gd"


func run() -> void:
	scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	await process_frame
	scene.get_node("Interface").call("_start_duel")
	scene.get_node("Interface").call("_begin_live_round")
	player = scene.get_node("Player")
	target = scene.get_node("TargetDummy")
	prepare()
	var modifier = player.get("_visual_rig").aim_modifier
	player.call("_perform_counter")
	check(not guard._panels.visible and not guard._timer_arc.visible, "preparation never advertises protection")
	check(modifier.counter_guard and modifier.counter_weight == 0.0, "guard starts from neutral pose")
	guard.update(0.04)
	check(modifier.counter_weight > 0.0 and modifier.counter_weight < 1.0, "guard pose blends during preparation")
	guard.update(0.04)
	check(guard._panels.visible and guard._timer_arc.visible and modifier.counter_weight == 1.0, "guard geometry and pose match actual protection")
	guard.update(float(guard.definition.guard_duration) * 0.5)
	var vertices: PackedVector3Array = guard._timer_arc.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	check(vertices.size() == 240 and vertices[vertices.size() - 1].z < -1.0, "half-spent guard displays half circle")
	guard.intercept(payload("visual-intercept"))
	check(not guard._panels.visible and not guard._timer_arc.visible, "interception removes protection immediately")
	check(guard._energy.visible and guard._weapon_halo.visible and guard._label.text.begins_with("BLOQUÉ"), "success identifies blocked hit and boosted weapon")
	guard.update(0.06)
	check(modifier.counter_weight > 0.0 and modifier.counter_weight < 1.0, "successful recovery blends out")
	guard.update(0.35)
	check(not modifier.counter_guard and guard._label.text.begins_with("SURCHARGE"), "success feedback becomes ready-to-fire cue")
	player.call("emit_passive_weapon")
	check(not guard._energy.visible and not guard._weapon_halo.visible and not guard._label.visible, "attack emission clears reward immediately")
	guard.cancel(true)
	guard.begin()
	guard.update(float(guard.definition.preparation) + float(guard.definition.guard_duration))
	check(not guard._outline.visible and not guard._panels.visible and not guard._energy.visible, "failed guard leaves no shield or reward")
	guard.cancel(true)
	guard.begin()
	guard.update(0.08)
	guard.intercept(payload("visual-expiry"))
	guard.update(3.0)
	check(not guard._energy.visible and not guard._weapon_halo.visible and not guard._label.visible, "reward expiry removes all persistent cues")
	guard.begin()
	guard.update(0.08)
	guard.cancel(true)
	check(not modifier.counter_guard and not guard._panels.visible and not guard.is_processing(), "cancel resets pose and stops idle VFX updates")
	# The same success snapshot may arrive repeatedly on a network replica.
	var replica := COUNTER.ensure(target)
	replica.authoritative = false
	var reward := {"phase": "recovery", "remaining": 0.12, "surcharge": 3.0, "successes": 1}
	replica.restore(reward)
	check(replica._weapon_halo.visible and not replica._panels.visible, "replica differentiates reward from guard")
	var effect_count := get_nodes_in_group("prototype0_fx_budget").size()
	replica.restore(reward)
	check(get_nodes_in_group("prototype0_fx_budget").size() == effect_count, "repeated snapshot does not replay burst")
	replica.cancel(true)
	# Short particle bursts clean up even when actors are not ticking gameplay.
	await create_timer(0.65).timeout
	var counter_effects := 0
	for effect in get_nodes_in_group("prototype0_fx_budget"):
		if str(effect.name).begins_with("CounterBurst"):
			counter_effects += 1
	check(counter_effects == 0, "all transient rings and particles are freed")
	if failures.is_empty():
		print("COUNTER VISUAL TEST: PASS (%d checks)" % checks)
		quit(0)
	else:
		for failure in failures:
			push_error("COUNTER VISUAL: " + failure)
		quit(1)
