class_name Music
extends RefCounted
## Background music. Static functions only (nobody makes a Music object): the
## first call creates ONE AudioStreamPlayer under the scene tree's root, which
## survives scene changes, so a track keeps playing straight through menus.
##
##   Music.play_for(tree, "res://scenes/Game.tscn")   - pick the track for a scene
##   Music.play(tree, "results")                      - or name a track directly
##
## Tracks live in res://audio/ (menu, select, battle, results .ogg). They were
## synthesized by audio/generate_music.py - run that to remake them, or just
## drop in your own .ogg files with the same names. Changing track fades the
## old one out and the new one in. Volume (0..1) is saved by the SETTINGS screen.

const TRACKS := {
	"menu": "res://audio/menu.ogg",
	"select": "res://audio/select.ogg",
	"battle": "res://audio/battle.ogg",
	"results": "res://audio/results.ogg",
}
const FADE := 0.3

static var volume: float = 0.6 # linear 0..1 (the SETTINGS slider)
static var muted: bool = false
static var _player: AudioStreamPlayer
static var _current: String = ""
static var _tween: Tween

## Which track a scene should have.
static func track_for(scene_path: String) -> String:
	if scene_path.ends_with("Game.tscn"):
		return "battle"
	if scene_path.ends_with("CharacterSelect.tscn"):
		return "select"
	return "menu" # title, mode select, almanac, leaderboard, lobby, settings...

static func play_for(tree: SceneTree, scene_path: String) -> void:
	play(tree, track_for(scene_path))

static func play(tree: SceneTree, track: String) -> void:
	if tree == null or not TRACKS.has(track):
		return
	_ensure(tree)
	if track == _current and _player.playing:
		return
	_current = track
	var stream = load(TRACKS[track]) if ResourceLoader.exists(TRACKS[track]) else null
	if stream == null:
		return # no file (yet) = silence, not a crash
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = tree.create_tween()
	if _player.playing:
		_tween.tween_property(_player, "volume_db", -40.0, FADE)
	_tween.tween_callback(_begin.bind(stream))
	_tween.tween_property(_player, "volume_db", _target_db(), FADE)

# Starts `stream` on the player (waiting a moment if the player node hasn't
# finished being added to the tree yet - that happens on the very first call
# from the InputSetup autoload).
static func _begin(stream) -> void:
	if not _player.is_inside_tree():
		_player.tree_entered.connect(_begin.bind(stream), CONNECT_ONE_SHOT)
		return
	if "loop" in stream:
		stream.loop = true # Ogg tracks loop forever
	_player.stream = stream
	_player.volume_db = -40.0
	_player.play()

static func _target_db() -> float:
	return -80.0 if muted or volume <= 0.001 else linear_to_db(volume)

static func _ensure(tree: SceneTree) -> void:
	if _player != null and is_instance_valid(_player):
		return
	_player = AudioStreamPlayer.new()
	_player.name = "MusicPlayer"
	_player.process_mode = Node.PROCESS_MODE_ALWAYS
	tree.root.add_child.call_deferred(_player)

## Called from the SETTINGS slider / mute box: applies instantly and saves.
static func set_volume(v: float, is_muted: bool) -> void:
	volume = clampf(v, 0.0, 1.0)
	muted = is_muted
	if _player != null and is_instance_valid(_player):
		if _tween != null and _tween.is_valid():
			_tween.kill()
			_player.volume_db = _target_db()
		else:
			_player.volume_db = _target_db()
	var cfg := ConfigFile.new()
	cfg.load("user://settings.cfg")
	cfg.set_value("audio", "music", volume)
	cfg.set_value("audio", "muted", muted)
	cfg.save("user://settings.cfg")

static func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load("user://settings.cfg") == OK:
		volume = float(cfg.get_value("audio", "music", volume))
		muted = bool(cfg.get_value("audio", "muted", false))
