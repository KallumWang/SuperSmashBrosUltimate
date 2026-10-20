extends Node2D

const PLAYER_SCENE := preload("res://scenes/Player.tscn")
const SPAWN_NAMES := ["SpawnP1", "SpawnP2", "SpawnP3", "SpawnP4"]

@onready var stage: Node2D = $Stage
@onready var players_root: Node2D = $Players
@onready var bottom_bar: ColorRect = $HUD/BottomBar
@onready var hud_entries_box: HBoxContainer = $HUD/BottomBar/Entries

var hud_entries: Array = []
var local_player: SmashPlayer
var remote_player: SmashPlayer

func _ready() -> void:
	randomize()
	
	# Keep HUD locked to the bottom of the screen on any resolution
	get_viewport().size_changed.connect(_update_hud_layout)
	_update_hud_layout()

	if GameManager.selected_mode == GameManager.Mode.ONLINE:
		_setup_online()
	else:
		_setup_local()

func _update_hud_layout() -> void:
	var vp_size := get_viewport_rect().size
	bottom_bar.global_position = Vector2(0, vp_size.y - 100)
	bottom_bar.size = Vector2(vp_size.x, 100)
	hud_entries_box.global_position = Vector2(0, vp_size.y - 100)
	hud_entries_box.size = Vector2(vp_size.x, 100)

func _physics_process(_delta: float) -> void:
	if GameManager.selected_mode == GameManager.Mode.ONLINE and local_player != null and is_instance_valid(local_player):
		NetworkManager.send({
			"type": "state",
			"x": local_player.global_position.x, "y": local_player.global_position.y,
			"vx": local_player.velocity.x, "vy": local_player.velocity.y,
			"dmg": local_player.damage_percent, "stocks": local_player.stocks,
			"facing": local_player.facing,
		})

func _process(_delta: float) -> void:
	for entry in hud_entries:
		var f = entry["fighter"]
		var percent_label: Label = entry["percent_label"]
		if f == null or not is_instance_valid(f):
			percent_label.text = "KO"
			_set_stock_count(entry, 0)
			continue
		percent_label.text = "%d%%" % int(f.damage_percent)
		_set_stock_count(entry, f.stocks)

func _setup_local() -> void:
	var fighters: Array = []
	
	# 1. Resolve Player 1
	var p1_char: int = GameManager.player1_character
	if p1_char < 0 or p1_char >= GameManager.characters.size():
		p1_char = randi_range(0, GameManager.characters.size() - 1)
		
	fighters.append(_spawn_player(_spawn_pos(0), "p1_", false, p1_char))

	# 2. Resolve CPUs
	var slot_index := 1
	for slot in GameManager.cpu_slots:
		if not slot["enabled"]:
			continue
		if slot_index >= SPAWN_NAMES.size():
			break
		
		var cpu_char: int = slot["character"]
		if cpu_char < 0 or cpu_char >= GameManager.characters.size():
			cpu_char = randi_range(0, GameManager.characters.size() - 1)

		var prefix := "cpu_%d_" % slot_index
		fighters.append(_spawn_player(_spawn_pos(slot_index), prefix, true, cpu_char))
		slot_index += 1

	_link_opponents(fighters)
	_build_hud(fighters)

func _setup_online() -> void:
	NetworkManager.message_received.connect(_on_network_message)
	NetworkManager.peer_left.connect(_on_opponent_left)

	var my_char: int = GameManager.player1_character
	var opp_char: int = GameManager.online_opponent_character
	var p1_char: int = my_char if NetworkManager.is_host else opp_char
	var p2_char: int = opp_char if NetworkManager.is_host else my_char

	var p1 := _spawn_player(_spawn_pos(0), "p1_", false, p1_char)
	var p2 := _spawn_player(_spawn_pos(1), "p1_", false, p2_char)

	if NetworkManager.is_host:
		local_player = p1
		remote_player = p2
	else:
		local_player = p2
		remote_player = p1

	remote_player.is_remote = true

	_link_opponents([p1, p2])
	_build_hud([p1, p2])

func _on_network_message(data: Dictionary) -> void:
	if remote_player == null or not is_instance_valid(remote_player):
		return
	match data.get("type", ""):
		"state":
			remote_player.apply_remote_state(data)
		"hit":
			if local_player != null and is_instance_valid(local_player):
				local_player.take_hit(
					data.get("damage", 0.0), int(data.get("from_dir", 1)),
					data.get("kb_base", 150.0), data.get("kb_scale", 6.0), data.get("angle", 35.0)
				)

func _on_opponent_left() -> void:
	if remote_player != null and is_instance_valid(remote_player):
		remote_player.is_remote = false

func _spawn_pos(index: int) -> Vector2:
	return stage.get_node(SPAWN_NAMES[index]).global_position

func _link_opponents(fighters: Array) -> void:
	for f in fighters:
		var others: Array = fighters.duplicate()
		others.erase(f)
		f.opponents = others

func _spawn_player(pos: Vector2, prefix: String, is_cpu: bool, char_index: int) -> SmashPlayer:
	var p: SmashPlayer = PLAYER_SCENE.instantiate()
	p.input_prefix = prefix
	p.is_cpu = is_cpu
	p.stats = GameManager.characters[char_index]
	
	players_root.add_child(p)
	p.global_position = pos
	
	return p

func _build_hud(fighters: Array) -> void:
	for child in hud_entries_box.get_children():
		child.queue_free()

	for f in fighters:
		var color: Color = f.stats.get("color", Color.WHITE)

		var vbox := VBoxContainer.new()
		vbox.custom_minimum_size = Vector2(140, 90)
		vbox.alignment = BoxContainer.ALIGNMENT_CENTER

		var name_label := Label.new()
		name_label.text = f.stats.get("name", "???")
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name_label.modulate = color
		vbox.add_child(name_label)

		var percent_label := Label.new()
		percent_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		percent_label.add_theme_font_size_override("font_size", 24)
		percent_label.text = "0%"
		vbox.add_child(percent_label)

		var stocks_box := HBoxContainer.new()
		stocks_box.alignment = BoxContainer.ALIGNMENT_CENTER
		stocks_box.add_theme_constant_override("separation", 6)
		stocks_box.custom_minimum_size = Vector2(0, 20)
		vbox.add_child(stocks_box)

		hud_entries_box.add_child(vbox)
		hud_entries.append({
			"fighter": f,
			"percent_label": percent_label,
			"stocks_box": stocks_box,
			"color": color,
			"last_stocks": -1,
		})

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
