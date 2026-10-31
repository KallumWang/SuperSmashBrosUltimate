class_name Scenes
extends RefCounted
## Scene changes with a quick fade to black and back, so screens don't just
## snap. Use these instead of get_tree().change_scene_to_file / reload_current_scene:
##   Scenes.go(get_tree(), "res://scenes/StartScreen.tscn")
##   Scenes.restart(get_tree())
## It also switches the music to that scene's track (see music.gd).
## The black overlay is one CanvasLayer parked on the tree's root, so it
## survives the scene swap - that's what lets it fade back IN on the new screen.

const FADE_OUT := 0.2
const FADE_IN := 0.25

static var _layer: CanvasLayer
static var _rect: ColorRect
static var _busy: bool = false

static func _ensure(tree: SceneTree) -> void:
	if _layer != null and is_instance_valid(_layer):
		return
	_layer = CanvasLayer.new()
	_layer.layer = 100 # above everything, including the results screen
	_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	_rect = ColorRect.new()
	_rect.color = Color.BLACK
	_rect.modulate.a = 0.0
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_layer.add_child(_rect)
	tree.root.add_child(_layer)

static func go(tree: SceneTree, path: String) -> void:
	if _busy:
		return # ignore button mashing during a transition
	_busy = true
	_ensure(tree)
	Music.play_for(tree, path)
	await _fade(tree, 1.0, FADE_OUT)
	tree.change_scene_to_file(path)
	await tree.process_frame
	await tree.process_frame
	await _fade(tree, 0.0, FADE_IN)
	_busy = false

static func restart(tree: SceneTree) -> void:
	if _busy:
		return
	_busy = true
	_ensure(tree)
	await _fade(tree, 1.0, FADE_OUT)
	tree.reload_current_scene()
	await tree.process_frame
	await tree.process_frame
	await _fade(tree, 0.0, FADE_IN)
	_busy = false

static func _fade(tree: SceneTree, to_alpha: float, time: float) -> void:
	_rect.mouse_filter = Control.MOUSE_FILTER_STOP if to_alpha > 0.0 else Control.MOUSE_FILTER_IGNORE # blocks clicks while dark
	var tw := tree.create_tween()
	tw.tween_property(_rect, "modulate:a", to_alpha, time)
	await tw.finished
	if to_alpha <= 0.0:
		_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
