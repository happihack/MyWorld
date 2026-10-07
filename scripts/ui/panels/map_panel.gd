class_name MapPanel
extends UIPanel
## The map (M13.3, WORLD → Map): the whole box from above, as large as the
## screen allows — dragged to look about, − and + to come closer — with its
## layers switched on and off: the ground, the water, the settlements (their
## fires and names), what nobody has explored (dimmed), and where things have
## happened lately. A tap on a place takes the camera there (and closes it).

## The camera to a place: Callable(world_xz: Vector2, animate: bool).
var move_camera: Callable

const LAYERS: Array[StringName] = [&"terrain", &"water", &"settlements", &"fog", &"events"]
const EDGE_MARGIN := 24.0
const TOP := 40.0
const ZOOM_MOST := 8.0
## A press that moves less than this (UI units) is a tap.
const TAP_SLOP := 24.0

var map := MapImage.new()
var layers := {&"terrain": true, &"water": true, &"settlements": true, &"fog": true, &"events": true}
var _session: WorldSession
var _canvas: MapCanvas
var _chips: Dictionary = {} # layer -> Button
var _title: Label
var _close: Button


## Draws the map and takes the touches on it.
class MapCanvas:
	extends Control
	var panel: MapPanel
	var zoom := 1.0
	var centre := Vector2.ZERO # the world position (XZ) in the middle
	var _press := Vector2.INF
	var _last := Vector2.INF
	var _moved := 0.0

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
		clip_contents = true
		texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

	## How many UI units a tile is drawn at.
	func scale_now() -> float:
		var image := panel.map.image
		if image == null:
			return 1.0
		var fit := minf(size.x / image.get_width(), size.y / image.get_height())
		return fit * zoom

	func point_of(world_xz: Vector2) -> Vector2:
		return size * 0.5 + (world_xz - centre) * scale_now()

	func world_at(point: Vector2) -> Vector2:
		return centre + (point - size * 0.5) / scale_now()

	func _draw() -> void:
		var map := panel.map
		if map.texture == null:
			return
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.05, 0.06, 0.08))
		var origin := Vector2(panel._session.world.bounds.position)
		var top_left := point_of(origin)
		draw_texture_rect(map.texture, Rect2(top_left, Vector2(map.image.get_size()) * scale_now()), false)
		draw_rect(Rect2(top_left, Vector2(map.image.get_size()) * scale_now()), HomeButton.RING, false, 2.0)
		var font := get_theme_default_font()
		for mark in panel.markers():
			var at := point_of(mark[1])
			match StringName(mark[0]):
				&"fire":
					draw_circle(at, 9.0, Minimap.FIRE)
					if String(mark[2]) != "":
						draw_string(font, at + Vector2(12.0, 8.0), String(mark[2]), HORIZONTAL_ALIGNMENT_LEFT, -1.0,
							UITheme.FONT_SMALL, UITheme.INK)
				&"event":
					draw_colored_polygon(PackedVector2Array([at + Vector2(0, -8), at + Vector2(8, 0), at + Vector2(0, 8), at + Vector2(-8, 0)]),
						Minimap.EVENT)
				&"ruin":
					draw_rect(Rect2(at - Vector2(5, 5), Vector2(10, 10)), Minimap.RUIN)

	func _gui_input(event: InputEvent) -> void:
		var point := Vector2.INF
		var pressed := false
		var released := false
		if event is InputEventScreenTouch:
			point = (event as InputEventScreenTouch).position
			pressed = (event as InputEventScreenTouch).pressed
			released = not pressed
		elif event is InputEventMouseButton and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
			point = (event as InputEventMouseButton).position
			pressed = (event as InputEventMouseButton).pressed
			released = not pressed
		elif event is InputEventScreenDrag:
			point = (event as InputEventScreenDrag).position
		elif event is InputEventMouseMotion and _press != Vector2.INF:
			point = (event as InputEventMouseMotion).position
		if point == Vector2.INF:
			return
		accept_event()
		if pressed:
			_press = point
			_last = point
			_moved = 0.0
		elif released:
			if _press != Vector2.INF and _moved < TAP_SLOP:
				panel.go_to(world_at(point))
			_press = Vector2.INF
		elif _press != Vector2.INF:
			# Dragged: the map moves with the finger.
			_moved += point.distance_to(_last)
			centre -= (point - _last) / scale_now()
			_last = point
			queue_redraw()


func _init() -> void:
	super._init()
	var content := VBoxContainer.new()
	add_child(content)
	var header := HBoxContainer.new()
	content.add_child(header)
	_title = Label.new()
	_title.text = MemoryText.translate("MAP_TITLE")
	_title.theme_type_variation = UITheme.TITLE
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(_title)
	for step: float in [-1.0, 1.0]:
		var zoom := Button.new()
		zoom.text = "−" if step < 0.0 else "+"
		zoom.focus_mode = Control.FOCUS_NONE
		zoom.custom_minimum_size = Vector2(UITheme.TOUCH_TARGET * 0.6, UITheme.TOUCH_TARGET * 0.6)
		zoom.pressed.connect(func() -> void: zoom_by(2.0 if step > 0.0 else 0.5))
		header.add_child(zoom)
	_close = CloseButton.new()
	_close.pressed.connect(close)
	header.add_child(_close)
	var chips := HFlowContainer.new()
	content.add_child(chips)
	for layer in LAYERS:
		var chip := Button.new()
		chip.text = MemoryText.translate("MAP_LAYER_" + String(layer).to_upper())
		chip.toggle_mode = true
		chip.button_pressed = true
		chip.focus_mode = Control.FOCUS_NONE
		chip.custom_minimum_size = Vector2(0.0, UITheme.TOUCH_TARGET * 0.55)
		var which := layer
		chip.toggled.connect(func(on: bool) -> void: set_layer(which, on))
		chips.add_child(chip)
		_chips[layer] = chip
	_canvas = MapCanvas.new()
	_canvas.panel = self
	_canvas.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_canvas.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_child(_canvas)


func _ready() -> void:
	get_viewport().size_changed.connect(layout)
	layout()


func setup(session: WorldSession) -> void:
	_session = session
	map.bind(session)
	map.refresh_all()
	var bounds := Rect2(session.world.bounds)
	_canvas.centre = bounds.get_center()
	_canvas.queue_redraw()


func layout() -> void:
	if not is_inside_tree():
		return
	var view := get_viewport_rect().size
	custom_minimum_size = Vector2(view.x - EDGE_MARGIN * 2.0, view.y - TOP - 330.0)
	reset_size()
	position = Vector2(EDGE_MARGIN, TOP)


func _process(_delta: float) -> void:
	if map.refresh() > 0:
		_canvas.queue_redraw()


## Switches a layer on or off.
func set_layer(layer: StringName, on: bool) -> void:
	layers[layer] = on
	if _chips.has(layer):
		(_chips[layer] as Button).set_pressed_no_signal(on)
	map.show_terrain = bool(layers[&"terrain"])
	map.show_water = bool(layers[&"water"])
	map.show_fog = bool(layers[&"fog"])
	if layer in [&"terrain", &"water", &"fog"]:
		map.mark_all()
		map.refresh_all()
	_canvas.queue_redraw()


func zoom_by(factor: float) -> void:
	_canvas.zoom = clampf(_canvas.zoom * factor, 1.0, ZOOM_MOST)
	AudioManager.play_ui(&"ui_tap")
	_canvas.queue_redraw()


## The camera to a place on the map (and the map put away).
func go_to(world_xz: Vector2) -> void:
	if _session == null or not Rect2(_session.world.bounds).has_point(world_xz):
		return
	if move_camera.is_valid():
		move_camera.call(world_xz, true)
	close()


## What is drawn over the map, by the layers on: [[kind, world XZ, label], …].
func markers() -> Array:
	var out: Array = []
	if _session == null:
		return out
	if bool(layers[&"settlements"]):
		for own in _session.settlements.all():
			var tile := own.start_info().settlement_tile
			out.append([&"fire", Vector2(tile) + Vector2(0.5, 0.5), own.display_name()])
		for prop in _session.props.of_kind(PropData.Kind.RUIN):
			if prop.kind == PropData.Kind.RUIN:
				out.append([&"ruin", prop.position2d(), ""])
	if bool(layers[&"events"]):
		var events := _session.events.all_events()
		var shown := 0
		for i in range(events.size() - 1, -1, -1):
			if shown >= Minimap.EVENTS_SHOWN * 2:
				break
			var event: WorldEvent = events[i]
			if event.position != Vector2.INF and event.significance >= Config.events.major_from:
				out.append([&"event", event.position, ""])
				shown += 1
	return out


# --- for tests --------------------------------------------------------------------------------------

func canvas() -> MapCanvas:
	return _canvas
