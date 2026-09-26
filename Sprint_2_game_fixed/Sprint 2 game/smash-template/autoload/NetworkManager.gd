extends Node
## True internet play via a small relay server (see /relay_server in the
## project root, deployed separately to Cloudflare Workers). Both the
## hosting and joining player are plain WebSocket CLIENTS of that relay -
## neither one needs to open a port or share an IP address. A "room code"
## just tells the relay which pair of connections should be forwarded to
## each other; the relay never looks at game data, it's a dumb pipe.
##
## This intentionally does NOT use Godot's high-level multiplayer/RPC
## system (no ENetMultiplayerPeer, no @rpc, no multiplayer_authority) -
## the relay is a plain byte pipe, not something Godot's MultiplayerPeer
## abstraction plugs into out of the box. Instead, game.gd and player.gd
## send/receive plain dictionaries through send()/message_received.

## Set this to the URL wrangler prints after `wrangler deploy` in
## /relay_server (wss:// instead of https://). See relay_server/README.md.
const RELAY_URL := "wss://smash-relay.diddy-blud-skyezan.workers.dev"

const CODE_LENGTH := 5
const CODE_ALPHABET := "23456789ABCDEFGHJKMNPQRSTVWXYZ" # no 0/1/I/O/L - avoids mixups

signal room_ready        # both players are connected - safe to move on
signal peer_left         # the other player's connection dropped
signal connection_failed
signal message_received(data: Dictionary)

var is_host: bool = false
var room_code: String = ""

var _socket: WebSocketPeer
var _got_ready: bool = false

## Generates a fresh room code, connects to it, and returns the code to
## show the host. The other player types this same code into join_room().
func host_room() -> String:
	is_host = true
	var code := _generate_code()
	_open_socket(code) # this resets room_code via close_connection() -
	room_code = code    # so set the real value AFTER opening, not before
	return code

func join_room(code: String) -> void:
	is_host = false
	var clean_code := code.strip_edges().to_upper()
	_open_socket(clean_code) # same ordering reason as above
	room_code = clean_code

func send(data: Dictionary) -> void:
	if _socket == null or _socket.get_ready_state() != WebSocketPeer.STATE_OPEN:
		return
	_socket.send_text(JSON.stringify(data))

func close_connection() -> void:
	if _socket != null:
		_socket.close()
	_socket = null
	_got_ready = false
	room_code = ""

func _open_socket(code: String) -> void:
	close_connection()
	_socket = WebSocketPeer.new()
	var url := "%s/room/%s" % [RELAY_URL, code]
	var err := _socket.connect_to_url(url)
	if err != OK:
		_socket = null
		connection_failed.emit()

func _process(_delta: float) -> void:
	if _socket == null:
		return
	_socket.poll()
	var state := _socket.get_ready_state()

	if state == WebSocketPeer.STATE_OPEN:
		while _socket.get_available_packet_count() > 0:
			_handle_packet(_socket.get_packet())
	elif state == WebSocketPeer.STATE_CLOSED:
		var was_ready := _got_ready
		_socket = null
		_got_ready = false
		if not was_ready:
			connection_failed.emit()
		else:
			peer_left.emit()

func _handle_packet(packet: PackedByteArray) -> void:
	var text := packet.get_string_from_utf8()
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	var data: Dictionary = parsed
	match data.get("type", ""):
		"ready":
			_got_ready = true
			room_ready.emit()
		"peer_left":
			peer_left.emit()
		_:
			message_received.emit(data)

func _generate_code() -> String:
	var code := ""
	for i in range(CODE_LENGTH):
		code += CODE_ALPHABET[randi() % CODE_ALPHABET.length()]
	return code
