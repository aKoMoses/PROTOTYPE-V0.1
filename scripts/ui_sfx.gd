extends Node

## Shared menu feedback, including controls created after a scene change.
## ui_sfx metadata overrides the family; "silent" reserves feedback for the result.
signal event_played(family: String)

const STREAMS := {
	"navigation": preload("res://art/audio/ui-sfx/01-navigation.wav"),
	"selection": preload("res://art/audio/ui-sfx/02-selection.wav"),
	"confirmation": preload("res://art/audio/ui-sfx/03-confirmation.wav"),
	"launch": preload("res://art/audio/ui-sfx/04-lancement.wav"),
	"back": preload("res://art/audio/ui-sfx/05-retour.wav"),
	"denied": preload("res://art/audio/ui-sfx/06-refus.wav"),
}
var _voice: AudioStreamPlayer
var _last_adjustment_ms := -1000
var _event_serial := 0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_voice = AudioStreamPlayer.new()
	_voice.bus = &"Effects"
	_voice.volume_db = -2.0
	add_child(_voice)
	get_tree().node_added.connect(_node_added)
	_scan(get_tree().root)

func play(family: String) -> void:
	if not STREAMS.has(family):
		return
	_voice.stream = STREAMS[family]
	_voice.play()
	_event_serial += 1
	event_played.emit(family)

func _scan(node: Node) -> void:
	_bind(node)
	for child in node.get_children():
		_scan(child)

func _node_added(node: Node) -> void:
	if not (node is BaseButton or node is PopupMenu or node is Slider):
		return
	# Constructors attach handlers and assign labels after add_child.
	_bind_instance.call_deferred(node.get_instance_id())

func _bind_instance(id: int) -> void:
	var node := instance_from_id(id)
	if is_instance_valid(node):
		_bind(node)

func _bind(node: Node) -> void:
	if not is_instance_valid(node) or node.has_meta("_ui_sfx_bound"):
		return
	var ancestor := node.get_parent()
	while ancestor != null:
		if ancestor.name == &"TouchControls":
			return
		ancestor = ancestor.get_parent()
	if node is BaseButton:
		node.set_meta("_ui_sfx_bound", true)
		node.button_down.connect(_button_down.bind(node))
		node.pressed.connect(_pressed.bind(node))
	elif node is PopupMenu:
		node.set_meta("_ui_sfx_bound", true)
		node.id_pressed.connect(_popup_selected.bind(node))
	elif node is Slider:
		node.set_meta("_ui_sfx_bound", true)
		node.value_changed.connect(_slider_changed.bind(node))

func _button_down(button: BaseButton) -> void:
	button.set_meta("_ui_sfx_press_serial", _event_serial)

func _pressed(button: BaseButton) -> void:
	if not is_instance_valid(button) or button.disabled:
		return
	var before := int(button.get_meta("_ui_sfx_press_serial", _event_serial))
	button.remove_meta("_ui_sfx_press_serial")
	# A synchronous result (notably a refusal) takes precedence over the click.
	if before == _event_serial:
		play(family_for(button))

func _popup_selected(id: int, popup: PopupMenu) -> void:
	if not is_instance_valid(popup):
		return
	var index := popup.get_item_index(id)
	if index < 0 or popup.is_item_disabled(index):
		return
	if popup.get_parent() is OptionButton:
		play("selection")
	else:
		play(_label_family(popup.get_item_text(index)))

func _slider_changed(_value: float, slider: Slider) -> void:
	# Settings refreshes and HUD layout synchronization must remain silent.
	if not slider.is_visible_in_tree() or not slider.has_focus():
		return
	if not (Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) or Input.is_action_pressed("ui_left") or Input.is_action_pressed("ui_right")):
		return
	var now := Time.get_ticks_msec()
	if now - _last_adjustment_ms >= 100:
		_last_adjustment_ms = now
		play("selection")

func family_for(button: BaseButton) -> String:
	if button.has_meta("ui_sfx"):
		return str(button.get_meta("ui_sfx"))
	if button is OptionButton or button is MenuButton:
		return "navigation"
	if button.toggle_mode:
		return "selection"
	var id := str(button.name)
	if id.begins_with("RewardChoice"):
		return "confirmation"
	if id.begins_with("Garage") and id != "GarageSaveAndPlay" and id != "GarageScanner":
		return "selection"
	if id in ["MenuSettingsShortcut", "PauseButton"]:
		return "navigation"
	if id.ends_with("Binding"):
		return "navigation"
	# Arena arrows and the arena title are unlabeled or change their text.
	var ancestor: Node = button.get_parent()
	while ancestor != null:
		if ancestor.name == &"SoloSetup" and (ancestor.get("arena_title") == button or (button is Button and button.text.is_empty())):
			return "selection"
		ancestor = ancestor.get_parent()
	if button.get_script() != null and str(button.get_script().resource_path).ends_with("solo_setup_screen.gd"):
		return "selection"
	return _label_family(button.text if button is Button else "")

func _label_family(label: String) -> String:
	var text := label.to_lower().strip_edges()
	for pair in [["é", "e"], ["è", "e"], ["ê", "e"], ["à", "a"], ["â", "a"], ["î", "i"], ["ô", "o"], ["ù", "u"], ["’", "'"]]:
		text = text.replace(pair[0], pair[1])
	# These actions report completion explicitly, sometimes several seconds later.
	if text in ["enregistrer", "sauvegarder", "sauver et jouer", "garder ce build", "enregistrer la carte"]:
		return "silent"
	for word in ["retour", "reprendre", "quitter", "annuler", "abandonner", "accueil", "atelier", "poursuivre"]:
		if text.contains(word):
			return "back"
	if text in ["‹", "menu", "menu principal"]:
		return "back"
	if text.begins_with("relancer les cartes"):
		return "confirmation"
	for word in ["lancer", "recommencer", "rejouer", "revanche", "nouvel adversaire", "entrer dans", "tester", "refaire", "entrainement libre", "parade", "marque et repositionnement", "ecrasement mural"]:
		if text.contains(word):
			return "launch"
	if text in ["survie", "entrainement", "test tutoriel"]:
		return "launch"
	for word in ["equiper", "creer", "dupliquer", "rejoindre", "actualiser", "reessayer", "relancer les cartes", "passer", "terminer", "soigner", "50 %", "tout retirer", "reset", "reinitialiser", "retablir"]:
		if text.contains(word):
			return "confirmation"
	if text == "✓":
		return "confirmation"
	for word in ["petit", "moyen", "grand", "classique", "piegee", "map test", "placer un", "supprimer un", "devant", "derriere"]:
		if text.contains(word):
			return "selection"
	if text in ["+", "−", "-"]:
		return "selection"
	return "navigation"
