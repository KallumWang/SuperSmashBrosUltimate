class_name SpriteGen
extends RefCounted

## Builds the placeholder "Godot guy" animations entirely in code, so every
## character has working sprites with no art files. player.gd's _ready()
## calls SpriteGen.build(color, face_color) once per fighter and hands the
## result to the $Sprite AnimatedSprite2D. Every function here is static, so
## nobody ever creates a SpriteGen object - it's just a toolbox.
## (To use real art instead, give the character a "frames" path in
## character_roster.gd - see the "frames" check in player.gd's _ready().)
## The animation names below (idle/run/jump/attack/hurt) are the exact
## names player.gd plays - _update_animation(), _do_attack() and take_hit()
## - so if you rename one here, rename it there too.

# Size in pixels of every generated frame. The Player scene's collision box
# is 36x64 (see Player.tscn), so the sprite is a bit wider (40) at the same height.
const W := 40
const H := 64

## face_color is the little square "face" - it defaults to black but
## character_roster.gd passes white for very dark characters, otherwise
## Guy Black's face would be invisible against his own body.
static func build(color: Color, face_color: Color = Color.BLACK) -> SpriteFrames:
	var frames := SpriteFrames.new()

	# Each animation is just a few frames of the same box nudged around by
	# "lean" amounts (lean_x, lean_y) - see _make_frame for what those do.
	# The last two arguments are speed in frames-per-second and whether it loops.
	_add_anim(frames, "idle", [
		_make_frame(color, face_color, 0, 0),
		_make_frame(color, face_color, 0, -3), # face bobs up a touch = breathing
	], 4.0, true)

	_add_anim(frames, "run", [
		_make_frame(color, face_color, -6, 0), # feet shuffle left...
		_make_frame(color, face_color, 6, 0),  # ...then right
	], 9.0, true)

	_add_anim(frames, "jump", [
		_make_frame(color, face_color, 0, -6),
	], 5.0, true)

	# Doesn't loop on purpose: player.gd's _do_attack() plays this once when
	# the swing starts, and _update_animation() skips itself while
	# is_attacking is true, so nothing overrides it mid-swing.
	_add_anim(frames, "attack", [
		_make_frame(color, face_color, 12, 0), # big lean into the swing
		_make_frame(color, face_color, 5, 0),  # settles back
	], 16.0, false)

	# Lightened body = a "got hit" flash. Played by player.gd's take_hit().
	_add_anim(frames, "hurt", [
		_make_frame(color.lightened(0.45), face_color, 0, 3),
	], 6.0, false)

	return frames

## Small helper so build() above stays readable: creates a named animation
## on the SpriteFrames and stuffs the given textures into it in order.
static func _add_anim(frames: SpriteFrames, anim_name: String, textures: Array, fps: float, loop: bool) -> void:
	frames.add_animation(anim_name)
	frames.set_animation_speed(anim_name, fps)
	frames.set_animation_loop(anim_name, loop)
	for t in textures:
		frames.add_frame(anim_name, t)

## Draws ONE frame of the guy into a fresh transparent image and turns it
## into a texture. lean_x/lean_y don't move the whole body - they only
## nudge the face and feet a little, which is enough to make the poses
## read as different without drawing any real art.
static func _make_frame(color: Color, face_color: Color, lean_x: float, lean_y: float) -> ImageTexture:
	var img := Image.create_empty(W, H, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0)) # start fully transparent so only the shapes below show

	# body
	_fill(img, Vector2i(4, 6), Vector2i(W - 8, H - 10), color)
	# face marker, nudged by the lean so poses read as slightly different
	# (clampi keeps it from being pushed off the edge of the image)
	var face_x: int = clampi(int(W / 2.0 - 5 + lean_x * 0.3), 2, W - 12)
	var face_y: int = clampi(int(12 + lean_y * 0.3), 2, H - 20)
	_fill(img, Vector2i(face_x, face_y), Vector2i(10, 10), face_color)
	# feet - a darker shade of the body color, and they slide in opposite
	# directions with lean_x so running looks like a little shuffle
	_fill(img, Vector2i(int(6 + lean_x * 0.5), H - 8), Vector2i(10, 8), color.darkened(0.25))
	_fill(img, Vector2i(int(W - 16 - lean_x * 0.5), H - 8), Vector2i(10, 8), color.darkened(0.25))

	return ImageTexture.create_from_image(img)

## Fills a rectangle on the image. The intersection() line clips the
## rectangle to the image bounds first, so a shape that hangs off the edge
## (the feet can, at big leans) just gets cut off at the edge.
static func _fill(img: Image, pos: Vector2i, size: Vector2i, color: Color) -> void:
	var rect := Rect2i(pos, size).intersection(Rect2i(Vector2i.ZERO, img.get_size()))
	img.fill_rect(rect, color)
