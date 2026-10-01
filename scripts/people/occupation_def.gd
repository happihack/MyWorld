class_name OccupationDef
extends Resource
## What someone does with their days (bible §13.6). One file per occupation in
## res://data/occupations/; nothing in code names an occupation that the data
## does not define.

## Stable id (saved with people; never rename).
@export var id: StringName = &""
## Stages of life in which someone can have this occupation (PersonData.LifeStage).
@export var life_stages: Array[PersonData.LifeStage] = [PersonData.LifeStage.ADULT]
## How much of a starting band takes this up, relative to the others open to
## the same stage of life (0 = nobody starts with it).
@export_range(0.0, 10.0, 0.05) var starting_share: float = 1.0
## Which traits draw people to it: Traits.Axis name -> weight (negative = the
## opposite end of the axis).
@export var trait_weights: Dictionary = {}
## What someone with this occupation carries ("staff", "basket", "axe" — see
## PersonMeshLibrary), or nothing.
@export var accessory: StringName = &""
## What the work is done at: "tree", "bush", "fire" — or nothing (no work to
## go to: children, placeholders).
@export var work_target: StringName = &""
## Something that has no work to do yet (kept so saves and data can refer to it).
@export var placeholder: bool = false
## The shape of a day (bible §13.5), as "HH:MM activity" entries in order:
##   "06:00 wake", "07:00 eat", "08:00 work", "12:00 eat", "13:00 work",
##   "17:00 socialize", "19:00 eat", "21:00 sleep"
## Each entry holds until the next (the last one over midnight until the
## first). The activity is an ActivityDef id; "wake" means nothing in
## particular. A routine is *soft*: the Brain gives what is due a push,
## never an order.
@export var routine: PackedStringArray = PackedStringArray()

var _routine_ready := false
var _slot_hours := PackedFloat32Array()
var _slot_ids: Array[StringName] = []


func allows(stage: PersonData.LifeStage) -> bool:
	return life_stages.has(stage)


## How well a person's traits suit this occupation (0 = indifferent).
func affinity(traits: PackedFloat32Array) -> float:
	var total := 0.0
	for axis_name: Variant in trait_weights:
		var axis: int = Traits.Axis.get(str(axis_name), -1)
		if axis < 0:
			continue
		var lean := Traits.value(traits, axis)
		if Traits.is_amount(axis):
			lean = lean * 2.0 - 1.0
		total += lean * float(trait_weights[axis_name])
	return total


## Gives the occupation another routine (tests; tuning at run time).
func set_routine(entries: PackedStringArray) -> void:
	routine = entries
	_routine_ready = false


## What the routine has for `hour` (0 … 24): an activity id, or &"" if
## nothing in particular (or there is no routine).
func scheduled(hour: float) -> StringName:
	var slot := _slot_at(hour)
	return _slot_ids[slot] if slot >= 0 else &""


## How long ago (hours) what is scheduled at `hour` began.
func hours_into_slot(hour: float) -> float:
	var slot := _slot_at(hour)
	if slot < 0:
		return 0.0
	return fposmod(fposmod(hour, 24.0) - _slot_hours[slot], 24.0)


## The routine as [[hour, activity id], ...], in order.
func slots() -> Array:
	_compile_routine()
	var out: Array = []
	for i in _slot_ids.size():
		out.append([_slot_hours[i], _slot_ids[i]])
	return out


## One entry of a routine: [hour (0 … 24, -1 if unreadable), activity id].
static func parse_entry(text: String) -> Array:
	var parts := text.strip_edges().split(" ", false)
	if parts.size() != 2:
		return [-1.0, &""]
	var clock := parts[0].split(":")
	if clock.size() != 2 or not clock[0].is_valid_int() or not clock[1].is_valid_int():
		return [-1.0, &""]
	var hour := float(int(clock[0])) + float(int(clock[1])) / 60.0
	if hour < 0.0 or hour >= 24.0 or int(clock[1]) > 59:
		return [-1.0, &""]
	return [hour, &"" if parts[1] == "wake" else StringName(parts[1])]


func _slot_at(hour: float) -> int:
	_compile_routine()
	if _slot_ids.is_empty():
		return -1
	var h := fposmod(hour, 24.0)
	var slot := _slot_ids.size() - 1 # before the first entry: still the last of yesterday
	for i in _slot_hours.size():
		if h >= _slot_hours[i]:
			slot = i
	return slot


func _compile_routine() -> void:
	if _routine_ready:
		return
	_routine_ready = true
	_slot_hours = PackedFloat32Array()
	_slot_ids = []
	for entry in routine:
		var parsed := parse_entry(entry)
		if float(parsed[0]) >= 0.0:
			_slot_hours.append(parsed[0])
			_slot_ids.append(parsed[1])


func validate() -> PackedStringArray:
	var problems := PackedStringArray()
	var last := -1.0
	for entry in routine:
		var parsed := parse_entry(entry)
		if float(parsed[0]) < 0.0:
			problems.append("%s: routine entry '%s' is not 'HH:MM activity'" % [id, entry])
		elif float(parsed[0]) <= last:
			problems.append("%s: routine entry '%s' is out of order" % [id, entry])
		last = maxf(last, float(parsed[0]))
	if id == &"":
		problems.append("occupation has no id")
	if life_stages.is_empty():
		problems.append("%s: no life stage can have it" % id)
	for axis_name: Variant in trait_weights:
		if not Traits.Axis.has(str(axis_name)):
			problems.append("%s: unknown trait axis '%s'" % [id, axis_name])
	return problems
