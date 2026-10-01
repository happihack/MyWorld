class_name GameClock
extends RefCounted
## The world's simulation clock (bible §9). One tick = one game minute.
##
## Pure data + math so it runs headless (tests, offline progression). The owner
## (WorldSession, later SimulationManager) calls advance() with real frame time
## and runs simulation work for the returned number of ticks.
## Calendar helpers (hour/day/season/year) arrive in M6.

signal speed_changed(speed_index: int)

const SPEED_PAUSE := 0
const SPEED_NORMAL := 1
const SPEED_FAST := 2
const SPEED_VERY_FAST := 3

## Game minutes elapsed since the world was created.
var tick: int = 0
var speed_index: int = SPEED_NORMAL

## Game minutes (fractions included) the last advance() covered: what
## systems that move things evenly step by. 0 while paused.
var last_advance_minutes := 0.0

var _config: TimeConfig
var _accumulator: float = 0.0 # game minutes not yet turned into ticks


func _init(config: TimeConfig) -> void:
	_config = config


## Advances by real elapsed seconds; returns how many ticks elapsed.
func advance(real_delta: float) -> int:
	if real_delta <= 0.0 or is_paused():
		last_advance_minutes = 0.0
		return 0
	var clamped := minf(real_delta, _config.max_frame_delta_s)
	last_advance_minutes = clamped * speed_multiplier() / _config.real_seconds_per_game_minute
	_accumulator += last_advance_minutes
	var ticks := int(_accumulator)
	_accumulator -= ticks
	tick += ticks
	return ticks


func set_speed(index: int) -> void:
	var clamped := clampi(index, 0, _config.speed_multipliers.size() - 1)
	if clamped == speed_index:
		return
	speed_index = clamped
	speed_changed.emit(speed_index)


func speed_multiplier() -> float:
	return _config.speed_multipliers[speed_index]


func is_paused() -> bool:
	return speed_multiplier() <= 0.0


## Fraction (0..1) of the way to the next tick; used to interpolate visuals.
func tick_fraction() -> float:
	return _accumulator


func to_dict() -> Dictionary:
	return {"tick": tick, "speed_index": speed_index, "accumulator": _accumulator}


func from_dict(data: Dictionary) -> void:
	tick = maxi(0, int(data.get("tick", 0)))
	_accumulator = clampf(float(data.get("accumulator", 0.0)), 0.0, 0.999999)
	var index := int(data.get("speed_index", SPEED_NORMAL))
	speed_index = clampi(index, 0, _config.speed_multipliers.size() - 1)
