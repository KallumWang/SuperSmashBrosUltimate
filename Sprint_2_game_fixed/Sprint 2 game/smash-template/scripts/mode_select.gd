extends Control
## The "Local vs CPU" / "Online" menu. The three handlers below are hooked up
## to the buttons by signal connections in ModeSelect.tscn (that's why
## nothing in this script calls them).

# Local: record the mode now so character_select.gd knows not to use the
# network, then pick a character.
func _on_local_pressed() -> void:
	GameManager.selected_mode = GameManager.Mode.LOCAL
	get_tree().change_scene_to_file("res://scenes/CharacterSelect.tscn")

# Online: don't set the mode yet - online_lobby.gd sets it to ONLINE only once
# you actually press Host or Join.
func _on_online_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/OnlineLobby.tscn")

func _on_back_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/StartScreen.tscn")
