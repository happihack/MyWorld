class_name SplashScreen
extends Control
## The splash screen (the owner, 2026-10-08): shown once as the game starts,
## then the main menu. In the middle of it, our mascot (Happi Hacking) plays
## its animation once — the sprite sheet's colours inverted, white line on the
## dark (MASCOT: 9 frames a row, MASCOT_FRAMES of them) — and holds its last
## frame a moment. A picture placed at CUSTOM (a PNG, any size: fitted to
## the screen) is shown in its place, if there is one. A tap, a click or a
## key goes on at once.

const TITLE_SCENE := "res://scenes/main/title.tscn"
## The splash picture, when there is one (see assets/splash/README.md).
const CUSTOM := "res://assets/splash/splash.png"
## The mascot's frames (made from sprHH_sheet.png: inverted, the paper clear).
const MASCOT := "res://assets/splash/mascot_sheet.png"
const MASCOT_COLUMNS := 9
const MASCOT_FRAMES := 67
const MASCOT_FRAME_SIZE := 256
## Frames a second, and how big on screen (of the screen's width, at most this many px).
const MASCOT_FPS := 16.0
const MASCOT_WIDTH_SHARE := 0.62
const MASCOT_MOST_PX := 720.0
const BACKGROUND := Color(0.113725, 0.141176, 0.188235) # (as the engine's own boot colour)
const FADE_IN := 0.35
## Held after the animation (or, with no animation, the whole of it).
const HOLD := 0.9
const FADE_OUT := 0.4

## How the menu is gone on to (tests replace it).
var next_action: Callable = func() -> void: get_tree().change_scene_to_file(TITLE_SCENE)

var _card: Control
var _atlas: AtlasTexture
var _frame := 0
var _time := 0.0
var _playing := false
var _gone := false


## How long the splash lasts, all told (seconds), as it will be shown.
static func length() -> float:
	var playing := 0.0
	if not ResourceLoader.exists(CUSTOM) and ResourceLoader.exists(MASCOT):
		playing = MASCOT_FRAMES / MASCOT_FPS
	return FADE_IN + playing + HOLD + FADE_OUT


func _ready() -> void:
	name = "Splash"
	theme = UITheme.get_theme()
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var backdrop := ColorRect.new()
	backdrop.color = BACKGROUND
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(backdrop)
	if ResourceLoader.exists(CUSTOM):
		_card = _custom_card()
	elif ResourceLoader.exists(MASCOT):
		_card = _mascot_card()
	else:
		_card = _title_card()
	add_child(_card)
	var reduced := bool(Settings.get_value(&"accessibility/reduced_motion"))
	if reduced:
		# (Still: the last frame, for a moment.)
		_show_frame(MASCOT_FRAMES - 1)
		get_tree().create_timer(FADE_IN + HOLD).timeout.connect(go_on)
		return
	_card.modulate.a = 0.0
	var tween := create_tween()
	tween.tween_property(_card, "modulate:a", 1.0, FADE_IN)
	if _atlas != null:
		tween.tween_callback(func() -> void: _playing = true)
		tween.tween_interval(MASCOT_FRAMES / MASCOT_FPS)
	tween.tween_interval(HOLD)
	tween.tween_property(_card, "modulate:a", 0.0, FADE_OUT)
	tween.tween_callback(go_on)


func _process(delta: float) -> void:
	if not _playing or _atlas == null:
		return
	_time += delta
	var frame := mini(int(_time * MASCOT_FPS), MASCOT_FRAMES - 1)
	if frame != _frame:
		_show_frame(frame)
	if frame >= MASCOT_FRAMES - 1:
		_playing = false


func uses_custom_picture() -> bool:
	return _card != null and _card.name == "Custom"


func shows_mascot() -> bool:
	return _atlas != null


## Which frame of the mascot is showing.
func mascot_frame() -> int:
	return _frame


## On to the main menu (once).
func go_on() -> void:
	if _gone:
		return
	_gone = true
	next_action.call()


func _gui_input(event: InputEvent) -> void:
	if (event is InputEventMouseButton and event.pressed) or (event is InputEventScreenTouch and event.pressed):
		accept_event()
		go_on()


func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_pressed():
		go_on()


func _show_frame(frame: int) -> void:
	_frame = frame
	if _atlas == null:
		return
	_atlas.region = Rect2((frame % MASCOT_COLUMNS) * MASCOT_FRAME_SIZE, floori(frame / float(MASCOT_COLUMNS)) * MASCOT_FRAME_SIZE,
		MASCOT_FRAME_SIZE, MASCOT_FRAME_SIZE)


func _custom_card() -> Control:
	var picture := TextureRect.new()
	picture.name = "Custom"
	picture.texture = load(CUSTOM)
	picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	picture.set_anchors_preset(Control.PRESET_FULL_RECT)
	picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return picture


## The mascot, in the middle of the screen.
func _mascot_card() -> Control:
	var holder := CenterContainer.new()
	holder.name = "Mascot"
	holder.set_anchors_preset(Control.PRESET_FULL_RECT)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_atlas = AtlasTexture.new()
	_atlas.atlas = load(MASCOT)
	_show_frame(0)
	var picture := TextureRect.new()
	picture.texture = _atlas
	picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(picture)
	var fit := func() -> void:
		var side := minf(get_viewport_rect().size.x * MASCOT_WIDTH_SHARE, MASCOT_MOST_PX)
		picture.custom_minimum_size = Vector2(side, side)
	fit.call()
	resized.connect(fit)
	return holder


func _title_card() -> Control:
	var card := VBoxContainer.new()
	card.name = "Card"
	card.set_anchors_preset(Control.PRESET_FULL_RECT)
	card.alignment = BoxContainer.ALIGNMENT_CENTER
	card.add_theme_constant_override("separation", 30)
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var icon := TextureRect.new()
	icon.texture = load("res://icon.svg")
	icon.custom_minimum_size = Vector2(260, 260)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	card.add_child(icon)
	var title := Label.new()
	title.text = MemoryText.translate("TITLE_NAME")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 84)
	title.add_theme_color_override("font_color", UITheme.INK)
	card.add_child(title)
	var by := Label.new() # (the line under the name)
	by.text = MemoryText.translate("TITLE_TAGLINE")
	by.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	by.add_theme_color_override("font_color", UITheme.RIM)
	by.add_theme_font_size_override("font_size", UITheme.FONT_SMALL)
	by.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	card.add_child(by)
	return card
