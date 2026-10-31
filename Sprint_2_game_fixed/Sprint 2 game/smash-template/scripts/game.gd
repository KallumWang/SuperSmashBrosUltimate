extends Node2D
## Spawns fighters onto the stage: you (P1) plus however many CPU slots
## are toggled on (local mode, up to 3 CPUs), or up to 4 networked players
## (online mode: one fighter per relay slot). Also builds and updates the bottom Smash-style
## HUD (name / damage% / stock pips per fighter).
## This is the script on the root of Game.tscn - every match, local or
## online, is this scene. It's loaded by cpu_setup.gd (local) or
## character_select.gd's _maybe_start_match() (online).

const PLAYER_SCENE := preload("res://scenes/Player.tscn")
# The Marker2D nodes inside Stage.tscn, in P1..P4 order. _spawn_pos() looks
# them up by these exact names, so renaming a marker in the Stage scene
# means renaming it here too.
const SPAWN_NAMES := ["SpawnP1", "SpawnP2", "SpawnP3", "SpawnP4"]
# Name-tag colours, in P1..P4 order (same as Character Select's panels).
const TAG_COLORS := [
	Color(0.85, 0.15, 0.15), # P1 red
	Color(0.15, 0.4, 0.9),   # P2 blue
	Color(0.95, 0.75, 0.1),  # P3 yellow
	Color(0.2, 0.7, 0.25),   # P4 green
]

# Pre-/post-match screens (VS intro + podium) - see match_screens.gd.
const MatchScreens := preload("res://scripts/match_screens.gd")

# Node paths into Game.tscn. players_root is the node every fighter gets
# added under; hud_entries_box is the HBoxContainer in the bottom bar where
# _build_hud() adds one column per fighter.
@onready var stage: Node2D = $Stage
@onready var players_root: Node2D = $Players
@onready var hud_entries_box: HBoxContainer = $HUD/BottomBar/Entries

# One dictionary per fighter, made by _build_hud() and read every frame by
# _process() - holds the fighter plus the UI labels/boxes that show their stats.
var hud_entries: Array = []
# Same order as hud_entries: what the intro and podium screens need to show
# for each fighter (slot tag, name, colour, character) - see _note_fighter.
var _infos: Array = []
# Indexes (into hud_entries) of fighters in the order they were knocked out -
# the podium is built from this (last one out = 2nd place, and so on).
var _elim_order: Array = []
# relay slot (online) or spawn slot (local) -> index into hud_entries / _infos,
# so a message from "slot 2" knows whose HUD column to pop a bubble over.
var _entry_of_slot: Dictionary = {}
# Emote wheel (hold the emote key, scroll the mouse wheel, release to send).
var _wheel_layer: CanvasLayer
var _wheel_open: bool = false
var _wheel_sel: int = 0
var _wheel_cells: Array = []
var _bubbles: Dictionary = {} # entry index -> the bubble currently showing there
# Match-end state. The match ends when only one fighter is left (see
# _check_match_end); a short delay lets the final KO effect play first.
const END_DELAY := 1.2 # seconds between the last KO and the results screen
var _match_over: bool = false
var _end_timer: float = 0.0
# Online results screen: slot -> true for every player who pressed PLAY AGAIN.
# (The relay decides when everyone has - see "rematch_go" below.)
var _rematch_votes: Dictionary = {}
var _rematch_button: Button
var _rematch_label: Label

# Online mode only: local_player is the fighter THIS machine controls;
# remote_players maps relay slot (0-3) -> the puppet of that other player.
# local_player stays null and remote_players stays empty in local mode.
var local_player: SmashPlayer
var remote_players: Dictionary = {}

func _ready() -> void:
	# selected_mode was set earlier by mode_select.gd / online_lobby.gd.
	if GameManager.selected_mode == GameManager.Mode.ONLINE:
		_setup_online()
	else:
		_setup_local()
	# VS intro: freeze everyone, show the panels, then let the fight begin.
	# (Skipped for solo practice, and when a test sets the "skip_intro" meta.)
	if hud_entries.size() >= 2 and not GameManager.has_meta("skip_intro"):
		players_root.process_mode = Node.PROCESS_MODE_DISABLED
		await MatchScreens.play_intro(self, _infos)
		players_root.process_mode = Node.PROCESS_MODE_INHERIT

# Runs on a fixed timer (60 times a second by default). In online mode this
# is how the other player finds out where we are: our position/velocity/
# damage/stocks go out as a "state" message every physics frame, and the
# other machine feeds it to SmashPlayer.apply_remote_state() through its
# own _on_network_message() below. The is_instance_valid check stops it
# once our fighter has been freed (out of stocks).
func _physics_process(_delta: float) -> void:
	if GameManager.selected_mode == GameManager.Mode.ONLINE and local_player != null and is_instance_valid(local_player):
		NetworkManager.send(_state_message())

# What we tell the other players about our fighter (see SmashPlayer.apply_remote_state).
func _state_message() -> Dictionary:
	return {
		"type": "state",
		"x": local_player.global_position.x, "y": local_player.global_position.y,
		"vx": local_player.velocity.x, "vy": local_player.velocity.y,
		"dmg": local_player.damage_percent, "stocks": local_player.stocks,
		"facing": local_player.facing,
		# visuals for the other players' copy of us: shield bubble size, see-through (dodging), stunned
		"br": local_player.bubble_r, "gh": local_player.dodge_time > 0.0, "st": local_player.stun_time > 0.0, "tn": local_player.is_taunting,
	}

# Our fighter just lost a stock (SmashPlayer's `ko` signal, connected in
# _setup_online). Send the new state RIGHT NOW instead of waiting for the next
# physics frame: when it was the LAST stock the fighter is freed immediately,
# so without this the other players would never hear "stocks = 0" - they'd
# keep showing a ghost with 1 stock, and the match could never end.
func _on_local_ko(_player: Node) -> void:
	if local_player != null and is_instance_valid(local_player):
		NetworkManager.send(_state_message())

# Refreshes the HUD every rendered frame by polling each fighter. Polling
# (instead of the fighter telling the HUD) is why SmashPlayer's `ko` signal
# has nothing connected to it - this just checks the numbers each frame.
func _process(delta: float) -> void:
	_update_wheel()
	_track_eliminations()
	_check_match_end(delta)
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

# =====================================================================
# MATCH END + RESULTS SCREEN
# =====================================================================

# Fighters that are still in the match: not freed (KO'd out of stocks, or
# disconnected) and with stocks left.
func _alive_fighters() -> Array:
	var alive: Array = []
	for entry in hud_entries:
		var f = entry["fighter"]
		if f != null and is_instance_valid(f) and not f.is_queued_for_deletion() and f.stocks > 0:
			alive.append(f)
	return alive

# ---- Taunt bubbles + emote wheel ------------------------------------------

# The human fighter on THIS machine (online: local_player; local: P1).
func _my_slot() -> int:
	return NetworkManager.my_slot if GameManager.selected_mode == GameManager.Mode.ONLINE else 0

# Shows a bubble over `slot`'s stock, and (online) tells everyone else to do the same.
func _send_bubble(slot: int, text: String, is_taunt: bool) -> void:
	_show_bubble(_entry_of_slot.get(slot, -1), text, is_taunt)
	if GameManager.selected_mode == GameManager.Mode.ONLINE:
		NetworkManager.send({"type": "emote", "text": text, "taunt": is_taunt})

# The Mario Party-style pop-up: it springs up above the player's stock
# counter in the bottom bar (so it never covers the fight), stays a moment,
# then fades. A new one replaces the old one for that player.
func _show_bubble(entry_idx: int, text: String, is_taunt: bool) -> void:
	if entry_idx < 0 or entry_idx >= hud_entries.size() or text == "":
		return
	var old = _bubbles.get(entry_idx)
	if old != null and is_instance_valid(old):
		old.queue_free()
	var entry: Dictionary = hud_entries[entry_idx]
	var color: Color = _infos[entry_idx]["color"]
	var bubble := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(1, 1, 1, 0.96)
	sb.border_color = color
	sb.set_border_width_all(4)
	sb.set_corner_radius_all(14)
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	bubble.add_theme_stylebox_override("panel", sb)
	var label := Label.new()
	label.text = ("★ %s ★" % text.substr(0, 20)) if is_taunt else text.substr(0, 20)
	label.add_theme_font_size_override("font_size", 22)
	label.add_theme_color_override("font_color", Color(0.1, 0.1, 0.15))
	bubble.add_child(label)
	$HUD.add_child(bubble)
	bubble.reset_size()
	var box: Control = entry["box"]
	var rect := box.get_global_rect()
	var size := bubble.get_combined_minimum_size()
	bubble.size = size
	bubble.position = Vector2(rect.position.x + rect.size.x / 2.0 - size.x / 2.0, rect.position.y - size.y - 6.0)
	bubble.pivot_offset = Vector2(size.x / 2.0, size.y) # grows out of the stock counter
	bubble.scale = Vector2.ZERO
	_bubbles[entry_idx] = bubble
	var tw := bubble.create_tween()
	tw.tween_property(bubble, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_interval(1.5)
	tw.tween_property(bubble, "modulate:a", 0.0, 0.3)
	tw.tween_callback(bubble.queue_free)

# Opens / updates / fires the wheel. Only for the human on this machine.
func _update_wheel() -> void:
	if _match_over or not InputMap.has_action("p1_emote"):
		return
	var me = _my_fighter()
	var held: bool = Input.is_action_pressed("p1_emote") and me != null
	if held and not _wheel_open:
		_open_wheel()
	elif not held and _wheel_open:
		_close_wheel(true)

func _my_fighter():
	var online: bool = GameManager.selected_mode == GameManager.Mode.ONLINE
	var f = local_player if online else (hud_entries[0]["fighter"] if hud_entries.size() > 0 else null)
	return f if f != null and is_instance_valid(f) else null

func _open_wheel() -> void:
	_wheel_open = true
	_wheel_sel = 0
	if _wheel_layer == null:
		_build_wheel()
	_wheel_layer.visible = true
	_refresh_wheel()

func _close_wheel(send: bool) -> void:
	_wheel_open = false
	if _wheel_layer != null:
		_wheel_layer.visible = false
	if send and Emotes.is_filled(_wheel_sel):
		_send_bubble(_my_slot(), str(Emotes.SLOTS[_wheel_sel]["text"]), false)

# The mouse wheel turns the selection (up = clockwise) while the wheel is open.
func _unhandled_input(event: InputEvent) -> void:
	if not _wheel_open or not (event is InputEventMouseButton) or not event.pressed:
		return
	var n: int = Emotes.SLOTS.size()
	if event.button_index == MOUSE_BUTTON_WHEEL_UP:
		_wheel_sel = (_wheel_sel + 1) % n
	elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		_wheel_sel = (_wheel_sel - 1 + n) % n
	else:
		return
	_refresh_wheel()
	get_viewport().set_input_as_handled()

func _build_wheel() -> void:
	_wheel_layer = CanvasLayer.new()
	_wheel_layer.layer = 15
	add_child(_wheel_layer)
	var center := Vector2(640, 250)
	var ring := Control.new()
	ring.position = center
	_wheel_layer.add_child(ring)
	var n: int = Emotes.SLOTS.size()
	for i in n:
		var ang := -PI / 2.0 + TAU * i / n # slot 0 at the top, going clockwise
		var cell := PanelContainer.new()
		cell.custom_minimum_size = Vector2(86, 86)
		cell.size = Vector2(86, 86)
		cell.position = Vector2(cos(ang), sin(ang)) * 120.0 - cell.size / 2.0
		var content := VBoxContainer.new()
		content.alignment = BoxContainer.ALIGNMENT_CENTER
		cell.add_child(content)
		var icon := TextureRect.new()
		icon.custom_minimum_size = Vector2(44, 44)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		var path := str(Emotes.SLOTS[i].get("icon", ""))
		if path != "" and ResourceLoader.exists(path):
			icon.texture = load(path)
		content.add_child(icon)
		var lbl := Label.new()
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.add_theme_font_size_override("font_size", 13)
		lbl.text = str(Emotes.SLOTS[i].get("text", "")) if Emotes.is_filled(i) else "-"
		content.add_child(lbl)
		ring.add_child(cell)
		_wheel_cells.append(cell)
	var hint := Label.new()
	hint.text = "SCROLL"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 14)
	hint.position = Vector2(-40, -10)
	hint.size = Vector2(80, 20)
	ring.add_child(hint)

func _refresh_wheel() -> void:
	for i in _wheel_cells.size():
		var cell: PanelContainer = _wheel_cells[i]
		var sb := StyleBoxFlat.new()
		var chosen: bool = i == _wheel_sel
		sb.bg_color = Color(0.12, 0.13, 0.2, 0.92) if not chosen else Color(0.25, 0.22, 0.08, 0.95)
		sb.border_color = Color(1.0, 0.85, 0.3) if chosen else Color(0.4, 0.42, 0.55)
		sb.set_border_width_all(4 if chosen else 2)
		sb.set_corner_radius_all(43)
		cell.add_theme_stylebox_override("panel", sb)
		cell.modulate = Color.WHITE if Emotes.is_filled(i) else Color(1, 1, 1, 0.55)

# Notes WHO was knocked out and in what order (for the podium). A knocked-out
# fighter is freed, so a dead reference = out.
func _track_eliminations() -> void:
	for i in hud_entries.size():
		var f = hud_entries[i]["fighter"]
		if (f == null or not is_instance_valid(f)) and not _elim_order.has(i):
			_elim_order.append(i)

# Called every frame. A match with 2+ fighters ends once 1 (or 0) are left.
# A match that STARTS with just one fighter (local, no CPUs switched on) never
# ends, so you can still practise alone.
func _check_match_end(delta: float) -> void:
	if _match_over or hud_entries.size() < 2:
		return
	if _alive_fighters().size() > 1:
		_end_timer = 0.0
		return
	_end_timer += delta
	if _end_timer >= END_DELAY:
		_end_match()

func _end_match() -> void:
	_match_over = true
	var alive := _alive_fighters()
	var winner: SmashPlayer = alive[0] if alive.size() == 1 else null
	# Freeze everyone still standing so the winner doesn't wander off while
	# the results show (also stops their online state broadcast).
	for f in alive:
		f.set_physics_process(false)

	# Online: tell the relay who won. Every player's game reports on its own;
	# the relay only records the match on the leaderboard when they all
	# agree (see the top of relay_server/src/worker.js). -1 = draw.
	var online: bool = GameManager.selected_mode == GameManager.Mode.ONLINE
	if online:
		NetworkManager.send({"type": "result", "winner": winner.net_slot if winner != null else -1})
	# Podium order: whoever is still standing first, then the others from last
	# knocked out (2nd) to first knocked out (last place).
	var ranking: Array = []
	for i in hud_entries.size():
		if not _elim_order.has(i) and i < _infos.size():
			ranking.append(_infos[i])
	for k in range(_elim_order.size() - 1, -1, -1):
		if _elim_order[k] < _infos.size():
			ranking.append(_infos[_elim_order[k]])
	_show_results(winner, online, ranking)

# The overlay: dark backdrop, who won, and the buttons. Built in code (like
# the HUD) so Game.tscn didn't need editing.
func _show_results(winner: SmashPlayer, online: bool, ranking: Array = []) -> void:
	$HUD.visible = false # the bottom stats bar would sit behind the buttons
	Music.play(get_tree(), "results") # victory loop
	var layer := CanvasLayer.new()
	layer.layer = 20
	add_child(layer)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(dim)

	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	box.grow_vertical = Control.GROW_DIRECTION_BOTH
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 14)
	layer.add_child(box)

	var title := Label.new()
	title.text = "GAME!"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 56)
	box.add_child(title)

	var who := Label.new()
	who.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	who.add_theme_font_size_override("font_size", 30)
	if winner == null:
		who.text = "DRAW"
	else:
		var fighter_name: String = winner.stats.get("name", "???")
		var username: String = NetworkManager.names.get(winner.net_slot, "") if online else ""
		who.text = ("%s (%s) WINS!" % [username, fighter_name]) if username != "" else ("%s WINS!" % fighter_name)
		who.add_theme_color_override("font_color", winner.stats.get("ui_color", Color.WHITE))
	box.add_child(who)

	# The podium: 1st place big, then the rest (see match_screens.gd).
	if ranking.size() >= 2:
		MatchScreens.build_ranking(box, ranking, winner != null)

	# Three choices, same words online and local:
	#   REMATCH          same characters again (online: everyone must agree)
	#   CHARACTER SELECT back to pick again (online: takes EVERYONE in the room)
	#   LEAVE            back to the title screen (online: leaves the room)
	# The three buttons sit side by side under the podium to save vertical room.
	var btn_row := HBoxContainer.new()
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_row.add_theme_constant_override("separation", 12)
	if online:
		_rematch_label = Label.new()
		_rematch_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		box.add_child(_rematch_label)
		box.add_child(btn_row)
		_rematch_button = _results_button("REMATCH", btn_row, _on_rematch_pressed)
		_results_button("CHARACTER SELECT", btn_row, func(): _go_to_character_select(true))
		_results_button("LEAVE", btn_row, _on_leave_pressed)
		_update_rematch_label()
	else:
		box.add_child(btn_row)
		# Local: REMATCH reloads this scene - same characters, and any CPU
		# set to Random rolls a new fighter (see _setup_local).
		_results_button("REMATCH", btn_row, func(): Scenes.restart(get_tree()))
		_results_button("CHARACTER SELECT", btn_row, func(): _go_to_character_select(false))
		_results_button("LEAVE", btn_row, func(): Scenes.go(get_tree(), "res://scenes/StartScreen.tscn"))

func _results_button(text: String, parent: Control, callback: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(230, 44)
	b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	b.pressed.connect(callback)
	parent.add_child(b)
	return b

# Online PLAY AGAIN: cast our vote. When EVERY player still in the room has
# voted, the relay sends "rematch_go" to all of us and the scene reloads
# (_on_network_message below) - characters stay as picked.
func _on_rematch_pressed() -> void:
	NetworkManager.send({"type": "rematch"})
	_rematch_votes[NetworkManager.my_slot] = true
	_rematch_button.disabled = true
	_update_rematch_label()

# CHARACTER SELECT. Online, we also tell everyone else ("to_select") so the
# whole room goes back to pick again together; the relay starts a fresh match
# record for the leaderboard when it sees that. Old picks are thrown away so
# the next match waits for NEW ones.
func _go_to_character_select(tell_others: bool) -> void:
	if GameManager.selected_mode == GameManager.Mode.ONLINE:
		NetworkManager.picks = {}
		if tell_others:
			NetworkManager.send({"type": "to_select"})
	Scenes.go(get_tree(), "res://scenes/CharacterSelect.tscn")

# Online LEAVE: hang up and go back to the title screen.
func _on_leave_pressed() -> void:
	NetworkManager.close_connection()
	Scenes.go(get_tree(), "res://scenes/StartScreen.tscn")

func _update_rematch_label() -> void:
	if _rematch_label == null:
		return
	var total: int = NetworkManager.slots.size()
	if total < 2:
		_rematch_label.text = "Everyone else left the room."
		_rematch_button.disabled = true
		return
	var voted: int = 0
	for slot in NetworkManager.slots:
		if _rematch_votes.has(slot):
			voted += 1
	_rematch_label.text = "Rematch? %d / %d ready" % [voted, total]

# Gives a fighter its name tag AND remembers what the intro / podium screens
# need to show for it. Call once per fighter, in the same order they are
# added to the `fighters` list (that order = hud_entries order).
func _note_fighter(f: SmashPlayer, label: String, display_name: String, slot: int) -> void:
	f.set_tag(display_name, TAG_COLORS[slot])
	_infos.append({"label": label, "name": display_name, "color": TAG_COLORS[slot], "stats": f.stats})
	_entry_of_slot[slot] = _infos.size() - 1
	# Your own fighter's taunt pops a bubble over your stock (and tells the others online).
	if not f.is_remote and not f.is_cpu:
		f.taunted.connect(func(_p): _send_bubble(slot, Emotes.taunt_line(), true))

# Local match: you are always P1 (spawn marker 0, WASD+F); each enabled CPU
# slot from GameManager.cpu_slots becomes the next fighter.
func _setup_local() -> void:
	var fighters: Array = []
	var me := _spawn_player(_spawn_pos(0), "p1_", false, GameManager.player1_character)
	_note_fighter(me, "P1", "P1", 0)
	fighters.append(me)

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
		# If this CPU was set to "Random" on Character Select, roll a real
		# character index now (a different one every match).
		var char_index: int = slot["character"]
		if char_index == GameManager.RANDOM_CHARACTER:
			char_index = randi() % GameManager.characters.size()
		var cpu := _spawn_player(_spawn_pos(slot_index), prefix, true, char_index)
		_note_fighter(cpu, "CPU %d" % slot_index, "CPU %d" % slot_index, slot_index)
		fighters.append(cpu)
		slot_index += 1

	_link_opponents(fighters)
	_build_hud(fighters)

func _setup_online() -> void:
	NetworkManager.message_received.connect(_on_network_message)
	NetworkManager.peer_left.connect(_on_opponent_left)

	# Everyone picked in CharacterSelect.tscn before landing here:
	# GameManager.online_picks maps relay slot -> character index (slot 0 is
	# the host = P1, slot 1 = P2 ...). Each player's fighter spawns at the
	# marker with their slot number, so all machines build the same stage.
	# Online players are on separate physical keyboards, so every fighter
	# reads WASD+F ("p1_") locally - the remote ones never read input at all
	# (see the is_remote guard in player.gd's _physics_process).
	var fighters: Array = []
	var slot_list: Array = GameManager.online_picks.keys()
	slot_list.sort()
	for slot in slot_list:
		if slot < 0 or slot >= SPAWN_NAMES.size():
			continue
		var p := _spawn_player(_spawn_pos(slot), "p1_", false, GameManager.online_picks[slot])
		p.net_slot = slot # so player.gd knows who to address "hit" messages to
		# Tag = their username (or "Player N" if they have no account).
		var tag_name: String = NetworkManager.names.get(slot, "")
		_note_fighter(p, "P%d" % (slot + 1), tag_name if tag_name != "" else "Player %d" % (slot + 1), slot)
		if slot == NetworkManager.my_slot:
			local_player = p
			p.ko.connect(_on_local_ko)
		else:
			# A puppet: not simulated here at all, just driven by "state"
			# messages from that player's machine (SmashPlayer.apply_remote_state).
			p.is_remote = true
			remote_players[slot] = p
		fighters.append(p)

	_link_opponents(fighters)
	_build_hud(fighters)

# Every message from another player lands here (NetworkManager's
# message_received signal, connected in _setup_online). The relay stamps
# each one with "from" (the sender's slot). Two kinds, matching what
# SmashPlayer/game.gd send: "state" (their position etc., sent from
# _physics_process above) and "hit" (sent from player.gd's
# _on_hitbox_body_entered when THEIR swing connects with OUR copy of someone).
func _on_network_message(data: Dictionary) -> void:
	match data.get("type", ""):
		"rematch":
			# Someone pressed REMATCH on their results screen.
			_rematch_votes[int(data.get("from", -1))] = true
			_update_rematch_label()
		"emote":
			# Another player's taunt line / emote: pop it over THEIR stock.
			_show_bubble(_entry_of_slot.get(int(data.get("from", -1)), -1), str(data.get("text", "")), bool(data.get("taunt", false)))
		"to_select":
			# Another player chose CHARACTER SELECT on their results screen.
			_go_to_character_select(false)
		"rematch_go":
			# The relay says everybody voted: start the same match again.
			Scenes.restart(get_tree())
		"state":
			# (untyped on purpose: a KO'd puppet is freed but still in the
			# dictionary, and putting a freed object into a typed variable is an error)
			var sender = remote_players.get(int(data.get("from", -1)))
			if sender != null and is_instance_valid(sender):
				sender.apply_remote_state(data)
		"attack":
			# That player just swung: play the same swing on their puppet.
			var swinger = remote_players.get(int(data.get("from", -1)))
			if swinger != null and is_instance_valid(swinger):
				swinger.show_remote_attack(str(data.get("variant", "neutral")), int(data.get("facing", 1)))
		"hit":
			# Every other player gets every hit message, so only the player
			# who was actually hit ("to") applies it. We're the authority on
			# our own fighter - the damage then reaches everyone else through
			# our next "state" broadcast.
			if int(data.get("to", -1)) != NetworkManager.my_slot:
				return
			if local_player != null and is_instance_valid(local_player):
				local_player.take_hit(
					data.get("damage", 0.0), int(data.get("from_dir", 1)),
					data.get("kb_base", 150.0), data.get("kb_scale", 6.0), data.get("angle", 35.0)
				)

# The relay told us a player disconnected (NetworkManager.peer_left, with
# their slot; -1 means OUR connection died). Their fighter just leaves the
# match: freeing it makes the HUD show "KO" for them.
func _on_opponent_left(slot: int) -> void:
	_rematch_votes.erase(slot)
	_update_rematch_label()
	var leaver = remote_players.get(slot) # untyped: may already be freed (KO'd)
	if leaver != null and is_instance_valid(leaver):
		leaver.queue_free()
	remote_players.erase(slot)

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
			"box": vbox, # the column - taunt bubbles pop up above it
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
