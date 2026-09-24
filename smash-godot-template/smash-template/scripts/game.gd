extends Node2D
## Spawns fighters onto the stage: you (P1) plus however many CPU slots
## are toggled on (local mode, up to 3 CPUs), or you + one networked
## opponent (online mode). Also builds and updates the bottom Smash-style
## HUD (name / damage% / stock pips per fighter).

const PLAYER_SCENE := preload("res://scenes/Player.tscn")
const SPAWN_NAMES := ["SpawnP1", "SpawnP2", "SpawnP3", "SpawnP4"]

@onready var stage: Node2D = $Stage
@onready var players_root: Node2D = $Players
@onready var hud_entries_box: HBoxContainer = $HUD/BottomBar/Entries

var hud_entries: Array = []

func _ready() -> void:
	if GameManager.selected_mode == GameManager.Mode.ONLINE:
		_setup_online()
	else:
		_setup_local()

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
	fighters.append(_spawn_player(_spawn_pos(0), "p1_", false, GameManager.player1_character))

	var slot_index := 1
	for slot in GameManager.cpu_slots:
		if not slot["enabled"]:
			continue
		if slot_index >= SPAWN_NAMES.size():
			break
		var prefix := "cpu_%d_" % slot_index
		fighters.append(_spawn_player(_spawn_pos(slot_index), prefix, true, slot["character"]))
		slot_index += 1

	_link_opponents(fighters)
	_build_hud(fighters)

func _setup_online() -> void:
	var host_id := 1
	var client_id := host_id
	if NetworkManager.is_host:
		var peers := multiplayer.get_peers()
		if peers.size() > 0:
			client_id = peers[0]
	else:
		client_id = multiplayer.get_unique_id()

	var p1 := _spawn_player(_spawn_pos(0), "p1_", false, 0)
	var p2 := _spawn_player(_spawn_pos(1), "p2_", false, 1)
	_link_opponents([p1, p2])
	_build_hud([p1, p2])
	p1.set_multiplayer_authority(host_id)
	p2.set_multiplayer_authority(client_id)

func _spawn_pos(index: int) -> Vector2:
	return stage.get_node(SPAWN_NAMES[index]).position

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
	p.global_position = pos
	players_root.add_child(p)
	return p

func _build_hud(fighters: Array) -> void:
	for f in fighters:
		var color: Color = f.stats.get("color", Color.WHITE)

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
