extends Control
## The Host / Join screen for online play. Hosting makes a 5-letter room
## code; joining means typing a friend's code. Up to 4 players can be in a
## room. Everyone waits here until the HOST presses START MATCH (it appears
## once hosting and needs 2+ players); that moves all of them on to
## Character Select together.
## Online play needs a USERNAME (the leaderboard tracks wins by account): the
## first time, an account box appears under the title - type a name and press
## REGISTER (see NetworkManager.register_name). It's saved on this computer,
## so it's a one-time thing.
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

# Made in code (the scene file didn't need editing): the host's START MATCH
# button. Hidden for joiners, enabled once at least 2 players are in the room.
var start_button: Button
# The one-time username box (shown only until you've registered), plus the
# "Playing as: X" line that replaces it afterwards. Both made in code.
var account_label: Label
var name_input: LineEdit
var register_button: Button

func _ready() -> void:
	# room_ready fires when the host presses START MATCH;
	# connection_failed fires if the socket couldn't open or closed before
	# the room was ever ready. Both are signals declared in NetworkManager.gd.
	NetworkManager.room_ready.connect(_on_room_ready)
	NetworkManager.connection_failed.connect(_on_connection_failed)
	# roster_changed fires every time someone joins or leaves the room.
	NetworkManager.roster_changed.connect(_on_roster_changed)
	NetworkManager.registered.connect(_on_registered)
	_build_account_box()

	start_button = Button.new()
	start_button.text = "START MATCH"
	start_button.visible = false
	start_button.disabled = true
	start_button.pressed.connect(_on_start_pressed)
	# Slot it in right above the status text.
	status_label.get_parent().add_child(start_button)
	status_label.get_parent().move_child(start_button, status_label.get_index())

# Builds the username UI and slots it in right under the "ONLINE" title.
func _build_account_box() -> void:
	var box := status_label.get_parent()
	account_label = Label.new()
	account_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_input = LineEdit.new()
	name_input.placeholder_text = "Choose a username (3-16 letters/numbers)"
	name_input.max_length = 16
	name_input.text_submitted.connect(func(_t): _on_register_pressed()) # Enter works too
	register_button = Button.new()
	register_button.text = "REGISTER"
	register_button.pressed.connect(_on_register_pressed)
	for node in [account_label, name_input, register_button]:
		box.add_child(node)
	# Title is child 0 - put the account widgets right after it.
	box.move_child(account_label, 1)
	box.move_child(name_input, 2)
	box.move_child(register_button, 3)
	_refresh_account_box()

# Registered -> just "Playing as: Name". Not yet -> the name box + button.
func _refresh_account_box() -> void:
	var registered_now := NetworkManager.is_registered()
	name_input.visible = not registered_now
	register_button.visible = not registered_now
	account_label.text = ("Playing as: %s" % NetworkManager.player_name) if registered_now else "Register a username to play online"
	if registered_now:
		account_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))

func _on_register_pressed() -> void:
	register_button.disabled = true
	status_label.text = "Registering..."
	NetworkManager.register_name(name_input.text)

# The answer to register_name(): either a new account, or the reason it failed
# (name taken, bad characters, server unreachable...).
func _on_registered(ok: bool, message: String) -> void:
	register_button.disabled = false
	status_label.text = message
	_refresh_account_box()

# HOST button. host_room() makes a random code AND connects to the relay
# room with it, then we show the code so the friend can type it in.
func _on_host_pressed() -> void:
	if not NetworkManager.is_registered():
		status_label.text = "Register a username first (the box under ONLINE)."
		return
	var code := NetworkManager.host_room()
	room_code_label.text = "Room code: %s" % code
	copy_button.visible = true # hidden in the scene until there's a code to copy
	status_label.text = "Give your friends the room code above (up to 4 players). Press START MATCH when everyone is in."
	start_button.visible = true # only the host ever sees this
	# Flip the whole game into online mode (game.gd and character_select.gd
	# both check this). mode_select.gd's _on_online_pressed() doesn't set it,
	# so this and _on_join_pressed() below are the only places it happens.
	GameManager.selected_mode = GameManager.Mode.ONLINE

# JOIN button.
func _on_join_pressed() -> void:
	if not NetworkManager.is_registered():
		status_label.text = "Register a username first (the box under ONLINE)."
		return
	var code := room_code_input.text.strip_edges() # forgive stray spaces from copy/paste
	if code == "":
		status_label.text = "Enter the room code your friend gave you."
		return
	NetworkManager.join_room(code) # also upper-cases it, so "abc12" works
	status_label.text = "Connecting..."
	GameManager.selected_mode = GameManager.Mode.ONLINE

# Shows who is in the room. The host's START MATCH unlocks at 2+ players;
# joiners just see a waiting message until the host starts.
func _on_roster_changed() -> void:
	var count: int = NetworkManager.slots.size()
	# A readable list of who is here, e.g. "Kal, Bob, Sam".
	var who: Array = []
	for slot in NetworkManager.slots:
		who.append(NetworkManager.names.get(slot, "") if NetworkManager.names.get(slot, "") != "" else "Player %d" % (slot + 1))
	var list_text := ", ".join(who)
	if NetworkManager.is_host:
		start_button.disabled = count < 2
		status_label.text = "Players in room (%d / 4): %s. %s" % [count, list_text, "Press START MATCH when everyone is in." if count >= 2 else "Waiting for someone to join..."]
	else:
		status_label.text = "Connected! Players in room (%d / 4): %s. Waiting for the host to start..." % [count, list_text]

# HOST ONLY. Tells the relay to start the match; NetworkManager.start_match()
# then triggers room_ready for us and the relay sends everyone else "go".
func _on_start_pressed() -> void:
	NetworkManager.start_match()

func _on_copy_code_pressed() -> void:
	DisplayServer.clipboard_set(NetworkManager.room_code)
	status_label.text = "Room code copied to clipboard!"

func _on_back_pressed() -> void:
	NetworkManager.close_connection() # drop out of the room if we were in one
	get_tree().change_scene_to_file("res://scenes/ModeSelect.tscn")

# The host started the match (NetworkManager's "go"). The status text is set
# but you'll barely see it, since the scene changes on the very next line.
func _on_room_ready() -> void:
	status_label.text = "Starting! Choose your character..."
	get_tree().change_scene_to_file("res://scenes/CharacterSelect.tscn")

func _on_connection_failed() -> void:
	status_label.text = "Couldn't connect. Double-check the room code and try again."
