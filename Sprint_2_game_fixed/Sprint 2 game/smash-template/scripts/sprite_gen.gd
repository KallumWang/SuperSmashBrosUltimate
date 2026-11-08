class_name SpriteGen
extends RefCounted

## Builds the placeholder silly-cat animations entirely in code, so every
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
		_make_frame(color.lightened(0.45), face_color, 0, 3, true),
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

## Draws ONE frame of the silly cat into a fresh transparent image and turns it
## into a texture. A big white cat head (ears, black eyes, pink cheeks and nose,
## whiskers, tongue out) on a small body in the character's colour. lean_x/lean_y
## nudge the head, arms and feet so the poses read differently. `hurt` swaps the
## eyes for squeezed-shut dashes.
static func _make_frame(color: Color, _face_color: Color, lean_x: float, lean_y: float, hurt: bool = false) -> ImageTexture:
	var img := Image.create_empty(W, H, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0)) # start fully transparent so only the shapes below show

	var ink := Color(0.12, 0.1, 0.14)
	var fur := Color.WHITE.lerp(color, 0.15)
	var pink := Color(1.0, 0.62, 0.72)
	var ox: int = int(round(lean_x * 0.3))
	var oy: int = int(round(lean_y * 0.5))

	# body: white cat fur with the character's colour as a scarf and belly patch,
	# little arms, a curled tail and round white paws
	_outlined(img, Rect2i(30, 44, 8, 3), fur, ink) # tail out...
	_outlined(img, Rect2i(35, 36, 3, 11), fur, ink) # ...and curling up
	_outlined(img, Rect2i(11, 35, 18, 18), fur, ink)
	_fill(img, Vector2i(13, 44), Vector2i(14, 6), color) # belly patch
	_fill(img, Vector2i(10, 35), Vector2i(20, 4), color) # scarf
	_fill(img, Vector2i(10, 35), Vector2i(20, 1), color.lightened(0.25))
	_outlined(img, Rect2i(8 - int(lean_x * 0.2), 38, 4, 9), fur, ink)
	_outlined(img, Rect2i(28 + int(lean_x * 0.5), 38, 4, 9), fur, ink)
	# paws - white with a dark outline and a pink toe bean, shuffling opposite ways
	for fx in [int(6 + lean_x * 0.5), int(W - 16 - lean_x * 0.5)]:
		_outlined(img, Rect2i(fx, H - 8, 10, 7), fur, ink)
		_fill(img, Vector2i(fx + 3, H - 5), Vector2i(4, 2), pink)

	# ears (stair-stepped triangles) with pink insides
	for r in 9:
		_outlined_row(img, Rect2i(5 + ox, 0 + r + oy, 2 + r, 1), fur, ink)
		_outlined_row(img, Rect2i(34 - (1 + r) + ox, 0 + r + oy, 2 + r, 1), fur, ink)
	for r in range(3, 9):
		_fill(img, Vector2i(8 + ox, r + oy), Vector2i(maxi(1, r - 2), 1), pink)
		_fill(img, Vector2i(32 - maxi(1, r - 2) + ox, r + oy), Vector2i(maxi(1, r - 2), 1), pink)
	# head (two overlapping rects = rounded corners)
	for r in [Rect2i(5 + ox, 7 + oy, 30, 30), Rect2i(3 + ox, 9 + oy, 34, 26)]: # outlines first...
		_fill(img, r.position - Vector2i(1, 1), r.size + Vector2i(2, 2), ink)
	for r in [Rect2i(5 + ox, 7 + oy, 30, 30), Rect2i(3 + ox, 9 + oy, 34, 26)]: # ...then the fur over both
		_fill(img, r.position, r.size, fur)
	# eyes
	if hurt:
		_fill(img, Vector2i(10 + ox, 17 + oy), Vector2i(5, 2), ink)
		_fill(img, Vector2i(25 + ox, 17 + oy), Vector2i(5, 2), ink)
	else:
		_fill(img, Vector2i(11 + ox, 14 + oy), Vector2i(3, 6), ink)
		_fill(img, Vector2i(26 + ox, 14 + oy), Vector2i(3, 6), ink)
		_fill(img, Vector2i(11 + ox, 14 + oy), Vector2i(1, 1), Color.WHITE)
		_fill(img, Vector2i(26 + ox, 14 + oy), Vector2i(1, 1), Color.WHITE)
	# cheeks, nose, "w" mouth, tongue sticking out
	_fill(img, Vector2i(6 + ox, 22 + oy), Vector2i(5, 3), pink)
	_fill(img, Vector2i(29 + ox, 22 + oy), Vector2i(5, 3), pink)
	_fill(img, Vector2i(18 + ox, 22 + oy), Vector2i(4, 2), Color(0.95, 0.45, 0.55))
	for px in [[16, 25], [17, 26], [18, 26], [19, 25], [20, 25], [21, 26], [22, 26], [23, 25]]:
		_fill(img, Vector2i(int(px[0]) + ox, int(px[1]) + oy), Vector2i(1, 1), ink)
	_fill(img, Vector2i(20 + ox, 27 + oy), Vector2i(5, 5), pink)
	_fill(img, Vector2i(22 + ox, 27 + oy), Vector2i(1, 4), pink.darkened(0.25))
	_fill(img, Vector2i(20 + ox, 31 + oy), Vector2i(5, 1), pink.darkened(0.15))
	# whiskers
	for wy in [26, 29]:
		_fill(img, Vector2i(0 + ox, wy + oy), Vector2i(6, 1), ink)
		_fill(img, Vector2i(34 + ox, wy + oy), Vector2i(6, 1), ink)

	return ImageTexture.create_from_image(img)

## A rectangle with a 1px dark outline around it.
static func _outlined(img: Image, r: Rect2i, color: Color, ink: Color) -> void:
	_fill(img, r.position - Vector2i(1, 1), r.size + Vector2i(2, 2), ink)
	_fill(img, r.position, r.size, color)

## Like _outlined but for a 1px-tall ear row: the outline is only left/right so rows stack cleanly.
static func _outlined_row(img: Image, r: Rect2i, color: Color, ink: Color) -> void:
	_fill(img, r.position - Vector2i(1, 0), r.size + Vector2i(2, 0), ink)
	_fill(img, r.position, r.size, color)

## Fills a rectangle on the image. The intersection() line clips the
## rectangle to the image bounds first, so a shape that hangs off the edge
## (the feet can, at big leans) just gets cut off at the edge.
static func _fill(img: Image, pos: Vector2i, size: Vector2i, color: Color) -> void:
	var rect := Rect2i(pos, size).intersection(Rect2i(Vector2i.ZERO, img.get_size()))
	img.fill_rect(rect, color)
