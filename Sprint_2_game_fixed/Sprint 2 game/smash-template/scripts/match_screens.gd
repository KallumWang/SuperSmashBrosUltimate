extends RefCounted
## The two big "TV-style" screens around a match, built entirely in code (like
## the HUD) so Game.tscn didn't need editing:
##   play_intro()    - the VS screen before the fight: one tall coloured panel per
##                     fighter (slot colour, "P1 / name" plate, big portrait, character
##                     name) that slides in, then READY? / GO!
##   build_ranking() - the results podium: 1st place big and gold, then 2nd / 3rd /
##                     4th as smaller panels in each player's colour with their slot tag.
## game.gd calls both. It passes in "infos" - one Dictionary per fighter:
##   { "label": "P1" / "CPU 2",   - the slot tag (shown small)
##     "name":  "TheGoat" / "P1", - the username online, or the slot tag locally
##     "color": Color,            - that slot's colour (same as the name tags)
##     "stats": Dictionary }      - the character's entry from character_roster.gd
## (this file has no class_name: game.gd loads it with preload, so it needs no
## re-scan of the project to be picked up)

const INTRO_PANEL_W := 290.0
const INTRO_PANEL_H := 520.0
const MEDAL_COLORS := [Color(1.0, 0.82, 0.2), Color(0.82, 0.86, 0.92), Color(0.85, 0.55, 0.28), Color(0.7, 0.7, 0.75)]

## The fighter's idle picture, for the panels. Uses the character's own frames
## if it has them, otherwise the generated placeholder - same rule as player.gd.
static func portrait(stats: Dictionary) -> Texture2D:
	var frames: SpriteFrames
	var path: String = stats.get("frames", "")
	if path != "" and ResourceLoader.exists(path):
		frames = load(path)
	else:
		frames = SpriteGen.build(stats.get("color", Color.WHITE), stats.get("face_color", Color.BLACK))
	if frames.has_animation("idle") and frames.get_frame_count("idle") > 0:
		return frames.get_frame_texture("idle", 0)
	return null

static func _plate(text: String, size: int, color: Color, bg: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.content_margin_left = 8
	sb.content_margin_right = 8
	sb.content_margin_top = 4
	sb.content_margin_bottom = 4
	l.add_theme_stylebox_override("normal", sb)
	return l

static func _portrait_rect(stats: Dictionary, min_size: Vector2) -> TextureRect:
	var tr := TextureRect.new()
	tr.texture = portrait(stats)
	tr.custom_minimum_size = min_size
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST # keep the pixels crisp when scaled up
	return tr

## Plays the VS intro on top of the game and returns when it's over.
## Usage:  await MatchScreens.play_intro(self, infos)
static func play_intro(host: Node, infos: Array) -> void:
	var tree := host.get_tree()
	var layer := CanvasLayer.new()
	layer.layer = 30
	host.add_child(layer)
	var vp: Vector2 = host.get_viewport().get_visible_rect().size
	var backdrop := ColorRect.new()
	backdrop.color = Color(0.03, 0.03, 0.06, 0.92)
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(backdrop)

	var n := infos.size()
	var panel_w := minf(INTRO_PANEL_W, vp.x / maxf(n, 1))
	var left := (vp.x - n * panel_w) / 2.0
	var top := (vp.y - INTRO_PANEL_H) / 2.0
	var panels: Array = []
	for i in n:
		var info: Dictionary = infos[i]
		var color: Color = info["color"]
		var stats: Dictionary = info["stats"]
		var panel := Panel.new()
		var sb := StyleBoxFlat.new()
		sb.bg_color = color.darkened(0.35)
		sb.border_color = color.lightened(0.2)
		sb.set_border_width_all(3)
		panel.add_theme_stylebox_override("panel", sb)
		panel.size = Vector2(panel_w, INTRO_PANEL_H)
		panel.position = Vector2(left + i * panel_w, vp.y + 40.0) # starts below the screen
		layer.add_child(panel)
		var box := VBoxContainer.new()
		box.set_anchors_preset(Control.PRESET_FULL_RECT)
		box.add_theme_constant_override("separation", 6)
		panel.add_child(box)
		# Top plate: small slot tag over the big name, like Smash's panels.
		var head := VBoxContainer.new()
		head.add_theme_constant_override("separation", 0)
		var tag := _plate(info["label"], 14, color.lightened(0.3), Color(0, 0, 0, 0.85))
		var nm := _plate(info["name"], 26, Color.WHITE, Color(0, 0, 0, 0.85))
		nm.clip_text = true
		head.add_child(tag)
		head.add_child(nm)
		box.add_child(head)
		# Margins keep the (scaled-up) pixel portrait from filling the whole panel.
		var margin := MarginContainer.new()
		margin.size_flags_vertical = Control.SIZE_EXPAND_FILL
		for side in ["left", "right"]:
			margin.add_theme_constant_override("margin_" + side, 50)
		for side in ["top", "bottom"]:
			margin.add_theme_constant_override("margin_" + side, 40)
		var pic := _portrait_rect(stats, Vector2(panel_w - 100, 200))
		margin.add_child(pic)
		box.add_child(margin)
		box.add_child(_plate(stats.get("name", "???"), 22, stats.get("ui_color", Color.WHITE), Color(0, 0, 0, 0.85)))
		panels.append(panel)

	# Slide the panels up one after another.
	for i in n:
		var tw := host.create_tween()
		tw.tween_interval(0.12 * i)
		tw.tween_property(panels[i], "position:y", top, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	await tree.create_timer(2.2).timeout

	# READY? ... GO!
	var call := Label.new()
	call.text = "READY?"
	call.set_anchors_preset(Control.PRESET_FULL_RECT)
	call.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	call.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	call.add_theme_font_size_override("font_size", 96)
	call.add_theme_color_override("font_color", Color.WHITE)
	call.add_theme_color_override("font_outline_color", Color.BLACK)
	call.add_theme_constant_override("outline_size", 14)
	layer.add_child(call)
	await tree.create_timer(0.6).timeout
	call.text = "GO!"
	call.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2))
	# The fight starts as soon as this returns (game.gd un-freezes the fighters),
	# so give "GO!" a moment, then let the screen fade away while play is already on.
	await tree.create_timer(0.2).timeout
	for c in layer.get_children():
		host.create_tween().tween_property(c, "modulate:a", 0.0, 0.45)
	tree.create_timer(0.5).timeout.connect(layer.queue_free)

## Fills `parent` with the podium. `ranking` = infos ordered 1st place first.
## `show_places` false (a draw) hides the 1/2/3 numbers and the gold highlight.
static func build_ranking(parent: Control, ranking: Array, show_places: bool = true) -> void:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 14)
	parent.add_child(row)
	for i in ranking.size():
		var info: Dictionary = ranking[i]
		var first: bool = i == 0 and show_places
		var color: Color = info["color"]
		var size := Vector2(250, 310) if first else Vector2(190, 250)
		var panel := PanelContainer.new()
		var sb := StyleBoxFlat.new()
		sb.bg_color = color.darkened(0.3)
		sb.border_color = MEDAL_COLORS[0] if first else color.lightened(0.25)
		sb.set_border_width_all(5 if first else 3)
		sb.set_corner_radius_all(6)
		panel.add_theme_stylebox_override("panel", sb)
		panel.custom_minimum_size = size
		panel.size_flags_vertical = Control.SIZE_SHRINK_END # panels line up along the bottom, 1st is taller
		row.add_child(panel)
		var box := VBoxContainer.new()
		box.add_theme_constant_override("separation", 4)
		panel.add_child(box)
		var top := HBoxContainer.new()
		box.add_child(top)
		if show_places:
			var place := Label.new()
			place.text = str(i + 1)
			place.add_theme_font_size_override("font_size", 64 if first else 40)
			place.add_theme_color_override("font_color", MEDAL_COLORS[mini(i, 3)])
			place.add_theme_color_override("font_outline_color", Color.BLACK)
			place.add_theme_constant_override("outline_size", 8)
			top.add_child(place)
		var spacer := Control.new()
		spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		top.add_child(spacer)
		var tag := _plate(info["label"], 16, Color.WHITE, Color(0, 0, 0, 0.7))
		tag.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		top.add_child(tag)
		var pic := _portrait_rect(info["stats"], Vector2(size.x - 20, size.y * 0.5))
		pic.size_flags_vertical = Control.SIZE_EXPAND_FILL
		box.add_child(pic)
		var nm := _plate(info["name"], 22 if first else 17, Color.WHITE, Color(0, 0, 0, 0.75))
		nm.clip_text = true
		box.add_child(nm)
		box.add_child(_plate(info["stats"].get("name", "???"), 15 if first else 13, info["stats"].get("ui_color", Color.WHITE), Color(0, 0, 0, 0.75)))
