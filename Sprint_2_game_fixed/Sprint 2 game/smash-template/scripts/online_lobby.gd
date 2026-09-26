extends Control

#Some variables which are very important
@onready var status_label: Label = $VBox/StatusLabel
@onready var room_code_input: LineEdit = $VBox/RoomCodeInput
@onready var room_code_label: Label = $VBox/RoomCodeRow/RoomCodeLabel
@onready var copy_button: Button = $VBox/RoomCodeRow/CopyButton

func _ready() -> void:
	NetworkManager.room_ready.connect(_on_room_ready)
	NetworkManager.connection_failed.connect(_on_connection_failed)

func _on_host_pressed() -> void:
	var code := NetworkManager.host_room()
	room_code_label.text = "Room code: %s" % code
	copy_button.visible = true
	status_label.text = "Give your friend the room code above. Waiting for them to join..."
	GameManager.selected_mode = GameManager.Mode.ONLINE

func _on_join_pressed() -> void:
	var code := room_code_input.text.strip_edges()
	if code == "":
		status_label.text = "Enter the room code your friend gave you."
		return
	NetworkManager.join_room(code)
	status_label.text = "Connecting..."
	GameManager.selected_mode = GameManager.Mode.ONLINE

func _on_copy_code_pressed() -> void:
	DisplayServer.clipboard_set(NetworkManager.room_code)
	status_label.text = "Room code copied to clipboard!"

func _on_back_pressed() -> void:
	NetworkManager.close_connection()
	get_tree().change_scene_to_file("res://scenes/ModeSelect.tscn")

func _on_room_ready() -> void:
	status_label.text = "Opponent connected! Choose your character..."
	get_tree().change_scene_to_file("res://scenes/CharacterSelect.tscn")

func _on_connection_failed() -> void:
	status_label.text = "Couldn't connect. Double-check the room code and try again."
