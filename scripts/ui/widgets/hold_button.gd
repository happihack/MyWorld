class_name HoldButton
extends Button
## A button that has to be held (M22: erasing a world — bible §31.9 "Reset
## World requires confirmation: hold-to-confirm + a second step"). It fills up
## while held; let go early and nothing happens.

## Held for long enough.
signal held

## How long it must be held (seconds).
@export var hold_seconds := 1.5

var _label := ""
var _holding := false
var _held_for := 0.0
var _done := false


func _init() -> void:
	focus_mode = Control.FOCUS_NONE
	button_down.connect(func() -> void:
		_holding = true
		_held_for = 0.0)
	button_up.connect(func() -> void:
		_holding = false
		_held_for = 0.0
		_show())


func _ready() -> void:
	_label = text
	set_process(true)


## Held for this share of the time it takes, 0 … 1.
func share() -> float:
	return clampf(_held_for / maxf(hold_seconds, 0.01), 0.0, 1.0)


func _process(delta: float) -> void:
	if not _holding or _done:
		return
	advance(delta)


## Time held passes (the frame's — or a test's).
func advance(seconds: float) -> void:
	_held_for += seconds
	_show()
	if _held_for >= hold_seconds and not _done:
		_done = true
		_holding = false
		held.emit()


## Pressed down (as a finger would; tests).
func press_down() -> void:
	button_down.emit()


func _show() -> void:
	text = _label if _held_for <= 0.0 else "%s  %d%%" % [_label, roundi(share() * 100.0)]
