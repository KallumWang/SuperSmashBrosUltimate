extends Node
## Holds state that needs to survive scene changes: which mode was picked,
## who's a CPU, and every character's stats/moveset.
## (This is an autoload - registered in project.godot under [autoload] - so
## any script can just write GameManager.something without loading it.)

enum Mode { LOCAL, ONLINE }

# Set by mode_select.gd / online_lobby.gd / cpu_setup.gd, read by game.gd's
# _ready() to decide between _setup_local() and _setup_online().
var selected_mode: int = Mode.LOCAL
# Index into the characters array below. Set by character_select.gd's
# _on_confirm_pressed(). In online mode this is always "my own pick", never
# the host's or the joiner's specifically - game.gd's _setup_online() sorts
# out who ends up as P1/P2.
var player1_character: int = 0
var is_cpu_p2: bool = false # currently unused - nothing reads it (CPUs are configured through cpu_slots below instead)
var online_opponent_character: int = 1 # (old 2-player value, no longer read - see online_picks below)
# Online matches (up to 4 players): slot number -> character index, filled in
# by character_select.gd once everyone has confirmed. game.gd's
# _setup_online() spawns one fighter per entry at that slot's spawn marker.
var online_picks: Dictionary = {}

# Up to 3 local CPU opponents for free-for-alls. Toggle "enabled" and
# change "character" on the CPU Opponents screen (cpu_setup.gd edits these
# dictionaries directly). game.gd's _setup_local() spawns one CPU per
# enabled slot, in this order, at SpawnP2/SpawnP3/SpawnP4 on the Stage.
# "character" is an index into the characters array, so it's looked up by
# id here - that way adding/reordering characters in character_roster.gd
# can't silently change which character each CPU starts as.
# "character" can also be RANDOM_CHARACTER (-1) meaning "pick a random
# character for this CPU" - game.gd's _setup_local() rolls the dice each
# time a match starts, so "Random" gives a different fighter every match.
const RANDOM_CHARACTER := -1
var cpu_slots: Array = [
	{"enabled": true, "character": 0}, # fixed up in _ready() below - needs "characters" to exist first
	{"enabled": false, "character": 0},
	{"enabled": false, "character": 0},
]

#Movement
# (start of this comment got cut off - it's describing a single character:
# every character is a dictionary of numbers that plug into)
# player.gd's physics directly. "attacks" has four moves - "neutral"
# (plain attack button), "up" (hold up/jump + attack), "down" (hold
# down + attack), and "back" (a pivot strike - reverse direction and
# hit attack in the same beat to strike behind you) - each with its own
# damage/knockback/range/angle, so different charactersplay
# differently.
# speed/jump_velocity/gravity_scale/extra_jumps - movement feel
# weight - how much knockback they take (lighter flies further)
# attacks.*.hits  - >1 means a quick multi-hit flurry
# attacks.*.angle - knockback launch angle in degrees
#Basically just the Character's stats TS THE MOST IMPORTANT COMMENT SORTA
# ^ all of the above is still true, but the stats themselves moved out of
# this file: to add or tweak a character, open scripts/character_roster.gd
# (there's a copy-paste template at the top of it). This line builds the
# finished array from that file one time when the game boots, and every
# other script (character_select.gd, cpu_setup.gd, game.gd, player.gd)
# keeps reading GameManager.characters[index] exactly like before.
var characters: Array = CharacterRoster.build()

func _ready() -> void:
	# The default CPU opponents: CPU 1 = Guy Blue, CPU 2 = Guy Green,
	# CPU 3 = Guy Yellow (same as the old hard-coded 1, 2, 3).
	cpu_slots[0]["character"] = character_index("blue")
	cpu_slots[1]["character"] = character_index("green")
	cpu_slots[2]["character"] = character_index("yellow")
	# Same default as before (index 1 = Guy Blue) for online mode's
	# opponent before the other player has actually picked.
	online_opponent_character = character_index("blue")

## Finds a character's position in the characters array from its "id" in
## character_roster.gd (e.g. character_index("blue") -> 1). Returns 0 and
## prints an error if the id doesn't exist, so a typo can't crash the game.
func character_index(id: String) -> int:
	for i in characters.size():
		if characters[i]["id"] == id:
			return i
	push_error("GameManager.character_index: no character with id \"%s\" in character_roster.gd" % id)
	return 0
