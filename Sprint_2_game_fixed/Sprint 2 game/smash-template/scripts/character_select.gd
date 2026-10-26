extends Control
#this code should work for both CPU and Online
#Hopefully it works how I intended and Online both players use WASD F
# (Note on "WASD F": this screen itself is mouse-only - the WASD+F part is
# the in-match controls. Both online players use the p1_ layout from
# InputSetup.gd, see game.gd's _setup_online().)
##
## Smash-style layout: a grid odefeeeeeef character tiles on top and a row of four
## colored player panels (P1 red, P2 blue, P3 yellow, P4 green) along the
## bottom. P1 is you. P2-P4 are the three CPU slots from
## GameManager.cpu_slots (local mode) - or just "P2 = the other player" in
## online mode.
##rrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrr
## How to use it:
##   1. Click a panel to make it the ACTIVE one (white border). Clicking an
##      empty CPU panel adds that CPU; its REMOVE button turns it off again.
##   2. Click a tile in the grid to give the active panel that character.
##      The "?" tile at the end means Random (for a CPU, a new random
##      fighter is rolled every match - see game.gd's _setup_local()).
##   3. CONFIRM.
## Nothing here spawns fighters: every click only writes into GameManager
## (player1_character / cpu_slots) and game.gd reads it when the match starts.

# Classic Smash player colors, in P1..P4 order.
const PANEL_COLORS := [
	Color(0.85, 0.15, 0.15), # P1 red
	Color(0.15, 0.4, 0.9),   # P2 blue
	Color(0.95, 0.75, 0.1),  # P3 yellow
	Color(0.2, 0.7, 0.25),   # P4 green
]
# The roster grid is laid out like Smash's: a fixed number of columns, tiles
# packed tightly across the whole width, and empty slots filling out the
# rows so it looks like a full roster waiting to be filled. The "?" Random
# tile always sits in the very last slot (bottom-right corner).
const GRID_COLUMNS := 10
const MIN_ROWS := 3 # always draw at least this many rows, even with only a few characters
const TILE_W := 104
const TILE_GAP := 4
const GRID_HEIGHT := 290 # roughly how much vertical space the grid area has - tile height shrinks to fit more rows
const EMPTY_SLOT_COLOR := Color(0.14, 0.15, 0.2)
const OFF_COLOR := Color(0.25, 0.25, 0.28) # a CPU panel that's switched off
const RANDOM_COLOR := Color(0.45, 0.45, 0.5) # the "?" tile and a Random pick

# Node paths into CharacterSelect.tscn - these have to match the scene tree.
# grid is the GridContainer the cfharacter tiles get added to, cursor is the
# yellow outline box that sits around the tile the ACTIVE panel has picked,
# preview_panel is the old big preview box on the right (hidden now - the
# bottom panels replaced it), and cpu_hint is the line of text in the middle
# of the BACK / CONFIRM row.
@onready var grid: GridContainer = $VBox/Main/GridPanel/CharacterGrid
@onready var cursor: Panel = $SelectionCursor
@onready var preview_panel: PanelContainer = $VBox/Main/PreviewPanel
@onready var cpu_hint: Label = $VBox/Bottom/CpuHint

# tiles[i] is the button for character i, and the LAST tile (index
# GameManager.characters.size()) is the "?" Random tile.
var tiles: Array[Button] = []
# One dictionary per bottom panel with the UI pieces _refresh() needs to
# update (see _build_panels for what's inside).
var panels: Array[Dictionary] = []
# Which panel clicks on the grid currently go to (0 = P1/you, 1..3 = CPUs).
var active_panel: int = 0
# P1's pick - a character index, or GameManager.RANDOM_CHARACTER (-1).
# (CPU picks live in GameManager.cpu_slots instead, so they survive
# leaving and re-entering this screen.)
var _p1_choice: int = 0

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

	preview_panel.visible = false # the bottom panels do this job now
	grid.columns = GRID_COLUMNS # overrides the 4 set in the scene
	grid.add_theme_constant_override("h_separation", TILE_GAP) # (the scene had 16 - too loose for Smash-style)
	grid.add_theme_constant_override("v_separation", TILE_GAP)
	grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	grid.size_flags_vertical = Control.SIZE_SHRINK_CENTER # float in the middle of the panel instead of hugging the top

	cpu_hint.text = "Waiting for the other player to be ready" if _is_online else "Click a panel, then click a character"

	_build_tiles()
	_build_panels()
	_refresh()
	# The grid hasn't been laid out yet on the first frame, so the tiles
	# don't have real positions - wait one frame, THEN place the cursor.
	await get_tree().process_frame
	_update_cursor()

# Builds the roster grid. Slots are filled in this order: every character in
# the roster, then empty placeholder slots, then the "?" Random tile in the
# very last slot. Nothing here is hard-coded per character, which is why
# adding to character_roster.gd is enough for a new character to show up
# (it just takes over the next empty slot).
func _build_tiles() -> void:
	var count: int = GameManager.characters.size()
	# Round up to whole rows (+1 because Random takes a slot too), minimum MIN_ROWS.
	var rows: int = maxi(MIN_ROWS, ceili((count + 1) / float(GRID_COLUMNS)))
	var slot_count: int = rows * GRID_COLUMNS
	# More rows -> shorter tiles so the whole grid still fits on screen.
	var tile_h: int = clampi((GRID_HEIGHT - (rows - 1) * TILE_GAP) / rows, 48, 78)

	for slot in slot_count:
		if slot < count:
			var data: Dictionary = GameManager.characters[slot]
			var btn := _make_tile(data["color"], tile_h)
			# .bind(slot) bakes the tile's number into the callback so
			# _on_tile_pressed knows WHICH tile was clicked
			btn.pressed.connect(_on_tile_pressed.bind(slot))
			grid.add_child(btn)
			tiles.append(btn)

			# The little face square on the tile, same idea as the face in
			# sprite_gen.gd (and the same face_color so Guy Black's face
			# shows up white instead of vanishing). Sits a bit above
			# center to leave room for the name along the bottom.
			var face := ColorRect.new()
			face.color = data.get("face_color", Color(0, 0, 0, 1))
			face.size = Vector2(18, 18)
			face.position = Vector2((TILE_W - 18) / 2.0, (tile_h - 18) / 2.0 - 8)
			face.mouse_filter = Control.MOUSE_FILTER_IGNORE # so clicks pass through to the tile underneath
			btn.add_child(face)

			var name_label := _make_label(data["name"].to_upper(), 13)
			name_label.add_theme_constant_override("outline_size", 4)
			name_label.position = Vector2(0, tile_h - 22)
			name_label.size = Vector2(TILE_W, 20)
			btn.add_child(name_label)
		elif slot < slot_count - 1:
			# An empty slot: a dark, disabled tile that just fills out the grid.
			var empty := _make_tile(EMPTY_SLOT_COLOR, tile_h)
			empty.disabled = true
			grid.add_child(empty)
		else:
			# The last slot is always Random. Its number is characters.size(),
			# one past the last real character, which _tile_to_choice()
			# turns into RANDOM_CHARACTER.
			var random_tile := _make_tile(RANDOM_COLOR, tile_h)
			random_tile.text = "?"
			random_tile.add_theme_font_size_override("font_size", 36)
			random_tile.pressed.connect(_on_tile_pressed.bind(count))
			grid.add_child(random_tile)
			tiles.append(random_tile) # lands at index `count`, matching the number bound above

	# Each tile also gets a row of small "P1" / "P2"... tags in its top-left
	# corner showing which panels have picked it - filled in by _refresh().
	for t in tiles:
		var tag_row := HBoxContainer.new()
		tag_row.position = Vector2(3, 3)
		tag_row.add_theme_constant_override("separation", 2)
		tag_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		t.add_child(tag_row)
		t.set_meta("tag_row", tag_row)

# A button filled with a solid color. The default Button look is dark grey,
# so tinting it (self_modulate) came out muddy - instead each state gets its
# own flat colored box: a bit lighter on hover.
func _make_tile(color: Color, tile_h: int) -> Button:
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(TILE_W, tile_h)
	for state in ["normal", "pressed", "focus", "disabled"]:
		btn.add_theme_stylebox_override(state, _tile_style(color))
	btn.add_theme_stylebox_override("hover", _tile_style(color.lightened(0.2)))
	return btn

func _tile_style(color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(4)
	return style

# A small colored "P1"-style badge, the same color as that player's bottom panel.
func _make_tag(panel_index: int) -> PanelContainer:
	var tag := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = PANEL_COLORS[panel_index]
	style.set_corner_radius_all(3)
	style.content_margin_left = 4
	style.content_margin_right = 4
	style.content_margin_top = 0
	style.content_margin_bottom = 0
	tag.add_theme_stylebox_override("panel", style)
	tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var label := _make_label("P%d" % (panel_index + 1), 12)
	label.add_theme_constant_override("outline_size", 3)
	tag.add_child(label)
	return tag

# Builds the row of colored player panels along the bottom: 4 in local mode
# (you + 3 CPUs), 2 in online mode (you + the other player). Made in code so
# the scene file doesn't need editing, then slotted into the $VBox just above
# the BACK/CONFIRM row. Each panel is stacked like Smash's: "P1" tag, a big
# swatch with the character's face, their name, and a bottom line (plus an
# ADD CPU / REMOVE button on CPU panels).
func _build_panels() -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.custom_minimum_size = Vector2(0, 210)

	var count: int = 2 if _is_online else 4
	for i in count:
		var root := PanelContainer.new()
		root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		# The panel's look: a solid color box with a border. _refresh() swaps
		# the border color/thickness to show which panel is active.
		var style := StyleBoxFlat.new()
		style.bg_color = PANEL_COLORS[i]
		style.set_corner_radius_all(8)
		root.add_theme_stylebox_override("panel", style)
		# Clicking anywhere on the panel (not on its button) makes it active.
		root.gui_input.connect(_on_panel_gui_input.bind(i))

		var box := VBoxContainer.new()
		box.alignment = BoxContainer.ALIGNMENT_CENTER
		box.add_theme_constant_override("separation", 4)
		root.add_child(box)

		var tag := _make_label("P%d" % (i + 1), 26)
		box.add_child(tag)

		# The big colored square showing the character (same body + face
		# idea as the tiles). IGNORE so clicks fall through to the panel.
		var swatch := ColorRect.new()
		swatch.custom_minimum_size = Vector2(90, 90)
		swatch.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		swatch.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_child(swatch)
		var face := ColorRect.new()
		face.size = Vector2(22, 22)
		face.position = Vector2(34, 34)
		face.mouse_filter = Control.MOUSE_FILTER_IGNORE
		swatch.add_child(face)
		# Shown instead of the face when the pick is Random.
		var question := _make_label("?", 56)
		question.size = Vector2(90, 90)
		question.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		swatch.add_child(question)

		var name_label := _make_label("", 22)
		box.add_child(name_label)

		var info := _make_label("", 16) # "Player 1" / "CPU 2" / "Opponent"
		box.add_child(info)

		# P1 can't be removed (and online's P2 is the other human), so only
		# CPU panels in local mode get a button.
		var button: Button = null
		if i > 0 and not _is_online:
			button = Button.new()
			button.pressed.connect(_on_panel_button_pressed.bind(i))
			box.add_child(button)

		row.add_child(root)
		panels.append({
			"root": root, "style": style, "swatch": swatch, "face": face,
			"question": question, "name": name_label, "info": info, "button": button,
		})

	var vbox: VBoxContainer = $VBox
	vbox.add_child(row)
	# add_child puts it last (below the buttons), so move it to Bottom's
	# position to push the BACK/CONFIRM row down underneath it.
	vbox.move_child(row, $VBox/Bottom.get_index())

# White text with a black outline so it reads on every panel color.
func _make_label(text: String, font_size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", Color.WHITE)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 6)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label

# --- reading/writing a panel's pick ---------------------------------------
# "choice" everywhere below means: a character index, or
# GameManager.RANDOM_CHARACTER (-1) for Random.

func _get_choice(panel_index: int) -> int:
	if panel_index == 0:
		return _p1_choice
	return GameManager.cpu_slots[panel_index - 1]["character"]

func _set_choice(panel_index: int, choice: int) -> void:
	if panel_index == 0:
		_p1_choice = choice
	else:
		GameManager.cpu_slots[panel_index - 1]["character"] = choice

# Is this panel "in the match"? P1 always is; online P2 (the other player)
# always is; a CPU panel is whatever its slot's "enabled" says.
func _panel_on(panel_index: int) -> bool:
	if panel_index == 0 or _is_online:
		return true
	return GameManager.cpu_slots[panel_index - 1]["enabled"]

# The grid's last tile (the "?") stands for Random; every other tile number
# is just the character's index. These two convert between the two.
func _tile_to_choice(tile_index: int) -> int:
	return GameManager.RANDOM_CHARACTER if tile_index == GameManager.characters.size() else tile_index

func _choice_to_tile(choice: int) -> int:
	return GameManager.characters.size() if choice == GameManager.RANDOM_CHARACTER else choice

# --- clicks ----------------------------------------------------------------

# A tile in the grid was clicked: give that character to the active panel.
func _on_tile_pressed(tile_index: int) -> void:
	if _confirmed:
		return # already locked in (online) - ignore clicks
	_set_choice(active_panel, _tile_to_choice(tile_index))
	_refresh()

# Click on the body of a panel. Local mode only (online has just your own
# panel to edit). Clicking an OFF CPU panel switches that CPU on.
func _on_panel_gui_input(event: InputEvent, panel_index: int) -> void:
	if _confirmed or _is_online:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if panel_index > 0:
			GameManager.cpu_slots[panel_index - 1]["enabled"] = true
		active_panel = panel_index
		_refresh()

# The ADD CPU / REMOVE button on a CPU panel.
func _on_panel_button_pressed(panel_index: int) -> void:
	var slot: Dictionary = GameManager.cpu_slots[panel_index - 1]
	slot["enabled"] = not slot["enabled"]
	if slot["enabled"]:
		active_panel = panel_index # newly added -> ready to pick its character
	elif active_panel == panel_index:
		active_panel = 0 # can't keep editing a CPU that's gone
	_refresh()

# --- drawing -----------------------------------------------------------------

# Redraws every panel from the current data (call after ANY change), then
# moves the cursor. This is the one place that turns data into pixels, so the
# click handlers above only ever change data and call this.
func _refresh() -> void:
	for i in panels.size():
		var p: Dictionary = panels[i]
		var on: bool = _panel_on(i)
		var choice: int = _get_choice(i) if i == 0 or not _is_online else 0
		var swatch: ColorRect = p["swatch"]
		var face: ColorRect = p["face"]
		var question: Label = p["question"]
		var name_label: Label = p["name"]
		var info: Label = p["info"]
		var style: StyleBoxFlat = p["style"]
		var root: PanelContainer = p["root"]

		face.visible = false
		question.visible = false
		if _is_online and i == 1:
			# The other player: don't reveal their pick before the match,
			# just whether they've confirmed yet.
			swatch.color = RANDOM_COLOR
			question.visible = true
			name_label.text = "OPPONENT"
			info.text = "Ready!" if _opponent_pick != -1 else "Choosing..."
		elif not on:
			swatch.color = OFF_COLOR
			name_label.text = "OFF"
			info.text = "Click to add a CPU"
		elif choice == GameManager.RANDOM_CHARACTER:
			swatch.color = RANDOM_COLOR
			question.visible = true
			name_label.text = "RANDOM"
			info.text = "Player 1" if i == 0 else "CPU %d" % i
		else:
			var data: Dictionary = GameManager.characters[choice]
			swatch.color = data["color"]
			face.color = data.get("face_color", Color.BLACK)
			face.visible = true
			name_label.text = data["name"].to_upper()
			info.text = "Player 1" if i == 0 else "CPU %d" % i
		if _is_online and i == 0:
			info.text = "You"

		# Active panel gets a thick white border; the rest a thin dark one.
		var is_active := (i == active_panel)
		style.set_border_width_all(6 if is_active else 2)
		style.border_color = Color.WHITE if is_active else Color(0, 0, 0, 0.6)
		root.modulate = Color(1, 1, 1, 1.0 if on else 0.5) # dim switched-off CPUs

		var button: Button = p["button"]
		if button != null:
			button.text = "REMOVE" if on else "ADD CPU"

	# Re-draw the little P1/P2... badges on the tiles: wipe them all, then
	# add one for every panel that's in the match and has picked that tile.
	for t in tiles:
		for old_tag in t.get_meta("tag_row").get_children():
			old_tag.queue_free()
	for i in panels.size():
		if _panel_on(i) and not (_is_online and i == 1):
			var tile_row: HBoxContainer = tiles[_choice_to_tile(_get_choice(i))].get_meta("tag_row")
			tile_row.add_child(_make_tag(i))

	_update_cursor()

# Puts the yellow outline box around the tile the ACTIVE panel has picked:
# 6px bigger on every side (the -6 offset and the +12 size). Hidden if the
# active panel isn't in the match or hasn't a tile to show.
func _update_cursor() -> void:
	if tiles.is_empty():
		return
	var btn := tiles[_choice_to_tile(_get_choice(active_panel))]
	cursor.visible = true
	cursor.global_position = btn.global_position - Vector2(6, 6)
	cursor.size = btn.size + Vector2(12, 12)

# --- confirm / online / back -----------------------------------------------

# CONFIRM button (connected in CharacterSelect.tscn). Saves your pick to
# GameManager, then goes a different direction per mode: local goes straight
# into the match (the CPUs were already set up on this screen), online sends
# the pick to the other player and waits.
func _on_confirm_pressed() -> void:
	if _confirmed:
		return
	var pick: int = _p1_choice
	if pick == GameManager.RANDOM_CHARACTER:
		pick = randi() % GameManager.characters.size() # roll it now so online sends a real character
	GameManager.player1_character = pick

	if _is_online:
		_confirmed = true
		_my_pick = pick
		cpu_hint.text = "Waiting for the other player to pick..."
		# The pick goes over the wire as the INDEX in the roster, so both
		# players need the same roster in the same order (same game version).
		NetworkManager.send({"type": "pick", "character": pick})
		_maybe_start_match()
	else:
		GameManager.selected_mode = GameManager.Mode.LOCAL
		get_tree().change_scene_to_file("res://scenes/Game.tscn")

# The other player's "pick" message arrives here (their copy of
# _on_confirm_pressed above sent it).
func _on_message_received(data: Dictionary) -> void:
	if data.get("type") == "pick":
		_opponent_pick = int(data.get("character", 0))
		_refresh() # flips their panel to "Ready!"
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
