class_name BoxIntro
extends Node
## The first opening of the box (VS.4, bible §26.1), on the first launch
## only: black → the ambience fades in → the closed box on its table → the lid
## swings open → the camera comes down to someone walking → "Something lives
## inside." (the first hint, until the first touch). At most `LENGTH` seconds;
## a touch skips to the end. With reduced motion it is simply the end.

signal finished

## When each part begins and ends (seconds from the start).
const FADE := Vector2(0.0, 1.2)
const LID := Vector2(0.6, 2.4)
const DESCENT := Vector2(2.0, 5.4)
const LENGTH := 5.6
## Where the camera comes to rest (tiles), unless told otherwise (play).
const REST_DISTANCE := 18.0
## The figures inside (people, animals) are seen once the lid is this far open
## (their far-off markers would show through it).
const FIGURES_FROM := 0.35

var _rig: CameraRig
var _frame: BoxFrame
var _hints: HintDirector
## Where the one they come down to is now (Callable -> Vector3).
var _target: Callable
var _rest_distance := REST_DISTANCE
var _overlay: ColorRect
var _layer: CanvasLayer
var _time := 0.0
var _running := false
var _from_pivot := Vector3.ZERO
var _from_distance := 1.0
## Hidden while it plays: the HUD (no menus at the first opening), and the
## figures inside until the lid is open.
var _hud: CanvasLayer
var _figures: Array[Node3D] = []


## Begins the opening. `target`: where the person the camera comes to rest
## on stands now (followed as they walk). `hud` is hidden until the end, and
## `figures` (people, animals) until the lid is open.
func play(rig: CameraRig, frame: BoxFrame, hints: HintDirector, target: Callable, reduced_motion: bool,
		hud: CanvasLayer = null, figures: Array[Node3D] = [], rest_distance: float = REST_DISTANCE) -> void:
	_rest_distance = rest_distance
	_hud = hud
	_figures = figures
	if _hud != null:
		_hud.visible = false
	_rig = rig
	_frame = frame
	_hints = hints
	_target = target
	_layer = CanvasLayer.new()
	_layer.layer = 50 # over the world and the HUD, under nothing that matters yet
	add_child(_layer)
	_overlay = ColorRect.new()
	_overlay.color = Color.BLACK
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE # (a touch still reaches the world: it skips)
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_layer.add_child(_overlay)
	_hints.set_intro_running(true)
	_rig.frame_box(false)
	_from_pivot = _rig.pivot()
	_from_distance = _rig.distance()
	_running = true
	_time = 0.0
	if reduced_motion:
		skip()
		return
	_set_ambience(0.0)
	_apply()


func is_running() -> bool:
	return _running


## How far it has got (seconds).
func time() -> float:
	return _time


## Straight to the end: the box open, the camera at rest above them.
func skip() -> void:
	if not _running:
		return
	_time = LENGTH
	_apply()
	_finish()


func _process(delta: float) -> void:
	if not _running:
		return
	_time += delta
	_apply()
	if _time >= LENGTH:
		_finish()


## Everything as it is `_time` seconds in.
func _apply() -> void:
	var fade := _part(FADE)
	_overlay.color.a = 1.0 - fade
	_set_ambience(fade)
	var lid := _part(LID)
	_frame.set_lid_open(lid if lid < 1.0 or _time < DESCENT.x + 0.8 else -1.0)
	for figure in _figures:
		if is_instance_valid(figure):
			figure.visible = lid >= FIGURES_FROM
	var descent := _part(DESCENT)
	if descent > 0.0:
		var to: Vector3 = _target.call() if _target.is_valid() else _from_pivot
		# (Distance eased in proportion: the descent feels even all the way down.)
		var distance := _from_distance * pow(_rest_distance / _from_distance, descent)
		_rig.focus_on(_from_pivot.lerp(to, descent), distance, false)


## 0 … 1 through a part, eased.
func _part(span: Vector2) -> float:
	return smoothstep(span.x, span.y, _time)


func _finish() -> void:
	_running = false
	_frame.set_lid_open(-1.0)
	_set_ambience(1.0)
	AudioManager.apply_volumes()
	if is_instance_valid(_layer):
		_layer.queue_free()
	if _hud != null and is_instance_valid(_hud):
		_hud.visible = true
	for figure in _figures:
		if is_instance_valid(figure):
			figure.visible = true
	_hints.set_intro_running(false)
	_hints.complete(HintDirector.INTRO)
	_hints.offer_inside()
	finished.emit()


## The ambience bus at `share` of its set volume.
func _set_ambience(share: float) -> void:
	var index := AudioServer.get_bus_index(AudioManager.BUS_AMBIENCE)
	if index < 0:
		return
	var wanted := float(Settings.get_value(&"audio/ambience"))
	AudioServer.set_bus_volume_db(index, AudioManager.slider_to_db(wanted * maxf(share, 0.0001)))
