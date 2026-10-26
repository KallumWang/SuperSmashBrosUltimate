extends Control
#this code should work for both CPU and Online
#Hopefully it works how I intended and Online both players use WASD F
# (Note on "WASD F": this screen itself is mouse-only - the WASD+F part is
# the in-match controls. Both online players use the p1_ layout from
# InputSetup.gd, see game.gd's _setup_online().)

# Node paths into CharacterSelect.tscn - these have to match the scene tree.
# grid is the 4-column GridContainer the character buttons get added to
# (columns = 4 is set in the scene, not here), cursor is the yellow outline
# box that sits around whichever button is selected, and preview_* is the big
# swatch + name panel on the right.
@onready var grid: GridContainer = $VBox/Main/GridPanel/CharacterGrid
@onready var cursor: Panel = $SelectionCursor
@onready var preview_swatch: ColorRect = $VBox/Main/PreviewPanel/PreviewVBox/PreviewSwatch
@onready var preview_face: ColorRect = $VBox/Main/PreviewPanel/PreviewVBox/PreviewSwatch/PreviewFace
@onready var preview_name: Label = $VBox/Main/PreviewPanel/PreviewVBox/PreviewName
@onready var cpu_hint: Label = $VBox/Bottom/CpuHint

# selected_index is a position in GameManager.characters (built in
# scripts/character_roster.gd). buttons[i] is the grid button for character i.
var selected_index: int = 0
var buttons: Array[Button] = []

# Online-only state. _confirmed locks the screen after you hit CONFIRM so you
# can't change your pick; _my_pick / _opponent_pick start at -1 meaning "not
# chosen yet", and the match only starts once both are filled in
# (see _maybe_start_match).
var _is_online: bool = false
var _confirmed: bool = false
var _my_pick: int = -1
var _opponent_pick: int = -1

func _ready() -> void:
	_is_online = GameManager.selected_mode == GameManager.Mode.ONLINE
	if _is_online:
		# Listen for the other player's "pick" message and for them leaving.
		# (NetworkManager is an autoload that survived the scene change from
		# OnlineLobby, so the connection is still open.)
		NetworkManager.message_received.connect(_on_message_received)
		NetworkManager.peer_left.connect(_on_peer_left)

	# One button per character in the roster - nothing here is hard-coded
	# per character, which is why adding to character_roster.gd is enough
	# for a new character to show up on this screen.
	for i in GameManager.characters.size():
		var data: Dictionary = GameManager.characters[i]

		var btn := Button.new()
		btn.custom_minimum_size = Vector2(110, 110)
		btn.toggle_mode = true # stays "pressed" so the selected one looks held down
		btn.self_modulate = data["color"] # tints just the button, not its children
		# .bind(i) bakes the character's index into the callback so
		# _on_character_pressed knows WHICH button was clicked
		btn.pressed.connect(_on_character_pressed.bind(i))
		grid.add_child(btn)
		buttons.append(btn)

		# The little face square drawn on each button, same idea as the
		# face in sprite_gen.gd (and the same face_color so Guy Black's
		# face shows up white instead of vanishing).
		var face := ColorRect.new()
		face.color = data.get("face_color", Color(0, 0, 0, 1))
		face.size = Vector2(20, 20)
		face.position = Vector2(45, 45) # centered in the 110x110 button
		face.mouse_filter = Control.MOUSE_FILTER_IGNORE # so clicks pass through to the button underneath
		btn.add_child(face)

	_select(0)
	# The grid hasn't been laid out yet on the first frame, so the buttons
	# don't have real positions - wait one frame, THEN place the cursor.
	await get_tree().process_frame
	_update_cursor()

func _on_character_pressed(index: int) -> void:
	if _confirmed:
		return # already locked in (online) - ignore clicks
	_select(index)

# Highlights one character: un-presses every other button, updates the
# preview panel, and moves the cursor. Doesn't lock anything in - that's
# _on_confirm_pressed.
func _select(index: int) -> void:
	selected_index = index
	for i in buttons.size():
		buttons[i].button_pressed = (i == index)

	var data: Dictionary = GameManager.characters[index]
	preview_swatch.color = data["color"]
	preview_face.color = data.get("face_color", Color(0, 0, 0, 1))
	preview_name.text = data["name"]
	cpu_hint.text = "Waiting for the other player to be ready" if _is_online else "Next: choose your CPU opponents"

	_update_cursor()

# Puts the yellow outline box around the selected button: 6px bigger on
# every side (the -6 offset and the +12 size).
func _update_cursor() -> void:
	if buttons.is_empty():
		return
	var btn := buttons[selected_index]
	cursor.global_position = btn.global_position - Vector2(6, 6)
	cursor.size = btn.size + Vector2(12, 12)

# CONFIRM button (connected in CharacterSelect.tscn). Saves your pick to
# GameManager, then goes a different direction per mode: local goes to the
# CPU Opponents screen, online sends the pick to the other player and waits.
func _on_confirm_pressed() -> void:
	if _confirmed:
		return
	GameManager.player1_character = selected_index

	if _is_online:
		_confirmed = true
		_my_pick = selected_index
		cpu_hint.text = "Waiting for the other player to pick..."
		# The pick goes over the wire as the INDEX in the roster, so both
		# players need the same roster in the same order (same game version).
		NetworkManager.send({"type": "pick", "character": selected_index})
		_maybe_start_match()
	else:
		get_tree().change_scene_to_file("res://scenes/CpuSetup.tscn")

# The other player's "pick" message arrives here (their copy of
# _on_confirm_pressed above sent it).
func _on_message_received(data: Dictionary) -> void:
	if data.get("type") == "pick":
		_opponent_pick = int(data.get("character", 0))
		_maybe_start_match()

# Called after EITHER side's pick lands. Does nothing until both picks are in,
# so it doesn't matter who confirms first.
func _maybe_start_match() -> void:
	if _my_pick == -1 or _opponent_pick == -1:
		return
	GameManager.online_opponent_character = _opponent_pick
	get_tree().change_scene_to_file("res://scenes/Game.tscn")

func _on_peer_left() -> void:
	cpu_hint.text = "The other player disconnected."

func _on_back_pressed() -> void:
	if _is_online:
		NetworkManager.close_connection() # leave the room so the relay frees it up
	get_tree().change_scene_to_file("res://scenes/ModeSelect.tscn")
