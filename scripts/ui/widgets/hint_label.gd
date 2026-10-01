class_name HintLabel
extends PanelContainer
## A quiet line of text near the bottom of the screen (bible §26.3): fades in,
## stays until it is no longer needed, fades out. It never takes a touch — the
## world under it stays touchable.

const FADE_SECONDS := 0.35
## Distance from the bottom of the screen (clear of the Home button's row).
const BOTTOM_OFFSET := 400.0
const FONT_SIZE := 44

var _label: Label
var _showing := false
var _tween: Tween


func _init() -> void:
	theme = UITheme.get_theme()
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var pill := StyleBoxFlat.new()
	pill.bg_color = Color(UITheme.CARD, 0.72)
	pill.set_corner_radius_all(44)
	pill.content_margin_left = 44
	pill.content_margin_right = 44
	pill.content_margin_top = 18
	pill.content_margin_bottom = 20
	add_theme_stylebox_override(&"panel", pill)
	_label = Label.new()
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.add_theme_font_size_override(&"font_size", FONT_SIZE)
	add_child(_label)
	modulate.a = 0.0
	visible = false


func _ready() -> void:
	get_viewport().size_changed.connect(_place)


func show_text(text: String) -> void:
	_label.text = text
	_showing = true
	visible = true
	_place()
	_fade_to(1.0)


func hide_hint() -> void:
	if not _showing:
		return
	_showing = false
	_fade_to(0.0)


func is_showing() -> bool:
	return _showing


func text() -> String:
	return _label.text


## Centred near the bottom of the screen.
func _place() -> void:
	if not is_inside_tree():
		return
	reset_size()
	var view := get_viewport_rect().size
	position = Vector2((view.x - size.x) * 0.5, view.y - BOTTOM_OFFSET - size.y)


func _fade_to(alpha: float) -> void:
	if _tween != null:
		_tween.kill()
	if not is_inside_tree():
		modulate.a = alpha
		visible = alpha > 0.0
		return
	_tween = create_tween()
	_tween.tween_property(self, "modulate:a", alpha, FADE_SECONDS)
	if alpha <= 0.0:
		_tween.tween_callback(func() -> void: visible = false)
