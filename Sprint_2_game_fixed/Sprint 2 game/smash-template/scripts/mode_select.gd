extends Control
#This lets you choose between online or local
func _on_local_pressed() -> void:
	GameManager.selected_mode = GameManager.Mode.LOCAL
	get_tree().change_scene_to_file("res://scenes/CharacterSelect.tscn")

func _on_online_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/OnlineLobby.tscn")

func _on_back_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/StartScreen.tscn")
