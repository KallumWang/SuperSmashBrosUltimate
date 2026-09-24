extends CanvasLayer
## Persistent full-screen overlay (autoloaded, so it survives every scene
## change) running the old-cartoon shader. Press F9 anytime to toggle it
## for an easy before/after comparison.

@onready var rect: ColorRect = $FilterRect

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_F9:
		visible = not visible

func set_enabled(value: bool) -> void:
	visible = value

func set_param(param_name: String, value) -> void:
	rect.material.set_shader_parameter(param_name, value)
