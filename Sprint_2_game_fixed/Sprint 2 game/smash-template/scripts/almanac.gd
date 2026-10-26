extends Control
## The ALMANAC: a reference book reachable from the main menu (the ALMANAC
## button that start_screen.gd adds under START). Two tabs:
##   CHARACTERS - pick anyone from the list to see their bio, stats and every
##                move (normals + the four specials) with real numbers.
##   CONTROLS   - the keys, how each attack is performed, and how to play.
##
## Nothing here is hand-written per character or per key: the characters tab
## reads GameManager.characters (built from scripts/character_roster.gd), and
## the controls tab reads the keys back out of Godot's InputMap (registered in
## autoload/InputSetup.gd). So when you add a character, retune a move, or
## rebind a key, the Almanac updates by itself. The whole screen is built in
## code, like cpu_setup.gd's rows, so Almanac.tscn is just an empty Control
## with this script on it.

const BG_COLOR := Color(0.09, 0.1, 0.16) # same dark blue as the Start and Mode Select screens
const GOLD := Color(1.0, 0.85, 0.3) # headings and tag text
const SPECIAL_TEXT := Color(1.0, 0.95, 0.7) # the four special rows are tinted so they stand out from normals
const DIM := Color(0.7, 0.72, 0.8) # secondary text (the "how to read" notes)

# Every move a character can have, in the order they're listed: the key in
# stats["attacks"] and the name shown in the Almanac's first column.
const MOVE_ROWS := [
	["neutral", "Neutral"], ["up", "Up"], ["down", "Down"], ["back", "Back"],
	["special_neutral", "Neutral Special"], ["special_side", "Side Special"],
	["special_up", "Up Special"], ["special_down", "Down Special"],
]

# Columns of the moves table: header text and minimum width in pixels.
const MOVE_COLUMNS := [
	["MOVE", 130], ["NAME", 170], ["DAMAGE", 75], ["RANGE", 70],
	["STARTUP", 80], ["COOLDOWN", 90], ["HITS", 55], ["LAUNCH", 75],
]

# The stat bars: label, a function of the character's stats that gives a
# 0..1 fill amount, and a function that gives the text next to the bar. The
# divisors (420, 700, 2.0 ...) are just "what counts as a full bar" - roughly
# the best value in the current roster.
const STAT_BARS := ["Speed", "Jump power", "Weight", "Jumps", "Fall speed"]

var detail: VBoxContainer # the right-hand pane that gets rebuilt every time you pick someone
var char_group := ButtonGroup.new() # makes the list buttons behave like radio buttons (one highlighted at a time)

func _ready() -> void:
	var bg := ColorRect.new()
	bg.color = BG_COLOR
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	# Everything else lives in one VBox with a margin around the screen edge:
	# title on top, the tabs in the middle (they take all the spare height),
	# BACK button along the bottom.
	var page := VBoxContainer.new()
	page.set_anchors_preset(Control.PRESET_FULL_RECT)
	page.offset_left = 40
	page.offset_top = 20
	page.offset_right = -40
	page.offset_bottom = -20
	page.add_theme_constant_override("separation", 10)
	add_child(page)

	var title := Label.new()
	title.text = "ALMANAC"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 30)
	page.add_child(title)

	# A TabContainer shows one child at a time and uses each child's NODE NAME
	# as its tab title - that's why the tabs below set .name before being added.
	var tabs := TabContainer.new()
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page.add_child(tabs)
	var chars_tab := _build_characters_tab()
	chars_tab.name = "CHARACTERS"
	tabs.add_child(chars_tab)
	var controls_tab := _build_controls_tab()
	controls_tab.name = "CONTROLS"
	tabs.add_child(controls_tab)

	var back := Button.new()
	back.text = "BACK"
	back.custom_minimum_size = Vector2(140, 36)
	back.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	back.pressed.connect(_on_back_pressed)
	page.add_child(back)

	_select_character(0)

func _on_back_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/StartScreen.tscn")

# =====================================================================
# CHARACTERS TAB
# =====================================================================

# Left: a scrolling list with one button per character. Right: the detail pane.
func _build_characters_tab() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)

	var list_scroll := ScrollContainer.new()
	list_scroll.custom_minimum_size = Vector2(240, 0)
	list_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	row.add_child(list_scroll)

	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list_scroll.add_child(list)

	for i in GameManager.characters.size():
		var data: Dictionary = GameManager.characters[i]
		var btn := Button.new()
		btn.text = data["name"]
		btn.icon = _color_icon(data["color"]) # little square in the character's color
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.toggle_mode = true
		btn.button_group = char_group # only one can be "pressed" at a time
		btn.pressed.connect(_select_character.bind(i)) # .bind(i) = which character this button is
		list.add_child(btn)

	var detail_scroll := ScrollContainer.new()
	detail_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	row.add_child(detail_scroll)

	detail = VBoxContainer.new()
	detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail.add_theme_constant_override("separation", 10)
	detail_scroll.add_child(detail)
	return row

# Rebuilds the whole right-hand pane for character `index`. Cheap enough
# (a few dozen labels) that wiping and rebuilding is simpler than updating.
func _select_character(index: int) -> void:
	for child in detail.get_children():
		detail.remove_child(child)
		child.queue_free()
	# Highlight the matching list button (needed on first open, when nobody clicked yet).
	var buttons := char_group.get_buttons()
	if index < buttons.size():
		buttons[index].set_pressed_no_signal(true)

	var data: Dictionary = GameManager.characters[index]
	var ui_color: Color = data.get("ui_color", data["color"])

	# --- header: swatch with the face, then name / bio / tags
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 16)
	detail.add_child(header)

	var swatch := ColorRect.new()
	swatch.color = data["color"]
	swatch.custom_minimum_size = Vector2(84, 84)
	header.add_child(swatch)
	var face := ColorRect.new()
	face.color = data.get("face_color", Color.BLACK)
	face.size = Vector2(22, 22)
	face.position = Vector2(31, 31)
	swatch.add_child(face)

	var texts := VBoxContainer.new()
	texts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(texts)
	var name_label := Label.new()
	name_label.text = data["name"].to_upper()
	name_label.add_theme_font_size_override("font_size", 28)
	name_label.add_theme_color_override("font_color", ui_color) # ui_color so Guy Black isn't invisible
	texts.add_child(name_label)
	var bio := Label.new()
	bio.text = data.get("bio", "")
	bio.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	bio.custom_minimum_size = Vector2(400, 0) # autowrap needs a width to wrap to
	texts.add_child(bio)
	var tags := Label.new()
	tags.text = _tags_for(data)
	tags.add_theme_color_override("font_color", GOLD)
	texts.add_child(tags)

	# --- stat bars
	detail.add_child(_heading("STATS"))
	var stats_grid := GridContainer.new()
	stats_grid.columns = 3
	stats_grid.add_theme_constant_override("h_separation", 14)
	stats_grid.add_theme_constant_override("v_separation", 6)
	detail.add_child(stats_grid)
	for stat in STAT_BARS:
		var info := _stat_info(stat, data)
		var name := Label.new()
		name.text = stat
		name.custom_minimum_size = Vector2(110, 0)
		stats_grid.add_child(name)
		stats_grid.add_child(_make_bar(info[0], ui_color))
		var value := Label.new()
		value.text = info[1]
		stats_grid.add_child(value)

	# --- moves table
	detail.add_child(_heading("MOVES"))
	var moves := GridContainer.new()
	moves.columns = MOVE_COLUMNS.size()
	moves.add_theme_constant_override("h_separation", 10)
	moves.add_theme_constant_override("v_separation", 4)
	detail.add_child(moves)
	for col in MOVE_COLUMNS:
		moves.add_child(_cell(col[0], col[1], GOLD))
	for entry in MOVE_ROWS:
		var key: String = entry[0]
		var atk: Dictionary = data["attacks"].get(key, {})
		var is_special: bool = key.begins_with("special_")
		var color := SPECIAL_TEXT if is_special else Color.WHITE
		var cells := [
			entry[1],
			atk.get("name", entry[1] + " Attack"), # normals have no custom name, so show e.g. "Up Attack"
			"%d" % int(atk.get("damage", 0)),
			"%d" % int(atk.get("range", 0)),
			"%.2fs" % float(atk.get("startup", 0)),
			"%.2fs" % float(atk.get("cooldown", 0)),
			"%d" % int(atk.get("hits", 1)),
			"%d°" % int(atk.get("angle", 0)),
		]
		for c in cells.size():
			moves.add_child(_cell(cells[c], MOVE_COLUMNS[c][1], color))

	var legend := Label.new()
	legend.text = "DAMAGE = total % added (split across HITS). RANGE = how far in front the hit reaches. STARTUP = wind-up before it lands. COOLDOWN = wait before your next attack. LAUNCH = knockback angle (0 = sideways, 90 = straight up)."
	legend.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	legend.custom_minimum_size = Vector2(700, 0)
	legend.add_theme_color_override("font_color", DIM)
	detail.add_child(legend)

# A few quick one-word labels worked out from the numbers, e.g. "FAST - HEAVY -
# LONG REACH". Purely for skimming; none of this affects gameplay.
func _tags_for(data: Dictionary) -> String:
	var tags: Array = []
	var speed: float = data.get("speed", 300.0)
	var weight: float = data.get("weight", 1.0)
	if speed >= 350.0: tags.append("FAST")
	elif speed <= 270.0: tags.append("SLOW")
	if weight >= 1.3: tags.append("HEAVY")
	elif weight <= 0.85: tags.append("LIGHT")
	if data.get("gravity_scale", 1.0) <= 0.8: tags.append("FLOATY")
	var jumps: int = 1 + int(data.get("extra_jumps", 1))
	if jumps >= 4: tags.append("%d JUMPS" % jumps)
	elif jumps == 1: tags.append("ONE JUMP")
	var longest := 0.0
	var multi := false
	for key in data["attacks"]:
		var atk: Dictionary = data["attacks"][key]
		longest = maxf(longest, float(atk.get("range", 0)))
		if int(atk.get("hits", 1)) >= 3:
			multi = true
	if longest >= 90.0: tags.append("LONG REACH")
	if multi: tags.append("COMBO MOVES")
	return " • ".join(tags) if not tags.is_empty() else "ALL-ROUNDER"

# Returns [fill 0..1, text] for one stat bar.
func _stat_info(stat: String, data: Dictionary) -> Array:
	match stat:
		"Speed":
			var v: float = data.get("speed", 300.0)
			return [v / 420.0, "%d" % int(v)]
		"Jump power":
			var v: float = absf(data.get("jump_velocity", -600.0))
			return [v / 700.0, "%d" % int(v)]
		"Weight":
			var v: float = data.get("weight", 1.0)
			return [v / 2.0, "%.2f" % v]
		"Jumps":
			var n: int = 1 + int(data.get("extra_jumps", 1)) # counts the ground jump too, like player.gd's max_jumps
			return [n / 4.0, "%d total" % n]
		_: # "Fall speed" - low = floaty
			var v: float = data.get("gravity_scale", 1.0)
			return [v / 1.4, "%.2f" % v]

# A horizontal bar filled to `ratio` in the character's color.
func _make_bar(ratio: float, color: Color) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.min_value = 0.0
	bar.max_value = 1.0
	bar.value = clampf(ratio, 0.0, 1.0)
	bar.show_percentage = false # we print our own number next to it
	bar.custom_minimum_size = Vector2(260, 16)
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var fill := StyleBoxFlat.new()
	fill.bg_color = color
	bar.add_theme_stylebox_override("fill", fill)
	return bar

# =====================================================================
# CONTROLS TAB
# =====================================================================

func _build_controls_tab() -> Control:
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var page := VBoxContainer.new()
	page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	page.add_theme_constant_override("separation", 10)
	scroll.add_child(page)

	# --- the key table (keys are read from the InputMap, never typed here)
	page.add_child(_heading("KEYS"))
	var keys := GridContainer.new()
	keys.columns = 3
	keys.add_theme_constant_override("h_separation", 30)
	keys.add_theme_constant_override("v_separation", 6)
	page.add_child(keys)
	for h in ["ACTION", "PLAYER 1", "PLAYER 2"]:
		keys.add_child(_cell(h, 230, GOLD))
	var key_rows := [
		["Move left / right", _pair("left", "right", "p1_"), _pair("left", "right", "p2_")],
		["Jump (press again in the air to double / triple jump)", _key("p1_jump"), _key("p2_jump")],
		["Down (hold it for down attacks)", _key("p1_down"), _key("p2_down")],
		["Attack", _key("p1_attack"), _key("p2_attack")],
		["Special", _key("p1_special"), _key("p2_special")],
	]
	for r in key_rows:
		var action := _cell(r[0], 230, Color.WHITE)
		action.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		keys.add_child(action)
		keys.add_child(_cell(r[1], 230, Color.WHITE))
		keys.add_child(_cell(r[2], 230, Color.WHITE))
	page.add_child(_note("Online matches: both players use the Player 1 keys on their own keyboards. The Player 2 keys are reserved for local two-player."))

	# --- how to perform each move
	var atk := _key("p1_attack")
	var spc := _key("p1_special")
	var jmp := _key("p1_jump")
	var dwn := _key("p1_down")
	page.add_child(_heading("ATTACKS (Player 1 keys shown)"))
	var combos := GridContainer.new()
	combos.columns = 2
	combos.add_theme_constant_override("h_separation", 30)
	combos.add_theme_constant_override("v_separation", 6)
	page.add_child(combos)
	var combo_rows := [
		["Neutral", "Tap %s" % atk],
		["Up", "Hold %s + tap %s" % [jmp, atk]],
		["Down", "Hold %s + tap %s" % [dwn, atk]],
		["Back (pivot strike)", "Tap the opposite direction at the same moment as %s - hits behind you" % atk],
		["Neutral Special", "Tap %s" % spc],
		["Side Special", "Hold left or right + tap %s" % spc],
		["Up Special", "Hold %s + tap %s" % [jmp, spc]],
		["Down Special", "Hold %s + tap %s" % [dwn, spc]],
	]
	for r in combo_rows:
		var special: bool = r[0].contains("Special")
		combos.add_child(_cell(r[0], 230, SPECIAL_TEXT if special else Color.WHITE))
		var how := _cell(r[1], 600, SPECIAL_TEXT if special else Color.WHITE)
		how.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		combos.add_child(how)

	# --- the basics
	page.add_child(_heading("HOW TO PLAY"))
	var tips := [
		"Every hit adds to your damage %. The higher your %, the farther you get launched by the next hit.",
		"Heavy fighters (see WEIGHT in the Characters tab) fly less far; light ones fly farther.",
		"Get launched past the edge of the screen - sides, top or bottom - and you lose a stock. Everyone starts with 3.",
		"Specials glow while they wind up and burst out as a big star, so you can see them coming (and dodge them).",
		"Moves with several hits split their damage between the hits, and each hit launches on its own.",
		"On Character Select, click a player panel, then click a character. Click an empty CPU panel to add a CPU, REMOVE to drop one, and the ? tile picks a random fighter.",
		"Press F9 any time to switch the old-film filter on or off.",
	]
	for t in tips:
		page.add_child(_note("•  " + t, Color.WHITE))
	return scroll

# =====================================================================
# small helpers
# =====================================================================

# Name of the first keyboard key bound to an action, e.g. "G" or "Slash".
# physical_keycode matches how InputSetup.gd registered them.
func _key(action: String) -> String:
	if not InputMap.has_action(action):
		return "-"
	for ev in InputMap.action_get_events(action):
		if ev is InputEventKey:
			return OS.get_keycode_string(ev.physical_keycode)
	return "-"

# "A / D" style text for two actions with the same prefix.
func _pair(a: String, b: String, prefix: String) -> String:
	return "%s / %s" % [_key(prefix + a), _key(prefix + b)]

# A gold section title.
func _heading(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 20)
	label.add_theme_color_override("font_color", GOLD)
	return label

# One table cell: a label with a minimum width so columns line up.
func _cell(text: String, min_width: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.custom_minimum_size = Vector2(min_width, 0)
	label.add_theme_color_override("font_color", color)
	return label

# A wrapped paragraph (autowrap needs a width, so it gets a fixed minimum one).
func _note(text: String, color: Color = DIM) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size = Vector2(800, 0)
	label.add_theme_color_override("font_color", color)
	return label

# A small solid-color square used as the icon next to each name in the list.
func _color_icon(color: Color) -> ImageTexture:
	var img := Image.create_empty(16, 16, false, Image.FORMAT_RGBA8)
	img.fill(color)
	return ImageTexture.create_from_image(img)
