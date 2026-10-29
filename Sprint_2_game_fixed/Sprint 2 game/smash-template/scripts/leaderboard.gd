extends Control
## The global LEADERBOARD screen (LEADERBOARD button on the main menu, added
## by start_screen.gd). It downloads the list from the relay
## (GET /leaderboard - see relay_server/src/worker.js) and shows every player's
## wins, games played and win %. Only ONLINE matches count, and the relay
## records them itself, so nobody can type in fake numbers from the game.
##
## The three sort buttons re-sort the list the game already downloaded (no
## new request). Like almanac.gd, the whole screen is built in code, so
## Leaderboard.tscn is just an empty Control with this script on it.

const BG_COLOR := Color(0.09, 0.1, 0.16) # same dark blue as the other menu screens
const GOLD := Color(1.0, 0.85, 0.3) # headings, and YOUR row
const DIM := Color(0.7, 0.72, 0.8)
# Win % is only meaningful after a few games (1 win from 1 game = 100%),
# so players below this many games are listed after everyone who qualifies.
const MIN_GAMES_FOR_PERCENT := 3
const SORT_MODES := ["WIN %", "WINS", "GAMES"]

var rows: Array = [] # what the relay sent: [{name, games, wins}, ...]
var sort_mode: int = 0 # index into SORT_MODES
var status: Label
var table: GridContainer
var sort_buttons: Array[Button] = []
var http: HTTPRequest

func _ready() -> void:
	var bg := ColorRect.new()
	bg.color = BG_COLOR
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var page := VBoxContainer.new()
	page.set_anchors_preset(Control.PRESET_FULL_RECT)
	page.offset_left = 40
	page.offset_top = 20
	page.offset_right = -40
	page.offset_bottom = -20
	page.add_theme_constant_override("separation", 10)
	add_child(page)

	var title := Label.new()
	title.text = "LEADERBOARD"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 30)
	page.add_child(title)

	# Sort buttons: a row of toggle buttons where only one is "on" at a time.
	var sort_row := HBoxContainer.new()
	sort_row.alignment = BoxContainer.ALIGNMENT_CENTER
	sort_row.add_theme_constant_override("separation", 8)
	page.add_child(sort_row)
	var group := ButtonGroup.new()
	for i in SORT_MODES.size():
		var b := Button.new()
		b.text = "Sort: " + SORT_MODES[i]
		b.toggle_mode = true
		b.button_group = group
		b.button_pressed = (i == sort_mode)
		b.pressed.connect(_on_sort_pressed.bind(i))
		sort_row.add_child(b)
		sort_buttons.append(b)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	page.add_child(scroll)
	table = GridContainer.new()
	table.columns = 5
	table.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	table.add_theme_constant_override("h_separation", 20)
	table.add_theme_constant_override("v_separation", 6)
	scroll.add_child(table)

	status = Label.new()
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status.add_theme_color_override("font_color", DIM)
	page.add_child(status)

	var back := Button.new()
	back.text = "BACK"
	back.custom_minimum_size = Vector2(140, 36)
	back.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	back.pressed.connect(_on_back_pressed)
	page.add_child(back)

	_rebuild_table()
	_load()

func _on_back_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/StartScreen.tscn")

# Downloads the list. Needs the internet; the status line says what happened.
func _load() -> void:
	status.text = "Loading..."
	http = HTTPRequest.new()
	add_child(http)
	http.request_completed.connect(_on_loaded)
	if http.request(NetworkManager.http_base() + "/leaderboard") != OK:
		status.text = "Couldn't reach the leaderboard."

func _on_loaded(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	var parsed: Variant = JSON.parse_string(body.get_string_from_utf8())
	if result != HTTPRequest.RESULT_SUCCESS or code != 200 or typeof(parsed) != TYPE_ARRAY:
		status.text = "Couldn't reach the leaderboard. Check your internet and try again."
		return
	rows = parsed
	status.text = "No online matches have been recorded yet." if rows.is_empty() else "Only online matches count. Win %% needs %d+ games to rank." % MIN_GAMES_FOR_PERCENT
	_rebuild_table()

func _on_sort_pressed(mode: int) -> void:
	sort_mode = mode
	_rebuild_table()

func _win_percent(row: Dictionary) -> float:
	var games: int = int(row.get("games", 0))
	return 100.0 * int(row.get("wins", 0)) / games if games > 0 else 0.0

# Sorts a copy of rows by the current mode and redraws the grid.
func _rebuild_table() -> void:
	for child in table.get_children():
		table.remove_child(child)
		child.queue_free()
	for header in ["#", "PLAYER", "WINS", "GAMES", "WIN %"]:
		table.add_child(_cell(header, GOLD, header == "PLAYER"))

	var sorted: Array = rows.duplicate()
	sorted.sort_custom(_before)
	for i in sorted.size():
		var row: Dictionary = sorted[i]
		var mine: bool = NetworkManager.is_registered() and str(row.get("name", "")) == NetworkManager.player_name
		var color := GOLD if mine else Color.WHITE
		var games: int = int(row.get("games", 0))
		var pct := "%.0f%%" % _win_percent(row)
		if games < MIN_GAMES_FOR_PERCENT:
			pct += "*" # not ranked by % yet
		table.add_child(_cell(str(i + 1), color, false))
		table.add_child(_cell(str(row.get("name", "?")), color, true))
		table.add_child(_cell(str(int(row.get("wins", 0))), color, false))
		table.add_child(_cell(str(games), color, false))
		table.add_child(_cell(pct, color, false))

# Comparison for sort_custom: returns true if `a` should be listed above `b`.
func _before(a: Dictionary, b: Dictionary) -> bool:
	var ga: int = int(a.get("games", 0))
	var gb: int = int(b.get("games", 0))
	var wa: int = int(a.get("wins", 0))
	var wb: int = int(b.get("wins", 0))
	match sort_mode:
		0: # WIN %: players with enough games first, then by percent, then by games
			var qa: bool = ga >= MIN_GAMES_FOR_PERCENT
			var qb: bool = gb >= MIN_GAMES_FOR_PERCENT
			if qa != qb:
				return qa
			var pa := _win_percent(a)
			var pb := _win_percent(b)
			if not is_equal_approx(pa, pb):
				return pa > pb
			return ga > gb
		1: # WINS
			if wa != wb:
				return wa > wb
			return ga < gb # same wins from fewer games ranks higher
		_: # GAMES
			if ga != gb:
				return ga > gb
			return wa > wb

func _cell(text: String, color: Color, expand: bool) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_color_override("font_color", color)
	if expand:
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	else:
		label.custom_minimum_size = Vector2(70, 0)
	return label
