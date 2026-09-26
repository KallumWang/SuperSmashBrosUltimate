extends Control
#this code should work for both CPU and Online
#Hopefully it works how I intended and Online both players use WASD F

@onready var grid: GridContainer = $VBox/Main/GridPanel/CharacterGrid
@onready var cursor: Panel = $SelectionCursor
@onready var preview_swatch: ColorRect = $VBox/Main/PreviewPanel/PreviewVBox/PreviewSwatch
@onready var preview_name: Label = $VBox/Main/PreviewPanel/PreviewVBox/PreviewName
@onready var cpu_hint: Label = $VBox/Bottom/CpuHint

var selected_index: int = 0
var buttons: Array[Button] = []

var _is_online: bool = false
var _confirmed: bool = false
var _my_pick: int = -1
var _opponent_pick: int = -1

func _ready() -> void:
	_is_online = GameManager.selected_mode == GameManager.Mode.ONLINE
	if _is_online:
		NetworkManager.message_received.connect(_on_message_received)
		NetworkManager.peer_left.connect(_on_peer_left)

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
	if _confirmed:
		return
	_select(index)

func _select(index: int) -> void:
	selected_index = index
	for i in buttons.size():
		buttons[i].button_pressed = (i == index)

	var data: Dictionary = GameManager.characters[index]
	preview_swatch.color = data["color"]
	preview_name.text = data["name"]
	cpu_hint.text = "Waiting for the other player to be ready" if _is_online else "Next: choose your CPU opponents"

	_update_cursor()

func _update_cursor() -> void:
	if buttons.is_empty():
		return
	var btn := buttons[selected_index]
	cursor.global_position = btn.global_position - Vector2(6, 6)
	cursor.size = btn.size + Vector2(12, 12)

func _on_confirm_pressed() -> void:
	if _confirmed:
		return
	GameManager.player1_character = selected_index

	if _is_online:
		_confirmed = true
		_my_pick = selected_index
		cpu_hint.text = "Waiting for the other player to pick..."
		NetworkManager.send({"type": "pick", "character": selected_index})
		_maybe_start_match()
	else:
		get_tree().change_scene_to_file("res://scenes/CpuSetup.tscn")

func _on_message_received(data: Dictionary) -> void:
	if data.get("type") == "pick":
		_opponent_pick = int(data.get("character", 0))
		_maybe_start_match()

func _maybe_start_match() -> void:
	if _my_pick == -1 or _opponent_pick == -1:
		return
	GameManager.online_opponent_character = _opponent_pick
	get_tree().change_scene_to_file("res://scenes/Game.tscn")

func _on_peer_left() -> void:
	cpu_hint.text = "The other player disconnected."

func _on_back_pressed() -> void:
	if _is_online:
		NetworkManager.close_connection()
	get_tree().change_scene_to_file("res://scenes/ModeSelect.tscn")
