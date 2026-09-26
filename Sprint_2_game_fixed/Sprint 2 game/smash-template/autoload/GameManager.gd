extends Node
## Holds state that needs to survive scene changes: which mode was picked,
## who's a CPU, and every character's stats/moveset.

enum Mode { LOCAL, ONLINE }

var selected_mode: int = Mode.LOCAL
var player1_character: int = 0
var is_cpu_p2: bool = false
var online_opponent_character: int = 1 # set once the other player picks in online Character Select

# Up to 3 local CPU opponents for free-for-alls. Toggle "enabled" and

var cpu_slots: Array = [
	{"enabled": true, "character": 1},
	{"enabled": false, "character": 2},
	{"enabled": false, "character": 3},
]

#Movement
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
var characters: Array = [
	{
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
	}, # Added missing closing bracket here
	{
		"name": "Guy black",
		"color": Color(0.0, 0.0, 0.0),
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
]
