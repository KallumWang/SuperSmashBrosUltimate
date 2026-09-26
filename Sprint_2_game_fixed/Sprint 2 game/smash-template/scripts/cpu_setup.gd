extends Control
## Lets you switch each of up to 3 CPU opponents on/off and cycle their
## character color - this is the "toggle multiple CPUs" screen.

@onready var rows_container: VBoxContainer = $VBox/Rows

var toggle_buttons: Array[Button] = []
var color_buttons: Array[Button] = []

func _ready() -> void:
	for i in GameManager.cpu_slots.size():
		var slot: Dictionary = GameManager.cpu_slots[i]

		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 16)

		var label := Label.new()
		label.text = "CPU %d" % (i + 1)
		label.custom_minimum_size = Vector2(80, 0)
		row.add_child(label)

		var toggle := Button.new()
		toggle.toggle_mode = true
		toggle.button_pressed = slot["enabled"]
		toggle.text = "ON" if slot["enabled"] else "OFF"
		toggle.custom_minimum_size = Vector2(90, 0)
		toggle.toggled.connect(_on_toggle.bind(i))
		row.add_child(toggle)
		toggle_buttons.append(toggle)

		var swatch := Button.new()
		swatch.custom_minimum_size = Vector2(70, 40)
		swatch.self_modulate = GameManager.characters[slot["character"]]["color"]
		swatch.pressed.connect(_on_cycle_color.bind(i))
		row.add_child(swatch)
		color_buttons.append(swatch)

		var name_label := Label.new()
		name_label.text = GameManager.characters[slot["character"]]["name"]
		name_label.custom_minimum_size = Vector2(90, 0)
		row.add_child(name_label)
		swatch.set_meta("name_label", name_label)

		rows_container.add_child(row)

func _on_toggle(pressed: bool, index: int) -> void:
	GameManager.cpu_slots[index]["enabled"] = pressed
	toggle_buttons[index].text = "ON" if pressed else "OFF"

func _on_cycle_color(index: int) -> void:
	var count: int = GameManager.characters.size()
	var new_index: int = (GameManager.cpu_slots[index]["character"] + 1) % count
	GameManager.cpu_slots[index]["character"] = new_index
	color_buttons[index].self_modulate = GameManager.characters[new_index]["color"]
	var name_label: Label = color_buttons[index].get_meta("name_label")
	name_label.text = GameManager.characters[new_index]["name"]

func _on_confirm_pressed() -> void:
	GameManager.selected_mode = GameManager.Mode.LOCAL
	get_tree().change_scene_to_file("res://scenes/Game.tscn")

func _on_back_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/CharacterSelect.tscn")
