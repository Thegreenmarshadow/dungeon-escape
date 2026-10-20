extends Control
## Pantalla de perfiles (se abre desde el menú principal): muestra cada perfil
## con su tiempo jugado y permite elegirlo, crear uno nuevo o borrarlo. Elegir
## o crear un perfil vuelve al menú con ese perfil. Borrar pide confirmación
## (un segundo clic) porque también borra su telemetría y su partida guardada.

## Segundos que espera el segundo clic de "Borrar".
const DELETE_CONFIRM_TIME := 3.0
const SELECTED_COLOR := Color(1, 0.86, 0.5, 1)
const NORMAL_COLOR := Color(0.95, 0.88, 0.7, 1)
const TIME_COLOR := Color(0.8, 0.72, 0.85, 0.85)

@onready var profile_list: VBoxContainer = %ProfileList
@onready var name_edit: LineEdit = %NameEdit
@onready var create_button: Button = %CreateButton
@onready var back_button: Button = %BackButton
@onready var status_label: Label = %StatusLabel

# Perfil que espera el segundo clic de "Borrar" ("" si ninguno).
var _pending_delete := ""


func _ready() -> void:
	Profiles.ensure_profile()
	create_button.pressed.connect(_on_create_pressed)
	name_edit.text_submitted.connect(func(_text: String) -> void: _on_create_pressed())
	back_button.pressed.connect(Game.go_to_menu)
	status_label.text = ""
	refresh()
	back_button.grab_focus()


## Vuelve a armar la lista de perfiles.
func refresh() -> void:
	for child in profile_list.get_children():
		profile_list.remove_child(child)
		child.queue_free()
	var selected := Profiles.store.selected_slug()
	for profile in Profiles.store.list_profiles():
		profile_list.add_child(_make_row(profile, profile["slug"] == selected))


func _make_row(profile: Dictionary, is_selected: bool) -> HBoxContainer:
	var slug: String = profile["slug"]
	var row := HBoxContainer.new()
	row.name = "Row_" + slug
	row.add_theme_constant_override("separation", 12)

	var name_label := Label.new()
	name_label.text = ("▶ " if is_selected else "") + str(profile["name"])
	name_label.custom_minimum_size = Vector2(260, 0)
	name_label.add_theme_font_size_override("font_size", 22)
	name_label.add_theme_color_override("font_color", SELECTED_COLOR if is_selected else NORMAL_COLOR)
	row.add_child(name_label)

	var time_label := Label.new()
	time_label.text = ProfileStore.format_duration(profile["total_time_s"])
	time_label.custom_minimum_size = Vector2(120, 0)
	time_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	time_label.add_theme_color_override("font_color", TIME_COLOR)
	row.add_child(time_label)

	var save: Dictionary = profile["save"]
	var save_label := Label.new()
	save_label.text = "Nivel %d guardado" % save["level"] if not save.is_empty() else ""
	save_label.custom_minimum_size = Vector2(150, 0)
	save_label.add_theme_color_override("font_color", TIME_COLOR)
	row.add_child(save_label)

	var choose := Button.new()
	choose.name = "ChooseButton"
	choose.text = "En uso" if is_selected else "Elegir"
	choose.disabled = is_selected
	choose.custom_minimum_size = Vector2(110, 0)
	choose.pressed.connect(_on_choose_pressed.bind(slug))
	row.add_child(choose)

	var delete := Button.new()
	delete.name = "DeleteButton"
	delete.text = "Borrar"
	delete.custom_minimum_size = Vector2(110, 0)
	delete.pressed.connect(_on_delete_pressed.bind(slug, delete))
	row.add_child(delete)
	return row


func _on_choose_pressed(slug: String) -> void:
	Profiles.select_profile(slug)
	Game.go_to_menu()


func _on_create_pressed() -> void:
	if name_edit.text.strip_edges().is_empty():
		status_label.text = "Escribe un nombre o apodo"
		name_edit.grab_focus()
		return
	Profiles.create_profile(name_edit.text)
	Game.go_to_menu()


## Primer clic: pide confirmación. Segundo clic (antes de
## DELETE_CONFIRM_TIME): borra el perfil.
func _on_delete_pressed(slug: String, button: Button) -> void:
	if _pending_delete != slug:
		_pending_delete = slug
		button.text = "¿Seguro?"
		status_label.text = "Se borran su tiempo, su partida guardada y su telemetría"
		get_tree().create_timer(DELETE_CONFIRM_TIME).timeout.connect(func() -> void:
			if _pending_delete == slug:
				_pending_delete = ""
				if is_instance_valid(button):
					button.text = "Borrar"
				status_label.text = "")
		return
	_pending_delete = ""
	Profiles.delete_profile(slug)
	status_label.text = "Perfil borrado"
	refresh()
