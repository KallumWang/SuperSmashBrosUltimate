extends Control
## Lets you switch each of up to 3 CPU opponents on/off and cycle their
## character color - this is the "toggle multiple CPUs" screen.
## Everything here edits GameManager.cpu_slots directly (see the comment
## above it in GameManager.gd); game.gd's _setup_local() reads it when the
## match starts. Local mode only - online mode never visits this screen.

# The VBoxContainer in CpuSetup.tscn that each CPU row gets added to.
@onready var rows_container: VBoxContainer = $VBox/Rows

# toggle_buttons[i] / color_buttons[i] are the ON/OFF button and the color
# swatch for CPU slot i, kept so the handlers below can update them by index.
var toggle_buttons: Array[Button] = []
var color_buttons: Array[Button] = []

func _ready() -> void:
	# Builds one row per slot in cpu_slots: [label] [ON/OFF] [swatch] [name].
	for i in GameManager.cpu_slots.size():
		var slot: Dictionary = GameManager.cpu_slots[i]

		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 16)

		var label := Label.new()
		label.text = "CPU %d" % (i + 1) # slots are 0-based internally, 1-based on screen
		label.custom_minimum_size = Vector2(80, 0)
		row.add_child(label)

		# Starts in whatever state the slot was last left in, so coming back
		# to this screen (via the BACK button flow) remembers your choices.
		var toggle := Button.new()
		toggle.toggle_mode = true
		toggle.button_pressed = slot["enabled"]
		toggle.text = "ON" if slot["enabled"] else "OFF"
		toggle.custom_minimum_size = Vector2(90, 0)
		toggle.toggled.connect(_on_toggle.bind(i)) # .bind(i) = tell the handler which slot
		row.add_child(toggle)
		toggle_buttons.append(toggle)

		# Clicking the swatch cycles to the next character in the roster
		# (see _on_cycle_color). The swatch shows that character's color.
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
		# Stash the name label on the swatch itself so _on_cycle_color can
		# find it again without keeping a third parallel array.
		swatch.set_meta("name_label", name_label)

		rows_container.add_child(row)

# Toggle button handler. `pressed` is the new state (toggled signal passes
# it automatically), `index` is the slot number we bound in _ready().
func _on_toggle(pressed: bool, index: int) -> void:
	GameManager.cpu_slots[index]["enabled"] = pressed
	toggle_buttons[index].text = "ON" if pressed else "OFF"

# Swatch click: moves this CPU to the next character in
# GameManager.characters, wrapping back to the first after the last one
# (the % count). Because it loops over the whole roster, new characters from
# character_roster.gd show up here automatically.
func _on_cycle_color(index: int) -> void:
	var count: int = GameManager.characters.size()
	var new_index: int = (GameManager.cpu_slots[index]["character"] + 1) % count
	GameManager.cpu_slots[index]["character"] = new_index
	color_buttons[index].self_modulate = GameManager.characters[new_index]["color"]
	var name_label: Label = color_buttons[index].get_meta("name_label")
	name_label.text = GameManager.characters[new_index]["name"]

# CONFIRM: set the mode again to be safe (this screen is only ever reached in
# local mode) and jump into the match.
func _on_confirm_pressed() -> void:
	GameManager.selected_mode = GameManager.Mode.LOCAL
	Scenes.go(get_tree(), "res://scenes/Game.tscn")

func _on_back_pressed() -> void:
	Scenes.go(get_tree(), "res://scenes/CharacterSelect.tscn")
