extends SceneTree

var _failures: Array[String] = []

func _initialize() -> void:
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	await process_frame
	var flow: Node = scene.get_node_or_null("Interface")
	var player: Node = scene.get_node_or_null("Player")
	var target: Node = scene.get_node_or_null("TargetDummy")
	var camera_rig: Node = scene.get_node_or_null("CameraRig")
	if flow == null or player == null or target == null or camera_rig == null:
		_failures.append("flow ou acteur manquant")
	else:
		if int(flow.get("current_screen")) != 0:
			_failures.append("écran menu absent au démarrage")
		var menu_music := flow.get_node("MenuMusic") as AudioStreamPlayer
		if menu_music.stream == null or not menu_music.playing:
			_failures.append("musique du menu absente au démarrage")
		elif menu_music.stream.resource_path != "res://art/audio/menu_poussiere_et_cambouis.wav":
			_failures.append("le menu ne joue pas la piste choisie")
		else:
			var menu_stream := menu_music.stream as AudioStreamWAV
			if menu_stream.loop_mode != AudioStreamWAV.LOOP_FORWARD or menu_stream.loop_begin <= 0 or menu_stream.loop_end <= menu_stream.loop_begin:
				_failures.append("boucle du menu absente ou invalide")
			menu_music.seek(menu_stream.get_length() - 0.2)
			await create_timer(0.6).timeout
			if not menu_music.playing or menu_music.get_playback_position() < 4.75 or menu_music.get_playback_position() > 8.0:
				_failures.append("la musique ne reboucle pas après son introduction")
			menu_music.seek(0.0)
		await create_timer(0.15).timeout
		var menu_position := menu_music.get_playback_position()
		flow.call("_open_settings")
		flow.call("_open_equipment")
		if not menu_music.playing or menu_music.get_playback_position() < menu_position:
			_failures.append("musique du menu interrompue pendant la navigation")
		var tabs: Dictionary = flow.get("_equipment_nav_buttons")
		(tabs["passive"] as Button).emit_signal("pressed")
		if str(flow.get("_equipment_category")) != "passive":
			_failures.append("onglet passif inaccessible")
		var choices: Dictionary = flow.get("_selection_buttons")
		(choices["passive"]["omnivamp"] as Button).emit_signal("pressed")
		var current_loadout: Dictionary = flow.get("loadout")
		if str(current_loadout.passive) != "omnivamp":
			_failures.append("la sélection du passif ne met pas à jour l'équipement")
		var previews: Dictionary = flow.get("_equipment_preview_buttons")
		(previews["weapon"] as Button).emit_signal("pressed")
		if str(flow.get("_equipment_category")) != "weapon":
			_failures.append("le récapitulatif ne ramène pas à la catégorie choisie")
		var selected := {"weapon": "shotgun", "offensive": "javelin", "defensive": "static_shield", "mobility": "bio_injector", "passive": "omnivamp"}
		flow.set("loadout", selected)
		flow.call("_start_duel")
		await process_frame
		if int(flow.get("current_screen")) != 3:
			_failures.append("le duel ne démarre pas depuis l'équipement")
		if str(flow.call("get_round_phase_name")) != "COUNTDOWN":
			_failures.append("le décompte de manche n'est pas actif")
		if bool(player.call("is_gameplay_enabled")):
			_failures.append("joueur actif pendant le décompte")
		var intro_audio := flow.get_node("CountdownAudio") as AudioStreamPlayer
		var match_music := flow.get_node("MatchMusic") as AudioStreamPlayer
		var result_audio := flow.get_node("ResultAudio") as AudioStreamPlayer
		await create_timer(0.6).timeout
		if menu_music.playing:
			_failures.append("musique du menu encore active pendant le duel")
		if match_music.stream == null or not match_music.stream is AudioStreamWAV:
			_failures.append("musique locale du duel absente")
		else:
			var music_stream := match_music.stream as AudioStreamWAV
			if music_stream.resource_path != "res://son-musique/musiques/02_tambours_de_guerre_30s.wav" or music_stream.loop_mode != AudioStreamWAV.LOOP_FORWARD or music_stream.loop_begin != 0 or music_stream.loop_end != 1323000:
				_failures.append("boucle musicale mal configurée")
			if not match_music.playing:
				_failures.append("musique non lancée au décompte")
		var intro_image := flow.get_node("FlowRoot/CountdownOverlay/CountdownDigit") as TextureRect
		if intro_audio.stream == null or intro_audio.stream.resource_path != "res://art/audio/countdown-3.mp3":
			_failures.append("son du chiffre 3 absent")
		var countdown_before_pause := float(flow.get("_countdown_remaining"))
		flow.call("_toggle_pause")
		await process_frame
		if not match_music.stream_paused:
			_failures.append("musique non suspendue pendant la pause")
		if absf(float(flow.get("_countdown_remaining")) - countdown_before_pause) > 0.01:
			_failures.append("pause n'arrête pas le décompte")
		flow.call("_resume")
		if match_music.stream_paused:
			_failures.append("musique non reprise après la pause")
		flow.set("_countdown_remaining", 2.05)
		flow.call("_process", 0.1)
		if intro_image.texture.resource_path != "res://art/countdown/2.png" or intro_audio.stream.resource_path != "res://art/audio/countdown-2.mp3":
			_failures.append("image ou son du chiffre 2 absent")
		flow.set("_countdown_remaining", 1.05)
		flow.call("_process", 0.1)
		if intro_image.texture.resource_path != "res://art/countdown/1.png" or intro_audio.stream.resource_path != "res://art/audio/countdown-1.mp3":
			_failures.append("image ou son du chiffre 1 absent")
		flow.set("_countdown_remaining", 0.01)
		flow.call("_process", 0.02)
		if str(flow.call("get_round_phase_name")) != "FIGHT" or bool(player.call("is_gameplay_enabled")):
			_failures.append("FIGHT doit précéder le combat actif")
		if intro_image.texture.resource_path != "res://art/countdown/fight.png" or intro_audio.stream.resource_path != "res://art/audio/countdown-fight.mp3":
			_failures.append("image ou son FIGHT absent")
		var fight_before_pause := float(flow.get("_fight_remaining"))
		flow.call("_toggle_pause")
		await process_frame
		if absf(float(flow.get("_fight_remaining")) - fight_before_pause) > 0.01:
			_failures.append("pause n'arrête pas FIGHT")
		flow.call("_resume")
		if str(player.call("get_weapon_id")) != "shotgun":
			_failures.append("arme de départ non transmise")
		if str(player.call("get_offensive_module_id")) != "javelin":
			_failures.append("module offensif non transmis")
		flow.set("_fight_remaining", 0.01)
		flow.call("_process", 0.02)
		await process_frame
		if str(flow.call("get_round_phase_name")) != "LIVE" or not bool(player.call("is_gameplay_enabled")):
			_failures.append("la manche ne passe pas en combat actif")
		var player_bar := player.get_node_or_null("WorldUIAnchor/PlayerHealthReadout/HealthBarSprite") as Sprite3D
		var target_bar := target.get_node_or_null("TargetHealthReadout/HealthBarSprite") as Sprite3D
		if player_bar == null or target_bar == null or player_bar.texture == null or target_bar.texture == null:
			_failures.append("barres de vie des combattants absentes")
		target.call("take_damage", 50.0, "test", "readout_hit")
		var target_number := target.get_node_or_null("TargetHealthReadout/HealthBarViewport/HealthBarUI/HealthNumber") as Label
		var damage_popup := target.get_node_or_null("TargetHealthReadout/DamageNumber1")
		if target_number == null or target_number.text != str(roundi(float(target.call("get_max_health")) - 50.0)) or damage_popup == null:
			_failures.append("PV ou chiffre de dégâts non mis à jour")
		target.call("take_damage", 20.0, "test:burn", "readout_burn")
		target.call("take_damage", 30.0, "test:melee", "readout_melee")
		if damage_popup == null or float(damage_popup.get("total_damage")) != 100.0 or int(damage_popup.get("hit_count")) != 3 or target.get_node_or_null("TargetHealthReadout/DamageNumber2") != null:
			_failures.append("les dégâts rapprochés de sources différentes ne sont pas regroupés")
		var target_readout := target.get_node_or_null("TargetHealthReadout")
		if target_readout != null:
			var segments: Array = target_readout.get("_segments")
			if segments.size() != 10 or (segments[9].visible and segments[9].size.x >= 23.0):
				_failures.append("les segments ne montrent pas les PV perdus")
		if damage_popup != null:
			damage_popup.call("_process", 0.23)
		target.call("take_damage", 10.0, "test", "readout_later")
		if target.get_node_or_null("TargetHealthReadout/DamageNumber2") == null:
			_failures.append("des coups espacés restent fusionnés")
		target.call("reset_combat_state")
		flow.call("_toggle_pause")
		if not bool(flow.get("_pause_active")):
			_failures.append("pause non activée")
		flow.call("_resume")
		if bool(flow.get("_pause_active")):
			_failures.append("pause non levée")
		flow.call("resolve_round", false, true)
		await process_frame
		if result_audio.playing:
			_failures.append("jingle joué avant le résultat final du match")
		if str(flow.call("get_round_phase_name")) != "WINNER_FOCUS" or flow.get("_result_panel").visible:
			_failures.append("focus vainqueur absent avant le résultat")
		if camera_rig.get("_focus_target") != player:
			_failures.append("caméra ne cible pas le vainqueur")
		if player_bar == null or player_bar.visible:
			_failures.append("la barre masque le plan du vainqueur")
		var score: Vector2i = flow.call("get_match_score")
		if score != Vector2i(1, 0):
			_failures.append("score de victoire incorrect: %s" % score)
		var focus_before_pause := float(flow.get("_winner_focus_remaining"))
		flow.call("_toggle_pause")
		await process_frame
		if absf(float(flow.get("_winner_focus_remaining")) - focus_before_pause) > 0.01:
			_failures.append("pause n'arrête pas le focus vainqueur")
		flow.call("_resume")
		flow.call("_process", 1.6)
		if str(flow.call("get_round_phase_name")) != "ROUND_RESULT" or not flow.get("_result_panel").visible:
			_failures.append("résultat absent après la transition")
		flow.call("resolve_round", false, true)
		var duplicate_score: Vector2i = flow.call("get_match_score")
		if duplicate_score != Vector2i(1, 0):
			_failures.append("un même résultat incrémente deux fois")
		flow.set("_round_result_remaining", 0.0)
		flow.call("_start_next_round")
		if str(flow.call("get_round_phase_name")) != "COUNTDOWN" or not is_equal_approx(float(target.call("get_health")), float(target.call("get_max_health"))):
			_failures.append("la manche suivante ne réinitialise pas les PV")
		flow.call("_begin_live_round")
		flow.call("resolve_round", true, true)
		var tie_score: Vector2i = flow.call("get_match_score")
		if tie_score != Vector2i(1, 0):
			_failures.append("une égalité attribue un point")
		flow.set("player_round_score", 2)
		flow.set("bot_round_score", 0)
		flow.set("round_phase", 2)
		flow.set("_round_resolved", false)
		flow.call("resolve_round", false, true)
		flow.call("_process", 1.6)
		flow.set("_round_result_remaining", 0.0)
		flow.call("_start_next_round")
		if str(flow.call("get_round_phase_name")) != "MATCH_RESULT" or int(flow.get("current_screen")) != 4:
			_failures.append("le match ne se termine pas à trois victoires")
		if not result_audio.playing or result_audio.stream.resource_path != "res://son-musique/musiques/01_victoire_rock.wav":
			_failures.append("signature de victoire absente au résultat final")
		if match_music.playing or intro_audio.playing:
			_failures.append("la musique du combat masque le résultat final")
		await create_timer(0.15).timeout
		var result_position := result_audio.get_playback_position()
		flow.call("_show_final_result")
		if result_audio.get_playback_position() < result_position:
			_failures.append("le résultat final relance sa signature")
		flow.call("_restart")
		if result_audio.playing:
			_failures.append("la signature continue après rejouer")
		flow.call("_begin_live_round")
		if player_bar != null and not player_bar.visible:
			_failures.append("la barre reste cachée au combat suivant")
		flow.call("resolve_round", true, false)
		if camera_rig.get("_focus_target") != target or flow.call("get_match_score") != Vector2i(0, 1):
			_failures.append("la défaite ne cadre pas le bot vainqueur")
		flow.set("bot_round_score", 3)
		flow.call("_process", 1.6)
		flow.set("_round_result_remaining", 0.0)
		flow.call("_start_next_round")
		if not result_audio.playing or result_audio.stream.resource_path != "res://son-musique/musiques/02_defaite_forge.wav":
			_failures.append("signature de défaite absente au résultat final")
		flow.call("_open_equipment")
		if result_audio.playing:
			_failures.append("la signature continue dans l'équipement")
		flow.call("_return_menu")
		if not menu_music.playing or match_music.playing:
			_failures.append("retour au menu ne restaure pas sa musique seule")
		# A quick return must cancel the pending fade-out callback.
		flow.call("_start_duel")
		flow.call("_return_menu")
		await create_timer(0.9).timeout
		if not menu_music.playing or menu_music.volume_db < -11.0:
			_failures.append("retour rapide au menu laisse sa musique coupée")
	scene.queue_free()
	for _cleanup_frame in range(3):
		await process_frame
	if _failures.is_empty():
		print("V02-02 MATCH FLOW TEST: PASS")
		quit(0)
	else:
		for failure in _failures:
			push_error("FAIL: " + failure)
		print("P0-125 GAME FLOW TEST: FAIL (%d)" % _failures.size())
		quit(1)
