class_name CharacterRoster
extends RefCounted
## THE place to add characdters. Nothing else in the project needs editing
## when you add one - GameManager.characters is built from _wdefinitions()
## below (see autoload/GameManager.gd), and Character Select, CPU Setup,
## the HUD and the match spawner (game.gd) all read that finished array.
##dede
## Why this exists: before, every character was a ~12 line dictionary
## pasted in by hand, and a typo like "dammage" silently fell back to the
## default value because player.gd reads everything withrrrrreeffe .get(key, default).
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
# "bio" is a one-line description shown in the Almanac (main menu).
const META_KEYS := ["id", "name", "color", "based_on", "attacks", "face_color", "ui_color", "frames", "bio"]

# The eight moves player.gd's _do_attack() knows how to run - see the
# "Four attack directions" and "Specials" comments at the top of player.gd for
# which button combo triggers which.
const MOVE_NAMES := ["neutral", "up", "down", "back",
	"special_neutral", "special_side", "special_up", "special_down"]
# "name" is the move's display name in the Almanac (e.g. "Fireball Punch") - it doesn't affect gameplay.
const MOVE_KEYS := ["name", "damage", "kb_base", "kb_scale", "range", "startup", "active", "cooldown", "hits", "angle"]

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
#this math stuff pmo like holy had to resort to my goat gemini to help me make this bit
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
##wwwwwwwwwwwwww I hate this stuff 
## My template for a character 
## Gonna attempt making special moves so then I can make more characters
##	{
##		"id": "purple",                      # unique, lowercase, no spaces
##		"name": "Guy Purple",                # shows on Character Select + HUD
##		"color": Color(0.6, 0.25, 0.85),
##		"based_on": "red",                   # starts as a copy of Guy Red
##		"weight": 1.6,                       # heavier = knocked back less
##		"speed": 230.0,
##		"attacks": {
			#normal moves
##			"neutral": {"damage": 20.0, "cooldown": 0.8},   # only what changes
##			"up":      {"angle": 90.0},
		#specials (prolly use G as special button)
		#"special_neutral": {"damage":16.0, "kb_base": 180.0, "range": 60.0, "startup": 0.25, "cooldown": 0.9},
		#"special_side": {"damage":12.0, "angle": 20.0, "range": 80.0, "startup": 0.15},
		#"special_up": {"damage":8.0, "angle": 90.0, "range": 40.0, "hits": 3},
		#"special_down": {"damage":18.0, "kb_base": 60.0,"startup": 0.25, "cooldown": 1.2},
##		},
	#}
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
			"name": "Connell",
			"bio": "Heavy bruiser: slow to start, brutal when it lands.",
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
						"special_neutral": {"name": "Haymaker", "damage": 24.0, "kb_base": 220.0, "kb_scale": 9.0, "range": 40.0, "startup": 0.35, "active": 0.12, "cooldown": 0.9, "angle": 40.0},
						"special_side": {"name": "Shoulder Charge", "damage": 16.0, "kb_base": 170.0, "kb_scale": 7.0, "range": 70.0, "startup": 0.18, "active": 0.2, "cooldown": 0.7, "angle": 25.0},
						"special_up": {"name": "Rising Fist", "damage": 14.0, "kb_base": 190.0, "kb_scale": 7.5, "range": 36.0, "startup": 0.15, "active": 0.14, "cooldown": 0.7, "angle": 88.0},
						"special_down": {"name": "Ground Pound", "damage": 18.0, "kb_base": 160.0, "kb_scale": 7.0, "range": 50.0, "startup": 0.3, "active": 0.16, "cooldown": 1.0, "angle": 70.0},
			},
		},
		{
			"id": "blue",
			"name": "Guy Blue",
			"bio": "Fast all-rounder with quick, safe moves.",
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
						"special_neutral": {"name": "Rapid Jabs", "damage": 9.0, "kb_base": 60.0, "kb_scale": 4.0, "range": 30.0, "startup": 0.08, "active": 0.25, "cooldown": 0.45, "hits": 3, "angle": 30.0},
						"special_side": {"name": "Dash Slash", "damage": 13.0, "kb_base": 140.0, "kb_scale": 6.0, "range": 75.0, "startup": 0.1, "active": 0.12, "cooldown": 0.5, "angle": 25.0},
						"special_up": {"name": "Skyward Slash", "damage": 12.0, "kb_base": 150.0, "kb_scale": 6.5, "range": 40.0, "startup": 0.08, "active": 0.14, "cooldown": 0.5, "angle": 85.0},
						"special_down": {"name": "Low Sweep", "damage": 10.0, "kb_base": 120.0, "kb_scale": 5.5, "range": 55.0, "startup": 0.1, "active": 0.14, "cooldown": 0.45, "angle": 20.0},
			},
		},
		{
			"id": "green",
			"name": "Nick",
			"bio": "Reach fighter: hits from far away but is slow to react.",
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
						"special_neutral": {"name": "Long Reach", "damage": 13.0, "kb_base": 170.0, "kb_scale": 6.5, "range": 90.0, "startup": 0.22, "active": 0.16, "cooldown": 0.8, "angle": 35.0},
						"special_side": {"name": "Lance Thrust", "damage": 15.0, "kb_base": 180.0, "kb_scale": 7.0, "range": 100.0, "startup": 0.25, "active": 0.16, "cooldown": 0.85, "angle": 22.0},
						"special_up": {"name": "Sky Spear", "damage": 12.0, "kb_base": 160.0, "kb_scale": 6.5, "range": 70.0, "startup": 0.2, "active": 0.16, "cooldown": 0.75, "angle": 85.0},
						"special_down": {"name": "Root Trap", "damage": 10.0, "kb_base": 140.0, "kb_scale": 6.0, "range": 80.0, "startup": 0.2, "active": 0.16, "cooldown": 0.8, "angle": 60.0},
			},
		},
		{
			"id": "yellow",
			"name": "Chud",
			"bio": "Light and floaty. Wins with fast multi-hit combos.",
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
						"special_neutral": {"name": "Spark Flurry", "damage": 8.0, "kb_base": 40.0, "kb_scale": 3.5, "range": 28.0, "startup": 0.1, "active": 0.5, "cooldown": 0.6, "hits": 5, "angle": 40.0},
						"special_side": {"name": "Lightning Dash", "damage": 10.0, "kb_base": 100.0, "kb_scale": 5.0, "range": 60.0, "startup": 0.06, "active": 0.1, "cooldown": 0.45, "angle": 30.0},
						"special_up": {"name": "Updraft", "damage": 7.0, "kb_base": 70.0, "kb_scale": 4.0, "range": 34.0, "startup": 0.06, "active": 0.2, "cooldown": 0.5, "hits": 2, "angle": 88.0},
						"special_down": {"name": "Static Burst", "damage": 9.0, "kb_base": 100.0, "kb_scale": 5.0, "range": 45.0, "startup": 0.12, "active": 0.12, "cooldown": 0.5, "angle": 50.0},
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
			"bio": "Yellow's quiet twin - same speed and floatiness, shadowy specials.",
			"based_on": "yellow",
			"attacks": {
				"special_neutral": {"name": "Shadow Flurry", "damage": 9.0, "kb_base": 45.0, "kb_scale": 4.0, "range": 28.0, "startup": 0.1, "active": 0.5, "cooldown": 0.6, "hits": 5, "angle": 40.0},
				"special_side": {"name": "Night Dash", "damage": 11.0, "kb_base": 110.0, "kb_scale": 5.0, "range": 65.0, "startup": 0.06, "active": 0.1, "cooldown": 0.45, "angle": 30.0},
				"special_up": {"name": "Dusk Updraft", "damage": 8.0, "kb_base": 75.0, "kb_scale": 4.0, "range": 34.0, "startup": 0.06, "active": 0.2, "cooldown": 0.5, "hits": 2, "angle": 88.0},
				"special_down": {"name": "Void Burst", "damage": 10.0, "kb_base": 110.0, "kb_scale": 5.0, "range": 45.0, "startup": 0.12, "active": 0.12, "cooldown": 0.5, "angle": 50.0},
			},
		},
		{
			"id": "purple",
			"name": "Guy Purple",
			"color": Color(0.6, 0.25, 0.85),
			"bio": "Slow, heavy mage with big, slow-moving special attacks.",
			"based_on": "red",
			"weight": 1.6,
			"speed": 230.0,
			"attacks": {
				# normal moves (the attack button, F)
				"neutral": {"damage": 20.0, "cooldown": 0.8},
				"up":      {"angle": 90.0},

				# specials (the new special button, G)
				"special_neutral": {"name": "Arcane Blast", "damage": 16.0, "kb_base": 180.0, "range": 60.0, "startup": 0.25, "cooldown": 0.9},
				"special_side":    {"name": "Void Slash", "damage": 12.0, "angle": 20.0, "range": 80.0, "startup": 0.15},
				"special_up":      {"name": "Star Spiral", "damage": 8.0,  "angle": 90.0, "range": 40.0, "hits": 3},
				"special_down":    {"name": "Meteor Drop", "damage": 18.0, "angle": 60.0, "startup": 0.3, "cooldown": 1.2},
			},
		},

		# ---- The rest of the roster (colors + stats + named specials) ----
		{
			"id": "orange",
			"name": "Guy Orange",
			"color": Color(1.0, 0.45, 0.1),
			"bio": "A fiery brawler who wins by landing one big hit.",
			"based_on": "red",
			"speed": 280.0,
			"weight": 1.3,
			"attacks": {
				"special_neutral": {"name": "Fireball Punch", "damage": 22.0, "kb_base": 210.0, "kb_scale": 8.5, "range": 55.0, "startup": 0.3, "active": 0.14, "cooldown": 0.9, "angle": 35.0},
				"special_side": {"name": "Blazing Rush", "damage": 15.0, "kb_base": 170.0, "kb_scale": 7.0, "range": 85.0, "startup": 0.15, "active": 0.22, "cooldown": 0.7, "angle": 25.0},
				"special_up": {"name": "Flame Uppercut", "damage": 16.0, "kb_base": 190.0, "kb_scale": 8.0, "range": 38.0, "startup": 0.14, "active": 0.16, "cooldown": 0.8, "angle": 85.0},
				"special_down": {"name": "Magma Slam", "damage": 20.0, "kb_base": 170.0, "kb_scale": 8.0, "range": 55.0, "startup": 0.32, "active": 0.16, "cooldown": 1.1, "angle": 65.0},
			},
		},
		{
			"id": "pink",
			"name": "Guy Pink",
			"color": Color(1.0, 0.55, 0.75),
			"bio": "Light and bouncy. Floats around poking from the air.",
			"based_on": "blue",
			"speed": 330.0,
			"gravity_scale": 0.8,
			"extra_jumps": 2,
			"weight": 0.85,
			"attacks": {
				"special_neutral": {"name": "Bubble Pop", "damage": 8.0, "kb_base": 45.0, "kb_scale": 3.5, "range": 45.0, "startup": 0.12, "active": 0.4, "cooldown": 0.7, "hits": 4, "angle": 40.0},
				"special_side": {"name": "Cotton Dash", "damage": 9.0, "kb_base": 120.0, "kb_scale": 5.0, "range": 70.0, "startup": 0.08, "active": 0.12, "cooldown": 0.45, "angle": 30.0},
				"special_up": {"name": "Balloon Rise", "damage": 7.0, "kb_base": 100.0, "kb_scale": 4.5, "range": 36.0, "startup": 0.08, "active": 0.2, "cooldown": 0.5, "hits": 2, "angle": 88.0},
				"special_down": {"name": "Pillow Drop", "damage": 12.0, "kb_base": 130.0, "kb_scale": 5.5, "range": 45.0, "startup": 0.18, "active": 0.14, "cooldown": 0.7, "angle": 55.0},
			},
		},
		{
			"id": "teal",
			"name": "Guy Teal",
			"color": Color(0.1, 0.6, 0.6),
			"bio": "Zoner: keeps opponents at arm's length with long water attacks.",
			"based_on": "blue",
			"speed": 305.0,
			"attacks": {
				"special_neutral": {"name": "Water Whip", "damage": 12.0, "kb_base": 150.0, "kb_scale": 6.0, "range": 90.0, "startup": 0.22, "active": 0.16, "cooldown": 0.75, "angle": 35.0},
				"special_side": {"name": "Tidal Sweep", "damage": 14.0, "kb_base": 170.0, "kb_scale": 6.5, "range": 110.0, "startup": 0.3, "active": 0.18, "cooldown": 0.9, "angle": 20.0},
				"special_up": {"name": "Geyser", "damage": 11.0, "kb_base": 150.0, "kb_scale": 6.0, "range": 60.0, "startup": 0.2, "active": 0.16, "cooldown": 0.8, "angle": 88.0},
				"special_down": {"name": "Whirlpool", "damage": 9.0, "kb_base": 60.0, "kb_scale": 4.0, "range": 70.0, "startup": 0.18, "active": 0.35, "cooldown": 0.9, "hits": 3, "angle": 50.0},
			},
		},
		{
			"id": "brown",
			"name": "Veeraj",
			"color": Color(0.5, 0.3, 0.15),
			"bio": "Slow tank. Very hard to launch and hits like a truck.",
			"based_on": "red",
			"speed": 235.0,
			"jump_velocity": -540.0,
			"gravity_scale": 1.2,
			"weight": 1.7,
			"attacks": {
				"special_neutral": {"name": "Boulder Smash", "damage": 28.0, "kb_base": 240.0, "kb_scale": 10.0, "range": 45.0, "startup": 0.5, "active": 0.14, "cooldown": 1.3, "angle": 40.0},
				"special_side": {"name": "Bulldoze", "damage": 20.0, "kb_base": 200.0, "kb_scale": 8.0, "range": 80.0, "startup": 0.3, "active": 0.25, "cooldown": 1.0, "angle": 22.0},
				"special_up": {"name": "Tree Toss", "damage": 18.0, "kb_base": 210.0, "kb_scale": 9.0, "range": 40.0, "startup": 0.3, "active": 0.16, "cooldown": 1.0, "angle": 88.0},
				"special_down": {"name": "Earthquake", "damage": 22.0, "kb_base": 180.0, "kb_scale": 8.0, "range": 70.0, "startup": 0.45, "active": 0.2, "cooldown": 1.3, "angle": 75.0},
			},
		},
		{
			"id": "white",
			"name": "Guy White",
			"color": Color(0.95, 0.95, 0.95),
			"bio": "Precise and clean. Every move comes out quickly.",
			"based_on": "blue",
			"speed": 340.0,
			"weight": 0.95,
			"attacks": {
				"special_neutral": {"name": "Flash Jab", "damage": 7.0, "kb_base": 70.0, "kb_scale": 4.5, "range": 32.0, "startup": 0.04, "active": 0.16, "cooldown": 0.35, "hits": 2, "angle": 35.0},
				"special_side": {"name": "Glint Slash", "damage": 10.0, "kb_base": 120.0, "kb_scale": 5.5, "range": 65.0, "startup": 0.05, "active": 0.1, "cooldown": 0.4, "angle": 30.0},
				"special_up": {"name": "Halo Rise", "damage": 9.0, "kb_base": 120.0, "kb_scale": 5.5, "range": 38.0, "startup": 0.06, "active": 0.12, "cooldown": 0.4, "angle": 86.0},
				"special_down": {"name": "Frost Edge", "damage": 8.0, "kb_base": 100.0, "kb_scale": 5.0, "range": 50.0, "startup": 0.06, "active": 0.12, "cooldown": 0.4, "angle": 20.0},
			},
		},
		{
			"id": "gray",
			"name": "Guy Gray",
			"color": Color(0.5, 0.5, 0.55),
			"bio": "Steady defender with long, reliable normals.",
			"based_on": "green",
			"weight": 1.2,
			"attacks": {
				"special_neutral": {"name": "Iron Poke", "damage": 14.0, "kb_base": 170.0, "kb_scale": 6.5, "range": 70.0, "startup": 0.2, "active": 0.14, "cooldown": 0.7, "angle": 35.0},
				"special_side": {"name": "Steel Charge", "damage": 16.0, "kb_base": 180.0, "kb_scale": 7.0, "range": 85.0, "startup": 0.22, "active": 0.2, "cooldown": 0.8, "angle": 25.0},
				"special_up": {"name": "Anvil Lift", "damage": 13.0, "kb_base": 170.0, "kb_scale": 6.5, "range": 55.0, "startup": 0.18, "active": 0.14, "cooldown": 0.7, "angle": 88.0},
				"special_down": {"name": "Shield Bash", "damage": 15.0, "kb_base": 160.0, "kb_scale": 6.5, "range": 60.0, "startup": 0.2, "active": 0.14, "cooldown": 0.8, "angle": 45.0},
			},
		},
		{
			"id": "cyan",
			"name": "Guy Cyan",
			"color": Color(0.2, 0.85, 0.95),
			"bio": "Flurry specialist: lots of fast, weak hits that add up.",
			"based_on": "yellow",
			"speed": 370.0,
			"attacks": {
				"special_neutral": {"name": "Ice Needles", "damage": 10.0, "kb_base": 40.0, "kb_scale": 3.5, "range": 40.0, "startup": 0.12, "active": 0.5, "cooldown": 0.7, "hits": 5, "angle": 40.0},
				"special_side": {"name": "Frost Dash", "damage": 11.0, "kb_base": 110.0, "kb_scale": 5.0, "range": 75.0, "startup": 0.06, "active": 0.12, "cooldown": 0.45, "angle": 28.0},
				"special_up": {"name": "Snow Spiral", "damage": 9.0, "kb_base": 50.0, "kb_scale": 3.5, "range": 40.0, "startup": 0.08, "active": 0.3, "cooldown": 0.6, "hits": 3, "angle": 88.0},
				"special_down": {"name": "Icicle Drop", "damage": 12.0, "kb_base": 130.0, "kb_scale": 5.5, "range": 40.0, "startup": 0.14, "active": 0.14, "cooldown": 0.6, "angle": 70.0},
			},
		},
		{
			"id": "lime",
			"name": "Guy Lime",
			"color": Color(0.65, 0.9, 0.2),
			"bio": "Tricky and bouncy. Its moves launch at odd angles.",
			"based_on": "green",
			"gravity_scale": 0.9,
			"extra_jumps": 2,
			"attacks": {
				"special_neutral": {"name": "Slime Splat", "damage": 11.0, "kb_base": 130.0, "kb_scale": 5.5, "range": 60.0, "startup": 0.16, "active": 0.14, "cooldown": 0.6, "angle": 60.0},
				"special_side": {"name": "Gloop Slide", "damage": 12.0, "kb_base": 130.0, "kb_scale": 5.5, "range": 80.0, "startup": 0.12, "active": 0.2, "cooldown": 0.6, "angle": 10.0},
				"special_up": {"name": "Sprout Spring", "damage": 10.0, "kb_base": 80.0, "kb_scale": 4.5, "range": 50.0, "startup": 0.1, "active": 0.2, "cooldown": 0.6, "hits": 2, "angle": 80.0},
				"special_down": {"name": "Goo Trap", "damage": 8.0, "kb_base": 120.0, "kb_scale": 5.0, "range": 70.0, "startup": 0.2, "active": 0.14, "cooldown": 0.8, "angle": 90.0},
			},
		},
		{
			"id": "navy",
			"name": "Guy Navy",
			"color": Color(0.1, 0.15, 0.5),
			"bio": "Patient fighter. Terrifying when he hits first.",
			"based_on": "blue",
			"speed": 300.0,
			"weight": 1.15,
			"attacks": {
				"special_neutral": {"name": "Anchor Swing", "damage": 20.0, "kb_base": 200.0, "kb_scale": 8.0, "range": 55.0, "startup": 0.35, "active": 0.14, "cooldown": 1.0, "angle": 30.0},
				"special_side": {"name": "Wave Crash", "damage": 16.0, "kb_base": 180.0, "kb_scale": 7.0, "range": 90.0, "startup": 0.25, "active": 0.2, "cooldown": 0.9, "angle": 25.0},
				"special_up": {"name": "Lighthouse", "damage": 14.0, "kb_base": 190.0, "kb_scale": 7.0, "range": 45.0, "startup": 0.22, "active": 0.14, "cooldown": 0.8, "angle": 86.0},
				"special_down": {"name": "Depth Charge", "damage": 18.0, "kb_base": 180.0, "kb_scale": 7.5, "range": 50.0, "startup": 0.35, "active": 0.14, "cooldown": 1.1, "angle": 60.0},
			},
		},
		{
			"id": "maroon",
			"name": "Leo Chuddong",
			"color": Color(0.5, 0.1, 0.15),
			"bio": "Hits hard, recovers slowly. Punishable but scary.",
			"based_on": "red",
			"speed": 270.0,
			"weight": 1.35,
			"attacks": {
				"special_neutral": {"name": "Grudge Slam", "damage": 20.0, "kb_base": 200.0, "kb_scale": 8.0, "range": 40.0, "startup": 0.3, "active": 0.12, "cooldown": 1.0, "angle": 40.0},
				"special_side": {"name": "Heavy Tackle", "damage": 17.0, "kb_base": 180.0, "kb_scale": 7.5, "range": 75.0, "startup": 0.2, "active": 0.22, "cooldown": 0.85, "angle": 25.0},
				"special_up": {"name": "Meteor Rise", "damage": 15.0, "kb_base": 190.0, "kb_scale": 7.5, "range": 40.0, "startup": 0.2, "active": 0.14, "cooldown": 0.85, "angle": 88.0},
				"special_down": {"name": "Crater Stomp", "damage": 19.0, "kb_base": 170.0, "kb_scale": 7.5, "range": 55.0, "startup": 0.35, "active": 0.16, "cooldown": 1.1, "angle": 70.0},
			},
		},
		{
			"id": "gold",
			"name": "Booster Gold",
			"color": Color(0.78, 0.58, 0.12),
			"bio": "Greedy speedster: fast, light and always in the air.",
			"based_on": "yellow",
			"speed": 395.0,
			"extra_jumps": 3,
			"weight": 0.75,
			"attacks": {
				"special_neutral": {"name": "Coin Flurry", "damage": 9.0, "kb_base": 45.0, "kb_scale": 3.5, "range": 34.0, "startup": 0.08, "active": 0.4, "cooldown": 0.6, "hits": 4, "angle": 40.0},
				"special_side": {"name": "Gilded Dash", "damage": 12.0, "kb_base": 120.0, "kb_scale": 5.0, "range": 80.0, "startup": 0.05, "active": 0.1, "cooldown": 0.4, "angle": 28.0},
				"special_up": {"name": "Sunburst", "damage": 10.0, "kb_base": 80.0, "kb_scale": 4.5, "range": 42.0, "startup": 0.08, "active": 0.2, "cooldown": 0.55, "hits": 2, "angle": 88.0},
				"special_down": {"name": "Gold Rush", "damage": 11.0, "kb_base": 110.0, "kb_scale": 5.0, "range": 48.0, "startup": 0.1, "active": 0.12, "cooldown": 0.5, "angle": 60.0},
			},
		},
		{
			"id": "silver",
			"name": "Chud Choi",
			"color": Color(0.72, 0.75, 0.8),
			"bio": "Sharp edge, quick feet. A swordfighter's rhythm.",
			"based_on": "blue",
			"speed": 325.0,
			"attacks": {
				"special_neutral": {"name": "Blade Dance", "damage": 11.0, "kb_base": 100.0, "kb_scale": 5.0, "range": 52.0, "startup": 0.1, "active": 0.22, "cooldown": 0.55, "hits": 2, "angle": 35.0},
				"special_side": {"name": "Slash Rush", "damage": 13.0, "kb_base": 130.0, "kb_scale": 5.5, "range": 90.0, "startup": 0.08, "active": 0.12, "cooldown": 0.5, "angle": 25.0},
				"special_up": {"name": "Rising Edge", "damage": 12.0, "kb_base": 130.0, "kb_scale": 5.5, "range": 46.0, "startup": 0.08, "active": 0.12, "cooldown": 0.5, "angle": 86.0},
				"special_down": {"name": "Cross Slash", "damage": 10.0, "kb_base": 110.0, "kb_scale": 5.0, "range": 55.0, "startup": 0.1, "active": 0.12, "cooldown": 0.5, "angle": 30.0},
			},
		},
		{
			"id": "coral",
			"name": "Guy Coral",
			"color": Color(1.0, 0.45, 0.4),
			"bio": "Sea dweller with wide arcs and long sweeping attacks.",
			"based_on": "green",
			"speed": 280.0,
			"attacks": {
				"special_neutral": {"name": "Tentacle Lash", "damage": 12.0, "kb_base": 140.0, "kb_scale": 6.0, "range": 80.0, "startup": 0.18, "active": 0.2, "cooldown": 0.7, "angle": 30.0},
				"special_side": {"name": "Reef Rush", "damage": 13.0, "kb_base": 150.0, "kb_scale": 6.0, "range": 95.0, "startup": 0.2, "active": 0.2, "cooldown": 0.8, "angle": 22.0},
				"special_up": {"name": "Bubble Column", "damage": 10.0, "kb_base": 50.0, "kb_scale": 3.5, "range": 50.0, "startup": 0.12, "active": 0.3, "cooldown": 0.8, "hits": 3, "angle": 88.0},
				"special_down": {"name": "Undertow", "damage": 11.0, "kb_base": 120.0, "kb_scale": 5.5, "range": 75.0, "startup": 0.18, "active": 0.16, "cooldown": 0.75, "angle": 15.0},
			},
		},
		{
			"id": "mint",
			"name": "Luk3y",
			"color": Color(0.6, 0.95, 0.75),
			"bio": "Cool-headed all-rounder. No weaknesses, no tricks *touches you violently*",
			"based_on": "blue",
			"attacks": {
				"special_neutral": {"name": "Fresh Burst", "damage": 14.0, "kb_base": 160.0, "kb_scale": 6.5, "range": 50.0, "startup": 0.18, "active": 0.14, "cooldown": 0.65, "angle": 35.0},
				"special_side": {"name": "Breeze Dash", "damage": 12.0, "kb_base": 140.0, "kb_scale": 6.0, "range": 70.0, "startup": 0.1, "active": 0.14, "cooldown": 0.55, "angle": 25.0},
				"special_up": {"name": "Cool Gust", "damage": 12.0, "kb_base": 140.0, "kb_scale": 6.0, "range": 45.0, "startup": 0.12, "active": 0.12, "cooldown": 0.55, "angle": 85.0},
				"special_down": {"name": "Chill Drop", "damage": 13.0, "kb_base": 140.0, "kb_scale": 6.0, "range": 50.0, "startup": 0.16, "active": 0.14, "cooldown": 0.6, "angle": 65.0},
			},
		},
		{
			"id": "indigo",
			"name": "Guy Indigo",
			"color": Color(0.3, 0.2, 0.65),
			"bio": "Mystic with odd timing and long-range magic.",
			"based_on": "blue",
			"speed": 310.0,
			"gravity_scale": 0.85,
			"weight": 0.9,
			"attacks": {
				"special_neutral": {"name": "Hex Bolt", "damage": 15.0, "kb_base": 170.0, "kb_scale": 7.0, "range": 70.0, "startup": 0.3, "active": 0.12, "cooldown": 0.9, "angle": 40.0},
				"special_side": {"name": "Phase Dash", "damage": 11.0, "kb_base": 130.0, "kb_scale": 5.5, "range": 90.0, "startup": 0.1, "active": 0.14, "cooldown": 0.55, "angle": 25.0},
				"special_up": {"name": "Star Beam", "damage": 12.0, "kb_base": 150.0, "kb_scale": 6.0, "range": 55.0, "startup": 0.18, "active": 0.14, "cooldown": 0.7, "angle": 88.0},
				"special_down": {"name": "Void Drop", "damage": 17.0, "kb_base": 190.0, "kb_scale": 7.5, "range": 45.0, "startup": 0.35, "active": 0.14, "cooldown": 1.1, "angle": 75.0},
			},
		},
		{
			"id": "crimson",
			"name": "Guy Crimson",
			"color": Color(0.7, 0.05, 0.2),
			"bio": "Aggressive rushdown: surprisingly fast for a heavy.",
			"based_on": "red",
			"speed": 315.0,
			"weight": 1.1,
			"attacks": {
				"special_neutral": {"name": "Blood Rush", "damage": 16.0, "kb_base": 180.0, "kb_scale": 7.0, "range": 45.0, "startup": 0.18, "active": 0.14, "cooldown": 0.7, "angle": 35.0},
				"special_side": {"name": "Crimson Charge", "damage": 15.0, "kb_base": 170.0, "kb_scale": 7.0, "range": 90.0, "startup": 0.12, "active": 0.22, "cooldown": 0.65, "angle": 25.0},
				"special_up": {"name": "Red Rise", "damage": 14.0, "kb_base": 170.0, "kb_scale": 7.0, "range": 40.0, "startup": 0.12, "active": 0.14, "cooldown": 0.65, "angle": 86.0},
				"special_down": {"name": "Scarlet Stomp", "damage": 16.0, "kb_base": 160.0, "kb_scale": 7.0, "range": 50.0, "startup": 0.22, "active": 0.16, "cooldown": 0.8, "angle": 68.0},
			},
		},
		{
			"id": "olive",
			"name": "Guy Olive",
			"color": Color(0.45, 0.5, 0.15),
			"bio": "Camouflaged trapper. Slow, sneaky, and patient.",
			"based_on": "green",
			"speed": 255.0,
			"attacks": {
				"special_neutral": {"name": "Ambush", "damage": 18.0, "kb_base": 200.0, "kb_scale": 8.0, "range": 50.0, "startup": 0.38, "active": 0.1, "cooldown": 1.0, "angle": 38.0},
				"special_side": {"name": "Creeping Vine", "damage": 10.0, "kb_base": 120.0, "kb_scale": 5.0, "range": 100.0, "startup": 0.3, "active": 0.25, "cooldown": 0.9, "angle": 20.0},
				"special_up": {"name": "Branch Snap", "damage": 12.0, "kb_base": 150.0, "kb_scale": 6.0, "range": 55.0, "startup": 0.2, "active": 0.14, "cooldown": 0.75, "angle": 85.0},
				"special_down": {"name": "Mine", "damage": 15.0, "kb_base": 170.0, "kb_scale": 7.0, "range": 40.0, "startup": 0.3, "active": 0.14, "cooldown": 1.0, "angle": 80.0},
			},
		},
		{
			"id": "peach",
			"name": "Guy Peach",
			"color": Color(1.0, 0.75, 0.55),
			"bio": "Gentle but speedy. All about stringing combos together.",
			"based_on": "yellow",
			"weight": 0.85,
			"attacks": {
				"special_neutral": {"name": "Soft Flurry", "damage": 7.0, "kb_base": 40.0, "kb_scale": 3.0, "range": 30.0, "startup": 0.06, "active": 0.35, "cooldown": 0.5, "hits": 4, "angle": 40.0},
				"special_side": {"name": "Blossom Dash", "damage": 9.0, "kb_base": 100.0, "kb_scale": 4.5, "range": 65.0, "startup": 0.06, "active": 0.12, "cooldown": 0.45, "angle": 30.0},
				"special_up": {"name": "Petal Lift", "damage": 8.0, "kb_base": 60.0, "kb_scale": 3.5, "range": 38.0, "startup": 0.06, "active": 0.2, "cooldown": 0.5, "hits": 2, "angle": 88.0},
				"special_down": {"name": "Pit Drop", "damage": 10.0, "kb_base": 100.0, "kb_scale": 4.5, "range": 40.0, "startup": 0.12, "active": 0.12, "cooldown": 0.55, "angle": 62.0},
			},
		},
		{
			"id": "violet",
			"name": "Guy Violet",
			"color": Color(0.78, 0.55, 0.98),
			"bio": "Purple's lighter cousin: big magic, a little less weight.",
			"based_on": "purple",
			"speed": 245.0,
			"weight": 1.5,
			"attacks": {
				"special_neutral": {"name": "Dark Orb", "damage": 18.0, "kb_base": 190.0, "kb_scale": 7.5, "range": 70.0, "startup": 0.3, "active": 0.12, "cooldown": 0.9, "angle": 35.0},
				"special_side": {"name": "Shadow Step", "damage": 13.0, "kb_base": 150.0, "kb_scale": 6.0, "range": 90.0, "startup": 0.12, "active": 0.14, "cooldown": 0.6, "angle": 25.0},
				"special_up": {"name": "Dusk Rise", "damage": 10.0, "kb_base": 60.0, "kb_scale": 4.0, "range": 45.0, "startup": 0.1, "active": 0.3, "cooldown": 0.6, "hits": 3, "angle": 88.0},
				"special_down": {"name": "Eclipse", "damage": 20.0, "kb_base": 190.0, "kb_scale": 8.0, "range": 50.0, "startup": 0.35, "active": 0.14, "cooldown": 1.2, "angle": 60.0},
			},
		},
		{
			"id": "azure",
			"name": "Guy Azure",
			"color": Color(0.5, 0.8, 1.0),
			"bio": "Wind rider. Floaty, quick, and hard to pin down.",
			"based_on": "blue",
			"speed": 340.0,
			"gravity_scale": 0.75,
			"extra_jumps": 2,
			"weight": 0.9,
			"attacks": {
				"special_neutral": {"name": "Gale Strike", "damage": 11.0, "kb_base": 130.0, "kb_scale": 5.5, "range": 55.0, "startup": 0.14, "active": 0.12, "cooldown": 0.55, "angle": 30.0},
				"special_side": {"name": "Jet Stream", "damage": 10.0, "kb_base": 110.0, "kb_scale": 5.0, "range": 100.0, "startup": 0.08, "active": 0.16, "cooldown": 0.6, "angle": 18.0},
				"special_up": {"name": "Cyclone", "damage": 9.0, "kb_base": 55.0, "kb_scale": 3.5, "range": 50.0, "startup": 0.1, "active": 0.3, "cooldown": 0.7, "hits": 3, "angle": 88.0},
				"special_down": {"name": "Downdraft", "damage": 12.0, "kb_base": 130.0, "kb_scale": 5.5, "range": 55.0, "startup": 0.14, "active": 0.12, "cooldown": 0.6, "angle": 75.0},
			},
		},
		{
			"id": "rose",
			"name": "Guy Rose",
			"color": Color(0.9, 0.2, 0.5),
			"bio": "Thorny. Long reach and punishing counters.",
			"based_on": "green",
			"speed": 285.0,
			"attacks": {
				"special_neutral": {"name": "Thorn Whip", "damage": 13.0, "kb_base": 160.0, "kb_scale": 6.5, "range": 85.0, "startup": 0.2, "active": 0.14, "cooldown": 0.7, "angle": 35.0},
				"special_side": {"name": "Briar Rush", "damage": 14.0, "kb_base": 160.0, "kb_scale": 6.5, "range": 95.0, "startup": 0.18, "active": 0.2, "cooldown": 0.75, "angle": 22.0},
				"special_up": {"name": "Bloom", "damage": 12.0, "kb_base": 90.0, "kb_scale": 4.5, "range": 55.0, "startup": 0.16, "active": 0.2, "cooldown": 0.7, "hits": 2, "angle": 86.0},
				"special_down": {"name": "Spike Patch", "damage": 11.0, "kb_base": 140.0, "kb_scale": 6.0, "range": 70.0, "startup": 0.22, "active": 0.14, "cooldown": 0.85, "angle": 75.0},
			},
		},
		{
			"id": "slate",
			"name": "Me67",
			"color": Color(0.35, 0.4, 0.5),
			"bio": "Stone-faced wall. Rarely moves far, never moves back.",
			"based_on": "red",
			"speed": 250.0,
			"jump_velocity": -560.0,
			"extra_jumps": 0,
			"weight": 1.5,
			"attacks": {
				"special_neutral": {"name": "Rock Fist", "damage": 21.0, "kb_base": 210.0, "kb_scale": 8.5, "range": 42.0, "startup": 0.4, "active": 0.12, "cooldown": 1.1, "angle": 38.0},
				"special_side": {"name": "Landslide", "damage": 17.0, "kb_base": 190.0, "kb_scale": 7.5, "range": 90.0, "startup": 0.28, "active": 0.24, "cooldown": 0.9, "angle": 22.0},
				"special_up": {"name": "Stone Spire", "damage": 15.0, "kb_base": 190.0, "kb_scale": 7.5, "range": 42.0, "startup": 0.24, "active": 0.14, "cooldown": 0.9, "angle": 88.0},
				"special_down": {"name": "Quake", "damage": 20.0, "kb_base": 180.0, "kb_scale": 8.0, "range": 60.0, "startup": 0.4, "active": 0.16, "cooldown": 1.2, "angle": 72.0},
			},
		},
		{
			"id": "amber",
			"name": "Guy Amber",
			"color": Color(0.95, 0.68, 0.1),
			"bio": "Air mobility king. Glows brightest while airborne.",
			"based_on": "yellow",
			"jump_velocity": -660.0,
			"gravity_scale": 0.65,
			"extra_jumps": 2,
			"attacks": {
				"special_neutral": {"name": "Honey Burst", "damage": 9.0, "kb_base": 50.0, "kb_scale": 3.5, "range": 40.0, "startup": 0.1, "active": 0.3, "cooldown": 0.6, "hits": 3, "angle": 40.0},
				"special_side": {"name": "Glow Dash", "damage": 11.0, "kb_base": 110.0, "kb_scale": 5.0, "range": 85.0, "startup": 0.07, "active": 0.12, "cooldown": 0.5, "angle": 26.0},
				"special_up": {"name": "Beacon", "damage": 9.0, "kb_base": 70.0, "kb_scale": 4.0, "range": 44.0, "startup": 0.08, "active": 0.2, "cooldown": 0.55, "hits": 2, "angle": 88.0},
				"special_down": {"name": "Amber Trap", "damage": 13.0, "kb_base": 130.0, "kb_scale": 5.5, "range": 50.0, "startup": 0.16, "active": 0.12, "cooldown": 0.7, "angle": 70.0},
			},
		},

		# ADD NEW CHARACTERS HERE (copy the template from the big comment
		# above this function). 
		#TS took me way too long to make
		
	]
