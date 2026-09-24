extends Node
## Minimal ENet host/join wrapper. This is a *starting point* for online
## play - two peers connecting directly. For anything beyond a quick local
## network test you'll want a relay/lobby service, since direct IP connects
## require port forwarding or being on the same network.

const PORT := 8910
const MAX_PLAYERS := 2

signal player_connected(id)
signal player_disconnected(id)
signal connection_failed
signal connection_succeeded

var is_host: bool = false

func host_game(port: int = PORT) -> Error:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(port, MAX_PLAYERS)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	is_host = true
	if not multiplayer.peer_connected.is_connected(_on_peer_connected):
		multiplayer.peer_connected.connect(_on_peer_connected)
		multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	return OK

func join_game(address: String, port: int = PORT) -> Error:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(address, port)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	is_host = false
	if not multiplayer.connected_to_server.is_connected(_on_connected_ok):
		multiplayer.connected_to_server.connect(_on_connected_ok)
		multiplayer.connection_failed.connect(_on_connected_fail)
		multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	return OK

func close_connection() -> void:
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = null

func _on_peer_connected(id: int) -> void:
	player_connected.emit(id)

func _on_peer_disconnected(id: int) -> void:
	player_disconnected.emit(id)

func _on_connected_ok() -> void:
	connection_succeeded.emit()

func _on_connected_fail() -> void:
	connection_failed.emit()
