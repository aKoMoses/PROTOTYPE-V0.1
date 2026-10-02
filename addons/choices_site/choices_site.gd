@tool
extends EditorPlugin

const CHOICES_URL := "https://prototype-zero-site.vercel.app/choix.html"
const MENU_LABEL := "Site des choix"

var _choices_button: Button


func _enter_tree() -> void:
	_choices_button = Button.new()
	_choices_button.name = "ChoicesSiteButton"
	_choices_button.text = MENU_LABEL
	_choices_button.tooltip_text = "Ouvrir les propositions et les votes dans le navigateur\n" + CHOICES_URL
	_choices_button.flat = true
	_choices_button.focus_mode = Control.FOCUS_NONE
	_choices_button.pressed.connect(_open_choices_site)
	add_control_to_container(CONTAINER_TOOLBAR, _choices_button)
	add_tool_menu_item(MENU_LABEL, _open_choices_site)


func _exit_tree() -> void:
	remove_tool_menu_item(MENU_LABEL)
	if is_instance_valid(_choices_button):
		remove_control_from_container(CONTAINER_TOOLBAR, _choices_button)
		_choices_button.queue_free()
		_choices_button = null


func _open_choices_site() -> void:
	var error := OS.shell_open(CHOICES_URL)
	if error != OK:
		push_error("Impossible d'ouvrir le site des choix : " + error_string(error))
