extends Control

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
	else:
		_setup_cpu_ui()

	for i in GameManager.characters.size():
		var data: Dictionary = GameManager.characters[i]

		var btn := Button.new()
		btn.custom_minimum_size = Vector2(110, 110)
		btn.toggle_mode = true
		
		# Use StyleBoxFlat instead of self_modulate for crisp colors
		var style := StyleBoxFlat.new()
		style.bg_color = data["color"]
		style.corner_radius_top_left = 6
		style.corner_radius_top_right = 6
		style.corner_radius_bottom_left = 6
		style.corner_radius_bottom_right = 6
		
		btn.add_theme_stylebox_override("normal", style)
		btn.add_theme_stylebox_override("hover", style)
		btn.add_theme_stylebox_override("pressed", style)
		btn.add_theme_stylebox_override("focus", style)
		
		btn.pressed.connect(_on_character_pressed.bind(i))
		grid.add_child(btn)
		buttons.append(btn)

		# Add character face indicator
		var face := ColorRect.new()
		face.color = Color(0, 0, 0, 1)
		face.size = Vector2(20, 20)
		face.position = Vector2(45, 45)
		face.mouse_filter = Control.MOUSE_FILTER_IGNORE
		btn.add_child(face)

	_select(0)
	await get_tree().process_frame
	_update_cursor()

func _setup_cpu_ui() -> void:
	cpu_hint.visible = false
	
	var cpu_box := HBoxContainer.new()
	cpu_box.add_theme_constant_override("separation", 10)
	cpu_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cpu_box.alignment = BoxContainer.ALIGNMENT_CENTER
	
	if GameManager.cpu_slots.is_empty():
		GameManager.cpu_slots = [
			{"enabled": true, "character": -1},
			{"enabled": false, "character": -1},
			{"enabled": false, "character": -1}
		]

	for i in GameManager.cpu_slots.size():
		var slot: Dictionary = GameManager.cpu_slots[i]
		if not slot.has("character"):
			slot["character"] = -1

		var btn := Button.new()
		btn.custom_minimum_size = Vector2(120, 36)
		_update_cpu_button_text(btn, i)
		btn.pressed.connect(_on_cpu_button_pressed.bind(i, btn))
		cpu_box.add_child(btn)

	$VBox/Bottom.add_child(cpu_box)
	$VBox/Bottom.move_child(cpu_box, 1)

func _on_cpu_button_pressed(index: int, button: Button) -> void:
	var slot: Dictionary = GameManager.cpu_slots[index]
	
	if not slot["enabled"]:
		slot["enabled"] = true
		slot["character"] = -1
	else:
		if slot["character"] == -1:
			slot["character"] = 0
		elif slot["character"] < GameManager.characters.size() - 1:
			slot["character"] += 1
		else:
			slot["enabled"] = false
			slot["character"] = -1

	_update_cpu_button_text(button, index)

func _update_cpu_button_text(button: Button, index: int) -> void:
	var slot: Dictionary = GameManager.cpu_slots[index]
	
	var style := StyleBoxFlat.new()
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_left = 4
	style.corner_radius_bottom_right = 4

	if not slot["enabled"]:
		button.text = "CPU %d: OFF" % (index + 1)
		style.bg_color = Color(0.2, 0.2, 0.25, 1)
	else:
		var char_idx: int = slot["character"]
		if char_idx == -1:
			button.text = "CPU %d: RANDOM" % (index + 1)
			style.bg_color = Color(0.35, 0.35, 0.45, 1)
		else:
			var char_name: String = GameManager.characters[char_idx]["name"]
			button.text = "CPU %d: %s" % [(index + 1), char_name]
			style.bg_color = GameManager.characters[char_idx]["color"]

	button.add_theme_stylebox_override("normal", style)
	button.add_theme_stylebox_override("hover", style)
	button.add_theme_stylebox_override("pressed", style)
	button.add_theme_stylebox_override("focus", style)

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
	if _is_online:
		cpu_hint.text = "Waiting for the other player to be ready"

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
		get_tree().change_scene_to_file("res://scenes/Game.tscn")

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
