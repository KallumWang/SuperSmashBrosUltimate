extends Control
#Simple starting screen possibly make it so it changes pictures around when I make some art
func _on_start_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/ModeSelect.tscn")
