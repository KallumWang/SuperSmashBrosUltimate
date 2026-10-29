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
signal room_ready        # the host pressed START MATCH - everyone moves on to Character Select
signal peer_left(slot: int) # a player's connection dropped (-1 = OUR OWN connection to the relay died)
signal roster_changed    # someone joined/left the room: my_slot, slots and names below were just updated
signal registered(ok: bool, message: String) # result of register_name(): success, or why it failed
signal connection_failed
signal message_received(data: Dictionary)

# is_host decides who becomes P1 in game.gd's _setup_online(). room_code is
# what online_lobby.gd shows and copies.
var is_host: bool = false
var room_code: String = ""
# The relay gives every player a slot number 0-3 (host = 0). my_slot is
# "which player am I" and slots is everyone currently in the room (me
# included). Both are filled in by the relay's "roster" message, so they are
# -1 / empty until the connection is up. A slot is also that player's spawn
# marker and P-number in game.gd and character_select.gd.
var my_slot: int = -1
var slots: Array = []
# slot -> that player's username ("" if they have no account), straight from
# the relay's roster message. Used to label players on Character Select.
var names: Dictionary = {}
# "pick" messages (slot -> character index) are remembered here as they
# arrive, because a fast player can confirm before a slow player's Character
# Select scene has even loaded. character_select.gd reads this in _ready().
# Cleared whenever a match is started.
var picks: Dictionary = {}

# The underscore means "private to this script" (just a naming convention in
# GDScript). _got_ready flips to true once the relay says both players are
# in - it's how _process() tells "never managed to connect" (connection_failed)
# apart from "was playing, then the other side dropped" (peer_left).
var _socket: WebSocketPeer
var _got_ready: bool = false
# True once we've told the relay "hello" on this socket (see _process).
var _announced: bool = false

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

## HOST ONLY: tells the relay (and so everyone else) to start the match, and
## locks the room so nobody else can join. The relay turns it into a "go"
## message for the other players; we trigger room_ready for ourselves here
## because the relay never echoes a message back to its sender.
func start_match() -> void:
	send({"type": "go"})
	picks = {}
	_got_ready = true
	room_ready.emit()

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
	_announced = false
	room_code = ""
	my_slot = -1
	slots = []
	names = {}
	picks = {}

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
func _ready() -> void:
	_load_profile()

func _process(_delta: float) -> void:
	if _socket == null:
		return
	_socket.poll()
	var state := _socket.get_ready_state()

	if state == WebSocketPeer.STATE_OPEN:
		# The first frame after the connection opens: say hello. The relay
		# answers with the room roster (who is in, and which slot we are).
		if not _announced:
			_announced = true
			# id + token prove which account we are (the relay checks them
			# against the leaderboard); both are "" if we haven't registered.
			_socket.send_text(JSON.stringify({"type": "hello", "id": player_id, "token": player_token}))
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
			peer_left.emit(-1) # the relay itself went away: nobody is reachable any more

# Decodes one incoming packet. "roster", "go" and "peer_left" are the only
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
		"roster":
			# Relay: "here is everyone in the room, and you are slot N".
			my_slot = int(data.get("you", -1))
			slots = []
			for s in data.get("slots", []):
				slots.append(int(s))
			names = {}
			var raw_names: Dictionary = data.get("names", {})
			for key in raw_names:
				names[int(key)] = str(raw_names[key])
			roster_changed.emit()
		"go":
			# The host started the match.
			picks = {}
			_got_ready = true
			room_ready.emit()
		"peer_left":
			peer_left.emit(int(data.get("slot", -1)))
		_:
			if data.get("type", "") == "to_select":
				picks = {} # room is going back to Character Select: forget old picks
			if data.get("type", "") == "pick":
				picks[int(data.get("from", -1))] = int(data.get("character", 0))
			message_received.emit(data)

# =====================================================================
# ACCOUNT (username) - used by the leaderboard
# =====================================================================
# Registering creates an account on the relay (POST /register): the server
# makes a unique id and a secret token, and we save all three in
# user://profile.cfg so it's a one-time thing per computer. The token is
# what proves the account is ours when we join a room (see the "hello"
# message in _process) - so never show it or send it anywhere else.
# Stats (wins / games) are kept by the relay, never by the game.
const PROFILE_PATH := "user://profile.cfg"
var player_name: String = ""
var player_id: String = ""
var player_token: String = ""
var _http: HTTPRequest

func _load_profile() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PROFILE_PATH) == OK:
		player_name = str(cfg.get_value("profile", "name", ""))
		player_id = str(cfg.get_value("profile", "id", ""))
		player_token = str(cfg.get_value("profile", "token", ""))

func _save_profile() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("profile", "name", player_name)
	cfg.set_value("profile", "id", player_id)
	cfg.set_value("profile", "token", player_token)
	cfg.save(PROFILE_PATH)

func is_registered() -> bool:
	return player_id != "" and player_token != ""

## "https://..." version of RELAY_URL, for the HTTP endpoints (/register, /leaderboard).
func http_base() -> String:
	return RELAY_URL.replace("wss://", "https://").replace("ws://", "http://")

## Asks the relay to create an account with this username. Emits
## `registered(ok, message)` when the answer comes back (several seconds at
## worst; the relay is on the internet). Usernames are 3-16 letters,
## numbers or _ and must be unique - the relay enforces that.
func register_name(wanted: String) -> void:
	wanted = wanted.strip_edges()
	if _http == null:
		_http = HTTPRequest.new()
		add_child(_http)
	if _http.get_http_client_status() != HTTPClient.STATUS_DISCONNECTED:
		return # a request is already running
	if _http.request_completed.is_connected(_on_register_done):
		_http.request_completed.disconnect(_on_register_done)
	_http.request_completed.connect(_on_register_done)
	var err := _http.request(http_base() + "/register", ["Content-Type: application/json"],
		HTTPClient.METHOD_POST, JSON.stringify({"name": wanted}))
	if err != OK:
		registered.emit(false, "Couldn't reach the server.")

func _on_register_done(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	var parsed: Variant = JSON.parse_string(body.get_string_from_utf8())
	var data: Dictionary = parsed if typeof(parsed) == TYPE_DICTIONARY else {}
	if result == HTTPRequest.RESULT_SUCCESS and code == 200 and data.has("id"):
		player_name = str(data["name"])
		player_id = str(data["id"])
		player_token = str(data["token"])
		_save_profile()
		registered.emit(true, "Welcome, %s!" % player_name)
	else:
		registered.emit(false, str(data.get("error", "Couldn't reach the server.")))

# Builds a random room code like "K7M2X" out of CODE_ALPHABET.
func _generate_code() -> String:
	var code := ""
	for i in range(CODE_LENGTH):
		code += CODE_ALPHABET[randi() % CODE_ALPHABET.length()]
	return code
