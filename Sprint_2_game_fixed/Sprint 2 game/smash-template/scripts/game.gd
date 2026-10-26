extends Node2D
## Spawns fighters onto the stage: you (P1) plus however many CPU slots
## are toggled on (local mode, up to 3 CPUs), or you + one networked
## opponent (online mode). Also builds and updates the bottom Smash-style
## HUD (name / damage% / stock pips per fighter).
## This is the script on the root of Game.tscn - every match, local or
## online, is this scene. It's loaded by cpu_setup.gd (local) or
## character_select.gd's _maybe_start_match() (online).

const PLAYER_SCENE := preload("res://scenes/Player.tscn")
# The Marker2D nodes inside Stage.tscn, in P1..P4 order. _spawn_pos() looks
# them up by these exact names, so renaming a marker in the Stage scene
# means renaming it here too.
const SPAWN_NAMES := ["SpawnP1", "SpawnP2", "SpawnP3", "SpawnP4"]

# Node paths into Game.tscn. players_root is the node every fighter gets
# added under; hud_entries_box is the HBoxContainer in the bottom bar where
# _build_hud() adds one column per fighter.
@onready var stage: Node2D = $Stage
@onready var players_root: Node2D = $Players
@onready var hud_entries_box: HBoxContainer = $HUD/BottomBar/Entries

# One dictionary per fighter, made by _build_hud() and read every frame by
# _process() - holds the fighter plus the UI labels/boxes that show their stats.
var hud_entries: Array = []
# Online mode only: local_player is the fighter THIS machine controls,
# remote_player is the puppet of the other player. Both stay null in local mode.
var local_player: SmashPlayer
var remote_player: SmashPlayer

func _ready() -> void:
	# selected_mode was set earlier by mode_select.gd / online_lobby.gd.
	if GameManager.selected_mode == GameManager.Mode.ONLINE:
		_setup_online()
	else:
		_setup_local()

# Runs on a fixed timer (60 times a second by default). In online mode this
# is how the other player finds out where we are: our position/velocity/
# damage/stocks go out as a "state" message every physics frame, and the
# other machine feeds it to SmashPlayer.apply_remote_state() through its
# own _on_network_message() below. The is_instance_valid check stops it
# once our fighter has been freed (out of stocks).
func _physics_process(_delta: float) -> void:
	if GameManager.selected_mode == GameManager.Mode.ONLINE and local_player != null and is_instance_valid(local_player):
		NetworkManager.send({
			"type": "state",
			"x": local_player.global_position.x, "y": local_player.global_position.y,
			"vx": local_player.velocity.x, "vy": local_player.velocity.y,
			"dmg": local_player.damage_percent, "stocks": local_player.stocks,
			"facing": local_player.facing,
		})

# Refreshes the HUD every rendered frame by polling each fighter. Polling
# (instead of the fighter telling the HUD) is why SmashPlayer's `ko` signal
# has nothing connected to it - this just checks the numbers each frame.
func _process(_delta: float) -> void:
	for entry in hud_entries:
		var f = entry["fighter"]
		var percent_label: Label = entry["percent_label"]
		# A fighter that ran out of stocks was queue_free()'d (see
		# SmashPlayer._on_ko), so the reference is dead - show "KO" and zero pips.
		if f == null or not is_instance_valid(f):
			percent_label.text = "KO"
			_set_stock_count(entry, 0)
			continue
		percent_label.text = "%d%%" % int(f.damage_percent)
		_set_stock_count(entry, f.stocks)

# Local match: you are always P1 (spawn marker 0, WASD+F); each enabled CPU
# slot from GameManager.cpu_slots becomes the next fighter.
func _setup_local() -> void:
	var fighters: Array = []
	fighters.append(_spawn_player(_spawn_pos(0), "p1_", false, GameManager.player1_character))

	# slot_index is the NEXT free spawn marker, not the CPU slot number - if
	# CPU 1 is OFF but CPU 2 is ON, CPU 2 still takes the SpawnP2 marker.
	var slot_index := 1
	for slot in GameManager.cpu_slots:
		if not slot["enabled"]:
			continue
		if slot_index >= SPAWN_NAMES.size():
			break # only 4 spawn markers exist on the Stage
		# "cpu_1_", "cpu_2_"... (never actually read as input - see
		# player.gd's input_prefix comment)
		var prefix := "cpu_%d_" % slot_index
		fighters.append(_spawn_player(_spawn_pos(slot_index), prefix, true, slot["character"]))
		slot_index += 1

	_link_opponents(fighters)
	_build_hud(fighters)

func _setup_online() -> void:
	NetworkManager.message_received.connect(_on_network_message)
	NetworkManager.peer_left.connect(_on_opponent_left)

	# Both players picked in CharacterSelect.tscn before landing here -
	# player1_character is always "my own pick", online_opponent_character
	# is whatever the other player sent over the relay. Host is always P1,
	# the joining player is always P2.
	var my_char: int = GameManager.player1_character
	var opp_char: int = GameManager.online_opponent_character
	var p1_char: int = my_char if NetworkManager.is_host else opp_char
	var p2_char: int = opp_char if NetworkManager.is_host else my_char

	# Online players are on separate physical keyboards, so both always
	# read WASD+F ("p1_") locally - there's no reason to make the joiner
	# use the P2 arrow-key layout meant for sharing one keyboard. The
	# remote player's input_prefix is never actually read (see the
	# is_remote guard in player.gd's _physics_process), so it's harmless
	# for both spawned nodes to use "p1_" here.
	var p1 := _spawn_player(_spawn_pos(0), "p1_", false, p1_char)
	var p2 := _spawn_player(_spawn_pos(1), "p1_", false, p2_char)

	if NetworkManager.is_host:
		local_player = p1
		remote_player = p2
	else:
		local_player = p2
		remote_player = p1
	# The remote player isn't simulated locally at all - it's just a
	# puppet driven entirely by "state" messages from the other machine
	# (see SmashPlayer.apply_remote_state and the is_remote guard in
	# player.gd's _physics_process).
	remote_player.is_remote = true

	_link_opponents([p1, p2])
	_build_hud([p1, p2])

# Every message from the other player lands here (NetworkManager's
# message_received signal, connected in _setup_online). Two kinds, matching
# the two things SmashPlayer/game.gd send: "state" (their position etc.,
# sent from _physics_process above) and "hit" (sent from player.gd's
# _on_hitbox_body_entered when THEIR swing connects with OUR puppet).
func _on_network_message(data: Dictionary) -> void:
	if remote_player == null or not is_instance_valid(remote_player):
		return
	match data.get("type", ""):
		"state":
			remote_player.apply_remote_state(data)
		"hit":
			# We're the authority on our own fighter, so the hit is applied
			# to local_player here - the damage then reaches the other
			# machine through our next "state" broadcast.
			if local_player != null and is_instance_valid(local_player):
				local_player.take_hit(
					data.get("damage", 0.0), int(data.get("from_dir", 1)),
					data.get("kb_base", 150.0), data.get("kb_scale", 6.0), data.get("angle", 35.0)
				)

# The relay told us the other player disconnected (NetworkManager.peer_left).
func _on_opponent_left() -> void:
	if remote_player != null and is_instance_valid(remote_player):
		remote_player.is_remote = false # stop waiting on packets that won't arrive

# Looks up where spawn marker number `index` (0 = SpawnP1 ...) sits in the Stage.
func _spawn_pos(index: int) -> Vector2:
	return stage.get_node(SPAWN_NAMES[index]).position

# Gives every fighter the list of everyone ELSE. SmashPlayer's CPU brain
# reads this (player.gd's _nearest_opponent) to pick who to chase.
func _link_opponents(fighters: Array) -> void:
	for f in fighters:
		var others: Array = fighters.duplicate()
		others.erase(f)
		f.opponents = others

# Creates one fighter from Player.tscn and drops it onto the stage.
# char_index is a position in GameManager.characters (built in
# scripts/character_roster.gd). The order matters: stats/prefix/is_cpu are
# set BEFORE add_child(), because SmashPlayer._ready() runs the moment it
# joins the tree and needs stats already filled in.
func _spawn_player(pos: Vector2, prefix: String, is_cpu: bool, char_index: int) -> SmashPlayer:
	var p: SmashPlayer = PLAYER_SCENE.instantiate()
	p.input_prefix = prefix
	p.is_cpu = is_cpu
	p.stats = GameManager.characters[char_index]
	p.global_position = pos
	players_root.add_child(p)
	return p

# Makes one HUD column per fighter: name on top, big damage % in the
# middle, row of stock squares underneath. Only creates the widgets once -
# the numbers are kept up to date by _process() and _set_stock_count().
func _build_hud(fighters: Array) -> void:
	for f in fighters:
		# ui_color (from character_roster.gd) is the body color, except
		# very dark characters get a lightened one so their name and
		# pips are readable on the dark bottom bar.
		var color: Color = f.stats.get("ui_color", f.stats.get("color", Color.WHITE))

		var vbox := VBoxContainer.new()
		vbox.custom_minimum_size = Vector2(120, 0)
		vbox.alignment = BoxContainer.ALIGNMENT_CENTER

		var name_label := Label.new()
		name_label.text = f.stats.get("name", "???")
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name_label.modulate = color
		vbox.add_child(name_label)

		var percent_label := Label.new()
		percent_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		percent_label.add_theme_font_size_override("font_size", 30)
		percent_label.text = "0%"
		vbox.add_child(percent_label)

		var stocks_box := HBoxContainer.new()
		stocks_box.alignment = BoxContainer.ALIGNMENT_CENTER
		stocks_box.add_theme_constant_override("separation", 4)
		vbox.add_child(stocks_box)

		hud_entries_box.add_child(vbox)
		# Everything _process() / _set_stock_count() need for this fighter.
		# last_stocks starts at -1 so the very first _set_stock_count call
		# always draws the pips (no real stock count is ever -1).
		hud_entries.append({
			"fighter": f,
			"percent_label": percent_label,
			"stocks_box": stocks_box,
			"color": color,
			"last_stocks": -1,
		})

# Redraws one fighter's row of stock squares, but only when the number
# actually changed - this runs every frame from _process(), and rebuilding
# the squares 60 times a second for nothing would be wasteful.
func _set_stock_count(entry: Dictionary, count: int) -> void:
	if entry["last_stocks"] == count:
		return
	entry["last_stocks"] = count
	var box: HBoxContainer = entry["stocks_box"]
	for child in box.get_children():
		child.queue_free()
	for i in count:
		var dot := ColorRect.new()
		dot.custom_minimum_size = Vector2(14, 14)
		dot.color = entry["color"]
		box.add_child(dot)
		
		
