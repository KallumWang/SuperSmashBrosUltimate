extends CanvasLayer
## Persistent autoloaded overlay for the "Screen KO" easter egg: when a
## fighter gets launched off the TOP blast line, there's a chance their
## face flattens comedically against the screen for a moment, Smash-style.

const WORDS := ["SPLAT!", "BONK!", "WHAM!", "YEOWCH!", "SMOOSH!", "OOF!"]

@onready var flash: ColorRect = $Flash
@onready var face_root: Control = $FaceRoot
@onready var blob: Panel = $FaceRoot/Blob
@onready var word_label: Label = $FaceRoot/WordLabel

func _ready() -> void:
	flash.modulate.a = 0.0
	face_root.modulate.a = 0.0
	face_root.scale = Vector2(1.0, 1.0)

func show_splat(color: Color) -> void:
	var style: StyleBoxFlat = blob.get_theme_stylebox("panel").duplicate()
	style.bg_color = color
	blob.add_theme_stylebox_override("panel", style)
	word_label.text = WORDS[randi() % WORDS.size()]
	word_label.modulate = color.lightened(0.3)

	face_root.modulate.a = 1.0
	face_root.scale = Vector2(1.6, 0.5)
	face_root.rotation = deg_to_rad(randf_range(-10.0, 10.0))
	flash.modulate.a = 0.8

	var tween := create_tween()
	tween.tween_property(flash, "modulate:a", 0.0, 0.25)
	tween.parallel().tween_property(face_root, "scale", Vector2(1.0, 1.0), 0.18) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_interval(0.35)
	tween.tween_property(face_root, "modulate:a", 0.0, 0.4)
