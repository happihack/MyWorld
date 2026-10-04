class_name Minimap
extends Control
## The minimap (M13.3, bible §26.4): the whole box from above in a corner —
## the settlements' fires, the one followed or selected, where things have
## happened lately, the ruins of those before — and what the camera shows,
## outlined. A tap takes the camera there; a drag scrubs it across. It folds
## away to a small round button (and is remembered so).

## Where the camera is asked to go: Callable(world_xz: Vector2, animate: bool).
var move_camera: Callable
## Who is selected now (Callable() -> int, 0: nobody).
var selected: Callable
## How many of the latest events with a place are marked.
const EVENTS_SHOWN := 5
const SIDE := 300.0
const FOLDED := 92.0
const SETTING := &"ui/minimap_open"
const FIRE := Color(1.0, 0.62, 0.22)
const PERSON := Color(1.0, 1.0, 1.0)
const EVENT := Color(0.98, 0.86, 0.45)
const RUIN := Color(0.70, 1.0, 0.92)
const VIEW := Color(1.0, 1.0, 1.0, 0.85)

var map := MapImage.new()
var _session: WorldSession
var _rig: CameraRig
var _fold: Button
var _open := true
var _dragging := false
## Drawn again this often (seconds), and what is marked looked at again this often.
const REDRAW_EVERY := 0.25
const MARKERS_EVERY := 1.0
var _redraw_in := 0.0
var _markers_in := 0.0
var _markers: Array = []


func _init() -> void:
	name = "Minimap"
	mouse_filter = Control.MOUSE_FILTER_STOP
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST # (a tile a pixel, crisp)
	add_to_group(InputRouter.UI_BLOCKER_GROUP)
	_fold = Button.new()
	_fold.name = "Fold"
	_fold.focus_mode = Control.FOCUS_NONE
	_fold.pressed.connect(toggle)
	add_child(_fold)


func _ready() -> void:
	set_open(bool(Settings.get_value(SETTING)))


func bind(session: WorldSession, rig: CameraRig) -> void:
	_session = session
	_rig = rig
	map.bind(session)
	if session != null and session.world != null:
		session.world.ground_changed.connect(map.mark_tile)
		session.water.tiles_changed.connect(func(tiles: Array[Vector2i]) -> void:
			for tile in tiles:
				map.mark_tile(tile))


func is_open() -> bool:
	return _open


func toggle() -> void:
	set_open(not _open)
	AudioManager.play_ui(&"ui_tap")


func set_open(open: bool) -> void:
	_open = open
	Settings.set_value(SETTING, open)
	custom_minimum_size = Vector2(SIDE, SIDE) if open else Vector2(FOLDED, FOLDED)
	size = custom_minimum_size
	_fold.text = "–" if open else "▣"
	_fold.size = Vector2(56.0, 56.0) if open else Vector2(FOLDED, FOLDED)
	_fold.position = Vector2(size.x - _fold.size.x, 0.0) if open else Vector2.ZERO
	queue_redraw()


func _process(delta: float) -> void:
	if map.texture == null:
		return
	var drawn := map.refresh() > 0
	_redraw_in -= delta
	_markers_in -= delta
	if _markers_in <= 0.0:
		_markers_in = MARKERS_EVERY
		_markers = markers()
	if _open and (drawn or _redraw_in <= 0.0):
		_redraw_in = REDRAW_EVERY
		queue_redraw()


## The square the map is drawn in (the box keeps its shape).
func map_rect() -> Rect2:
	if map.image == null:
		return Rect2(Vector2.ZERO, size)
	var image_size := Vector2(map.image.get_size())
	var scale := minf(size.x / image_size.x, size.y / image_size.y)
	var drawn := image_size * scale
	return Rect2((size - drawn) * 0.5, drawn)


## The world position (tiles, XZ) under a point of the control.
func world_at(point: Vector2) -> Vector2:
	var rect := map_rect()
	var pixel := (point - rect.position) / rect.size * Vector2(map.image.get_size())
	return map.world_at(pixel)


## The point of the control a world position (XZ) is drawn at.
func point_of(world_xz: Vector2) -> Vector2:
	var rect := map_rect()
	var pixel := world_xz - Vector2(_session.world.bounds.position)
	return rect.position + pixel / Vector2(map.image.get_size()) * rect.size


func _draw() -> void:
	if not _open or map.texture == null:
		draw_circle(size * 0.5, size.x * 0.5 - 2.0, HomeButton.BACKDROP)
		return
	var rect := map_rect()
	draw_rect(Rect2(Vector2.ZERO, size), HomeButton.BACKDROP)
	draw_texture_rect(map.texture, rect, false)
	draw_rect(rect, HomeButton.RING, false, 2.0)
	for mark in _markers:
		var at := point_of(mark[1])
		match StringName(mark[0]):
			&"fire":
				draw_circle(at, 6.0, FIRE)
			&"ruin":
				draw_rect(Rect2(at - Vector2(4, 4), Vector2(8, 8)), RUIN)
			&"event":
				draw_colored_polygon(PackedVector2Array([at + Vector2(0, -6), at + Vector2(6, 0), at + Vector2(0, 6), at + Vector2(-6, 0)]), EVENT)
			&"person":
				draw_arc(at, 7.0, 0.0, TAU, 20, PERSON, 2.5, true)
	var view := view_outline()
	if view.size() == 4:
		var points := PackedVector2Array()
		for corner in view:
			points.append(point_of(corner))
		points.append(points[0])
		draw_polyline(points, VIEW, 2.0, true)


## What is marked on the map: [[kind, world XZ], …] — "fire", "ruin", "event", "person".
func markers() -> Array:
	var out: Array = []
	if _session == null:
		return out
	for fire in _session.settlements.fire_tiles():
		out.append([&"fire", Vector2(fire) + Vector2(0.5, 0.5)])
	for prop in _session.props.all_props():
		if prop.kind == PropData.Kind.RUIN:
			out.append([&"ruin", prop.position2d()])
	var shown := 0
	var events := _session.events.all_events()
	for i in range(events.size() - 1, -1, -1):
		var event: WorldEvent = events[i]
		if shown >= EVENTS_SHOWN:
			break
		if event.position != Vector2.INF and event.significance >= Config.events.major_from:
			out.append([&"event", event.position])
			shown += 1
	var id: int = selected.call() if selected.is_valid() else 0
	var person := _session.people.get_person(id) if id != 0 else null
	if person != null:
		out.append([&"person", person.world2d()])
	return out


## The ground the camera shows: four corners (world XZ), or [] when it cannot tell.
func view_outline() -> Array[Vector2]:
	var out: Array[Vector2] = []
	if _rig == null:
		return out
	var screen := _rig.view_size()
	for corner in [Vector2.ZERO, Vector2(screen.x, 0.0), screen, Vector2(0.0, screen.y)]:
		var at: Variant = _rig.screen_to_ground(corner)
		if at == null:
			return [] as Array[Vector2]
		out.append(Vector2((at as Vector3).x, (at as Vector3).z))
	return out


func _gui_input(event: InputEvent) -> void:
	if not _open:
		return
	var point := Vector2.INF
	var pressed := false
	var moving := false
	if event is InputEventScreenTouch:
		point = (event as InputEventScreenTouch).position
		pressed = (event as InputEventScreenTouch).pressed
	elif event is InputEventScreenDrag:
		point = (event as InputEventScreenDrag).position
		moving = true
	elif event is InputEventMouseButton and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		point = (event as InputEventMouseButton).position
		pressed = (event as InputEventMouseButton).pressed
	elif event is InputEventMouseMotion and _dragging:
		point = (event as InputEventMouseMotion).position
		moving = true
	if point == Vector2.INF:
		return
	accept_event()
	if moving and _dragging:
		_go(point, false) # (scrubbing: the camera follows the finger)
	elif pressed:
		_dragging = true
	elif _dragging:
		_dragging = false
		_go(point, true)


## The camera to the place under `point` (a tap goes there, a drag follows).
func _go(point: Vector2, animate: bool) -> void:
	if not map_rect().has_point(point) or not move_camera.is_valid():
		return
	move_camera.call(world_at(point), animate)
