extends Control
## The SETTINGS screen (button on the title screen, added by start_screen.gd):
## music volume and key rebinding for both players. Like almanac.gd, the whole
## screen is built in code, so Settings.tscn is just an empty Control with this
## script on it. The real work lives in autoload/InputSetup.gd (rebind /
## reset_defaults / save) and scripts/music.gd (set_volume).
##
## To rebind: click a key button, then press the new key (Esc cancels). If that
## key was already used by another action of the same player, the two swap.

const BG_COLOR := Color(0.09, 0.1, 0.16)
const GOLD := Color(1.0, 0.85, 0.3)
const DIM := Color(0.7, 0.72, 0.8)

var _buttons: Dictionary = {} # action name ("p1_left") -> its Button
var _listening: String = "" # action waiting for a key press ("" = none)
var _hint: Label

func _ready() -> void:
	var bg := ColorRect.new()
	bg.color = BG_COLOR
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var page := VBoxContainer.new()
	page.set_anchors_preset(Control.PRESET_FULL_RECT)
	page.offset_left = 60
	page.offset_top = 20
	page.offset_right = -60
	page.offset_bottom = -20
	page.add_theme_constant_override("separation", 10)
	add_child(page)

	var title := Label.new()
	title.text = "SETTINGS"
	title.add_theme_font_size_override("font_size", 40)
	title.add_theme_color_override("font_color", GOLD)
	page.add_child(title)

	# --- music volume
	var audio := HBoxContainer.new()
	audio.add_theme_constant_override("separation", 14)
	page.add_child(audio)
	var vol_label := Label.new()
	vol_label.text = "Music volume"
	vol_label.custom_minimum_size.x = 160
	audio.add_child(vol_label)
	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.05
	slider.value = Music.volume
	slider.custom_minimum_size = Vector2(300, 24)
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	audio.add_child(slider)
	var mute := CheckBox.new()
	mute.text = "Mute"
	mute.button_pressed = Music.muted
	audio.add_child(mute)
	slider.value_changed.connect(func(v): Music.set_volume(v, mute.button_pressed))
	mute.toggled.connect(func(on): Music.set_volume(slider.value, on))

	# --- key table
	var heading := Label.new()
	heading.text = "CONTROLS  (click a key, then press the new one - Esc cancels)"
	heading.add_theme_color_override("font_color", GOLD)
	page.add_child(heading)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	page.add_child(scroll)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 24)
	grid.add_theme_constant_override("v_separation", 6)
	scroll.add_child(grid)
	for h in ["ACTION", "PLAYER 1", "PLAYER 2"]:
		var hl := Label.new()
		hl.text = h
		hl.add_theme_color_override("font_color", GOLD)
		hl.custom_minimum_size.x = 300 if h == "ACTION" else 170
		grid.add_child(hl)
	for entry in InputSetup.ACTIONS:
		var name_label := Label.new()
		name_label.text = entry[1]
		grid.add_child(name_label)
		for prefix in ["p1_", "p2_"]:
			var action: String = prefix + entry[0]
			var b := Button.new()
			b.custom_minimum_size = Vector2(170, 32)
			b.pressed.connect(_start_listening.bind(action))
			grid.add_child(b)
			_buttons[action] = b

	_hint = Label.new()
	_hint.add_theme_color_override("font_color", DIM)
	_hint.text = "Online matches use the Player 1 keys. Emote wheel: hold its key and scroll the mouse wheel, release to send."
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	page.add_child(_hint)

	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 12)
	page.add_child(bottom)
	var reset := Button.new()
	reset.text = "RESET TO DEFAULTS"
	reset.custom_minimum_size = Vector2(220, 40)
	reset.pressed.connect(func():
		InputSetup.reset_defaults()
		_cancel_listening()
		_refresh())
	bottom.add_child(reset)
	var back := Button.new()
	back.text = "BACK"
	back.custom_minimum_size = Vector2(160, 40)
	back.pressed.connect(func(): Scenes.go(get_tree(), "res://scenes/StartScreen.tscn"))
	bottom.add_child(back)
	_refresh()

func _refresh() -> void:
	for action in _buttons:
		var b: Button = _buttons[action]
		b.text = "press a key..." if action == _listening else OS.get_keycode_string(InputSetup.get_key(action) as Key)

func _start_listening(action: String) -> void:
	_listening = action
	_refresh()

func _cancel_listening() -> void:
	_listening = ""

# Grabs the next key press while a button is waiting for one.
func _input(event: InputEvent) -> void:
	if _listening == "" or not (event is InputEventKey) or not event.pressed or event.echo:
		return
	get_viewport().set_input_as_handled()
	if event.physical_keycode != KEY_ESCAPE:
		InputSetup.rebind(_listening, event.physical_keycode)
	_listening = ""
	_refresh()
