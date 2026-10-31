extends Node
## Registers the input actions used by both players at startup, and loads
## any key changes the player made on the SETTINGS screen.
## An action here is just a name like "p1_left" that player.gd reads with
## Input.get_axis / is_action_pressed(input_prefix + "left"). The name is
## built from SmashPlayer.input_prefix ("p1_" or "p2_") + the suffixes in
## ACTIONS below, so every suffix exists for both prefixes.
##
## Rebinding: scripts/settings.gd calls rebind() / reset_defaults(); the
## choices are saved to user://settings.cfg and re-applied here on the next
## launch. (Everything is keyboard: physical_keycode = the key's POSITION, so
## WASD stays under the left hand on AZERTY and other layouts too.)

# Every rebindable action (suffix, label shown on the Settings screen).
const ACTIONS := [
	["left", "Move left"], ["right", "Move right"], ["jump", "Jump / up"], ["down", "Down"],
	["attack", "Attack"], ["special", "Special"], ["shield", "Shield / dodge"],
	["taunt", "Taunt (dance)"], ["emote", "Emote wheel (hold, scroll)"],
]
# Player 1: WASD + F (this is also what BOTH players use online).
# Player 2: arrow keys + Enter. Nothing spawns with the "p2_" prefix right
# now (game.gd only uses "p1_" and CPU prefixes) - it's set up for when
# local 2-player gets wired in (see the README's "Extending it further").
const DEFAULTS := {
	"p1_left": KEY_A, "p1_right": KEY_D, "p1_jump": KEY_W, "p1_down": KEY_S,
	"p1_attack": KEY_F, "p1_special": KEY_G, "p1_shield": KEY_SHIFT,
	"p1_taunt": KEY_T, "p1_emote": KEY_E,
	"p2_left": KEY_LEFT, "p2_right": KEY_RIGHT, "p2_jump": KEY_UP, "p2_down": KEY_DOWN,
	"p2_attack": KEY_ENTER, "p2_special": KEY_SLASH, "p2_shield": KEY_PERIOD,
	"p2_taunt": KEY_COMMA, "p2_emote": KEY_M,
}
const SETTINGS_PATH := "user://settings.cfg"

func _ready() -> void:
	var saved := ConfigFile.new()
	var have_file := saved.load(SETTINGS_PATH) == OK
	for action in DEFAULTS:
		var code: int = DEFAULTS[action]
		if have_file:
			code = int(saved.get_value("keys", action, code)) # a saved choice wins over the default
		_set_key(action, code)
	# Music: load the saved volume, then start the menu track. (Music is a
	# plain script, not an autoload - see scripts/music.gd.)
	Music.load_settings()
	Music.play_for(get_tree(), get_tree().current_scene.scene_file_path if get_tree().current_scene else "")

# Replaces whatever key `action` had with `keycode` (creating the action if needed).
func _set_key(action: String, keycode: int) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	InputMap.action_erase_events(action)
	var ev := InputEventKey.new()
	ev.physical_keycode = keycode as Key
	InputMap.action_add_event(action, ev)

## The key (physical keycode) an action is currently bound to.
func get_key(action: String) -> int:
	for ev in InputMap.action_get_events(action):
		if ev is InputEventKey:
			return ev.physical_keycode
	return KEY_NONE

## Binds `action` to `keycode`. If another action of the SAME player already
## uses that key, the two swap keys (so you never end up with a dead control).
func rebind(action: String, keycode: int) -> void:
	var prefix := action.substr(0, 3) # "p1_" / "p2_"
	var old := get_key(action)
	for entry in ACTIONS:
		var other: String = prefix + entry[0]
		if other != action and get_key(other) == keycode:
			_set_key(other, old)
	_set_key(action, keycode)
	save()

func reset_defaults() -> void:
	for action in DEFAULTS:
		_set_key(action, DEFAULTS[action])
	save()

func save() -> void:
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH) # keep the [audio] section etc.
	for action in DEFAULTS:
		cfg.set_value("keys", action, get_key(action))
	cfg.save(SETTINGS_PATH)
