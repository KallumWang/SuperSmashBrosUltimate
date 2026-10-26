extends CanvasLayer
## Persistent full-screen overlay (autoloaded, so it survives every scene
## change) running the old-cartoon shader. Press F9 anytime to toggle it
## for an easy before/after comparison.
## The shader itself is shaders/cuphead_filter.gdshader; PostFX.tscn is just
## this layer with one full-screen ColorRect ("FilterRect") using that shader.

@onready var rect: ColorRect = $FilterRect

# _unhandled_input only sees keys nothing else (like a focused button) used.
# The checks: it's a key event, it's the press (not release), it isn't a
# held-key repeat (echo), and it's F9 - physical_keycode so it's the same
# key on any keyboard layout. Hiding the CanvasLayer hides the filter.
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_F9:
		visible = not visible

# For scripts that want to turn the filter on/off: PostFX.set_enabled(false)
func set_enabled(value: bool) -> void:
	visible = value

# Changes one shader uniform at runtime, e.g. PostFX.set_param("grain_amount", 0.3).
# The names are the `uniform` variables at the top of the .gdshader file.
func set_param(param_name: String, value) -> void:
	rect.material.set_shader_parameter(param_name, value)
