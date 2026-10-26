class_name CharacterRoster
extends RefCounted
## THE place to add characters. Nothing else in the project needs editing
## when you add one - GameManager.characters is built from _definitions()
## below (see autoload/GameManager.gd), and Character Select, CPU Setup,
## the HUD and the match spawner (game.gd) all read that finished array.
##
## Why this exists: before, every character was a ~12 line dictionary
## pasted in by hand, and a typo like "dammage" silently fell back to the
## default value because player.gd reads everything with .get(key, default).
## Now you only write what's DIFFERENT about a character:
##   - "based_on": "yellow"  copies every stat + move from an earlier
##                           character first (Guy Black is just Guy Yellow
##                           with a new color - that's 4 lines instead of 20)
##   - anything you leave out falls back to BASE_STATS / BASE_MOVE below
##   - "attacks" only needs the moves/fields you want to change
##   - typos and bad values get a warning in the Godot Output panel when the
##     game boots (see _check_keys / _check_values)

# Every key a character is allowed to have at the top level. Anything else
# triggers a warning (this is what catches typos).
const STAT_KEYS := ["speed", "jump_velocity", "gravity_scale", "extra_jumps", "weight"]
const META_KEYS := ["id", "name", "color", "based_on", "attacks", "face_color", "ui_color", "frames"]

# The four moves player.gd's _do_attack() knows how to run - see the
# "Four attack directions" comment at the top of player.gd for which
# button combo triggers which.
const MOVE_NAMES := ["neutral", "up", "down", "back"]
const MOVE_KEYS := ["damage", "kb_base", "kb_scale", "range", "startup", "active", "cooldown", "hits", "angle"]

# What a brand new character gets for anything you don't specify. These
# are the same "middle of the road" numbers as the fallback in player.gd
# (DEFAULT_ATTACK) so a half-filled-in character still plays sensibly.
const BASE_STATS := {
	"speed": 300.0,
	"jump_velocity": -600.0,
	"gravity_scale": 1.0,
	"extra_jumps": 1,
	"weight": 1.0,
}
const BASE_MOVE := {
	"damage": 12.0, "kb_base": 150.0, "kb_scale": 6.0, "range": 30.0,
	"startup": 0.06, "active": 0.12, "cooldown": 0.4, "hits": 1, "angle": 35.0,
}

## Called once, by GameManager, when the game boots. Returns the finished
## Array of character dictionaries - same shape GameManager.characters
## always had (name/color/speed/.../attacks), plus the new "id",
## "face_color" and "ui_color" keys. The array ORDER is the order they
## appear in Character Select, and the index is what gets sent over the
## network in online mode (see character_select.gd's _on_confirm_pressed).
static func build() -> Array:
	var roster: Array = []
	var by_id: Dictionary = {} # id -> finished character, so "based_on" can find earlier ones
	for def in _definitions():
		var built: Dictionary = _build_one(def, by_id)
		if built.is_empty():
			continue # _build_one already printed why - skip it instead of crashing the whole game
		by_id[built["id"]] = built
		roster.append(built)
	return roster

## Turns one short definition into a full character dictionary.
static func _build_one(def: Dictionary, by_id: Dictionary) -> Dictionary:
	var id: String = str(def.get("id", ""))
	if id == "":
		push_error("CharacterRoster: a character is missing its \"id\" (the short lowercase name, e.g. \"red\"): %s" % [def])
		return {}
	if by_id.has(id):
		push_error("CharacterRoster: two characters share the id \"%s\" - ids have to be unique." % id)
		return {}
	if not def.has("name"):
		push_error("CharacterRoster: character \"%s\" is missing its \"name\"." % id)
		return {}

	_check_keys(id, def)

	var result: Dictionary = {}
	if def.has("based_on"):
		var parent_id: String = str(def["based_on"])
		if not by_id.has(parent_id):
			# Has to be defined EARLIER in _definitions() than the character using it.
			push_error("CharacterRoster: \"%s\" is based_on \"%s\" but no earlier character has that id." % [id, parent_id])
			return {}
		result = by_id[parent_id].duplicate(true) # deep copy so editing the child never touches the parent
		# These are worked out from the NEW color below, so a recolored
		# copy doesn't keep the parent's face/UI color by accident.
		result.erase("face_color")
		result.erase("ui_color")
	else:
		result = BASE_STATS.duplicate()
		result["attacks"] = {}
		for move_name in MOVE_NAMES:
			result["attacks"][move_name] = BASE_MOVE.duplicate()

	# Copy over everything this character explicitly sets.
	for key in def:
		if key == "attacks":
			var overrides: Dictionary = def["attacks"]
			for move_name in overrides:
				if not MOVE_NAMES.has(move_name):
					continue # _check_keys already warned about it
				for field in overrides[move_name]:
					result["attacks"][move_name][field] = overrides[move_name][field]
		elif key != "based_on":
			result[key] = def[key]

	if not result.has("color"):
		push_warning("CharacterRoster: \"%s\" has no \"color\" - using white. Add \"color\": Color(r, g, b)." % id)
		result["color"] = Color.WHITE

	# Auto-contrast so very dark characters (like Guy Black) stay readable:
	# - face_color: the little face square on the sprite + select screen.
	#   Black on a black body was invisible, so dark bodies get a white face.
	# - ui_color: used for the HUD name + stock pips (game.gd's _build_hud),
	#   because a pure black name on the dark bottom bar can't be read.
	# Set either one yourself in the definition to override the auto pick.
	var body: Color = result["color"]
	var is_dark: bool = body.get_luminance() < 0.2
	if not result.has("face_color"):
		result["face_color"] = Color.WHITE if is_dark else Color.BLACK
	if not result.has("ui_color"):
		result["ui_color"] = body.lightened(0.6) if is_dark else body

	_check_values(id, result)
	return result

## Warns about anything in a definition that isn't a known key - this is
## the typo catcher ("dammage", "attack", "wieght" ...).
static func _check_keys(id: String, def: Dictionary) -> void:
	for key in def:
		if not (STAT_KEYS.has(key) or META_KEYS.has(key)):
			push_warning("CharacterRoster: \"%s\" has an unknown key \"%s\" (it will be ignored by player.gd). Valid keys: %s" % [id, key, STAT_KEYS + META_KEYS])
	if def.has("attacks"):
		for move_name in def["attacks"]:
			if not MOVE_NAMES.has(move_name):
				push_warning("CharacterRoster: \"%s\" has an unknown move \"%s\". Valid moves: %s" % [id, move_name, MOVE_NAMES])
				continue
			for field in def["attacks"][move_name]:
				if not MOVE_KEYS.has(field):
					push_warning("CharacterRoster: \"%s\" move \"%s\" has an unknown field \"%s\". Valid fields: %s" % [id, move_name, field, MOVE_KEYS])

## Warns about numbers that would break the game feel / math. These are
## the ones that actually cause trouble: weight is divided by in
## player.gd's take_hit(), and hits is divided by in _do_attack().
static func _check_values(id: String, c: Dictionary) -> void:
	if float(c["weight"]) <= 0.0:
		push_warning("CharacterRoster: \"%s\" weight must be above 0 (take_hit() divides by it)." % id)
	if int(c["extra_jumps"]) < 0:
		push_warning("CharacterRoster: \"%s\" extra_jumps can't be negative." % id)
	for move_name in MOVE_NAMES:
		if int(c["attacks"][move_name]["hits"]) < 1:
			push_warning("CharacterRoster: \"%s\" move \"%s\" needs hits >= 1." % [id, move_name])
	if c.has("frames") and not ResourceLoader.exists(str(c["frames"])):
		push_warning("CharacterRoster: \"%s\" frames path \"%s\" doesn't exist - it'll fall back to the generated placeholder sprite." % [id, c["frames"]])

## ---------------------------------------------------------------------
## THE ROSTER - add new characters at the bottom of this list.
## ---------------------------------------------------------------------
##
## COPY-PASTE TEMPLATE for the quickest possible new character (a tweaked
## copy of an existing one). Delete any line you don't want to change:
##
##	{
##		"id": "purple",                      # unique, lowercase, no spaces
##		"name": "Guy Purple",                # shows on Character Select + HUD
##		"color": Color(0.6, 0.25, 0.85),
##		"based_on": "red",                   # starts as a copy of Guy Red
##		"weight": 1.6,                       # heavier = knocked back less
##		"speed": 230.0,
##		"attacks": {
##			"neutral": {"damage": 20.0, "cooldown": 0.8},   # only what changes
##			"up":      {"angle": 90.0},
##		},
##		# optional extras:
##		# "frames": "res://art/purple_frames.tres",   # your own SpriteFrames (see README)
##		# "face_color": Color.WHITE,                  # override the auto face color
##	},
##
## Stat meanings (these used to live as a comment above the dictionary in
## GameManager - they're the "Basically just the Character's stats" notes):
## speed / jump_velocity / gravity_scale / extra_jumps - movement feel, read
##   straight into player.gd's _physics_process
## weight - how much knockback they take (lighter flies further)
## attacks.*.hits  - >1 means a quick multi-hit flurry
## attacks.*.angle - knockback launch angle in degrees (0 flat, 90 straight up)
static func _definitions() -> Array:
	return [
		# The four original characters are written out in full so you have
		# a complete example of every number a character can have.
		{
			"id": "red",
			"name": "Guy Red",
			"color": Color(0.85, 0.2, 0.2),
			"speed": 290.0,
			"jump_velocity": -580.0,
			"gravity_scale": 1.1,
			"extra_jumps": 1,
			"weight": 1.2,
			"attacks": {
				"neutral": {"damage": 14.0, "kb_base": 170.0, "kb_scale": 7.0, "range": 34.0, "startup": 0.12, "active": 0.1, "cooldown": 0.55, "hits": 1, "angle": 35.0},
				"up":      {"damage": 15.0, "kb_base": 160.0, "kb_scale": 7.5, "range": 28.0, "startup": 0.14, "active": 0.12, "cooldown": 0.6, "hits": 1, "angle": 80.0},
				"down":    {"damage": 10.0, "kb_base": 120.0, "kb_scale": 5.0, "range": 30.0, "startup": 0.1, "active": 0.12, "cooldown": 0.5, "hits": 1, "angle": 15.0},
				"back":    {"damage": 12.0, "kb_base": 150.0, "kb_scale": 6.5, "range": 30.0, "startup": 0.08, "active": 0.1, "cooldown": 0.5, "hits": 1, "angle": 30.0},
			},
		},
		{
			"id": "blue",
			"name": "Guy Blue",
			"color": Color(0.2, 0.45, 0.9),
			"speed": 320.0,
			"jump_velocity": -620.0,
			"gravity_scale": 1.0,
			"extra_jumps": 1,
			"weight": 1.0,
			"attacks": {
				"neutral": {"damage": 10.0, "kb_base": 140.0, "kb_scale": 6.0, "range": 30.0, "startup": 0.06, "active": 0.1, "cooldown": 0.35, "hits": 1, "angle": 35.0},
				"up":      {"damage": 11.0, "kb_base": 150.0, "kb_scale": 6.5, "range": 26.0, "startup": 0.08, "active": 0.1, "cooldown": 0.4, "hits": 1, "angle": 75.0},
				"down":    {"damage": 8.0, "kb_base": 110.0, "kb_scale": 5.0, "range": 28.0, "startup": 0.06, "active": 0.1, "cooldown": 0.35, "hits": 1, "angle": 15.0},
				"back":    {"damage": 9.0, "kb_base": 130.0, "kb_scale": 5.5, "range": 28.0, "startup": 0.05, "active": 0.1, "cooldown": 0.35, "hits": 1, "angle": 30.0},
			},
		},
		{
			"id": "green",
			"name": "Guy Green",
			"color": Color(0.25, 0.75, 0.3),
			"speed": 270.0,
			"jump_velocity": -580.0,
			"gravity_scale": 1.05,
			"extra_jumps": 1,
			"weight": 1.05,
			"attacks": {
				"neutral": {"damage": 9.0, "kb_base": 130.0, "kb_scale": 5.5, "range": 52.0, "startup": 0.14, "active": 0.16, "cooldown": 0.5, "hits": 1, "angle": 35.0},
				"up":      {"damage": 10.0, "kb_base": 140.0, "kb_scale": 6.0, "range": 40.0, "startup": 0.16, "active": 0.16, "cooldown": 0.55, "hits": 1, "angle": 80.0},
				"down":    {"damage": 7.0, "kb_base": 100.0, "kb_scale": 4.5, "range": 46.0, "startup": 0.12, "active": 0.16, "cooldown": 0.45, "hits": 1, "angle": 10.0},
				"back":    {"damage": 8.0, "kb_base": 120.0, "kb_scale": 5.0, "range": 44.0, "startup": 0.1, "active": 0.14, "cooldown": 0.45, "hits": 1, "angle": 25.0},
			},
		},
		{
			"id": "yellow",
			"name": "Guy Yellow",
			"color": Color(0.95, 0.8, 0.15),
			"speed": 380.0,
			"jump_velocity": -640.0,
			"gravity_scale": 0.7,
			"extra_jumps": 2,
			"weight": 0.8,
			"attacks": {
				"neutral": {"damage": 3.0, "kb_base": 50.0, "kb_scale": 4.0, "range": 26.0, "startup": 0.04, "active": 0.3, "cooldown": 0.35, "hits": 3, "angle": 35.0},
				"up":      {"damage": 9.0, "kb_base": 130.0, "kb_scale": 6.0, "range": 24.0, "startup": 0.05, "active": 0.08, "cooldown": 0.3, "hits": 1, "angle": 85.0},
				"down":    {"damage": 6.0, "kb_base": 90.0, "kb_scale": 4.5, "range": 22.0, "startup": 0.04, "active": 0.1, "cooldown": 0.3, "hits": 1, "angle": 15.0},
				"back":    {"damage": 4.0, "kb_base": 70.0, "kb_scale": 4.0, "range": 24.0, "startup": 0.03, "active": 0.12, "cooldown": 0.3, "hits": 1, "angle": 30.0},
			},
		},

		# Guy Black used to be a full copy-paste of Guy Yellow (identical
		# stats on purpose). Now it just says "start from yellow" - and
		# if you retune Yellow later, Black follows unless you override it
		# here. Its face is auto-switched to white so you can see it.
		{
			"id": "black",
			"name": "Guy Black",
			"color": Color(0.0, 0.0, 0.0),
			"based_on": "yellow",
		},

		# ADD NEW CHARACTERS HERE (copy the template from the big comment
		# above this function).
	]
