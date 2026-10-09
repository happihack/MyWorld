class_name SplashScreen
extends Control
## The splash screen (the owner, 2026-10-08): shown once as the game starts,
## for a moment, then the main menu. A picture placed at CUSTOM (a PNG, any
## size: it is fitted to the screen) is shown in place of the title card
## drawn here. A tap, a click or a key goes on at once.

const TITLE_SCENE := "res://scenes/main/title.tscn"
## The splash picture, when there is one (see assets/splash/README.md).
const CUSTOM := "res://assets/splash/splash.png"
const BACKGROUND := Color(0.113725, 0.141176, 0.188235) # (as the engine's own boot colour)
const FADE_IN := 0.5
const HOLD := 1.4
const FADE_OUT := 0.4

## How the menu is gone on to (tests replace it).
var next_action: Callable = func() -> void: get_tree().change_scene_to_file(TITLE_SCENE)

var _card: Control
var _gone := false


func _ready() -> void:
	name = "Splash"
	theme = UITheme.get_theme()
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var backdrop := ColorRect.new()
	backdrop.color = BACKGROUND
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(backdrop)
	_card = _custom_card() if ResourceLoader.exists(CUSTOM) else _title_card()
	add_child(_card)
	if bool(Settings.get_value(&"accessibility/reduced_motion")):
		get_tree().create_timer(FADE_IN + HOLD).timeout.connect(go_on)
		return
	_card.modulate.a = 0.0
	var tween := create_tween()
	tween.tween_property(_card, "modulate:a", 1.0, FADE_IN)
	tween.tween_interval(HOLD)
	tween.tween_property(_card, "modulate:a", 0.0, FADE_OUT)
	tween.tween_callback(go_on)


func uses_custom_picture() -> bool:
	return _card != null and _card.name == "Custom"


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


func _custom_card() -> Control:
	var picture := TextureRect.new()
	picture.name = "Custom"
	picture.texture = load(CUSTOM)
	picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	picture.set_anchors_preset(Control.PRESET_FULL_RECT)
	picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return picture


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
