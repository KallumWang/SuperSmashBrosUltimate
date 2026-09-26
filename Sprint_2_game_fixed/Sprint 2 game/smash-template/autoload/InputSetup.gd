extends Node
## Registers the input actions used by both players at startup.
## Doing this in code keeps the project.godot file simple and avoids
## hand-authored input map resources going stale.

func _ready() -> void:
	_add_action("p1_left", KEY_A)
	_add_action("p1_right", KEY_D)
	_add_action("p1_jump", KEY_W)
	_add_action("p1_down", KEY_S)
	_add_action("p1_attack", KEY_F)

	_add_action("p2_left", KEY_LEFT)
	_add_action("p2_right", KEY_RIGHT)
	_add_action("p2_jump", KEY_UP)
	_add_action("p2_down", KEY_DOWN)
	_add_action("p2_attack", KEY_ENTER)

func _add_action(action_name: String, keycode: Key) -> void:
	if InputMap.has_action(action_name):
		return
	InputMap.add_action(action_name)
	var ev := InputEventKey.new()
	ev.physical_keycode = keycode
	InputMap.action_add_event(action_name, ev)
