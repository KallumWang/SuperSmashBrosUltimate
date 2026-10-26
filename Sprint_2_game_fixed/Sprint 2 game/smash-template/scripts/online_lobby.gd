extends Control
## The Host / Join screen for online play. Hosting makes a 5-letter room
## code; joining means typing a friend's code. Once the relay says both
## players are in the room, this screen moves on to Character Select.
## All the actual networking lives in autoload/NetworkManager.gd - this
## script only drives the buttons and status text.

#Some variables which are very important
# (Node paths into OnlineLobby.tscn.) status_label is the line of text that
# tells you what's happening, room_code_input is where the joiner types the
# code, and room_code_label + copy_button are the "Room code: XXXXX" row that
# only appears once you've hosted.
@onready var status_label: Label = $VBox/StatusLabel
@onready var room_code_input: LineEdit = $VBox/RoomCodeInput
@onready var room_code_label: Label = $VBox/RoomCodeRow/RoomCodeLabel
@onready var copy_button: Button = $VBox/RoomCodeRow/CopyButton

func _ready() -> void:
	# room_ready fires when the relay reports both players are connected;
	# connection_failed fires if the socket couldn't open or closed before
	# the room was ever ready. Both are signals declared in NetworkManager.gd.
	NetworkManager.room_ready.connect(_on_room_ready)
	NetworkManager.connection_failed.connect(_on_connection_failed)

# HOST button. host_room() makes a random code AND connects to the relay
# room with it, then we show the code so the friend can type it in.
func _on_host_pressed() -> void:
	var code := NetworkManager.host_room()
	room_code_label.text = "Room code: %s" % code
	copy_button.visible = true # hidden in the scene until there's a code to copy
	status_label.text = "Give your friend the room code above. Waiting for them to join..."
	# Flip the whole game into online mode (game.gd and character_select.gd
	# both check this). mode_select.gd's _on_online_pressed() doesn't set it,
	# so this and _on_join_pressed() below are the only places it happens.
	GameManager.selected_mode = GameManager.Mode.ONLINE

# JOIN button.
func _on_join_pressed() -> void:
	var code := room_code_input.text.strip_edges() # forgive stray spaces from copy/paste
	if code == "":
		status_label.text = "Enter the room code your friend gave you."
		return
	NetworkManager.join_room(code) # also upper-cases it, so "abc12" works
	status_label.text = "Connecting..."
	GameManager.selected_mode = GameManager.Mode.ONLINE

func _on_copy_code_pressed() -> void:
	DisplayServer.clipboard_set(NetworkManager.room_code)
	status_label.text = "Room code copied to clipboard!"

func _on_back_pressed() -> void:
	NetworkManager.close_connection() # drop out of the room if we were in one
	get_tree().change_scene_to_file("res://scenes/ModeSelect.tscn")

# Both players are in. The status text is set but you'll barely see it,
# since the scene changes on the very next line.
func _on_room_ready() -> void:
	status_label.text = "Opponent connected! Choose your character..."
	get_tree().change_scene_to_file("res://scenes/CharacterSelect.tscn")

func _on_connection_failed() -> void:
	status_label.text = "Couldn't connect. Double-check the room code and try again."
