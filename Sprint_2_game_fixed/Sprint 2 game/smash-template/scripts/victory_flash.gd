extends Node
## VICTORY FLASHES - short cartoon cutscenes that play between the last KO and
## the podium (the results screen). game.gd makes one of these, calls play(),
## and shows the podium when it finishes. Press any key / click to skip.
##
## Two flashes so far (everything is drawn in code, no art files needed):
##   "slot" - only in a 4-fighter match. The winner runs up to a slot machine,
##            pulls the lever, and the three reels land on the three other
##            fighters - each with an X over their eyes.
##   "nah"  - works with 2+ fighters. Close-up of the 2nd-place fighter saying
##            "Nah, I'd win" in two speech bubbles, then a smash cut to the
##            winner standing over them - cut in half, cartoon style (clean
##            cut, no gore).
## With a draw there is no flash. With 4 fighters the game picks one of the two
## (online, every player's game picks the same one from the player names).
##
## To add another flash: write a func _my_flash(ranking) like _slot_machine,
## then add its name to _pick_kind() and the match in play().
##
## `ranking` = Array of infos, 1st place first: { label, name, color, stats }
## (built by game.gd - see _note_fighter there).

const MatchScreens := preload("res://scripts/match_screens.gd")

const SCREEN := Vector2(1280, 720)
const BAR_H := 64.0 # the black cinema bars at the top and bottom
const GOLD := Color(1.0, 0.85, 0.3)
const FACE_Y := 0.266 # where the eyes are on a fighter picture (fraction of its height)

var skipped: bool = false
var _age: float = 0.0
var _layer: CanvasLayer
var _stage: Control # every scene is built under this so the whole picture can shake
var _flash_rect: ColorRect
var _online: bool = false
var _names_hash: int = 0 # same on every machine online (from the sorted player names) - used for "random" choices that must match

# state for the running flash ("punch"); _process moves things while _run_active
var _run_active: bool = false
var _run_t: float = 0.0
var _run_dur: float = 2.7
var _run_winner: TextureRect
var _run_layer: Control # ghosts and dust live here, under the winner
var _run_x0: float = 0.0
var _run_x1: float = 0.0
var _run_ground: float = 560.0
var _scrollers: Array = [] # [{node, factor, wrap}] ground streaks that rush past
var _speed_lines: Array = []
var _ghost_timer: float = 0.0
var _scroll_speed: float = 0.0

func _process(delta: float) -> void:
	_age += delta
	if _run_active:
		_run_tick(delta)

# Any key or click skips (after a short grace period so a button the player was
# still mashing doesn't skip it by accident).
func _input(event: InputEvent) -> void:
	if _age < 0.5:
		return
	if (event is InputEventKey and event.pressed and not event.echo) \
			or (event is InputEventMouseButton and event.pressed):
		skipped = true

## Runs the whole flash; returns when it's over (or skipped).
func play(ranking: Array, online: bool) -> void:
	_layer = CanvasLayer.new()
	_layer.layer = 25 # above the game and its HUD, below the scene-fade layer
	add_child(_layer)
	_stage = Control.new()
	_stage.size = SCREEN
	_stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layer.add_child(_stage)
	# Cinema bars + skip hint stay put while the stage shakes.
	for y in [0.0, SCREEN.y - BAR_H]:
		var bar := ColorRect.new()
		bar.color = Color.BLACK
		bar.position = Vector2(0, y)
		bar.size = Vector2(SCREEN.x, BAR_H)
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_layer.add_child(bar)
	var hint := Label.new()
	hint.text = "press any key to skip"
	hint.add_theme_font_size_override("font_size", 14)
	hint.modulate = Color(1, 1, 1, 0.55)
	hint.position = Vector2(SCREEN.x - 210, SCREEN.y - 40)
	_layer.add_child(hint)
	_flash_rect = ColorRect.new()
	_flash_rect.color = Color.WHITE
	_flash_rect.size = SCREEN
	_flash_rect.modulate.a = 0.0
	_flash_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layer.add_child(_flash_rect)

	_online = online
	var names: Array = []
	for r in ranking:
		names.append(str(r["name"]))
	names.sort()
	_names_hash = absi(hash("|".join(names)))
	match _pick_kind(ranking, online):
		"punch":
			await _punch(ranking)
		"stairs":
			await _stairs(ranking)
		"laugh":
			await _laugh(ranking)
		"waffle":
			await _waffle(ranking)
		"slot":
			await _slot_machine(ranking)
		_:
			await _nah_id_win(ranking)
	if not skipped:
		_flash(0.25)
		await _wait(0.12)
	_layer.queue_free()

# Which flash? A test (or you) can force one: GameManager.set_meta("flash", "slot" / "nah").
## Every flash and the fewest fighters it needs. Add a line here and a case in play().
const KINDS := {
	"nah": 2, "punch": 2, "stairs": 2, "waffle": 2, "laugh": 3,
	"slot": 4, # the only special case: the reels need the 3 other fighters
}

## Kinds that can run with this many fighters, in a fixed order.
static func eligible_kinds(count: int) -> Array:
	var out: Array = []
	for k in KINDS:
		if count >= int(KINDS[k]):
			out.append(k)
	return out

## Picks equally among eligible kinds. `roll` is a number (any size) - random locally,
## the name hash online, so every machine agrees.
static func kind_for(count: int, roll: int) -> String:
	var kinds := eligible_kinds(count)
	return kinds[absi(roll) % kinds.size()]

# Which flash? A test (or you) can force one: GameManager.set_meta("flash", "slot" / "nah").
func _pick_kind(ranking: Array, online: bool) -> String:
	if GameManager.has_meta("flash"):
		return str(GameManager.get_meta("flash"))
	return kind_for(ranking.size(), _names_hash if online else randi())

# =====================================================================
# FLASH 1: the slot machine (4 fighters)
# =====================================================================

const CELL := Vector2(128, 206) # one reel window
const REEL_SPIN_ITEMS := [14, 22, 30] # how many pictures fly by before each reel lands
const REEL_TIMES := [1.3, 1.9, 2.5] # seconds until each reel stops

func _slot_machine(ranking: Array) -> void:
	var winner: Dictionary = ranking[0]
	var col: Color = winner["color"]
	_backdrop(col.darkened(0.6), col.darkened(0.4), Vector2(640, 360), 20)
	var floor_rect := ColorRect.new()
	floor_rect.color = Color(0.09, 0.07, 0.12)
	floor_rect.position = Vector2(0, 620)
	floor_rect.size = Vector2(SCREEN.x, 120)
	_stage.add_child(floor_rect)

	# --- the machine (all of it lives under `machine`, so it can slide in as one piece)
	var machine := Control.new()
	machine.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stage.add_child(machine)
	var dark := Color(0.3, 0.17, 0.05)
	machine.add_child(_panel(Rect2(250, 150, 500, 470), Color(0.93, 0.72, 0.2), dark, 8, 36)) # body
	machine.add_child(_panel(Rect2(330, 78, 340, 92), Color(0.78, 0.13, 0.2), dark, 6, 22)) # sign
	var sign_text := _text("JACKPOT", 46, GOLD, 10)
	machine.add_child(sign_text)
	_center(sign_text, Vector2(500, 124))
	machine.add_child(_panel(Rect2(278, 243, 444, 244), Color(0.25, 0.08, 0.1), dark, 6, 14)) # reel frame
	machine.add_child(_panel(Rect2(330, 505, 340, 76), Color(0.2, 0.15, 0.1), dark, 5, 12)) # coin tray
	machine.add_child(_panel(Rect2(440, 530, 120, 14), Color.BLACK, Color.BLACK, 0, 7)) # coin slot
	var bulbs: Array = []
	for i in 10: # blinking lights along the top of the body
		var bulb := _panel(Rect2(282 + i * 46, 160, 16, 16), Color(1, 0.95, 0.5), dark, 2, 8)
		machine.add_child(bulb)
		bulbs.append(bulb)
	# lever (pivot is its own origin: rotating swings the rod down on the right side)
	machine.add_child(_panel(Rect2(740, 330, 34, 70), Color(0.6, 0.6, 0.68), dark, 4, 8))
	var lever := Control.new()
	lever.position = Vector2(757, 365)
	lever.mouse_filter = Control.MOUSE_FILTER_IGNORE
	machine.add_child(lever)
	var rod := ColorRect.new()
	rod.color = Color(0.82, 0.82, 0.88)
	rod.position = Vector2(-7, -140)
	rod.size = Vector2(14, 140)
	lever.add_child(rod)
	lever.add_child(_panel(Rect2(-23, -178, 46, 46), Color(0.85, 0.12, 0.12), Color(0.35, 0.03, 0.03), 4, 23))

	# --- the three reels: each is a tall strip of pictures that scrolls up through a window
	var reels: Array = []
	var all_chars: Array = GameManager.characters
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	for r in 3:
		var target: Dictionary = ranking[r + 1] # 2nd, 3rd and 4th place, left to right
		var cell := Control.new()
		cell.position = Vector2(296 + r * 140, 261)
		cell.size = CELL
		cell.clip_contents = true
		cell.mouse_filter = Control.MOUSE_FILTER_IGNORE
		machine.add_child(cell)
		var cell_bg := ColorRect.new()
		cell_bg.color = Color(0.56, 0.6, 0.68) # mid grey-blue: shows both white and black fighters
		cell_bg.size = CELL
		cell.add_child(cell_bg)
		var strip := Control.new()
		strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cell.add_child(strip)
		var spin_items: int = REEL_SPIN_ITEMS[r]
		var x_mark: Node2D = null
		for i in spin_items + 2: # random pictures, then the TARGET, then one extra below it
			var stats: Dictionary = target["stats"] if i == spin_items else all_chars[rng.randi() % all_chars.size()]
			var item := Control.new()
			item.position = Vector2(0, i * CELL.y)
			item.size = CELL
			item.mouse_filter = Control.MOUSE_FILTER_IGNORE
			strip.add_child(item)
			var pic := _portrait_rect(stats, 160.0)
			pic.position = Vector2((CELL.x - pic.size.x) / 2.0, 22)
			item.add_child(pic)
			if i == spin_items:
				x_mark = _x_marks(pic.size)
				x_mark.position = pic.position
				x_mark.scale = Vector2.ZERO # pops in when the reel stops
				item.add_child(x_mark)
		reels.append({"cell": cell, "strip": strip, "end_y": -float(spin_items) * CELL.y, "x": x_mark})

	# --- the winner, hopping in from the right
	var wpic := _portrait_rect(winner["stats"], 300.0)
	wpic.flip_h = true # faces the machine
	var rest_x := 930.0 - wpic.size.x / 2.0
	wpic.position = Vector2(1400, 320)
	_stage.add_child(wpic)
	var wplate := MatchScreens._plate(str(winner["name"]), 26, Color.WHITE, Color(0, 0, 0, 0.8))
	_stage.add_child(wplate)
	wplate.reset_size()
	wplate.position = Vector2(930 - wplate.get_combined_minimum_size().x / 2.0, 272)
	wplate.modulate.a = 0.0

	# ---- action! ----
	machine.position.y = 760.0
	machine.create_tween().tween_property(machine, "position:y", 0.0, 0.55).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	for i in bulbs.size():
		var bt: Tween = bulbs[i].create_tween().set_loops()
		var on := Color(1, 1, 1)
		var off := Color(0.4, 0.35, 0.15)
		bulbs[i].modulate = on if i % 2 == 0 else off
		bt.tween_property(bulbs[i], "modulate", off if i % 2 == 0 else on, 0.25)
		bt.tween_property(bulbs[i], "modulate", on if i % 2 == 0 else off, 0.25)
	await _wait(0.45)
	if skipped: return
	var wt := wpic.create_tween()
	wt.tween_property(wpic, "position:x", rest_x, 0.7).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_hop(wpic, 3, 36.0, 0.23)
	wplate.create_tween().tween_property(wplate, "modulate:a", 1.0, 0.3).set_delay(0.5)
	await _wait(1.0)
	if skipped: return

	# PULL!
	var lt := lever.create_tween()
	lt.tween_property(lever, "rotation", deg_to_rad(140.0), 0.18).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	var lunge := wpic.create_tween()
	lunge.tween_property(wpic, "position:x", rest_x - 55.0, 0.12)
	lunge.tween_property(wpic, "position:x", rest_x, 0.25)
	var chunk := _text("KA-CHUNK!", 54, GOLD, 12)
	_stage.add_child(chunk)
	_center(chunk, Vector2(900, 190))
	chunk.rotation = deg_to_rad(-8.0)
	_pop(chunk)
	chunk.create_tween().tween_property(chunk, "modulate:a", 0.0, 0.4).set_delay(0.9)
	_shake(7.0, 0.25)
	lt.tween_property(lever, "rotation", 0.0, 0.4).set_delay(0.15)
	for r in 3: # all three reels start at once...
		var rt: Tween = reels[r]["strip"].create_tween()
		rt.tween_property(reels[r]["strip"], "position:y", reels[r]["end_y"], REEL_TIMES[r]) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	# ...and stop one after another, each with a thump and an X popping onto the eyes
	var waited := 0.0
	for r in 3:
		await _wait(REEL_TIMES[r] - waited)
		waited = REEL_TIMES[r]
		if skipped: return
		_shake(6.0, 0.18)
		var xm: Node2D = reels[r]["x"]
		xm.create_tween().tween_property(xm, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	await _wait(0.35)
	if skipped: return

	# JACKPOT
	_flash(0.4)
	_shake(10.0, 0.45)
	var win := _text("WINNER!", 84, GOLD, 16)
	_stage.add_child(win)
	_center(win, Vector2(930, 215))
	win.rotation = deg_to_rad(6.0)
	_pop(win, 0.35)
	_hop(wpic, 2, 50.0, 0.3)
	_confetti(Vector2(500, 200))
	_confetti(Vector2(930, 330))
	for r in 3: # the reel windows flash gold
		var glow := ColorRect.new()
		glow.color = Color(1, 0.9, 0.3, 0.55)
		glow.size = CELL
		reels[r]["cell"].add_child(glow)
		glow.create_tween().tween_property(glow, "modulate:a", 0.0, 0.8)
	await _wait(2.2)

# =====================================================================
# FLASH 2: "Nah, I'd win" + the cartoon cut (works with 2+ fighters)
# =====================================================================

func _nah_id_win(ranking: Array) -> void:
	var winner: Dictionary = ranking[0]
	var second: Dictionary = ranking[1]

	# ---- scene 1: manga-style close-up of 2nd place ----
	var paper := ColorRect.new()
	paper.color = Color(0.96, 0.95, 0.92)
	paper.size = SCREEN
	_stage.add_child(paper)
	var lines := Node2D.new() # the black "focus lines" bursting out from the face
	lines.position = Vector2(640, 385)
	_stage.add_child(lines)
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	for i in 90:
		var ang := rng.randf() * TAU
		var inner := rng.randf_range(300.0, 560.0)
		var half := rng.randf_range(0.004, 0.017)
		var tri := Polygon2D.new()
		tri.color = Color(0.05, 0.05, 0.07)
		tri.polygon = PackedVector2Array([
			Vector2(cos(ang - half), sin(ang - half)) * 1500.0,
			Vector2(cos(ang + half), sin(ang + half)) * 1500.0,
			Vector2(cos(ang), sin(ang)) * inner])
		lines.add_child(tri)
	lines.create_tween().set_loops().tween_property(lines, "rotation", 0.05, 1.2).as_relative()
	# the close-up: so big that only the face and shoulders fit, creeping slowly closer
	# a black copy a little bigger, behind: gives the picture a bold manga outline
	# (and keeps a white fighter from vanishing into the white paper)
	var outline_pic := _portrait_rect(second["stats"], 880.0 * 1.05)
	outline_pic.modulate = Color.BLACK
	outline_pic.position = Vector2(640 - outline_pic.size.x / 2.0, 385 - FACE_Y * outline_pic.size.y)
	outline_pic.pivot_offset = Vector2(outline_pic.size.x / 2.0, FACE_Y * outline_pic.size.y)
	_stage.add_child(outline_pic)
	outline_pic.scale = Vector2(0.92, 0.92)
	outline_pic.create_tween().tween_property(outline_pic, "scale", Vector2(1.06, 1.06), 4.0)
	var face := _portrait_rect(second["stats"], 880.0)
	face.position = Vector2(640 - face.size.x / 2.0, 385 - FACE_Y * face.size.y)
	face.pivot_offset = Vector2(face.size.x / 2.0, FACE_Y * face.size.y) # zoom toward the eyes
	_stage.add_child(face)
	face.scale = Vector2(0.92, 0.92)
	face.create_tween().tween_property(face, "scale", Vector2(1.06, 1.06), 4.0)
	var tag := MatchScreens._plate("2nd  -  %s" % str(second["name"]), 24, Color.WHITE, Color(0, 0, 0, 0.85))
	tag.position = Vector2(70, 560)
	_stage.add_child(tag)
	_flash(0.3)
	await _wait(0.7)
	if skipped: return
	var b1 := _bubble(_stage, Vector2(320, 190), Vector2(340, 160), Vector2(560, 400), "Nah,")
	_pop(b1, 0.2)
	_shake(5.0, 0.15)
	await _wait(1.0)
	if skipped: return
	var b2 := _bubble(_stage, Vector2(955, 250), Vector2(380, 170), Vector2(730, 410), "I'd win.")
	_pop(b2, 0.2)
	_shake(8.0, 0.2)
	await _wait(1.5)
	if skipped: return

	# ---- smash cut! ----
	_clear_stage()
	_flash(0.5)
	_shake(16.0, 0.5)

	# ---- scene 2: the winner stands over the (cut-in-half) 2nd place ----
	var ground_y := 590.0
	var sky := TextureRect.new()
	var grad := Gradient.new()
	grad.colors = PackedColorArray([Color(0.98, 0.62, 0.35), Color(0.55, 0.25, 0.45), Color(0.2, 0.12, 0.3)])
	grad.offsets = PackedFloat32Array([0.0, 0.55, 1.0])
	var gtex := GradientTexture2D.new()
	gtex.gradient = grad
	gtex.fill_from = Vector2(0, 0)
	gtex.fill_to = Vector2(0, 1)
	gtex.width = 8
	gtex.height = 256
	sky.texture = gtex
	sky.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	sky.stretch_mode = TextureRect.STRETCH_SCALE
	sky.size = SCREEN
	_stage.add_child(sky)
	var sun := Polygon2D.new()
	var sun_pts := PackedVector2Array()
	for i in 40:
		sun_pts.append(Vector2(cos(TAU * i / 40.0), sin(TAU * i / 40.0)) * 130.0)
	sun.polygon = sun_pts
	sun.position = Vector2(930, 330)
	sun.color = Color(1.0, 0.9, 0.55, 0.9)
	_stage.add_child(sun)
	# ruined skyline (jagged rooftops), like the manga panel it's inspired by
	rng.seed = 5
	var sx := -30.0
	while sx < SCREEN.x:
		var w := rng.randf_range(70.0, 130.0)
		var h := rng.randf_range(110.0, 300.0)
		var roof := Polygon2D.new()
		roof.color = Color(0.17, 0.1, 0.2)
		roof.polygon = PackedVector2Array([
			Vector2(sx, ground_y), Vector2(sx, ground_y - h),
			Vector2(sx + w * 0.35, ground_y - h - rng.randf_range(0.0, 40.0)),
			Vector2(sx + w * 0.7, ground_y - h + rng.randf_range(10.0, 50.0)),
			Vector2(sx + w, ground_y - h * 0.8), Vector2(sx + w, ground_y)])
		_stage.add_child(roof)
		sx += w + rng.randf_range(-10.0, 25.0)
	var ground := ColorRect.new()
	ground.color = Color(0.2, 0.13, 0.15)
	ground.position = Vector2(0, ground_y)
	ground.size = Vector2(SCREEN.x, SCREEN.y - ground_y)
	_stage.add_child(ground)
	for i in 14: # rubble
		var rock := Polygon2D.new()
		var rx := rng.randf_range(20.0, 1260.0)
		var rs := rng.randf_range(8.0, 22.0)
		rock.color = Color(0.3, 0.21, 0.22)
		rock.polygon = PackedVector2Array([Vector2(rx - rs, ground_y + 4), Vector2(rx - rs * 0.3, ground_y - rs * 0.6), Vector2(rx + rs, ground_y + 4)])
		_stage.add_child(rock)

	# the cut loser: two halves of the picture, lying on the ground, head to the right
	var s := 4.2 # picture pixels -> screen pixels
	var tex: Texture2D = MatchScreens.portrait(second["stats"])
	var ts := tex.get_size()
	var loser := Node2D.new()
	loser.position = Vector2(740, ground_y - ts.x * s / 2.0) # lying down: the picture's WIDTH becomes its height
	loser.rotation = PI / 2.0 # +90 degrees = head points right
	loser.scale = Vector2(s, s)
	_stage.add_child(loser)
	var cut_l := ts.y * 0.52 # the cut runs a little slanted across the body (left / right end heights)
	var cut_r := ts.y * 0.44
	var feet_half := _half(tex, [Vector2(0, cut_l), Vector2(ts.x, cut_r), Vector2(ts.x, ts.y), Vector2(0, ts.y)], Vector2(0, cut_l), Vector2(ts.x, cut_r))
	var head_half := _half(tex, [Vector2(0, 0), Vector2(ts.x, 0), Vector2(ts.x, cut_r), Vector2(0, cut_l)], Vector2(0, cut_l), Vector2(ts.x, cut_r))
	loser.add_child(feet_half)
	loser.add_child(head_half)
	var xm := _x_marks(ts) # the X over the eyes, in picture pixels (so it rides on the head half)
	xm.scale = Vector2.ZERO
	head_half.add_child(xm)
	xm.position = Vector2.ZERO
	# (the halves are centred on the picture's middle so rotation looks right)
	feet_half.position = -ts / 2.0
	head_half.position = -ts / 2.0

	# the winner towers over them
	var shadow := Polygon2D.new()
	var sh_pts := PackedVector2Array()
	for i in 30:
		sh_pts.append(Vector2(cos(TAU * i / 30.0) * 120.0, sin(TAU * i / 30.0) * 16.0))
	shadow.polygon = sh_pts
	shadow.color = Color(0, 0, 0, 0.35)
	shadow.position = Vector2(540, ground_y + 6)
	_stage.add_child(shadow)
	var wpic := _portrait_rect(winner["stats"], ts.y * s)
	wpic.position = Vector2(540 - wpic.size.x / 2.0, ground_y - wpic.size.y)
	wpic.pivot_offset = Vector2(wpic.size.x / 2.0, wpic.size.y)
	_stage.add_child(wpic)
	var wtag := MatchScreens._plate("1st  -  %s" % str(winner["name"]), 24, Color.WHITE, Color(0, 0, 0, 0.85))
	wtag.position = Vector2(70, 560)
	_stage.add_child(wtag)

	# the SHING: a bright slash across the body, the halves pop apart
	await _wait(0.45)
	if skipped: return
	var slash := Line2D.new()
	slash.width = 14.0
	slash.default_color = Color.WHITE
	slash.points = PackedVector2Array([Vector2(700, 380), Vector2(900, 560)])
	slash.begin_cap_mode = Line2D.LINE_CAP_ROUND
	slash.end_cap_mode = Line2D.LINE_CAP_ROUND
	_stage.add_child(slash)
	slash.create_tween().tween_property(slash, "modulate:a", 0.0, 0.35)
	_flash(0.25)
	_shake(10.0, 0.3)
	var shing := _text("SHING!", 96, Color(1.0, 0.95, 0.3), 18)
	_stage.add_child(shing)
	_center(shing, Vector2(900, 300))
	shing.rotation = deg_to_rad(-9.0)
	_pop(shing, 0.25)
	shing.create_tween().tween_property(shing, "modulate:a", 0.0, 0.5).set_delay(1.0)
	var sep := head_half.create_tween().set_parallel(true)
	sep.tween_property(head_half, "position", -ts / 2.0 + Vector2(0, -9), 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	sep.tween_property(head_half, "rotation", deg_to_rad(7.0), 0.3)
	var drop := feet_half.create_tween()
	drop.tween_property(feet_half, "rotation", deg_to_rad(-3.0), 0.3)
	# the winner flicks the "blade" away and strikes a pose
	var pose := wpic.create_tween()
	pose.tween_property(wpic, "rotation", deg_to_rad(8.0), 0.12)
	pose.tween_property(wpic, "rotation", 0.0, 0.4).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	await _wait(0.4)
	if skipped: return
	xm.create_tween().tween_property(xm, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	# dizzy stars circling the head half
	var orbit := Node2D.new()
	orbit.position = Vector2(740 + ts.y * s * 0.3, ground_y - ts.x * s - 8.0)
	_stage.add_child(orbit)
	for i in 3:
		var star := _text("★", 38, GOLD, 6)
		orbit.add_child(star)
		star.position = Vector2(cos(TAU * i / 3.0), sin(TAU * i / 3.0) * 0.4) * 70.0 - Vector2(14, 24)
	orbit.create_tween().set_loops().tween_property(orbit, "rotation", TAU, 1.6).as_relative()
	await _wait(2.4)

# =====================================================================
# FLASH 3: the speed-up punch (works with 2+ fighters)
# =====================================================================
# The winner runs at a RANDOM other fighter, speeding up exponentially (afterimages
# trailing behind, the ground rushing past), and punches them. The last shot -
# close-up fist, flying glass, the victim hurled across a cracked canyon - is the
# one the whole thing builds to.

func _punch(ranking: Array) -> void:
	var winner: Dictionary = ranking[0]
	var vi: int = 1 + (_names_hash % (ranking.size() - 1) if _online else randi() % (ranking.size() - 1))
	var victim: Dictionary = ranking[vi]

	# ---- scene 1: wide side view ----
	var ground_y := _run_ground
	var sky := ColorRect.new()
	sky.color = Color(0.66, 0.65, 0.64)
	sky.size = SCREEN
	_stage.add_child(sky)
	var rng := RandomNumberGenerator.new()
	rng.seed = 21
	for i in 5: # overcast clouds
		var cloud := Polygon2D.new()
		var pts := PackedVector2Array()
		var cw := rng.randf_range(160.0, 320.0)
		for j in 24:
			pts.append(Vector2(cos(TAU * j / 24.0) * cw, sin(TAU * j / 24.0) * cw * 0.16))
		cloud.polygon = pts
		cloud.color = Color(0.8, 0.8, 0.8, 0.7)
		cloud.position = Vector2(rng.randf_range(0.0, 1280.0), rng.randf_range(90.0, 230.0))
		_stage.add_child(cloud)
	var x := -40.0 # blocky ruined cliffs in the distance
	while x < SCREEN.x:
		var w := rng.randf_range(120.0, 260.0)
		var h := rng.randf_range(90.0, 200.0)
		var blk := ColorRect.new()
		blk.color = Color(0.42, 0.3, 0.26).lerp(Color(0.55, 0.42, 0.34), rng.randf())
		blk.position = Vector2(x, ground_y - 20.0 - h)
		blk.size = Vector2(w, h + 20.0)
		_stage.add_child(blk)
		x += w - rng.randf_range(0.0, 40.0)
	var ground := ColorRect.new()
	ground.color = Color(0.78, 0.64, 0.47)
	ground.position = Vector2(0, ground_y - 20.0)
	ground.size = Vector2(SCREEN.x, SCREEN.y - ground_y + 20.0)
	_stage.add_child(ground)
	_scrollers.clear()
	for i in 16: # light and dark streaks sliding left along the ground
		var streak := ColorRect.new()
		streak.color = Color(0.9, 0.78, 0.6, 0.8) if i % 2 == 0 else Color(0.6, 0.46, 0.32, 0.8)
		streak.size = Vector2(rng.randf_range(70.0, 240.0), rng.randf_range(4.0, 10.0))
		streak.position = Vector2(rng.randf_range(0.0, 1500.0), rng.randf_range(ground_y + 10.0, 640.0))
		_stage.add_child(streak)
		_scrollers.append({"node": streak, "factor": 0.6 + (streak.position.y - ground_y) / 120.0}) # lower = closer = faster
	_run_layer = Control.new() # afterimages + dust, behind the runner
	_run_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stage.add_child(_run_layer)

	var vpic := _portrait_rect(victim["stats"], 240.0)
	vpic.flip_h = true # faces the incoming runner
	vpic.position = Vector2(1010.0 - vpic.size.x / 2.0, ground_y - 240.0)
	_stage.add_child(vpic)
	var vplate := MatchScreens._plate(str(victim["name"]), 22, Color.WHITE, Color(0, 0, 0, 0.75))
	_stage.add_child(vplate)
	vplate.reset_size()
	vplate.position = Vector2(1010.0 - vplate.get_combined_minimum_size().x / 2.0, ground_y - 282.0)

	_run_winner = _portrait_rect(winner["stats"], 240.0)
	_run_winner.pivot_offset = Vector2(_run_winner.size.x / 2.0, _run_winner.size.y) # leans forward from the feet
	_run_x0 = 40.0
	_run_x1 = vpic.position.x - _run_winner.size.x + 36.0 # ends overlapping the victim = the hit
	_run_winner.position = Vector2(_run_x0, ground_y - 240.0)
	_stage.add_child(_run_winner)
	_speed_lines.clear()
	for i in 26: # white speed lines over everything, fading in as the runner speeds up
		var ln := ColorRect.new()
		ln.color = Color(1, 1, 1, 0.0)
		ln.size = Vector2(rng.randf_range(160.0, 520.0), rng.randf_range(2.0, 5.0))
		ln.position = Vector2(rng.randf_range(0.0, 1280.0), rng.randf_range(90.0, 640.0))
		_stage.add_child(ln)
		_speed_lines.append(ln)
	var wplate := MatchScreens._plate("1st  -  %s" % str(winner["name"]), 24, Color.WHITE, Color(0, 0, 0, 0.85))
	wplate.position = Vector2(70, 560)
	_stage.add_child(wplate)
	_flash(0.3)

	# ---- the run: starts slow and gets exponentially faster (see _run_tick) ----
	await _wait(0.5)
	if skipped: return
	_run_t = 0.0
	_run_active = true
	await _wait(_run_dur * 0.62)
	if skipped: return
	var bang := _text("!", 120, Color(1, 0.25, 0.2), 16) # the victim notices too late
	_stage.add_child(bang)
	_center(bang, Vector2(1010, ground_y - 330.0))
	_pop(bang, 0.15)
	await _wait(_run_dur * 0.38)
	_run_active = false
	if skipped: return

	# ---- impact ----
	var star := Polygon2D.new()
	star.polygon = _star_points(150.0, 60.0, 10)
	star.color = Color(1.0, 0.95, 0.5)
	star.position = Vector2(vpic.position.x + 20.0, ground_y - 130.0)
	_stage.add_child(star)
	star.scale = Vector2(0.3, 0.3)
	star.create_tween().tween_property(star, "scale", Vector2(1.4, 1.4), 0.12)
	_flash(0.2)
	_shake(18.0, 0.35)
	await _wait(0.2) # hit-stop: everything holds for a beat
	if skipped: return
	var fly := vpic.create_tween().set_parallel(true)
	fly.tween_property(vpic, "position", Vector2(1700, 40), 0.45).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	fly.tween_property(vpic, "rotation", 9.0, 0.45)
	vplate.visible = false
	bang.visible = false
	await _wait(0.4)
	if skipped: return

	# ---- scene 2: THE shot - fist in the foreground, glass flying, victim hurled away ----
	_clear_stage()
	_scrollers.clear()
	_speed_lines.clear()
	_flash(0.45)
	_shake(20.0, 0.5)
	var shot := Control.new() # the whole picture, tilted and enlarged so the tilt never shows the corners
	shot.size = SCREEN
	shot.pivot_offset = SCREEN / 2.0
	shot.rotation = deg_to_rad(-11.0)
	shot.scale = Vector2(1.24, 1.24)
	shot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stage.add_child(shot)
	var wcol: Color = winner["stats"].get("color", Color.WHITE)
	var sky2 := ColorRect.new()
	sky2.color = Color(0.74, 0.76, 0.8)
	sky2.size = SCREEN
	shot.add_child(sky2)
	for i in 4:
		var cl := Polygon2D.new()
		var cp := PackedVector2Array()
		var cwid := rng.randf_range(200.0, 360.0)
		for j in 24:
			cp.append(Vector2(cos(TAU * j / 24.0) * cwid, sin(TAU * j / 24.0) * cwid * 0.18))
		cl.polygon = cp
		cl.color = Color(0.93, 0.94, 0.96, 0.8)
		cl.position = Vector2(rng.randf_range(400.0, 1300.0), rng.randf_range(20.0, 200.0))
		shot.add_child(cl)
	# the cracked canyon: stepped orange cliffs going off diagonally
	var cliff_back := Polygon2D.new()
	cliff_back.color = Color(0.6, 0.38, 0.27)
	cliff_back.polygon = PackedVector2Array([Vector2(0, 150), Vector2(260, 190), Vector2(420, 290), Vector2(0, 360)])
	shot.add_child(cliff_back)
	var cliff := Polygon2D.new()
	cliff.color = Color(0.8, 0.52, 0.34)
	cliff.polygon = PackedVector2Array([Vector2(0, 330), Vector2(420, 290), Vector2(900, 470), Vector2(1280, 400), Vector2(1280, 720), Vector2(0, 720)])
	shot.add_child(cliff)
	var ledge := Polygon2D.new()
	ledge.color = Color(0.68, 0.42, 0.28)
	ledge.polygon = PackedVector2Array([Vector2(0, 470), Vector2(520, 520), Vector2(800, 640), Vector2(0, 720)])
	shot.add_child(ledge)
	for i in 9: # cracks in the ground
		var crack := Line2D.new()
		crack.width = rng.randf_range(3.0, 7.0)
		crack.default_color = Color(0.36, 0.2, 0.14)
		var cx := rng.randf_range(0.0, 900.0)
		var cy := rng.randf_range(400.0, 700.0)
		var pts2 := PackedVector2Array([Vector2(cx, cy)])
		for j in 4:
			cx += rng.randf_range(30.0, 90.0)
			cy += rng.randf_range(-25.0, 40.0)
			pts2.append(Vector2(cx, cy))
		crack.points = pts2
		shot.add_child(crack)
	# the victim, tiny in the distance, hurled through the air
	var far := _portrait_rect(victim["stats"], 105.0)
	far.position = Vector2(330, 205)
	far.pivot_offset = far.size / 2.0
	far.rotation = deg_to_rad(38.0)
	shot.add_child(far)
	for i in 3: # motion smear behind them
		var smear := _portrait_rect(victim["stats"], 105.0)
		smear.position = far.position + Vector2(-34.0 * (i + 1), 22.0 * (i + 1))
		smear.pivot_offset = smear.size / 2.0
		smear.rotation = far.rotation
		smear.modulate = Color(0.1, 0.1, 0.15, 0.35 - 0.1 * i)
		shot.add_child(smear)
		shot.move_child(smear, far.get_index())
	# the winner, huge: black outline copy first, then the picture
	for pass_i in 2:
		var big := _portrait_rect(winner["stats"], 560.0 * (1.05 if pass_i == 0 else 1.0))
		big.position = Vector2(900.0 - big.size.x / 2.0, 120.0 - (560.0 * 0.025 if pass_i == 0 else 0.0))
		big.pivot_offset = big.size / 2.0
		big.rotation = deg_to_rad(-7.0)
		if pass_i == 0:
			big.modulate = Color.BLACK
		shot.add_child(big)
	# the fist (and sleeve) punching toward the camera
	var sleeve := _panel(Rect2(930, 430, 420, 160), wcol.darkened(0.25), Color.BLACK, 7, 0)
	sleeve.pivot_offset = Vector2(0, 80)
	sleeve.rotation = deg_to_rad(-22.0)
	shot.add_child(sleeve)
	var fist := _panel(Rect2(740, 320, 240, 215), wcol.lightened(0.3), Color.BLACK, 8, 0)
	fist.pivot_offset = Vector2(120, 107)
	fist.rotation = deg_to_rad(-9.0)
	shot.add_child(fist)
	for i in 3: # the finger lines
		var fl := ColorRect.new()
		fl.color = Color.BLACK
		fl.position = Vector2(48 + i * 60, 18)
		fl.size = Vector2(6, 120)
		fist.add_child(fl)
	var thumb := _panel(Rect2(-32, 120, 104, 64), wcol.lightened(0.3), Color.BLACK, 7, 0)
	fist.add_child(thumb)
	# flying glass
	var shards: Array = []
	for i in 46:
		var shard := Polygon2D.new()
		var sz := rng.randf_range(10.0, 46.0)
		shard.polygon = PackedVector2Array([Vector2(-sz, -sz * 0.4), Vector2(sz * 0.5, -sz), Vector2(sz, sz * 0.5), Vector2(-sz * 0.3, sz * 0.8)])
		shard.color = Color(0.85, 0.93, 1.0, 0.55)
		shard.position = Vector2(rng.randf_range(0.0, 1180.0), rng.randf_range(10.0, 660.0))
		shard.rotation = rng.randf() * TAU
		var rim := Line2D.new()
		rim.width = 2.0
		rim.default_color = Color(1, 1, 1, 0.9)
		rim.closed = true
		rim.points = shard.polygon
		shard.add_child(rim)
		shot.add_child(shard)
		shards.append(shard)
	var tag2 := MatchScreens._plate("1st  -  %s" % str(winner["name"]), 24, Color.WHITE, Color(0, 0, 0, 0.85))
	tag2.position = Vector2(70, 560)
	_stage.add_child(tag2)
	# the shot lives: shards drift away from the fist, camera creeps in
	for sh in shards:
		var drift: Vector2 = (sh.position - Vector2(820, 380)).normalized() * rng.randf_range(40.0, 150.0)
		var st: Tween = sh.create_tween().set_parallel(true)
		st.tween_property(sh, "position", sh.position + drift, 2.8)
		st.tween_property(sh, "rotation", sh.rotation + rng.randf_range(-2.0, 2.0), 2.8)
	var cam := shot.create_tween().set_parallel(true)
	cam.tween_property(shot, "scale", Vector2(1.32, 1.32), 3.0)
	cam.tween_property(shot, "rotation", deg_to_rad(-9.0), 3.0)
	await _wait(3.0)

# Per-frame work for the run: exponential speed-up, afterimages, dust, rushing ground.
func _run_tick(delta: float) -> void:
	_run_t += delta
	var t := minf(_run_t, _run_dur)
	var k := 5.0 # bigger = more of the run is slow, then a more violent last burst
	var prog := (exp(k * t / _run_dur) - 1.0) / (exp(k) - 1.0)
	var u := t / _run_dur
	var w := _run_winner
	w.position.x = lerpf(_run_x0, _run_x1, prog)
	w.position.y = _run_ground - w.size.y - absf(sin(_run_t * (9.0 + 34.0 * prog))) * 16.0 * (1.0 - 0.6 * prog)
	w.rotation = deg_to_rad(3.0 + 20.0 * prog) # leans further into the run
	_scroll_speed = 120.0 * exp(3.7 * u)
	for sc in _scrollers:
		var n: ColorRect = sc["node"]
		n.position.x -= _scroll_speed * float(sc["factor"]) * delta
		if n.position.x < -n.size.x:
			n.position.x += 1300.0 + n.size.x
	for ln in _speed_lines:
		ln.position.x -= _scroll_speed * 1.4 * delta
		if ln.position.x < -ln.size.x:
			ln.position.x = 1280.0 + randf() * 300.0
			ln.position.y = randf_range(90.0, 640.0)
		ln.color.a = clampf((prog - 0.12) * 1.6, 0.0, 0.7)
	_ghost_timer -= delta
	if _ghost_timer <= 0.0:
		_ghost_timer = lerpf(0.1, 0.035, prog)
		var ghost := TextureRect.new() # a see-through copy left hanging in the air
		ghost.texture = w.texture
		ghost.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		ghost.stretch_mode = TextureRect.STRETCH_SCALE
		ghost.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		ghost.size = w.size
		ghost.pivot_offset = w.pivot_offset
		ghost.position = w.position
		ghost.rotation = w.rotation
		ghost.modulate = Color(0.75, 0.9, 1.0, 0.5)
		ghost.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_run_layer.add_child(ghost)
		var gt := ghost.create_tween()
		gt.tween_property(ghost, "modulate:a", 0.0, 0.4)
		gt.tween_callback(ghost.queue_free)
		var dust := ColorRect.new()
		dust.color = Color(0.88, 0.76, 0.58, 0.75)
		var ds := randf_range(10.0, 26.0)
		dust.size = Vector2(ds, ds)
		dust.position = Vector2(w.position.x + w.size.x * 0.3, _run_ground - ds)
		_run_layer.add_child(dust)
		var dt := dust.create_tween().set_parallel(true)
		dt.tween_property(dust, "position", dust.position + Vector2(-70.0 - 80.0 * prog, -30.0), 0.45)
		dt.tween_property(dust, "modulate:a", 0.0, 0.45)
		dt.chain().tween_callback(dust.queue_free)

func _star_points(outer: float, inner: float, n: int) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in n * 2:
		var r := outer if i % 2 == 0 else inner
		var a := PI * float(i) / n
		pts.append(Vector2(cos(a), sin(a)) * r)
	return pts

# =====================================================================
# drawing helpers
# =====================================================================

# =====================================================================
# FLASH: STAIRS - the winner climbs forever while a giant picture of them grins behind
# =====================================================================
func _stairs(ranking: Array) -> void:
	var winner: Dictionary = ranking[0]
	var bg := ColorRect.new()
	bg.color = Color(0.1, 0.07, 0.2)
	bg.size = SCREEN
	_stage.add_child(bg)
	_backdrop(Color(0.1, 0.07, 0.2), Color(0.18, 0.12, 0.34), Vector2(640, 300), 18)

	# giant looming picture of the winner, with a huge grin
	var big := _portrait_rect(winner["stats"], 980.0)
	big.position = Vector2(SCREEN.x * 0.5 - big.size.x / 2.0, -150.0)
	big.modulate = Color(0.55, 0.5, 0.75, 0.9)
	_stage.add_child(big)
	big.add_child(_grin(big.size))
	var sway := big.create_tween().set_loops()
	sway.tween_property(big, "position:y", -165.0, 1.1).set_trans(Tween.TRANS_SINE)
	sway.tween_property(big, "position:y", -135.0, 1.1).set_trans(Tween.TRANS_SINE)

	# the endless stairs (the world slides down-left so the climber stays put)
	var steps := Node2D.new()
	_stage.add_child(steps)
	for i in 60:
		var r := ColorRect.new()
		r.color = Color(0.82, 0.78, 0.9).lerp(Color(0.5, 0.45, 0.7), (i % 2) * 0.5)
		r.position = Vector2(i * 90.0, -i * 60.0)
		r.size = Vector2(90.0, 2400.0)
		steps.add_child(r)
		var lip := ColorRect.new()
		lip.color = Color(1, 1, 1, 0.8)
		lip.position = r.position
		lip.size = Vector2(90.0, 6.0)
		steps.add_child(lip)

	var me := _portrait_rect(winner["stats"], 170.0)
	var feet := Vector2(425.0, 470.0)
	me.position = feet - Vector2(me.size.x / 2.0, 170.0)
	_stage.add_child(me)

	var counter := _text("STEP 0", 64, GOLD, 12)
	_stage.add_child(counter)
	_center(counter, Vector2(1010, 150))
	_flash(0.4)

	var total := 40.0
	var dur := 4.6
	var climb := func(v: float) -> void:
		steps.position = Vector2(380.0 - 90.0 * v, 470.0 + 60.0 * v)
		var f := v - floorf(v)
		me.position = feet - Vector2(me.size.x / 2.0, 170.0) + Vector2(0, -sin(f * PI) * 34.0)
		me.rotation = sin(v * PI * 2.0) * 0.06
		var n := int(v)
		counter.text = "STEP %d" % n if n < 28 else "STEP ∞"
		_center(counter, Vector2(1010, 150))
	var tw := _stage.create_tween()
	tw.tween_method(climb, 0.0, total, dur).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	await _wait(dur - 0.2)
	if skipped:
		return
	_flash(0.4)
	_shake(10.0, 0.4)
	await _wait(0.45)

# A huge toothy grin drawn over a picture `pic_size` big (mouth sits just under the middle).
func _grin(pic_size: Vector2) -> Node2D:
	var root := Node2D.new()
	var c := Vector2(pic_size.x * 0.5, pic_size.y * 0.37)
	var w := pic_size.x * 0.34
	var pts := PackedVector2Array()
	for i in 21:
		var a := PI * i / 20.0
		pts.append(c + Vector2(-cos(a) * w, sin(a) * w * 0.55))
	var edge := Polygon2D.new()
	edge.color = Color.BLACK
	var big := PackedVector2Array()
	for p in pts:
		big.append(c + (p - c) * 1.1)
	edge.polygon = big
	root.add_child(edge)
	var mouth := Polygon2D.new()
	mouth.color = Color(0.97, 0.97, 0.95)
	mouth.polygon = pts
	root.add_child(mouth)
	for k in range(1, 6): # teeth lines
		var tx := c.x - w + w * 2.0 * k / 6.0
		var ln := Line2D.new()
		ln.width = 4.0
		ln.default_color = Color.BLACK
		ln.points = PackedVector2Array([Vector2(tx, c.y), Vector2(tx, c.y + w * 0.5)])
		root.add_child(ln)
	var mid := Line2D.new()
	mid.width = 4.0
	mid.default_color = Color.BLACK
	mid.points = PackedVector2Array([Vector2(c.x - w, c.y), Vector2(c.x + w, c.y)])
	root.add_child(mid)
	return root

# =====================================================================
# FLASH: LAUGH - 1st and 2nd howl over whoever came last
# =====================================================================
func _laugh(ranking: Array) -> void:
	var a: Dictionary = ranking[0]
	var b: Dictionary = ranking[1] if ranking.size() >= 3 else ranking[0] # 2 fighters: the winner laughs on both sides
	var loser: Dictionary = ranking[ranking.size() - 1]
	var bg := ColorRect.new()
	bg.color = Color(0.07, 0.05, 0.1)
	bg.size = SCREEN
	_stage.add_child(bg)
	var sides := [[a, -0.12, 0.23, Color(0.55, 0.2, 0.75)], [b, 0.12, 0.77, Color(0.85, 0.15, 0.2)]]
	var faces: Array = []
	for s in sides:
		var tint := ColorRect.new() # a slab of colour behind each face
		tint.color = (s[3] as Color).darkened(0.4)
		tint.size = Vector2(SCREEN.x * 0.5, SCREEN.y)
		tint.position = Vector2(0.0 if s[2] < 0.5 else SCREEN.x * 0.5, 0)
		_stage.add_child(tint)
		var f := _portrait_rect(s[0]["stats"], 820.0)
		f.pivot_offset = f.size / 2.0
		f.position = Vector2(SCREEN.x * float(s[2]) - f.size.x / 2.0, -40.0)
		f.rotation = float(s[1])
		f.modulate = (s[3] as Color).lerp(Color.WHITE, 0.55)
		_stage.add_child(f)
		f.add_child(_laugh_mouth(f.size))
		faces.append(f)
		var tw := f.create_tween().set_loops() # shaking with laughter
		tw.tween_property(f, "scale", Vector2(1.05, 0.96), 0.12)
		tw.tween_property(f, "scale", Vector2(0.97, 1.04), 0.12)
	for i in 6: # HA HA HA
		var t := _text("HA" if i % 2 == 0 else "HA!", 90 + (i % 3) * 20, Color(1, 0.95, 0.4), 14)
		_stage.add_child(t)
		_center(t, Vector2(300.0 + 110.0 * i, 140.0 + (i % 2) * 90.0))
		t.rotation = (i % 2 - 0.5) * 0.4
		_pop(t, 0.2)
		_hop(t, 5, 14.0, 0.25)
		await _wait(0.16)
		if skipped:
			return
	# the one who came last, small and sad between them
	var lp := _portrait_rect(loser["stats"], 210.0)
	lp.position = Vector2(SCREEN.x / 2.0 - lp.size.x / 2.0, SCREEN.y - BAR_H - 210.0 - 6.0)
	lp.modulate = Color(0.75, 0.75, 0.8)
	_stage.add_child(lp)
	lp.add_child(_x_marks(lp.size))
	_pop(lp, 0.3)
	var plate := MatchScreens._plate(str(loser["name"]), 22, Color.WHITE, Color(0, 0, 0, 0.75))
	_stage.add_child(plate)
	plate.reset_size()
	plate.position = Vector2(SCREEN.x / 2.0 - plate.size.x / 2.0, lp.position.y - 34.0)
	_shake(8.0, 0.5)
	await _wait(2.6)

# A wide-open laughing mouth with tears, for a picture `pic_size` big.
func _laugh_mouth(pic_size: Vector2) -> Node2D:
	var root := Node2D.new()
	var c := Vector2(pic_size.x * 0.5, pic_size.y * 0.36)
	var w := pic_size.x * 0.32
	var pts := PackedVector2Array()
	for i in 21:
		var ang := PI * i / 20.0
		pts.append(c + Vector2(-cos(ang) * w, sin(ang) * w * 0.8))
	var outline := Polygon2D.new()
	outline.color = Color.BLACK
	var grown := PackedVector2Array()
	for p in pts:
		grown.append(c + (p - c) * 1.1)
	outline.polygon = grown
	root.add_child(outline)
	var inside := Polygon2D.new()
	inside.color = Color(0.25, 0.02, 0.05)
	inside.polygon = pts
	root.add_child(inside)
	var tongue := Polygon2D.new()
	tongue.color = Color(0.95, 0.4, 0.5)
	var tp := PackedVector2Array()
	for i in 13:
		var ang := PI * i / 12.0
		tp.append(c + Vector2(-cos(ang) * w * 0.5, w * 0.8 - sin(ang) * w * 0.3 + 0.0))
	tongue.polygon = tp
	root.add_child(tongue)
	for sx in [-1.0, 1.0]: # tears
		var tear := Polygon2D.new()
		tear.color = Color(0.5, 0.85, 1.0)
		var ec := Vector2(pic_size.x * (0.5 + 0.2 * sx), pic_size.y * 0.29)
		tear.polygon = PackedVector2Array([ec + Vector2(0, -14), ec + Vector2(12, 14), ec + Vector2(0, 28), ec + Vector2(-12, 14)])
		root.add_child(tear)
	return root

# =====================================================================
# FLASH: WAFFLE - last place creeps in, thinks better of it, and gets waffled
# =====================================================================
func _waffle(ranking: Array) -> void:
	var winner: Dictionary = ranking[0]
	var loser: Dictionary = ranking[ranking.size() - 1]
	var ground_y := 580.0
	_backdrop(Color(0.93, 0.9, 0.8), Color(0.82, 0.78, 0.66), Vector2(900, 360), 24)
	for i in 14: # manga spikes along the ground
		var sp := Polygon2D.new()
		var bx := 40.0 + i * 95.0
		sp.polygon = PackedVector2Array([Vector2(bx, ground_y), Vector2(bx + 28.0, ground_y - 70.0 - (i % 3) * 25.0), Vector2(bx + 56.0, ground_y)])
		sp.color = Color(0.15, 0.13, 0.12)
		_stage.add_child(sp)
	var floor_r := ColorRect.new()
	floor_r.color = Color(0.2, 0.17, 0.15)
	floor_r.position = Vector2(0, ground_y)
	floor_r.size = Vector2(SCREEN.x, SCREEN.y - ground_y)
	_stage.add_child(floor_r)

	var w := _portrait_rect(winner["stats"], 300.0)
	w.position = Vector2(960.0 - w.size.x / 2.0, ground_y - 300.0)
	w.flip_h = true
	_stage.add_child(w)
	var l := _portrait_rect(loser["stats"], 250.0)
	var lx := 160.0
	l.position = Vector2(lx, ground_y - 250.0)
	_stage.add_child(l)
	_flash(0.3)

	# creeps closer...
	var walk := l.create_tween()
	walk.tween_property(l, "position:x", 520.0, 1.2)
	var bob := l.create_tween().set_loops(5)
	bob.tween_property(l, "scale:y", 0.96, 0.12)
	bob.tween_property(l, "scale:y", 1.0, 0.12)
	await _wait(1.3)
	if skipped:
		return
	# ...gulps, and jumps back
	var q := _text("!?", 80, Color(1, 0.9, 0.3), 14)
	_stage.add_child(q)
	_center(q, l.position + Vector2(l.size.x / 2.0, -40.0))
	_pop(q, 0.15)
	await _wait(0.55)
	if skipped:
		return
	var back := l.create_tween().set_parallel(true)
	back.tween_property(l, "position:x", 250.0, 0.55).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	var up := l.create_tween()
	up.tween_property(l, "position:y", ground_y - 250.0 - 140.0, 0.27).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	up.tween_property(l, "position:y", ground_y - 250.0, 0.27).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	q.queue_free()
	await _wait(0.7)
	if skipped:
		return

	# the winner swings - the slash is a flying waffle
	var swing := w.create_tween()
	w.pivot_offset = w.size / 2.0
	swing.tween_property(w, "rotation", -0.35, 0.12)
	swing.tween_property(w, "rotation", 0.15, 0.08)
	_shake(6.0, 0.25)
	var slash := _waffle_shape(Vector2(170, 170))
	slash.position = Vector2(860.0, ground_y - 260.0)
	_stage.add_child(slash)
	slash.pivot_offset = slash.size / 2.0
	var fly := slash.create_tween().set_parallel(true)
	fly.tween_property(slash, "position:x", l.position.x + l.size.x / 2.0 - 85.0, 0.35)
	fly.tween_property(slash, "rotation", -TAU, 0.35)
	var trail := _text("SWOOSH", 54, Color(0.2, 0.15, 0.1), 0)
	trail.rotation = -0.2
	_stage.add_child(trail)
	_center(trail, Vector2(700.0, ground_y - 330.0))
	await _wait(0.36)
	if skipped:
		return
	slash.queue_free()
	trail.queue_free()

	# impact: the loser is cut into a waffle grid of 9 pieces
	_flash(0.3)
	_shake(18.0, 0.5)
	var tex: Texture2D = l.texture
	var origin := l.position
	var psz := l.size
	l.queue_free()
	var cell := psz / 3.0
	for gx in 3:
		for gy in 3:
			var piece: Control
			if tex != null:
				var tr := TextureRect.new()
				var at := AtlasTexture.new()
				var ts := tex.get_size()
				at.atlas = tex
				at.region = Rect2(Vector2(gx, gy) * ts / 3.0, ts / 3.0)
				tr.texture = at
				tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
				tr.stretch_mode = TextureRect.STRETCH_SCALE
				tr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
				piece = tr
			else:
				var cr := ColorRect.new()
				cr.color = Color(0.9, 0.7, 0.3)
				piece = cr
			piece.size = cell
			piece.mouse_filter = Control.MOUSE_FILTER_IGNORE
			piece.position = origin + Vector2(gx, gy) * cell
			_stage.add_child(piece)
			var off := Vector2(gx - 1, gy - 1) * 7.0
			piece.create_tween().tween_property(piece, "position", piece.position + off, 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			var edge := Panel.new() # golden waffle border around each piece
			var sb := StyleBoxFlat.new()
			sb.bg_color = Color(0, 0, 0, 0)
			sb.border_color = Color(0.85, 0.6, 0.2)
			sb.set_border_width_all(3)
			edge.add_theme_stylebox_override("panel", sb)
			edge.size = cell
			edge.mouse_filter = Control.MOUSE_FILTER_IGNORE
			piece.add_child(edge)
	var butter := ColorRect.new() # a pat of butter on top
	butter.color = Color(1.0, 0.95, 0.5)
	butter.size = Vector2(46, 34)
	butter.position = origin + psz / 2.0 - butter.size / 2.0 + Vector2(0, -20)
	_stage.add_child(butter)
	_pop(butter, 0.3)
	var wt := _text("WAFFLED!", 110, Color(1, 0.8, 0.25), 16)
	_stage.add_child(wt)
	_center(wt, Vector2(SCREEN.x / 2.0, 190.0))
	wt.rotation = -0.06
	_pop(wt, 0.3)
	await _wait(2.2)

# A square golden waffle: grid of dimples on a toasted slab.
func _waffle_shape(size: Vector2) -> Control:
	var root := ColorRect.new()
	root.color = Color(0.9, 0.66, 0.25)
	root.size = size
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for i in range(1, 4):
		for horiz in [true, false]:
			var ln := ColorRect.new()
			ln.color = Color(0.6, 0.38, 0.12)
			ln.mouse_filter = Control.MOUSE_FILTER_IGNORE
			if horiz:
				ln.position = Vector2(0, size.y * i / 4.0 - 4.0)
				ln.size = Vector2(size.x, 8.0)
			else:
				ln.position = Vector2(size.x * i / 4.0 - 4.0, 0)
				ln.size = Vector2(8.0, size.y)
			root.add_child(ln)
	var border := Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0)
	sb.border_color = Color(0.35, 0.2, 0.05)
	sb.set_border_width_all(8)
	border.add_theme_stylebox_override("panel", sb)
	border.size = size
	border.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(border)
	return root

# Waits `t` seconds, or less if the player skipped.
func _wait(t: float) -> void:
	var left := t
	while left > 0.0 and not skipped:
		await get_tree().process_frame
		left -= get_process_delta_time()

func _clear_stage() -> void:
	for c in _stage.get_children():
		c.queue_free()

# White flash that fades out (used for cuts and impacts).
func _flash(time: float = 0.35) -> void:
	_flash_rect.modulate.a = 1.0
	_flash_rect.create_tween().tween_property(_flash_rect, "modulate:a", 0.0, time)

# Jolts the whole picture around, calming down over `time` seconds.
func _shake(strength: float, time: float) -> void:
	var tw := _stage.create_tween()
	var n := maxi(int(time / 0.04), 1)
	for i in n:
		var k := strength * (1.0 - float(i) / n)
		tw.tween_property(_stage, "position", Vector2(randf_range(-k, k), randf_range(-k, k)), 0.04)
	tw.tween_property(_stage, "position", Vector2.ZERO, 0.04)

# Springs a node up from nothing (scales around its middle).
func _pop(node: Control, time: float = 0.25) -> void:
	node.pivot_offset = node.size / 2.0
	node.scale = Vector2.ZERO
	node.create_tween().tween_property(node, "scale", Vector2.ONE, time).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

# Little jumps in place.
func _hop(node: Control, times: int, height: float, each: float) -> void:
	var y0 := node.position.y
	var tw := node.create_tween()
	for i in times:
		tw.tween_property(node, "position:y", y0 - height, each / 2.0).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw.tween_property(node, "position:y", y0, each / 2.0).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)

func _text(txt: String, size: int, color: Color, outline: int = 10) -> Label:
	var l := Label.new()
	l.text = txt
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", outline)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

# Centres a label on a point (call AFTER add_child).
func _center(l: Label, at: Vector2) -> void:
	l.reset_size()
	l.size = l.get_combined_minimum_size()
	l.position = at - l.size / 2.0
	l.pivot_offset = l.size / 2.0

func _panel(r: Rect2, bg: Color, border: Color, border_w: int, radius: int) -> Panel:
	var p := Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(border_w)
	sb.set_corner_radius_all(radius)
	p.add_theme_stylebox_override("panel", sb)
	p.position = r.position
	p.size = r.size
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return p

# A fighter's picture at a given height (width follows the picture's shape).
func _portrait_rect(stats: Dictionary, height: float) -> TextureRect:
	var tex: Texture2D = MatchScreens.portrait(stats)
	var tr := TextureRect.new()
	tr.texture = tex
	var aspect := 0.625
	if tex != null:
		aspect = tex.get_size().x / tex.get_size().y
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_SCALE
	tr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	tr.size = Vector2(height * aspect, height)
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return tr

# The defeated look: a red X (white outline) over the eyes of a picture `pic_size` big.
func _x_marks(pic_size: Vector2) -> Node2D:
	var root := Node2D.new()
	var c := Vector2(pic_size.x * 0.5, pic_size.y * FACE_Y)
	var h := pic_size.x * 0.17
	var w := pic_size.x * 0.07
	for pass_i in 2:
		for dir in [1.0, -1.0]:
			var ln := Line2D.new()
			ln.width = w + 6.0 * (pic_size.x / 80.0) if pass_i == 0 else w
			ln.default_color = Color.WHITE if pass_i == 0 else Color(0.9, 0.08, 0.1)
			ln.points = PackedVector2Array([c + Vector2(-h, -h * dir), c + Vector2(h, h * dir)])
			ln.begin_cap_mode = Line2D.LINE_CAP_ROUND
			ln.end_cap_mode = Line2D.LINE_CAP_ROUND
			root.add_child(ln)
	root.position = Vector2.ZERO
	return root

# One half of a cut picture: the same texture drawn through a polygon (UVs are
# in picture pixels), plus a cream edge along the cut so it reads as a clean
# slice. `a` -> `b` is the cut line.
func _half(tex: Texture2D, pts: Array, a: Vector2, b: Vector2) -> Node2D:
	var root := Node2D.new()
	var poly := Polygon2D.new()
	poly.texture = tex
	poly.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	poly.polygon = PackedVector2Array(pts)
	poly.uv = PackedVector2Array(pts)
	root.add_child(poly)
	var edge := Line2D.new()
	edge.width = 2.5
	edge.default_color = Color(1.0, 0.96, 0.85)
	edge.points = PackedVector2Array([a, b])
	root.add_child(edge)
	return root

# A comic speech bubble: black-outlined white ellipse with a pointed tail to `tip`.
# Returns the bubble (a Control centred on `center`, so _pop works on it).
func _bubble(parent: Control, center: Vector2, size: Vector2, tip: Vector2, txt: String) -> Control:
	var root := Control.new()
	root.position = center
	root.size = Vector2.ZERO
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(root)
	var a := size.x / 2.0
	var b := size.y / 2.0
	var ring := PackedVector2Array()
	for i in 56:
		ring.append(Vector2(cos(TAU * i / 56.0) * a, sin(TAU * i / 56.0) * b))
	var local_tip := tip - center
	var dir := local_tip.normalized()
	var perp := Vector2(-dir.y, dir.x)
	var base := Vector2(dir.x * a, dir.y * b) * 0.85 # where the tail grows out, just inside the edge
	var tail_w := 30.0
	var black_tail := Polygon2D.new()
	black_tail.color = Color.BLACK
	black_tail.polygon = PackedVector2Array([base + perp * (tail_w + 8.0), local_tip + dir * 8.0, base - perp * (tail_w + 8.0)])
	root.add_child(black_tail)
	var outline := Polygon2D.new()
	outline.color = Color.BLACK
	outline.polygon = ring
	root.add_child(outline)
	var fill := Polygon2D.new()
	fill.color = Color.WHITE
	var inner := PackedVector2Array()
	for p in ring:
		inner.append(p * 0.95)
	fill.polygon = inner
	root.add_child(fill)
	var white_tail := Polygon2D.new() # starts inside the white fill, so it opens the outline where the tail joins
	white_tail.color = Color.WHITE
	white_tail.polygon = PackedVector2Array([base + perp * tail_w, local_tip - dir * 2.0, base - perp * tail_w])
	root.add_child(white_tail)
	var label := Label.new()
	label.text = txt
	label.add_theme_font_size_override("font_size", 58)
	label.add_theme_color_override("font_color", Color(0.05, 0.05, 0.08))
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.size = size * 0.8
	label.position = -size * 0.4
	root.add_child(label)
	return root

# Pulls the cartoon "slot machine" colours out into rays behind everything.
func _backdrop(base: Color, ray: Color, center: Vector2, rays: int) -> void:
	var bg := ColorRect.new()
	bg.color = base
	bg.size = SCREEN
	_stage.add_child(bg)
	var root := Node2D.new()
	root.position = center
	_stage.add_child(root)
	for i in rays:
		var a0 := TAU * i / rays
		var a1 := TAU * (i + 0.5) / rays
		var tri := Polygon2D.new()
		tri.color = ray
		tri.polygon = PackedVector2Array([Vector2.ZERO, Vector2(cos(a0), sin(a0)) * 1600.0, Vector2(cos(a1), sin(a1)) * 1600.0])
		root.add_child(tri)
	root.create_tween().set_loops().tween_property(root, "rotation", TAU, 14.0).as_relative()

# Rainbow confetti burst.
func _confetti(at: Vector2) -> void:
	var p := CPUParticles2D.new()
	p.position = at
	p.amount = 70
	p.lifetime = 1.8
	p.one_shot = true
	p.explosiveness = 1.0
	p.direction = Vector2(0, -1)
	p.spread = 70.0
	p.initial_velocity_min = 300.0
	p.initial_velocity_max = 650.0
	p.gravity = Vector2(0, 900)
	p.scale_amount_min = 5.0
	p.scale_amount_max = 10.0
	var rainbow := Gradient.new() # each piece of confetti starts with a random colour from this
	rainbow.colors = PackedColorArray([Color(1, 0.3, 0.3), Color(1, 0.85, 0.2), Color(0.3, 0.9, 0.4), Color(0.3, 0.6, 1), Color(0.8, 0.4, 1)])
	rainbow.offsets = PackedFloat32Array([0.0, 0.25, 0.5, 0.75, 1.0])
	p.color_initial_ramp = rainbow
	p.angular_velocity_min = -400.0
	p.angular_velocity_max = 400.0
	_stage.add_child(p)
	p.emitting = true
