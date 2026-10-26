extends CanvasLayer
## Persistent autoloaded overlay for the "Screen KO" easter egg: when a
## fighter gets launched off the TOP blast line, there's a chance their
## face flattens comedically against the screen for a moment, Smash-style.
## Triggered from SmashPlayer._on_ko() in player.gd (35% chance, see
## SCREEN_SPLAT_CHANCE there) via ScreenFX.show_splat(color).

# One is picked at random each splat (see show_splat).
const WORDS := ["SPLAT!", "BONK!", "WHAM!", "YEOWCH!", "SMOOSH!", "OOF!"]

# Node paths into ScreenFX.tscn: Flash is the full-screen white blink,
# FaceRoot groups the blob + word so they can be scaled/faded together,
# Blob is the rounded colored face, WordLabel is the onomatopoeia text.
@onready var flash: ColorRect = $Flash
@onready var face_root: Control = $FaceRoot
@onready var blob: Panel = $FaceRoot/Blob
@onready var word_label: Label = $FaceRoot/WordLabel

func _ready() -> void:
	# Start fully transparent so nothing shows until the first splat.
	flash.modulate.a = 0.0
	face_root.modulate.a = 0.0
	face_root.scale = Vector2(1.0, 1.0)

# `color` is the KO'd fighter's color, so the blob matches who got launched.
func show_splat(color: Color) -> void:
	# Duplicate the blob's StyleBox before recoloring it - otherwise we'd
	# be editing the one shared resource in the scene file, and the change
	# would stick around for every later splat too.
	var style: StyleBoxFlat = blob.get_theme_stylebox("panel").duplicate()
	style.bg_color = color
	blob.add_theme_stylebox_override("panel", style)
	word_label.text = WORDS[randi() % WORDS.size()]
	word_label.modulate = color.lightened(0.3)

	# Snap to the "impact" look instantly: fully visible, squashed wide and
	# flat (scale 1.6 x 0.5), slightly tilted, with a bright flash...
	face_root.modulate.a = 1.0
	face_root.scale = Vector2(1.6, 0.5)
	face_root.rotation = deg_to_rad(randf_range(-10.0, 10.0))
	flash.modulate.a = 0.8

	# ...then ease back out. The tween runs steps in order unless one says
	# .parallel(): fade the flash (0.25s) while bouncing the face back to
	# normal size (0.18s, TRANS_BACK gives it the little overshoot), hold
	# for 0.35s, then fade the face away over 0.4s.
	var tween := create_tween()
	tween.tween_property(flash, "modulate:a", 0.0, 0.25)
	tween.parallel().tween_property(face_root, "scale", Vector2(1.0, 1.0), 0.18) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_interval(0.35)
	tween.tween_property(face_root, "modulate:a", 0.0, 0.4)
