class_name SpriteGen
extends RefCounted

## expects.

const W := 40
const H := 64

static func build(color: Color) -> SpriteFrames:
	var frames := SpriteFrames.new()

	_add_anim(frames, "idle", [
		_make_frame(color, 0, 0),
		_make_frame(color, 0, -3),
	], 4.0, true)

	_add_anim(frames, "run", [
		_make_frame(color, -6, 0),
		_make_frame(color, 6, 0),
	], 9.0, true)

	_add_anim(frames, "jump", [
		_make_frame(color, 0, -6),
	], 5.0, true)

	_add_anim(frames, "attack", [
		_make_frame(color, 12, 0),
		_make_frame(color, 5, 0),
	], 16.0, false)

	_add_anim(frames, "hurt", [
		_make_frame(color.lightened(0.45), 0, 3),
	], 6.0, false)

	return frames

static func _add_anim(frames: SpriteFrames, anim_name: String, textures: Array, fps: float, loop: bool) -> void:
	frames.add_animation(anim_name)
	frames.set_animation_speed(anim_name, fps)
	frames.set_animation_loop(anim_name, loop)
	for t in textures:
		frames.add_frame(anim_name, t)

static func _make_frame(color: Color, lean_x: float, lean_y: float) -> ImageTexture:
	var img := Image.create_empty(W, H, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))

	# body
	_fill(img, Vector2i(4, 6), Vector2i(W - 8, H - 10), color)
	# face marker, nudged by the lean so poses read as slightly different
	var face_x: int = clampi(int(W / 2.0 - 5 + lean_x * 0.3), 2, W - 12)
	var face_y: int = clampi(int(12 + lean_y * 0.3), 2, H - 20)
	_fill(img, Vector2i(face_x, face_y), Vector2i(10, 10), Color(0, 0, 0, 1))
	# feet
	_fill(img, Vector2i(int(6 + lean_x * 0.5), H - 8), Vector2i(10, 8), color.darkened(0.25))
	_fill(img, Vector2i(int(W - 16 - lean_x * 0.5), H - 8), Vector2i(10, 8), color.darkened(0.25))

	return ImageTexture.create_from_image(img)

static func _fill(img: Image, pos: Vector2i, size: Vector2i, color: Color) -> void:
	var rect := Rect2i(pos, size).intersection(Rect2i(Vector2i.ZERO, img.get_size()))
	img.fill_rect(rect, color)
