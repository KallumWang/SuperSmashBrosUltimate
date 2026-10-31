extends Control
## The title screen (project.godot's run/main_scene). START is connected to
## _on_start_pressed in StartScreen.tscn; the ALMANAC and LEADERBOARD buttons
## below are made in code (so the scene file didn't need editing).

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

	# Same idea for the leaderboard, right under ALMANAC.
	var board_button := Button.new()
	board_button.text = "LEADERBOARD"
	board_button.custom_minimum_size = start_button.custom_minimum_size
	board_button.pressed.connect(_on_leaderboard_pressed)
	box.add_child(board_button)
	box.move_child(board_button, almanac_button.get_index() + 1)

	# SETTINGS (music volume + key rebinding), under LEADERBOARD.
	var settings_button := Button.new()
	settings_button.text = "SETTINGS"
	settings_button.custom_minimum_size = start_button.custom_minimum_size
	settings_button.pressed.connect(func(): Scenes.go(get_tree(), "res://scenes/Settings.tscn"))
	box.add_child(settings_button)
	box.move_child(settings_button, board_button.get_index() + 1)

func _on_start_pressed() -> void:
	Scenes.go(get_tree(), "res://scenes/ModeSelect.tscn")

# Characters + controls reference (scripts/almanac.gd). Its BACK button
# returns here.
func _on_almanac_pressed() -> void:
	Scenes.go(get_tree(), "res://scenes/Almanac.tscn")

# Global wins/games table (scripts/leaderboard.gd). Its BACK button returns here.
func _on_leaderboard_pressed() -> void:
	Scenes.go(get_tree(), "res://scenes/Leaderboard.tscn")
