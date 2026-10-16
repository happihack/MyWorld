class_name TitleScreen
extends Control
## The main menu (the owner, 2026-10-08; its look, 2026-10-09): the lid of the
## box, painted brown and written on by hand. The game's name across the top;
## an opening into the box with the world alive inside it, fireflies rising
## out, and the mascot peeking over its rim; a taped-on note to go on with the
## world last played (and which it is); chalk buttons to start a new one (the
## usual box, or a larger) or open another; and Quit, small, at the foot. The
## game itself (Main) opens whatever is chosen (SaveManager.open_next).
## Back on a page of it: to the first page; on the first page: quit.

const MAIN_SCENE := "res://scenes/main/main.tscn"
const BACKGROUND := "res://assets/splash/title_background.jpg"
const ROOT := &"root"
const NEW := &"new"
const WORLDS := &"worlds"
const MAX_WIDTH := 980.0
const EDGE := 60.0
## The mascot on the lid waves: the first three rows of its sheet, over and over.
const WAVE_FRAMES := 27
const MASCOT_SIDE := 380.0
## How long the world inside drifts one way before it drifts back (seconds).
const DRIFT_SECONDS := 28.0
const FIREFLIES := 5

## How quitting is done (tests replace it).
var quit_action: Callable = func() -> void: get_tree().quit()
## How a world is opened (tests replace it): the plan for Main.
## (The game: a moment's covering screen at once, the game loaded behind it.)
var open_action: Callable = func(plan: Dictionary) -> void: open_world(plan)

## Opening a world (2026-10-08: a touch answered at once, never a frozen screen).
var _opening := false
var _opening_frames := 0
var _cover: Control
var _cover_icon: Control
var _cover_label: Label
var _cover_text := ""
var _cover_time := 0.0

## The parts of the lid, laid out one way held upright and another on its side.
var _column: VBoxContainer
var _row: HBoxContainer
var _left: VBoxContainer
var _right: VBoxContainer
var _name_part: Control
var _opening_part: Control
var _bubble_part: Control
var _gap_part: Control
var _list: VBoxContainer
var _landscape := false
var _content_width := 960.0
var _page := ROOT
var _reduced := false
## The mascot's wave.
var _atlas: AtlasTexture
var _wave_time := 0.0
var _frame := -1


func _ready() -> void:
	let_go_orientation() # (back from a world, or one that did not open: turning again)
	name = "Title"
	theme = UITheme.get_theme()
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_reduced = bool(Settings.get_value(&"accessibility/reduced_motion"))
	_apply_scale()
	get_window().size_changed.connect(_apply_scale)
	_paint_lid()
	_column = VBoxContainer.new()
	_column.name = "Column"
	_column.add_theme_constant_override("separation", 0)
	add_child(_column)
	_row = HBoxContainer.new()
	_row.name = "Row"
	_row.add_theme_constant_override("separation", 60)
	_row.visible = false
	add_child(_row)
	_left = VBoxContainer.new()
	_left.name = "Left"
	_left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_left.add_theme_constant_override("separation", 0)
	_row.add_child(_left)
	_right = VBoxContainer.new()
	_right.name = "Right"
	_right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_right.alignment = BoxContainer.ALIGNMENT_CENTER
	_right.add_theme_constant_override("separation", 0)
	_row.add_child(_right)
	_name_part = _name_block()
	_opening_part = _opening_block()
	_bubble_part = _bubble_row()
	_gap_part = Control.new()
	_gap_part.custom_minimum_size = Vector2(0, 16)
	_list = VBoxContainer.new()
	_list.name = "Choices"
	_list.add_theme_constant_override("separation", 26)
	EventBus.back_requested.connect(_on_back)
	resized.connect(_fit)
	_fit()
	show_page(ROOT)


func _exit_tree() -> void:
	if EventBus.back_requested.is_connected(_on_back):
		EventBus.back_requested.disconnect(_on_back)
	get_window().content_scale_factor = 1.0


## A unit the same physical size however the phone is held (as the game's UIRoot does).
func _apply_scale() -> void:
	var window := get_window()
	var base := Vector2(
		ProjectSettings.get_setting("display/window/size/viewport_width", 1080),
		ProjectSettings.get_setting("display/window/size/viewport_height", 1920))
	var factor := UIRoot.ui_scale_for(Vector2(window.size), base)
	if not is_equal_approx(window.content_scale_factor, factor):
		window.content_scale_factor = factor


## Held upright: one column down the middle. On its side: the name and the
## opening at the left, the choices at the right. Either is held by its
## anchors, so it is always the screen's height: the opening takes what the
## rest leaves, however the labels wrapped at first.
func _fit() -> void:
	if _column == null:
		return
	_landscape = size.x > size.y
	var width := minf(MAX_WIDTH * (2.0 if _landscape else 1.0), maxf(size.x - 2.0 * EDGE, 300.0))
	var holder: Control = _row if _landscape else _column
	_row.visible = _landscape
	_column.visible = not _landscape
	holder.anchor_left = 0.5
	holder.anchor_right = 0.5
	holder.anchor_top = 0.0
	holder.anchor_bottom = 1.0
	holder.offset_left = -width * 0.5
	holder.offset_right = width * 0.5
	holder.offset_top = 40.0
	holder.offset_bottom = -40.0
	_content_width = (width - 60.0) * 0.5 if _landscape else width
	if _landscape:
		_place([_name_part, _opening_part, _bubble_part], _left)
		_place([_list], _right)
	else:
		_place([_name_part, _opening_part, _bubble_part, _gap_part, _list], _column)
	# (A label that wraps must know its width, or it asks for the height of
	# one word a line and the column runs off the screen.)
	for label: Label in _wrapping:
		if is_instance_valid(label):
			label.custom_minimum_size.x = maxf(_content_width - float(label.get_meta("reserve", 0.0)), 160.0)


## Puts `parts` in `holder`, in that order (moved from wherever they were).
static func _place(parts: Array, holder: Control) -> void:
	for part: Control in parts:
		var parent := part.get_parent()
		if parent == holder:
			continue
		if parent != null:
			parent.remove_child(part)
		holder.add_child(part)
	for i in parts.size():
		holder.move_child(parts[i], i)


var _wrapping: Array[Label] = []


## A label that wraps: told how much of the column's width is its own (`reserve`: what is not).
func _wraps(label: Label, reserve: float) -> Label:
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.set_meta("reserve", reserve)
	_wrapping.append(label)
	label.custom_minimum_size.x = maxf(_content_width - reserve, 160.0)
	return label


func page() -> StringName:
	return _page


## The choices of the page, in order: every button in it (tests).
func _choice_buttons() -> Array[Button]:
	var out: Array[Button] = []
	for node in _list.find_children("*", "Button", true, false):
		if not node.is_queued_for_deletion() and node.has_meta("choice"):
			out.append(node)
	return out


## What the choices read, in order (tests).
func choices() -> PackedStringArray:
	var out := PackedStringArray()
	for button in _choice_buttons():
		out.append(str(button.get_meta("choice")))
	return out


## Presses the choice that reads `text` (tests). False: there is none.
func choose(text: String) -> bool:
	for button in _choice_buttons():
		if str(button.get_meta("choice")) == text:
			button.pressed.emit()
			return true
	return false


func show_page(page_name: StringName) -> void:
	_page = page_name
	for child in _list.get_children():
		_list.remove_child(child)
		child.queue_free()
	var worlds := SaveManager.worlds()
	var now_unix := int(Time.get_unix_time_from_system())
	match page_name:
		ROOT:
			if worlds.is_empty():
				_note_button("TITLE_FIRST", "", func() -> void: open_action.call({"kind": "new", "size": MainMenu.NEW_WORLD_SIZES[0]}))
			else:
				var latest: Dictionary = worlds[0]
				_note_button("TITLE_CONTINUE", MainMenu.world_text(latest, now_unix),
					func() -> void: open_action.call({"kind": "world", "world_id": latest["world_id"]}))
				var row := HBoxContainer.new()
				row.add_theme_constant_override("separation", 26)
				_list.add_child(row)
				row.add_child(_chalk_button("TITLE_NEW", &"plus", func() -> void: show_page(NEW), 1))
				if worlds.size() > 1:
					row.add_child(_chalk_button("TITLE_WORLDS", &"box_medium", func() -> void: show_page(WORLDS), 2))
			_foot("TITLE_QUIT", &"door", quit)
		NEW:
			_note(MemoryText.translate("TITLE_NEW_ASK"))
			var icons: Array[StringName] = [&"box_small", &"box_medium", &"box_large"]
			for i in MainMenu.NEW_WORLD_SIZES.size():
				var size_now: int = MainMenu.NEW_WORLD_SIZES[i]
				var key := "MENU_BOX_USUAL" if size_now == MainMenu.NEW_WORLD_SIZES[0] else "MENU_BOX_LARGER"
				_list.add_child(_chalk_button_text(MemoryText.translate(key).format({"tiles": size_now}), icons[mini(i, 2)],
					func() -> void: open_action.call({"kind": "new", "size": size_now}), 10 + i))
			_foot("TITLE_BACK", &"back", func() -> void: show_page(ROOT))
		WORLDS:
			for world in worlds:
				var world_id: String = world["world_id"]
				_paper_button(MainMenu.world_text(world, now_unix), func() -> void:
					open_action.call({"kind": "world", "world_id": world_id}), hash(world_id) % 500)
			_foot("TITLE_BACK", &"back", func() -> void: show_page(ROOT))


## Saves nothing (no world is open here) and quits.
func quit() -> void:
	Log.info(Log.Category.UI, "Quit from the main menu")
	quit_action.call()


func _on_back() -> void:
	if _page != ROOT:
		show_page(ROOT)
	else:
		quit()


# --- the lid -----------------------------------------------------------------------------------

## Painted brown, darker at the edges, a few lines of grain and two knots drawn in.
func _paint_lid() -> void:
	var paint := TextureRect.new()
	paint.name = "Lid"
	var gradient := Gradient.new()
	gradient.set_color(0, UITheme.LID)
	gradient.set_color(1, UITheme.LID_EDGE)
	var fill := GradientTexture2D.new()
	fill.gradient = gradient
	fill.fill = GradientTexture2D.FILL_RADIAL
	fill.fill_from = Vector2(0.5, 0.3)
	fill.fill_to = Vector2(1.1, 1.2)
	fill.width = 64
	fill.height = 64
	paint.texture = fill
	paint.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	paint.stretch_mode = TextureRect.STRETCH_SCALE
	paint.set_anchors_preset(Control.PRESET_FULL_RECT)
	paint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(paint)
	var grain := Control.new()
	grain.name = "Grain"
	grain.set_anchors_preset(Control.PRESET_FULL_RECT)
	grain.mouse_filter = Control.MOUSE_FILTER_IGNORE
	grain.draw.connect(_draw_grain.bind(grain))
	grain.resized.connect(grain.queue_redraw)
	add_child(grain)


func _draw_grain(on: Control) -> void:
	var ink := Color(UITheme.INK, 0.22)
	var across := on.size.x
	var seams := [0.33, 0.67]
	for i in seams.size():
		HandDraw.draw_stroke(on, Vector2(across * seams[i], 0.0), Vector2(across * seams[i], on.size.y), ink, 9.0, 40 + i, 8.0)
	for i in 9:
		var x := across * (0.08 + i * 0.105) + (i % 3) * 9.0
		if absf(x - across * 0.33) < 30.0 or absf(x - across * 0.67) < 30.0:
			continue
		HandDraw.draw_stroke(on, Vector2(x, 0.0), Vector2(x + (i % 2) * 12.0 - 6.0, on.size.y), ink, 5.0, 50 + i, 14.0)
	# Two knots.
	for knot: Array in [[Vector2(across * 0.12, 300.0), 28.0, 60], [Vector2(across * 0.86, on.size.y * 0.78), 44.0, 61]]:
		for ring in 3:
			var radius: float = knot[1] * (0.45 + ring * 0.4)
			on.draw_polyline(HandDraw.circle_points(knot[0], radius, int(knot[2]) + ring, 0.4, 24), ink, 5.0, true)


## The game's name, written large and a little off level, a squiggle under it.
func _name_block() -> Control:
	var block := VBoxContainer.new()
	block.name = "NameBlock"
	block.mouse_filter = Control.MOUSE_FILTER_IGNORE
	block.add_theme_constant_override("separation", 0)
	var title := Label.new()
	title.name = "Name"
	title.text = MemoryText.translate("TITLE_NAME")
	title.theme_type_variation = UITheme.DISPLAY
	_wraps(title, 20.0)
	title.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.45))
	title.add_theme_constant_override("shadow_offset_x", 3)
	title.add_theme_constant_override("shadow_offset_y", 5)
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	block.add_child(title)
	HandDraw.tilt(title, -2.5)
	var line := Control.new()
	line.name = "Squiggle"
	line.custom_minimum_size = Vector2(0, 36.0)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.draw.connect(func() -> void:
		HandDraw.draw_squiggle(line, Vector2(20.0, 10.0), Vector2(minf(680.0, line.size.x * 0.7), 16.0),
			Color(UITheme.CHALK, 0.75), 8.0, 70))
	line.resized.connect(line.queue_redraw)
	block.add_child(line)
	return block


## The mascot's words, in a bubble to the left of it, under the opening.
func _bubble_row() -> Control:
	var row := HBoxContainer.new()
	row.name = "BubbleRow"
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 0)
	var bubble := _bubble()
	bubble.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(bubble)
	var room := Control.new() # (where the mascot leans over)
	room.custom_minimum_size = Vector2(MASCOT_SIDE - 40.0, 0.0)
	room.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(room)
	return row


## The opening into the box: the world alive inside, fireflies, the mascot at its rim.
func _opening_block() -> Control:
	var opening := Control.new()
	opening.name = "Opening"
	opening.size_flags_vertical = Control.SIZE_EXPAND_FILL
	opening.custom_minimum_size = Vector2(0, 520.0)
	opening.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# The world: in a window that keeps it inside the rim as it drifts.
	var window := Control.new()
	window.name = "Window"
	window.clip_contents = true
	window.set_anchors_preset(Control.PRESET_FULL_RECT)
	window.offset_left = 24.0
	window.offset_right = -24.0
	window.offset_top = 24.0
	window.offset_bottom = -24.0
	window.mouse_filter = Control.MOUSE_FILTER_IGNORE
	opening.add_child(window)
	var dark := ColorRect.new()
	dark.color = Color(0.055, 0.07, 0.094)
	dark.set_anchors_preset(Control.PRESET_FULL_RECT)
	dark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	window.add_child(dark)
	if ResourceLoader.exists(BACKGROUND):
		var picture := TextureRect.new()
		picture.name = "World"
		picture.texture = load(BACKGROUND)
		picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		picture.set_anchors_preset(Control.PRESET_FULL_RECT)
		picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
		window.add_child(picture)
		if not _reduced:
			picture.resized.connect(func() -> void: picture.pivot_offset = picture.size * 0.5)
			picture.scale = Vector2(1.02, 1.02)
			var drift := picture.create_tween().set_loops()
			drift.tween_property(picture, "scale", Vector2(1.12, 1.12), DRIFT_SECONDS).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
			drift.tween_property(picture, "scale", Vector2(1.02, 1.02), DRIFT_SECONDS).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	# Shadow inside the rim: the world is down in the box.
	var shade := TextureRect.new()
	var gradient := Gradient.new()
	gradient.set_color(0, Color(0, 0, 0, 0.62))
	gradient.add_point(0.3, Color(0, 0, 0, 0.0))
	gradient.add_point(0.8, Color(0, 0, 0, 0.0))
	gradient.set_color(gradient.get_point_count() - 1, Color(0, 0, 0, 0.4))
	var fill := GradientTexture2D.new()
	fill.gradient = gradient
	fill.fill_from = Vector2(0.5, 0.0)
	fill.fill_to = Vector2(0.5, 1.0)
	shade.texture = fill
	shade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	shade.stretch_mode = TextureRect.STRETCH_SCALE
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	window.add_child(shade)
	for i in FIREFLIES:
		window.add_child(_firefly(i))
	# The cut edge of the opening, drawn over the window.
	var rim := Control.new()
	rim.name = "Rim"
	rim.set_anchors_preset(Control.PRESET_FULL_RECT)
	rim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rim.draw.connect(func() -> void:
		var cut := HandDraw.chalk_box(80, Color(0, 0, 0, 0), UITheme.CUT, 20.0, 48.0)
		rim.draw_style_box(cut, Rect2(Vector2.ZERO, rim.size))
		var inner := HandDraw.chalk_box(80, Color(0, 0, 0, 0), UITheme.LID_EDGE, 6.0, 36.0)
		rim.draw_style_box(inner, Rect2(Vector2(20, 20), rim.size - Vector2(40, 40)))
		rim.draw_line(Vector2(24.0, 23.0), Vector2(rim.size.x - 24.0, 23.0), Color(1, 1, 1, 0.18), 2.0))
	rim.resized.connect(rim.queue_redraw)
	opening.add_child(rim)
	opening.add_child(_mascot())
	return opening


## A firefly in the window: rises, blinks, and comes again lower down.
func _firefly(index: int) -> Control:
	var fly := Control.new()
	fly.name = "Firefly%d" % index
	fly.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fly.size = Vector2(16, 16)
	fly.draw.connect(func() -> void:
		fly.draw_circle(Vector2(8, 8), 7.0, Color(UITheme.FIREFLY, 0.35))
		fly.draw_circle(Vector2(8, 8), 3.5, UITheme.FIREFLY))
	var rng := RandomNumberGenerator.new()
	rng.seed = 100 + index
	var place := func() -> void:
		var parent := fly.get_parent() as Control
		if parent == null:
			return
		fly.position = Vector2(rng.randf_range(0.1, 0.9) * parent.size.x, rng.randf_range(0.55, 0.95) * parent.size.y)
	fly.ready.connect(place)
	if _reduced:
		fly.modulate.a = 0.6
		return fly
	fly.modulate.a = 0.0
	var tween := fly.create_tween().set_loops()
	tween.tween_interval(rng.randf_range(0.0, 4.0))
	tween.tween_callback(place)
	tween.tween_property(fly, "modulate:a", 0.9, 1.2)
	tween.parallel().tween_property(fly, "position", Vector2(30.0, -190.0), 6.0).as_relative().set_trans(Tween.TRANS_SINE)
	tween.tween_property(fly, "modulate:a", 0.3, 1.5)
	tween.tween_property(fly, "modulate:a", 0.8, 1.2)
	tween.tween_property(fly, "modulate:a", 0.0, 1.6)
	return fly


## The mascot, peeking over the bottom-right rim, waving.
func _mascot() -> Control:
	var holder := Control.new()
	holder.name = "Mascot"
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.anchor_left = 1.0
	holder.anchor_right = 1.0
	holder.anchor_top = 1.0
	holder.anchor_bottom = 1.0
	holder.offset_left = -MASCOT_SIDE + 20.0
	holder.offset_right = 20.0
	holder.offset_top = -MASCOT_SIDE * 0.62
	holder.offset_bottom = MASCOT_SIDE * 0.38
	if not ResourceLoader.exists(SplashScreen.MASCOT):
		return holder
	_atlas = AtlasTexture.new()
	_atlas.atlas = load(SplashScreen.MASCOT)
	_show_frame(0)
	# (The holder keeps to the rim by its anchors; what bobs is the body inside it.)
	var body := Control.new()
	body.name = "Body"
	body.size = Vector2(MASCOT_SIDE, MASCOT_SIDE)
	body.pivot_offset = Vector2(MASCOT_SIDE * 0.5, MASCOT_SIDE * 0.9)
	body.rotation_degrees = -5.0
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(body)
	# Its shadow first (the same drawing, dark, a little down and to the right), then it.
	for layer in 2:
		var picture := TextureRect.new()
		picture.name = "Shadow" if layer == 0 else "Picture"
		picture.texture = _atlas
		picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		picture.set_anchors_preset(Control.PRESET_FULL_RECT)
		picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if layer == 0:
			picture.modulate = Color(0, 0, 0, 0.55)
			picture.position = Vector2(5.0, 7.0)
		body.add_child(picture)
	if not _reduced:
		var bob := body.create_tween().set_loops()
		bob.tween_property(body, "rotation_degrees", -3.0, 1.7).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		bob.parallel().tween_property(body, "position:y", -14.0, 1.7).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		bob.tween_property(body, "rotation_degrees", -5.0, 1.7).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		bob.parallel().tween_property(body, "position:y", 0.0, 1.7).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	return holder


func _show_frame(frame: int) -> void:
	_frame = frame
	if _atlas != null:
		var side := SplashScreen.MASCOT_FRAME_SIZE
		_atlas.region = Rect2((frame % SplashScreen.MASCOT_COLUMNS) * side, floori(frame / float(SplashScreen.MASCOT_COLUMNS)) * side, side, side)


## Which frame of the wave the mascot shows.
func mascot_frame() -> int:
	return _frame


## What it says, in a bubble by the mascot.
func _bubble() -> Control:
	var bubble := PanelContainer.new()
	bubble.name = "Bubble"
	bubble.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var box := HandDraw.chalk_box(90, Color(UITheme.INK, 0.35), UITheme.CHALK, UITheme.CHALK_WIDTH, 60.0)
	box.content_margin_left = 32.0
	box.content_margin_right = 32.0
	box.content_margin_top = 14.0
	box.content_margin_bottom = 14.0
	bubble.add_theme_stylebox_override("panel", box)
	var text := Label.new()
	text.text = MemoryText.translate("TITLE_TAGLINE")
	text.theme_type_variation = UITheme.CHALK_LABEL
	text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_wraps(text, MASCOT_SIDE - 40.0 + 64.0)
	bubble.add_child(text)
	bubble.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	HandDraw.tilt(bubble, -1.5)
	return bubble


func _process(delta: float) -> void:
	if _atlas != null and not _reduced and not _opening:
		# (One frame on at a time, never frames jumped over: see SplashScreen.)
		_wave_time += minf(delta, 1.0 / SplashScreen.MASCOT_FPS)
		var frame := int(_wave_time * SplashScreen.MASCOT_FPS) % WAVE_FRAMES
		if frame != _frame:
			_show_frame(frame)
	if not _opening or _cover == null:
		return
	_opening_frames += 1
	_cover_time += delta
	_cover.modulate.a = minf(_cover.modulate.a + delta / COVER_FADE, 1.0)
	# (It breathes, and the dots go round: not frozen.)
	var breath := 1.0 + 0.04 * sin(_cover_time * TAU / 1.4)
	_cover_icon.scale = Vector2(breath, breath)
	_cover_label.text = _cover_text + ".".repeat(1 + int(_cover_time * 3.0) % 3)
	var status := ResourceLoader.load_threaded_get_status(MAIN_SCENE)
	# (On only once the cover has been drawn a few times: the last frame before the world opens is it.)
	if _opening_frames < COVER_FRAMES_FIRST:
		return
	if status == ResourceLoader.THREAD_LOAD_LOADED:
		set_process(false)
		get_tree().change_scene_to_packed(ResourceLoader.load_threaded_get(MAIN_SCENE))
	elif status == ResourceLoader.THREAD_LOAD_FAILED or status == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
		set_process(false)
		get_tree().change_scene_to_file(MAIN_SCENE)


# --- the choices -------------------------------------------------------------------------------

## A note taped to the lid: the first choice. `line`: what it says under its
## title (the world it opens); "" for none.
func _note_button(key: String, line: String, pressed: Callable) -> Button:
	var button := Button.new()
	button.name = "Note"
	button.text = ""
	button.set_meta("choice", MemoryText.translate(key))
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(0, UITheme.TOUCH_TARGET * (1.45 if line != "" else 1.1))
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var paper := HandDraw.paper_box(30, 0.0)
	var pressed_paper := paper.duplicate() as StyleBoxFlat
	pressed_paper.bg_color = UITheme.PAPER_EDGE
	for state: String in ["normal", "hover", "focus"]:
		button.add_theme_stylebox_override(state, paper)
	for state: String in ["pressed", "hover_pressed"]:
		button.add_theme_stylebox_override(state, pressed_paper)
	button.draw.connect(func() -> void:
		HandDraw.draw_tape(button, Vector2(button.size.x * 0.5, 2.0), Vector2(220.0, 50.0), -2.0)
		var arrow := Rect2(button.size.x - 110.0, button.size.y * 0.5 - 36.0, 72.0, 72.0)
		HandIcons.draw(button, &"arrow", arrow, UITheme.INK))
	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.set_anchors_preset(Control.PRESET_FULL_RECT)
	column.offset_left = 44.0
	column.offset_right = -120.0
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override("separation", 0)
	button.add_child(column)
	var title := Label.new()
	title.text = MemoryText.translate(key)
	title.theme_type_variation = UITheme.TITLE
	title.add_theme_font_size_override("font_size", UITheme.FONT_HEADING + 14)
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(title)
	if line != "":
		var note := Label.new()
		note.text = line
		note.theme_type_variation = UITheme.NOTE
		note.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_wraps(note, 164.0)
		column.add_child(note)
	# (As tall as what is written on it, however the line wraps.)
	var fit := func() -> void:
		button.custom_minimum_size.y = maxf(UITheme.TOUCH_TARGET * 1.1, column.get_combined_minimum_size().y + 44.0)
	column.minimum_size_changed.connect(fit)
	fit.call_deferred()
	_press_feel(button, pressed)
	HandDraw.tilt(button, 1.2)
	_list.add_child(button)
	return button


## A button drawn in chalk on the lid, an icon before its words.
func _chalk_button(key: String, icon: StringName, pressed: Callable, seed: int) -> Button:
	return _chalk_button_text(MemoryText.translate(key), icon, pressed, seed)


func _chalk_button_text(text: String, icon: StringName, pressed: Callable, seed: int) -> Button:
	var button := Button.new()
	button.text = text
	button.set_meta("choice", text)
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(0, UITheme.TOUCH_TARGET)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	button.add_theme_font_size_override("font_size", UITheme.FONT_BODY + 6)
	if HandIcons.has(icon):
		button.icon = HandIcons.texture(icon, 56)
		button.add_theme_constant_override("icon_max_width", 56)
		button.add_theme_constant_override("h_separation", 20)
	for state: String in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color",
			"icon_normal_color", "icon_hover_color", "icon_pressed_color", "icon_hover_pressed_color", "icon_focus_color"]:
		button.add_theme_color_override(state, UITheme.CHALK)
	var box := HandDraw.chalk_box(seed, Color(UITheme.INK, 0.28), Color(UITheme.CHALK, 0.9), UITheme.CHALK_WIDTH, 60.0)
	box.content_margin_left = 34.0
	box.content_margin_right = 34.0
	var down := box.duplicate() as StyleBoxFlat
	down.bg_color = Color(UITheme.INK, 0.5)
	for state: String in ["normal", "hover", "focus"]:
		button.add_theme_stylebox_override(state, box)
	for state: String in ["pressed", "hover_pressed"]:
		button.add_theme_stylebox_override(state, down)
	_press_feel(button, pressed)
	HandDraw.tilt(button, HandDraw.tilt_for(seed, 1.0))
	return button


## A world on a slip of paper (the Your worlds page).
func _paper_button(text: String, pressed: Callable, seed: int) -> Button:
	var button := Button.new()
	button.text = text
	button.set_meta("choice", text)
	button.focus_mode = Control.FOCUS_NONE
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	button.custom_minimum_size = Vector2(0, UITheme.TOUCH_TARGET)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.add_theme_font_override("font", UITheme.note_font())
	button.add_theme_font_size_override("font_size", UITheme.FONT_BODY - 2)
	var paper := HandDraw.paper_box(seed, 0.0)
	paper.content_margin_left = 40.0
	paper.content_margin_right = 40.0
	var down := paper.duplicate() as StyleBoxFlat
	down.bg_color = UITheme.PAPER_EDGE
	for state: String in ["normal", "hover", "focus"]:
		button.add_theme_stylebox_override(state, paper)
	for state: String in ["pressed", "hover_pressed"]:
		button.add_theme_stylebox_override(state, down)
	button.draw.connect(func() -> void:
		HandDraw.draw_tape(button, Vector2(button.size.x * 0.5, 2.0), Vector2(180.0, 44.0), HandDraw.tilt_for(seed + 1, 3.0)))
	_press_feel(button, pressed)
	HandDraw.tilt(button, HandDraw.tilt_for(seed, 1.3))
	_list.add_child(button)
	return button


## The row at the foot: the version, and a small choice at the right (Quit, Back).
func _foot(key: String, icon: StringName, pressed: Callable) -> void:
	var row := HBoxContainer.new()
	row.name = "Foot"
	var version := Label.new()
	version.text = "v" + str(ProjectSettings.get_setting("application/config/version", ""))
	version.theme_type_variation = UITheme.CHALK_SMALL
	version.modulate.a = 0.5
	version.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	version.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(version)
	var button := Button.new()
	button.text = MemoryText.translate(key)
	button.set_meta("choice", button.text)
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(UITheme.TOUCH_TARGET * 1.6, UITheme.TOUCH_TARGET * 0.8)
	button.add_theme_font_size_override("font_size", UITheme.FONT_BODY)
	if HandIcons.has(icon):
		button.icon = HandIcons.texture(icon, 48)
		button.add_theme_constant_override("icon_max_width", 48)
	for state: String in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color",
			"icon_normal_color", "icon_hover_color", "icon_pressed_color", "icon_hover_pressed_color", "icon_focus_color"]:
		button.add_theme_color_override(state, Color(UITheme.CHALK, 0.8))
	_press_feel(button, pressed)
	row.add_child(button)
	_list.add_child(row)


## A note on the lid (not a choice): what a page asks.
func _note(text: String) -> void:
	var sheet := PanelContainer.new()
	sheet.add_theme_stylebox_override("panel", HandDraw.paper_box(31, 26.0))
	sheet.draw.connect(func() -> void:
		HandDraw.draw_tape(sheet, Vector2(sheet.size.x * 0.5, 2.0), Vector2(200.0, 46.0), 2.0))
	var label := Label.new()
	label.text = text
	label.theme_type_variation = UITheme.NOTE
	_wraps(label, 52.0)
	sheet.add_child(label)
	HandDraw.tilt(sheet, -1.2)
	_list.add_child(sheet)


const PRESSED_SCALE := 0.96


## Felt and seen the moment a finger is down: a tick, and the button pressed in.
func _press_feel(button: Button, pressed: Callable) -> void:
	button.button_down.connect(func() -> void:
		Haptics.pulse(Haptics.Strength.LIGHT)
		button.create_tween().tween_property(button, "scale", Vector2(PRESSED_SCALE, PRESSED_SCALE), 0.06))
	button.button_up.connect(func() -> void:
		button.create_tween().tween_property(button, "scale", Vector2.ONE, 0.12))
	button.pressed.connect(func() -> void:
		AudioManager.play_ui(&"ui_tap")
		pressed.call())


# --- opening a world ---------------------------------------------------------------------------

## Opens a world: the covering screen at once ("Opening the box…"), the game
## loaded behind it while it breathes, then the game.
func open_world(plan: Dictionary) -> void:
	if _opening:
		return
	_opening = true
	_opening_frames = 0
	hold_orientation(size)
	SaveManager.open_next = plan
	_show_cover(MemoryText.translate("TITLE_MAKING" if str(plan.get("kind", "")) == "new" else "TITLE_OPENING"))
	if ResourceLoader.load_threaded_request(MAIN_SCENE) != OK:
		get_tree().change_scene_to_file.call_deferred(MAIN_SCENE)


## While the world opens the screen keeps the way it is held (either way up of
## it): the game builds the world in one long step, and a phone turned
## meanwhile stretched the last frame drawn — the cover's text — across the
## screen (the owner, 2026-10-16). Let go once the opening is over (Main).
static func hold_orientation(view: Vector2) -> void:
	if not OS.has_feature("mobile"):
		return
	DisplayServer.screen_set_orientation(DisplayServer.SCREEN_SENSOR_LANDSCAPE if view.x > view.y else DisplayServer.SCREEN_SENSOR_PORTRAIT)


## The screen turns with the phone again (as the project sets it).
static func let_go_orientation() -> void:
	if not OS.has_feature("mobile"):
		return
	DisplayServer.screen_set_orientation(int(ProjectSettings.get_setting("display/window/handheld/orientation", DisplayServer.SCREEN_SENSOR)) as DisplayServer.ScreenOrientation)


func is_opening() -> bool:
	return _opening


const COVER_FADE := 0.15
const COVER_FRAMES_FIRST := 3


## The lid, bare, a note on it: "Opening the box…".
func _show_cover(text: String) -> void:
	_cover_text = text.trim_suffix("…").trim_suffix("...")
	_cover = Control.new()
	_cover.name = "Opening"
	_cover.set_anchors_preset(Control.PRESET_FULL_RECT)
	_cover.mouse_filter = Control.MOUSE_FILTER_STOP # (nothing else pressed meanwhile)
	_cover.modulate.a = 0.35
	add_child(_cover)
	var dark := ColorRect.new()
	dark.color = UITheme.LID_EDGE
	dark.set_anchors_preset(Control.PRESET_FULL_RECT)
	_cover.add_child(dark)
	var middle := CenterContainer.new()
	middle.set_anchors_preset(Control.PRESET_FULL_RECT)
	_cover.add_child(middle)
	var sheet := PanelContainer.new()
	sheet.add_theme_stylebox_override("panel", HandDraw.paper_box(32, 40.0))
	sheet.custom_minimum_size = Vector2(minf(680.0, size.x - 2.0 * EDGE), 0.0)
	sheet.draw.connect(func() -> void:
		HandDraw.draw_tape(sheet, Vector2(sheet.size.x * 0.5, 2.0), Vector2(220.0, 50.0), -2.0))
	middle.add_child(sheet)
	_cover_icon = sheet
	sheet.resized.connect(func() -> void: sheet.pivot_offset = sheet.size * 0.5)
	_cover_label = Label.new()
	_cover_label.text = _cover_text + "."
	_cover_label.theme_type_variation = UITheme.TITLE
	_cover_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sheet.add_child(_cover_label)
	HandDraw.tilt(sheet, -1.5)
