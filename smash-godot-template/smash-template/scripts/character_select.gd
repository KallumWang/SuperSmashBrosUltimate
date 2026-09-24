extends Control

## This picks YOUR character; CPU opponents are configured on the next
## screen (CpuSetup.tscn).

@onready var grid: GridContainer = $VBox/Main/GridPanel/CharacterGrid
@onready var cursor: Panel = $SelectionCursor
@onready var preview_swatch: ColorRect = $VBox/Main/PreviewPanel/PreviewVBox/PreviewSwatch
@onready var preview_name: Label = $VBox/Main/PreviewPanel/PreviewVBox/PreviewName
@onready var cpu_hint: Label = $VBox/Bottom/CpuHint

var selected_index: int = 0
var buttons: Array[Button] = []

func _ready() -> void:
	for i in GameManager.characters.size():
		var data: Dictionary = GameManager.characters[i]

		var btn := Button.new()
		btn.custom_minimum_size = Vector2(110, 110)
		btn.toggle_mode = true
		btn.self_modulate = data["color"]
		btn.pressed.connect(_on_character_pressed.bind(i))
		grid.add_child(btn)
		buttons.append(btn)

		var face := ColorRect.new()
		face.color = Color(0, 0, 0, 1)
		face.size = Vector2(20, 20)
		face.position = Vector2(45, 45)
		face.mouse_filter = Control.MOUSE_FILTER_IGNORE
		btn.add_child(face)

	_select(0)
	await get_tree().process_frame
	_update_cursor()

func _on_character_pressed(index: int) -> void:
	_select(index)

func _select(index: int) -> void:
	selected_index = index
	for i in buttons.size():
		buttons[i].button_pressed = (i == index)

	var data: Dictionary = GameManager.characters[index]
	preview_swatch.color = data["color"]
	preview_name.text = data["name"]
	cpu_hint.text = "Next: choose your CPU opponents"

	_update_cursor()

func _update_cursor() -> void:
	if buttons.is_empty():
		return
	var btn := buttons[selected_index]
	cursor.global_position = btn.global_position - Vector2(6, 6)
	cursor.size = btn.size + Vector2(12, 12)

func _on_confirm_pressed() -> void:
	GameManager.player1_character = selected_index
	GameManager.selected_mode = GameManager.Mode.LOCAL
	get_tree().change_scene_to_file("res://scenes/CpuSetup.tscn")

func _on_back_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/ModeSelect.tscn")
