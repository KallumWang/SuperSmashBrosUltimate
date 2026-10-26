extends Control
## The title screen (project.godot's run/main_scene). Its one button is
## connected to this function in StartScreen.tscn.

func _on_start_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/ModeSelect.tscn")
