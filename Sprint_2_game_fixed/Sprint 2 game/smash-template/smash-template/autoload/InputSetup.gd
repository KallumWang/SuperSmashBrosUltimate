extends Node
## Registers the input actions used by both players at startup.
## Doing this in code keeps the project.godot file simple and avoids
## hand-authored input map resources going stale.
## An action here is just a name like "p1_left" that player.gd reads with
## Input.get_axis / is_action_pressed(input_prefix + "left"). The name is
## built from SmashPlayer.input_prefix ("p1_" or "p2_") + left/right/jump/down/attack,
## so every action below needs all five suffixes for each prefix.

func _ready() -> void:
	# Player 1: WASD + F (this is also what BOTH players use online)
	_add_action("p1_left", KEY_A)
	_add_action("p1_right", KEY_D)
	_add_action("p1_jump", KEY_W)
	_add_action("p1_down", KEY_S)
	_add_action("p1_attack", KEY_F)
	_add_action("p1_special", KEY_G)
	_add_action("p1_shield", KEY_SHIFT) # hold to block; + left/right = roll, + down = spot dodge
	# Player 2: arrow keys + Enter. Nothing spawns with the "p2_" prefix right
	# now (game.gd only uses "p1_" and CPU prefixes) - it's set up for when
	# local 2-player gets wired in (see the README's "Extending it further").
	_add_action("p2_left", KEY_LEFT)
	_add_action("p2_right", KEY_RIGHT)
	_add_action("p2_jump", KEY_UP)
	_add_action("p2_down", KEY_DOWN)
	_add_action("p2_attack", KEY_ENTER)
	_add_action("p2_special", KEY_SLASH)
	_add_action("p2_shield", KEY_PERIOD)

func _add_action(action_name: String, keycode: Key) -> void:
	if InputMap.has_action(action_name):
		return # already exists (e.g. if you later add it in Project Settings) - don't double up
	InputMap.add_action(action_name)
	var ev := InputEventKey.new()
	# physical_keycode = the key's position on the keyboard, not what letter
	# it prints - so WASD stays under the left hand on AZERTY and other layouts too.
	ev.physical_keycode = keycode
	InputMap.action_add_event(action_name, ev)
