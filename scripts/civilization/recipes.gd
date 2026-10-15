class_name Recipes
extends RefCounted
## What is made at a building (buildings & villagers W1, F1's `recipe`): a step
## is {"in": {resource: units}, "out": {resource: units}, "minutes": n}. The
## worker takes the inputs from the stores, works the minutes at the
## building, and the outputs go to the stores (as the toolmaker's tools, and
## FB5's nets, always did). The first step that can be made now is made.


## The building of `def_id` that `own` keeps near its fire (null: none).
static func workplace(own: Settlement, def: BuildingDef) -> PropData:
	if own == null or def == null or own.planner == null or own.props() == null:
		return null
	var ids := own.planner.standing_near(def.prop_kind)
	return own.props().get_prop(ids[0]) if not ids.is_empty() else null


## The first step of `def`'s recipe that can be made now from `own`'s stores,
## with room for what comes of it (-1: none).
static func next_step(own: Settlement, def: BuildingDef) -> int:
	if own == null or def == null:
		return -1
	for i in def.recipe.size():
		var step: Dictionary = def.recipe[i]
		var enough := true
		for resource: Variant in step.get("in", {}):
			enough = enough and own.stockpile.available(StringName(str(resource))) >= int(step["in"][resource])
		var room := true
		for resource: Variant in step.get("out", {}):
			room = room and own.stockpile.room(StringName(str(resource))) >= int(step["out"][resource])
			# ("keep": made only while the stores hold less than this — a quarry
			# with nothing put in would quarry for ever.)
			if step.has("keep"):
				room = room and own.stockpile.amount(StringName(str(resource))) < int(step["keep"])
		if enough and room:
			return i
	return -1


## A step made: the inputs out of the stores, the outputs in. False if they
## are no longer there (someone took them meanwhile).
static func make(own: Settlement, def: BuildingDef, index: int) -> bool:
	if own == null or def == null or index < 0 or index >= def.recipe.size():
		return false
	var step: Dictionary = def.recipe[index]
	for resource: Variant in step.get("in", {}):
		if own.stockpile.available(StringName(str(resource))) < int(step["in"][resource]):
			return false
	for resource: Variant in step.get("in", {}):
		own.stockpile.take(StringName(str(resource)), int(step["in"][resource]))
	for resource: Variant in step.get("out", {}):
		own.stockpile.add(StringName(str(resource)), int(step["out"][resource]))
	return true


## The workplaces of `occupation` that `own` has, with something to make
## there now: [[BuildingDef, PropData, step index], …].
static func work_for(own: Settlement, occupation: OccupationDef, buildings: BuildingLibrary) -> Array:
	var out: Array = []
	if own == null or occupation == null or buildings == null:
		return out
	for place in occupation.workplaces:
		var def := buildings.get_def(StringName(place))
		var at := workplace(own, def)
		var step := next_step(own, def) if at != null else -1
		if step >= 0:
			out.append([def, at, step])
	return out
