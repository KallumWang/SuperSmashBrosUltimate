extends Control

@onready var status_label: Label = $VBox/StatusLabel
@onready var ip_input: LineEdit = $VBox/IPInput

func _ready() -> void:
	NetworkManager.player_connected.connect(_on_player_connected)
	NetworkManager.connection_succeeded.connect(_on_connection_succeeded)
	NetworkManager.connection_failed.connect(_on_connection_failed)

func _on_host_pressed() -> void:
	var err := NetworkManager.host_game()
	if err == OK:
		status_label.text = "Hosting on port %d. Waiting for opponent..." % NetworkManager.PORT
		GameManager.selected_mode = GameManager.Mode.ONLINE
		GameManager.is_cpu_p2 = false
	else:
		status_label.text = "Failed to host (error %s)" % err
		#multiplayer doesnt work rn and idk why

func _on_join_pressed() -> void:
	var addr := ip_input.text.strip_edges()
	if addr == "":
		addr = "127.0.0.1"
	var err := NetworkManager.join_game(addr)
	if err == OK:
		status_label.text = "Connecting to %s..." % addr
		GameManager.selected_mode = GameManager.Mode.ONLINE
		GameManager.is_cpu_p2 = false
	else:
		status_label.text = "Failed to connect (error %s)" % err

func _on_back_pressed() -> void:
	NetworkManager.close_connection()
	get_tree().change_scene_to_file("res://scenes/ModeSelect.tscn")

func _on_player_connected(_id: int) -> void:
	if NetworkManager.is_host:
		status_label.text = "Opponent connected! Starting..."
		start_game.rpc()

@rpc("call_local", "reliable")
func start_game() -> void:
	get_tree().change_scene_to_file("res://scenes/Game.tscn")

func _on_connection_succeeded() -> void:
	status_label.text = "Connected! Waiting for host to start..."

func _on_connection_failed() -> void:
	status_label.text = "Connection failed."
