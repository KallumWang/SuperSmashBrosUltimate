extends Control
## The title screen (project.godot's run/main_scene). START is connected to
## _on_start_pressed in StartScreen.tscn; the ALMANAC button below is made in
## code (so the scene file didn't need editing) and opens the reference book.

func _ready() -> void:
	# Copy the START button's height so the two buttons match, then slot the
	# new one right under it inside the same VBox.
	var start_button: Button = $VBox/StartButton
	var almanac_button := Button.new()
	almanac_button.text = "ALMANAC"
	almanac_button.custom_minimum_size = start_button.custom_minimum_size
	almanac_button.pressed.connect(_on_almanac_pressed)
	var box := start_button.get_parent()
	box.add_child(almanac_button)
	box.move_child(almanac_button, start_button.get_index() + 1) # add_child puts it last, which is already right here - this just makes the order explicit

func _on_start_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/ModeSelect.tscn")

# Characters + controls reference (scripts/almanac.gd). Its BACK button
# returns here.
func _on_almanac_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/Almanac.tscn")
