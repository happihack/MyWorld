class_name ToolReveals
extends RefCounted
## Which of the player's powers have shown themselves (bible §23.2, M9.5):
## a tool appears in the tool bar when the world has given the player the
## idea of it — RAIN after the first rain (or the first crop that stands
## dry), WIND after the first storm, WATER after the water has been touched
## a few times. Kept with the world.

## A tool has shown itself (not for those found again when a world is opened).
signal revealed(id: StringName)

const RAIN := &"rain"
const WIND := &"wind"
const WATER := &"water"
## In the order they stand in the tool bar.
const ALL: Array[StringName] = [RAIN, WIND, WATER]

var _known: Dictionary = {} # tool id -> the game tick it showed itself at


func clear() -> void:
	_known.clear()


func is_known(id: StringName) -> bool:
	return _known.has(id)


## The tools that have shown themselves, in tool-bar order.
func known() -> Array[StringName]:
	var out: Array[StringName] = []
	for id in ALL:
		if _known.has(id):
			out.append(id)
	return out


## When a tool showed itself (-1 if it has not).
func since(id: StringName) -> int:
	return int(_known.get(id, -1))


## Shows a tool. `quiet`: without telling anyone (found again on opening a
## world). True if it was new.
func reveal(id: StringName, now: int, quiet: bool = false) -> bool:
	if not ALL.has(id) or _known.has(id):
		return false
	_known[id] = now
	if not quiet:
		revealed.emit(id)
	return true


# --- what gives the player the idea -----------------------------------------------------------------

## The weather has changed to `state`.
func on_weather(state: StringName, now: int, quiet: bool = false) -> void:
	if state == WeatherSystem.RAIN or state == WeatherSystem.HEAVY_RAIN or state == WeatherSystem.STORM:
		reveal(RAIN, now, quiet)
	if state == WeatherSystem.STORM:
		reveal(WIND, now, quiet)


## A crop stands dry in the field.
func on_dry_crop(now: int, quiet: bool = false) -> void:
	reveal(RAIN, now, quiet)


## The water has been touched `times` times in all.
func on_water_touched(times: int, now: int, quiet: bool = false) -> void:
	if times >= Config.tools.water_touches:
		reveal(WATER, now, quiet)


# --- saving -----------------------------------------------------------------------------------------

func to_dict() -> Dictionary:
	var known_saved := {}
	for id: StringName in _known:
		known_saved[String(id)] = int(_known[id])
	return {"known": known_saved}


func from_dict(data: Dictionary) -> void:
	_known.clear()
	var saved: Variant = data.get("known")
	if typeof(saved) != TYPE_DICTIONARY:
		return
	for key: Variant in saved:
		var id := StringName(str(key))
		if ALL.has(id) and typeof((saved as Dictionary)[key]) == TYPE_INT:
			_known[id] = int(saved[key])
