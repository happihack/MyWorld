class_name ConstructionSystem
extends RefCounted
## Building (bible §17.2, M12.1): projects — a building going up on its site,
## or one being repaired — with the materials they need, what has been
## brought, and the work done. Builders carry the materials there themselves
## (from the stores) and build as far as what has been brought allows; the
## site shows how far it is (stakes, then a frame), and when it is done the
## building stands. Buildings wear: floods and storms damage them (and they
## are repaired), and a home nobody lives in falls apart into a ruin.
##
## Project record (plain data, saved):
##   {"id", "kind": "build" | "repair", "def": building id, "tile": Vector2i,
##    "site": prop id (the site, or the building repaired), "needed": {res -> units},
##    "delivered": {res -> units}, "labor": strokes, "done": float, "started": tick,
##    "builders": {person id (String) -> strokes}}

signal begun(project: Dictionary)
signal finished(project: Dictionary, building_id: int)
signal repaired(project: Dictionary, building_id: int)
signal damaged(building_id: int, why: StringName)
## `why`: &"empty" (nobody lived in it), &"worn" (damage), &"washed" (a bridge gone).
signal ruined(building_id: int, def_id: StringName, why: StringName)

const BUILD := "build"
const REPAIR := "repair"
## The site's look as the work goes on (PropData.variant of a SITE).
const STAKES := 0
const FRAME := 1
## From this share of the work the frame stands.
const FRAME_FROM := 0.4

var buildings: BuildingLibrary
## How a settlement roofs its homes: Callable(settlement id) -> int (the hut's
## variant, CultureSystem.architecture_of); unset: the band's way.
var style_of := Callable()
## Every settlement (M12.3; null: only the first). Each project is of one.
var settlements: Settlements
var _props: PropRegistry
var _ids: IdAllocator
var _start: WorldSetup.StartInfo
var _people: PersonRegistry
var _config: ConstructionConfig
var _projects: Array[Dictionary] = []
var _next_id := 1
var _empty_since: Dictionary = {} # home id -> tick it was last lived in
## The homes of settlements that have been abandoned (M12.5): nobody's, they fall into ruin in time.
var abandoned_homes: Array[int] = []
var _day := -1_000_000
var _standing: Dictionary = {} # prop kind -> ids, while the props are as they were
var _standing_version := -1


func bind(props: PropRegistry, ids: IdAllocator, library: BuildingLibrary, start: WorldSetup.StartInfo,
		people: PersonRegistry, now: int, config: ConstructionConfig = null) -> void:
	_props = props
	_ids = ids
	buildings = library
	_start = start
	_people = people
	_config = config if config != null else Config.construction
	_projects.clear()
	_next_id = 1
	_empty_since.clear()
	_day = Config.time.day_index(now)


# --- what there is ----------------------------------------------------------------------------------

## What stands in the world (the sites and buildings among it).
func props() -> PropRegistry:
	return _props


func projects() -> Array[Dictionary]:
	return _projects


func project(id: int) -> Dictionary:
	for p in _projects:
		if int(p["id"]) == id:
			return p
	return {}


## The project going on at a site (or for a building being repaired) ({}: none).
func project_at(prop_id: int) -> Dictionary:
	for p in _projects:
		if int(p["site"]) == prop_id:
			return p
	return {}


## New buildings being built (not repairs) — of one settlement (-1: of all).
func builds(settlement_id: int = -1) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for p in _projects:
		if str(p["kind"]) == BUILD and (settlement_id < 0 or settlement_of(p) == settlement_id):
			out.append(p)
	return out


## The projects of one settlement (M12.3).
func projects_of(settlement_id: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for p in _projects:
		if settlement_of(p) == settlement_id:
			out.append(p)
	return out


## Which settlement a project is of (a project from before there were more: the first).
func settlement_of(p: Dictionary) -> int:
	return int(p.get("settlement", _start.settlement_id if _start != null else 0))


## The start (fire, homes) of a project's settlement.
func _start_of(p: Dictionary) -> WorldSetup.StartInfo:
	var own := settlements.get_settlement(settlement_of(p)) if settlements != null else null
	return own.start_info() if own != null else _start


## Every building of a kind that stands (prop ids, in order).
func standing(prop_kind: int) -> Array[int]:
	var out: Array[int] = []
	if _props == null:
		return out
	# (Asked for often — every job board's refresh — and the props seldom change: kept until they do.)
	if _standing_version != _props.version:
		_standing_version = _props.version
		_standing.clear()
	if _standing.has(prop_kind):
		out.assign(_standing[prop_kind])
		return out
	for prop in _props.all_props():
		if prop.kind == prop_kind:
			out.append(prop.id)
	out.sort()
	_standing[prop_kind] = out.duplicate()
	return out


## What a project still needs brought: {resource -> units}.
func still_needed(p: Dictionary) -> Dictionary:
	var out := {}
	var delivered: Dictionary = p.get("delivered", {})
	for resource: Variant in p.get("needed", {}):
		var left := int(p["needed"][resource]) - int(delivered.get(str(resource), 0))
		if left > 0:
			out[StringName(str(resource))] = left
	return out


## How far what has been brought lets the work go (0 … 1).
func brought_share(p: Dictionary) -> float:
	var needed := 0
	var delivered := 0
	for resource: Variant in p.get("needed", {}):
		needed += int(p["needed"][resource])
		delivered += mini(int((p.get("delivered", {}) as Dictionary).get(str(resource), 0)), int(p["needed"][resource]))
	return 1.0 if needed <= 0 else float(delivered) / float(needed)


## Can someone build on now (there is work left that what has been brought allows)?
func can_work(p: Dictionary) -> bool:
	return float(p["done"]) < float(p["labor"]) * brought_share(p) - 0.001


## How far it is, 0 … 1.
func progress(p: Dictionary) -> float:
	return clampf(float(p["done"]) / maxf(float(p["labor"]), 1.0), 0.0, 1.0)


func debug_text() -> String:
	var parts := PackedStringArray()
	for p in _projects:
		parts.append("%s %s %.0f%% (brought %.0f%%)" % [p["kind"], p["def"], progress(p) * 100.0, brought_share(p) * 100.0])
	return "construction: %s" % (", ".join(parts) if not parts.is_empty() else "nothing")


# --- building -----------------------------------------------------------------------------------------

## Begins a building of `def_id` on `tile`: its site is staked out. Returns the
## project ({}: it cannot be).
func start(def_id: StringName, tile: Vector2i, now: int, rotation_step: int = 0, settlement_id: int = -1) -> Dictionary:
	var def := buildings.get_def(def_id) if buildings != null else null
	if def == null or _props == null or _props.prop_at(tile) != null:
		return {}
	var site := PropData.new()
	site.id = _ids.next_id()
	# (A bridge is built where it will stand, in the ford: people wade past it meanwhile.)
	site.kind = PropData.Kind.BRIDGE if def.has_tag("bridge") else PropData.Kind.SITE
	site.tile = tile
	site.variant = STAKES
	site.rotation_step = rotation_step
	if not _props.add(site):
		return {}
	var p := {"id": _next_id, "kind": BUILD, "def": String(def_id), "tile": tile, "site": site.id,
		"needed": _units_of(def.materials), "delivered": {}, "labor": def.labor, "done": 0.0, "started": now, "builders": {},
		"settlement": settlement_id if settlement_id >= 0 else (_start.settlement_id if _start != null else 0)}
	_next_id += 1
	_projects.append(p)
	begun.emit(p)
	return p


## `units` of `resource` brought to a project. Returns how many it took (what
## it does not need any more is not taken).
func deliver(p: Dictionary, resource: StringName, units: int) -> int:
	var wanted := int(still_needed(p).get(resource, 0))
	var taken := mini(units, wanted)
	if taken <= 0:
		return 0
	var delivered: Dictionary = p["delivered"]
	delivered[String(resource)] = int(delivered.get(String(resource), 0)) + taken
	return taken


## `person` works at a project for `minutes`: strokes of building, as far as
## what has been brought allows. Returns whether it is now finished.
func work(p: Dictionary, person: PersonData, minutes: float, now: int) -> bool:
	if not can_work(p):
		return false
	var skill := float(person.skills.get("builder", 0.0)) if person != null else 0.0
	var strokes := minutes * _config.strokes_per_minute * (0.5 + skill)
	var cap := float(p["labor"]) * brought_share(p)
	var before := float(p["done"])
	p["done"] = minf(before + strokes, cap)
	if person != null:
		var builders: Dictionary = p["builders"]
		builders[str(person.id)] = float(builders.get(str(person.id), 0.0)) + float(p["done"]) - before
	# The site shows how far it has come.
	var site := _props.get_prop(int(p["site"])) if str(p["kind"]) == BUILD else null
	if site != null and (site.kind == PropData.Kind.SITE or site.kind == PropData.Kind.BRIDGE) and progress(p) >= FRAME_FROM \
			and site.variant == STAKES:
		site.variant = FRAME
		_props.touch(site.id)
	if float(p["done"]) >= float(p["labor"]) - 0.001 and still_needed(p).is_empty():
		_finish(p, now)
		return true
	return false


## Who built most of it, most first (person ids).
static func builders_of(p: Dictionary) -> Array[int]:
	var out: Array[int] = []
	var by: Dictionary = p.get("builders", {})
	for key: Variant in by:
		out.append(int(str(key)))
	out.sort_custom(func(a: int, b: int) -> bool:
		return float(by[str(a)]) > float(by[str(b)]) or (float(by[str(a)]) == float(by[str(b)]) and a < b))
	return out


func _finish(p: Dictionary, now: int) -> void:
	_projects.erase(p)
	if str(p["kind"]) == REPAIR:
		var building := _props.get_prop(int(p["site"]))
		if building != null:
			building.condition = PropData.SOUND
			_props.touch(building.id)
		repaired.emit(p, int(p["site"]))
		return
	var def := buildings.get_def(StringName(str(p["def"])))
	var tile: Vector2i = p["tile"]
	var building := _props.get_prop(int(p["site"]))
	if building != null and building.kind == def.prop_kind:
		# (Built where it stands: a bridge.)
		building.variant = PropData.BRIDGE_DONE
		building.condition = PropData.SOUND
		_props.touch(building.id)
	else:
		_props.remove(int(p["site"]))
		building = PropData.new()
		building.id = _ids.next_id()
		building.kind = def.prop_kind as PropData.Kind
		building.tile = tile
		building.rotation_step = 0
		# Homes are roofed as their settlement roofs them (M17.1).
		if def.has_tag("home") and style_of.is_valid():
			building.variant = int(style_of.call(settlement_of(p)))
		if not _props.add(building):
			return
	var own := _start_of(p)
	if def.has_tag("home") and own != null and not own.hut_ids.has(building.id):
		own.hut_ids.append(building.id)
		_empty_since[building.id] = now
	# The builders grow better at it.
	for id in builders_of(p):
		var person := _people.get_person(id) if _people != null else null
		if person != null:
			person.skills["builder"] = clampf(float(person.skills.get("builder", 0.0)) + _config.skill_per_building, 0.0, 1.0)
	finished.emit(p, building.id)


# --- wear ---------------------------------------------------------------------------------------------

## Something takes from a building's condition (a flood, a storm). Below the
## line a repair is begun; at nothing it falls (a ruin).
func damage(building_id: int, amount: int, why: StringName, now: int) -> void:
	var building := _props.get_prop(building_id) if _props != null else null
	if building == null or not building.is_building() or amount <= 0:
		return
	var was := building.condition
	building.condition = maxi(building.condition - amount, 0)
	_props.touch(building.id)
	# (What history notes: damage that needs mending — not every storm's wear.)
	if building.condition < _config.repair_below and (was >= _config.repair_below or amount >= _config.repair_below / 2):
		damaged.emit(building.id, why)
	if building.condition <= 0:
		_ruin(building, &"washed" if building.kind == PropData.Kind.BRIDGE else &"worn")
	elif building.condition < _config.repair_from and not _left_to_fall(building, now):
		start_repair(building, now)


## Begins repairing a building (unless that is going on already). Returns the project.
func start_repair(building: PropData, now: int) -> Dictionary:
	var going := project_at(building.id)
	if not going.is_empty():
		return going
	var def := buildings.of_kind(building.kind) if buildings != null else null
	if def == null:
		return {}
	var worn := 1.0 - float(building.condition) / float(PropData.SOUND)
	var needed := {}
	for resource: Variant in def.materials:
		var units := ceili(int(def.materials[resource]) * _config.repair_material_share * worn)
		if units > 0:
			needed[str(resource)] = units
	var owner := settlements.nearest(building.tile) if settlements != null else null
	var p := {"id": _next_id, "kind": REPAIR, "def": String(def.id), "tile": building.tile, "site": building.id,
		"needed": needed, "delivered": {}, "labor": maxi(roundi(def.labor * _config.repair_labor_share * worn), 1), "done": 0.0,
		"started": now, "builders": {},
		"settlement": owner.id if owner != null else (_start.settlement_id if _start != null else 0)}
	_next_id += 1
	_projects.append(p)
	return p


## Once a game day: homes nobody lives in fall apart, little by little.
func advance_to(now: int) -> void:
	if _props == null or _start == null:
		return
	var today := Config.time.day_index(now)
	if _day == -1_000_000 or today < _day:
		_day = today
		return
	if today == _day:
		return
	var days := mini(today - _day, 30)
	_day = today
	# What is worn is mended (by the builders: a repair, worked like a build).
	for prop in _props.all_props():
		if prop.is_building() and prop.condition < _config.repair_from and project_at(prop.id).is_empty() \
				and not _left_to_fall(prop, now):
			start_repair(prop, now)
	var homes: Array[int] = settlements.all_homes() if settlements != null and settlements.size() > 0 else _start.hut_ids.duplicate()
	homes.append_array(abandoned_homes)
	for home_id: int in homes:
		var home := _props.get_prop(home_id)
		if home == null:
			continue
		if _people != null and not _people.living_in(home_id).is_empty():
			_empty_since[home_id] = now
			continue
		var since := int(_empty_since.get(home_id, now))
		_empty_since[home_id] = since
		# (Only the days it has stood empty past the first few count.)
		var past := (now - since) / TimeConfig.MINUTES_PER_DAY - _config.empty_home_days
		if past <= 0:
			continue
		home.condition = maxi(home.condition - _config.decay_per_day * mini(days, past), 0)
		_props.touch(home.id)
		if home.condition <= 0:
			_ruin(home, &"empty")


## A home abandoned, or one nobody has lived in for a while (past the days it
## stands empty before it decays): not mended — it is left to fall.
func _left_to_fall(building: PropData, now: int) -> bool:
	if abandoned_homes.has(building.id):
		return true
	if building.kind != PropData.Kind.HUT or _people == null or not _people.living_in(building.id).is_empty():
		return false
	var since := int(_empty_since.get(building.id, now))
	return (now - since) / TimeConfig.MINUTES_PER_DAY > _config.empty_home_days


## A building has fallen: what is left of it is a ruin (and history).
func _ruin(building: PropData, why: StringName) -> void:
	var def := buildings.of_kind(building.kind) if buildings != null else null
	var going := project_at(building.id)
	if not going.is_empty():
		_projects.erase(going)
	_start.hut_ids.erase(building.id)
	abandoned_homes.erase(building.id)
	if settlements != null:
		for own in settlements.all():
			own.start_info().hut_ids.erase(building.id)
	_empty_since.erase(building.id)
	var tile := building.tile
	var id := building.id
	_props.remove(id)
	if building.kind == PropData.Kind.BRIDGE:
		# (Washed away: nothing is left standing in the ford.)
		ruined.emit(id, def.id if def != null else &"", why)
		return
	var ruin := PropData.new()
	ruin.id = _ids.next_id()
	ruin.kind = PropData.Kind.RUIN
	ruin.tile = tile
	_props.add(ruin)
	ruined.emit(ruin.id, def.id if def != null else &"", why)


## A settlement has been abandoned: what it was building is left undone (its
## sites taken away), and its homes are nobody's — they fall into ruin in time.
func abandon(settlement_id: int, homes: Array[int]) -> void:
	for p in projects_of(settlement_id):
		_projects.erase(p)
		var site := _props.get_prop(int(p["site"])) if _props != null else null
		if site != null and str(p["kind"]) == BUILD and site.kind == PropData.Kind.SITE:
			_props.remove(site.id)
	for id in homes:
		if not abandoned_homes.has(id):
			abandoned_homes.append(id)


## Materials as plain data: resource id (String) -> units.
static func _units_of(materials: Dictionary) -> Dictionary:
	var out := {}
	for resource: Variant in materials:
		out[str(resource)] = int(materials[resource])
	return out


# --- saving -------------------------------------------------------------------------------------------

func to_dict() -> Dictionary:
	var empty := {}
	for id: int in _empty_since:
		empty[str(id)] = _empty_since[id]
	return {"next_id": _next_id, "projects": _projects.duplicate(true), "empty_since": empty, "day": _day,
		"abandoned_homes": abandoned_homes.duplicate()}


## Returns how many saved projects were unusable (their site is gone, …).
func from_dict(data: Dictionary) -> int:
	_projects.clear()
	_next_id = maxi(int(data.get("next_id", 1)), 1)
	if typeof(data.get("day")) == TYPE_INT:
		_day = data["day"]
	var skipped := 0
	if typeof(data.get("projects")) == TYPE_ARRAY:
		for entry: Variant in data["projects"]:
			if typeof(entry) != TYPE_DICTIONARY or not (entry as Dictionary).has_all(["id", "kind", "def", "site", "labor"]) \
					or typeof(entry["tile"]) != TYPE_VECTOR2I or _props == null or _props.get_prop(int(entry["site"])) == null \
					or buildings == null or not buildings.has_def(StringName(str(entry["def"]))):
				skipped += 1
				continue
			var p: Dictionary = (entry as Dictionary).duplicate(true)
			p["done"] = clampf(float(p.get("done", 0.0)), 0.0, float(p["labor"]))
			for key: String in ["needed", "delivered", "builders"]:
				if typeof(p.get(key)) != TYPE_DICTIONARY:
					p[key] = {}
			_projects.append(p)
			_next_id = maxi(_next_id, int(p["id"]) + 1)
	abandoned_homes.clear()
	if typeof(data.get("abandoned_homes")) == TYPE_ARRAY:
		for id: Variant in data["abandoned_homes"]:
			if typeof(id) == TYPE_INT and _props != null and _props.get_prop(id) != null:
				abandoned_homes.append(id)
	if typeof(data.get("empty_since")) == TYPE_DICTIONARY:
		for key: Variant in data["empty_since"]:
			_empty_since[int(str(key))] = int(data["empty_since"][key])
	return skipped
