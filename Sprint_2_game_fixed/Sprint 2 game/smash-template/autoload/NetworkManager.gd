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
# (30 characters ^ 5 slots is about 24 million possible codes, plenty for a
# game where only a handful of rooms exist at once)

# Who listens to these: room_ready + connection_failed -> online_lobby.gd,
# peer_left -> character_select.gd and game.gd, message_received ->
# character_select.gd (the "pick" message) and game.gd (the "state"/"hit" messages).
signal room_ready        # both players are connected - safe to move on
signal peer_left         # the other player's connection dropped
signal connection_failed
signal message_received(data: Dictionary)

# is_host decides who becomes P1 in game.gd's _setup_online(). room_code is
# what online_lobby.gd shows and copies.
var is_host: bool = false
var room_code: String = ""

# The underscore means "private to this script" (just a naming convention in
# GDScript). _got_ready flips to true once the relay says both players are
# in - it's how _process() tells "never managed to connect" (connection_failed)
# apart from "was playing, then the other side dropped" (peer_left).
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

## Sends any Dictionary to the other player as JSON text. Silently does
## nothing if we're not connected, so callers like game.gd's _physics_process
## can call it every frame without checking first.
func send(data: Dictionary) -> void:
	if _socket == null or _socket.get_ready_state() != WebSocketPeer.STATE_OPEN:
		return
	_socket.send_text(JSON.stringify(data))

## Hangs up and resets everything. Called when backing out of a screen, and
## also at the start of _open_socket so there's never two sockets at once.
func close_connection() -> void:
	if _socket != null:
		_socket.close()
	_socket = null
	_got_ready = false
	room_code = ""

# Connects to wss://<RELAY_URL>/room/<code>. Opening is asynchronous:
# connect_to_url only STARTS the connection, and _process() below watches
# for it finishing. It only returns an error right away for things like a
# malformed URL, which is the one case handled here.
func _open_socket(code: String) -> void:
	close_connection()
	_socket = WebSocketPeer.new()
	var url := "%s/room/%s" % [RELAY_URL, code]
	var err := _socket.connect_to_url(url)
	if err != OK:
		_socket = null
		connection_failed.emit()

# WebSocketPeer does nothing by itself - poll() has to be called every frame
# to actually send/receive. That's the whole reason this autoload has a
# _process.
func _process(_delta: float) -> void:
	if _socket == null:
		return
	_socket.poll()
	var state := _socket.get_ready_state()

	if state == WebSocketPeer.STATE_OPEN:
		# Several packets can pile up between frames, so drain them all.
		while _socket.get_available_packet_count() > 0:
			_handle_packet(_socket.get_packet())
	elif state == WebSocketPeer.STATE_CLOSED:
		# Closed for any reason (relay unreachable, room full, or the other
		# player's side vanished). What it MEANS depends on whether the room
		# ever became ready - see _got_ready above.
		var was_ready := _got_ready
		_socket = null
		_got_ready = false
		if not was_ready:
			connection_failed.emit()
		else:
			peer_left.emit()

# Decodes one incoming packet. "ready" and "peer_left" are the only two
# message types the RELAY itself makes up (see relay_server/src/worker.js);
# everything else came from the other player's game and is passed on through
# message_received for game.gd / character_select.gd to deal with.
func _handle_packet(packet: PackedByteArray) -> void:
	var text := packet.get_string_from_utf8()
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		return # not valid JSON, or JSON that isn't an object - ignore it
	var data: Dictionary = parsed
	match data.get("type", ""):
		"ready":
			_got_ready = true
			room_ready.emit()
		"peer_left":
			peer_left.emit()
		_:
			message_received.emit(data)

# Builds a random room code like "K7M2X" out of CODE_ALPHABET.
func _generate_code() -> String:
	var code := ""
	for i in range(CODE_LENGTH):
		code += CODE_ALPHABET[randi() % CODE_ALPHABET.length()]
	return code
