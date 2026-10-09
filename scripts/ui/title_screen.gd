class_name TitleScreen
extends Control
## The main menu (the owner, 2026-10-08): over a picture of the world, the
## game's name and what can be done — go on with the world last played (and
## which it is), start a new one (the usual box, or a larger), open another,
## or quit. The game itself (Main) opens whatever is chosen (SaveManager.open_next).
## Back on a page of it: to the first page; on the first page: quit.

const MAIN_SCENE := "res://scenes/main/main.tscn"
const BACKGROUND := "res://assets/splash/title_background.jpg"
const ROOT := &"root"
const NEW := &"new"
const WORLDS := &"worlds"
const MAX_WIDTH := 760.0

## How quitting is done (tests replace it).
var quit_action: Callable = func() -> void: get_tree().quit()
## How a world is opened (tests replace it): the plan for Main.
## (The game: a moment's covering screen at once, the game loaded behind it.)
var open_action: Callable = func(plan: Dictionary) -> void: open_world(plan)

## Opening a world (2026-10-08: a touch answered at once, never a frozen screen).
var _opening := false
var _opening_frames := 0
var _cover: Control
var _cover_icon: TextureRect
var _cover_label: Label
var _cover_text := ""
var _cover_time := 0.0

var _list: VBoxContainer
var _page := ROOT


func _ready() -> void:
	name = "Title"
	theme = UITheme.get_theme()
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var backdrop := ColorRect.new()
	backdrop.color = Color(0.078, 0.094, 0.122)
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(backdrop)
	if ResourceLoader.exists(BACKGROUND):
		var picture := TextureRect.new()
		picture.name = "Background"
		picture.texture = load(BACKGROUND)
		picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		picture.set_anchors_preset(Control.PRESET_FULL_RECT)
		picture.modulate = Color(1, 1, 1, 0.55)
		add_child(picture)
	# (Darker towards the bottom, where the words are.)
	var shade := TextureRect.new()
	var gradient := Gradient.new()
	gradient.set_color(0, Color(0.078, 0.094, 0.122, 0.15))
	gradient.set_color(1, Color(0.078, 0.094, 0.122, 0.95))
	var fill := GradientTexture2D.new()
	fill.gradient = gradient
	fill.fill_from = Vector2(0.5, 0.0)
	fill.fill_to = Vector2(0.5, 1.0)
	shade.texture = fill
	shade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	shade.stretch_mode = TextureRect.STRETCH_SCALE
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	var column := VBoxContainer.new()
	column.name = "Column"
	column.set_anchors_preset(Control.PRESET_FULL_RECT)
	column.offset_left = 56.0
	column.offset_right = -56.0
	column.offset_top = 56.0
	column.offset_bottom = -72.0
	column.alignment = BoxContainer.ALIGNMENT_END
	column.add_theme_constant_override("separation", 22)
	add_child(column)
	var icon := TextureRect.new()
	icon.texture = load("res://icon.svg")
	icon.custom_minimum_size = Vector2(150, 150)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	column.add_child(icon)
	var title := Label.new()
	title.name = "Name"
	title.text = MemoryText.translate("TITLE_NAME")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 92)
	title.add_theme_color_override("font_color", UITheme.INK)
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(title)
	var tagline := Label.new()
	tagline.text = MemoryText.translate("TITLE_TAGLINE")
	tagline.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tagline.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tagline.add_theme_color_override("font_color", UITheme.INK_DIM)
	column.add_child(tagline)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 40)
	column.add_child(gap)
	var holder := CenterContainer.new()
	column.add_child(holder)
	_list = VBoxContainer.new()
	_list.name = "Choices"
	_list.custom_minimum_size = Vector2(MAX_WIDTH, 0)
	_list.add_theme_constant_override("separation", 18)
	holder.add_child(_list)
	var version := Label.new()
	version.text = "v" + str(ProjectSettings.get_setting("application/config/version", ""))
	version.add_theme_color_override("font_color", UITheme.INK_DIM)
	version.add_theme_font_size_override("font_size", UITheme.FONT_SMALL)
	version.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	version.position = Vector2(-160, -60)
	add_child(version)
	EventBus.back_requested.connect(_on_back)
	resized.connect(_fit)
	_fit()
	show_page(ROOT)


func _exit_tree() -> void:
	if EventBus.back_requested.is_connected(_on_back):
		EventBus.back_requested.disconnect(_on_back)


## The choices narrower than the screen.
func _fit() -> void:
	if _list != null:
		_list.custom_minimum_size.x = minf(MAX_WIDTH, maxf(size.x - 112.0, 300.0))


func page() -> StringName:
	return _page


## What the choices read, in order (tests).
func choices() -> PackedStringArray:
	var out := PackedStringArray()
	for child in _list.get_children():
		if child is Button and not child.is_queued_for_deletion():
			out.append((child as Button).text)
	return out


## Presses the choice that reads `text` (tests). False: there is none.
func choose(text: String) -> bool:
	for child in _list.get_children():
		if child is Button and not child.is_queued_for_deletion() and (child as Button).text == text:
			(child as Button).pressed.emit()
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
				_primary(_button("TITLE_FIRST", func() -> void: open_action.call({"kind": "new", "size": MainMenu.NEW_WORLD_SIZES[0]})))
			else:
				var latest: Dictionary = worlds[0]
				_primary(_button("TITLE_CONTINUE", func() -> void: open_action.call({"kind": "world", "world_id": latest["world_id"]})))
				_note(MainMenu.world_text(latest, now_unix))
				_button("TITLE_NEW", func() -> void: show_page(NEW))
				if worlds.size() > 1:
					_button("TITLE_WORLDS", func() -> void: show_page(WORLDS))
			_button("TITLE_QUIT", quit)
		NEW:
			_note(MemoryText.translate("TITLE_NEW_ASK"))
			for tiles in MainMenu.NEW_WORLD_SIZES:
				var size_now := tiles
				var key := "MENU_BOX_USUAL" if size_now == MainMenu.NEW_WORLD_SIZES[0] else "MENU_BOX_LARGER"
				_button_text(MemoryText.translate(key).format({"tiles": size_now}), func() -> void:
					open_action.call({"kind": "new", "size": size_now}))
			_button("TITLE_BACK", func() -> void: show_page(ROOT))
		WORLDS:
			for world in worlds:
				var world_id: String = world["world_id"]
				_button_text(MainMenu.world_text(world, now_unix), func() -> void:
					open_action.call({"kind": "world", "world_id": world_id}))
			_button("TITLE_BACK", func() -> void: show_page(ROOT))


## Saves nothing (no world is open here) and quits.
func quit() -> void:
	Log.info(Log.Category.UI, "Quit from the main menu")
	quit_action.call()


func _on_back() -> void:
	if _page != ROOT:
		show_page(ROOT)
	else:
		quit()


func _button(key: String, pressed: Callable) -> Button:
	return _button_text(MemoryText.translate(key), pressed)


func _button_text(text: String, pressed: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(0, UITheme.TOUCH_TARGET)
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_font_size_override("font_size", UITheme.FONT_BODY)
	for state: String in ["normal", "hover", "pressed", "focus"]:
		button.add_theme_stylebox_override(state, _card(Color(0.07, 0.09, 0.12, 0.82 if state == "normal" else 0.95), UITheme.RIM))
	# Felt and seen the moment a finger is down: a tick, and the button pressed in.
	button.button_down.connect(func() -> void:
		Haptics.pulse(Haptics.Strength.LIGHT)
		button.pivot_offset = button.size * 0.5
		button.create_tween().tween_property(button, "scale", Vector2(PRESSED_SCALE, PRESSED_SCALE), 0.06))
	button.button_up.connect(func() -> void:
		button.create_tween().tween_property(button, "scale", Vector2.ONE, 0.12))
	button.pressed.connect(func() -> void:
		AudioManager.play_ui(&"ui_tap")
		pressed.call())
	_list.add_child(button)
	return button


const PRESSED_SCALE := 0.95


## Opens a world: the covering screen at once ("Opening the box…"), the game
## loaded behind it while it breathes, then the game.
func open_world(plan: Dictionary) -> void:
	if _opening:
		return
	_opening = true
	_opening_frames = 0
	SaveManager.open_next = plan
	_show_cover(MemoryText.translate("TITLE_MAKING" if str(plan.get("kind", "")) == "new" else "TITLE_OPENING"))
	if ResourceLoader.load_threaded_request(MAIN_SCENE) != OK:
		get_tree().change_scene_to_file.call_deferred(MAIN_SCENE)


func is_opening() -> bool:
	return _opening


func _process(delta: float) -> void:
	if not _opening or _cover == null:
		return
	_opening_frames += 1
	_cover_time += delta
	_cover.modulate.a = minf(_cover.modulate.a + delta / COVER_FADE, 1.0)
	# (It breathes, and the dots go round: not frozen.)
	var breath := 1.0 + 0.06 * sin(_cover_time * TAU / 1.4)
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


const COVER_FADE := 0.15
const COVER_FRAMES_FIRST := 3


func _show_cover(text: String) -> void:
	_cover_text = text.trim_suffix("…").trim_suffix("...")
	_cover = Control.new()
	_cover.name = "Opening"
	_cover.set_anchors_preset(Control.PRESET_FULL_RECT)
	_cover.mouse_filter = Control.MOUSE_FILTER_STOP # (nothing else pressed meanwhile)
	_cover.modulate.a = 0.35
	add_child(_cover)
	var dark := ColorRect.new()
	dark.color = Color(0.078, 0.094, 0.122, 1.0)
	dark.set_anchors_preset(Control.PRESET_FULL_RECT)
	_cover.add_child(dark)
	var column := VBoxContainer.new()
	column.set_anchors_preset(Control.PRESET_FULL_RECT)
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override("separation", 34)
	_cover.add_child(column)
	_cover_icon = TextureRect.new()
	_cover_icon.texture = load("res://icon.svg")
	_cover_icon.custom_minimum_size = Vector2(200, 200)
	_cover_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_cover_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_cover_icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_cover_icon.pivot_offset = Vector2(100, 100)
	column.add_child(_cover_icon)
	_cover_label = Label.new()
	_cover_label.text = _cover_text + "."
	_cover_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_cover_label.add_theme_font_size_override("font_size", UITheme.FONT_TITLE)
	_cover_label.add_theme_color_override("font_color", UITheme.INK)
	column.add_child(_cover_label)


## The choice to make first: gold.
func _primary(button: Button) -> void:
	var gold := Color(0.784, 0.631, 0.396)
	for state: String in ["normal", "hover", "pressed", "focus"]:
		button.add_theme_stylebox_override(state, _card(gold.lightened(0.12) if state == "hover" else gold, gold.lightened(0.3)))
	for which: String in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		button.add_theme_color_override(which, Color(0.106, 0.078, 0.031))


static func _card(fill: Color, rim: Color) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = fill
	box.border_color = rim
	box.set_border_width_all(3)
	box.set_corner_radius_all(int(UITheme.TOUCH_TARGET / 2.0))
	box.content_margin_left = 40.0
	box.content_margin_right = 40.0
	return box


func _note(text: String) -> void:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_color_override("font_color", UITheme.INK_DIM)
	label.add_theme_font_size_override("font_size", UITheme.FONT_SMALL)
	_list.add_child(label)
