class_name SettlementPlanner
extends RefCounted
## What a settlement builds (bible §17.2, M12.1): the player never places a
## building — once a game day the settlement weighs its needs and, if one of
## them calls for a building and nothing is being built yet (a home: no other
## home), it begins one
## on the best ground for it.
##
##   homes full (or someone without a roof,   → a hut
##   or two households crowded under one)
##   the stores overflowing, food going bad   → a storehouse
##   water to drink far from the fire         → a well
##   land near the fire cut off by water      → a bridge across, bank to bank,
##     (a crossing: tile by tile, the near      (Crossing; at the owner's word,
##     bank first)                               2026-10-04 — it was one tile
##                                               over a ford waded often, M12.2)
##   (crafting and the knowing of toolmaking  → a workshop: M12.4, M18)
##
## Where: open, dry ground a few tiles from the fire, above the highest water
## the settlement remembers, clear of other buildings and of the graves, as
## even as can be and as near as can be (unevenness and distance weigh against it).
## A hut for someone without a roof, when no such ground is within reach, goes
## on the highest dry ground there is, where the river has been or not: better
## a hut on the floodplain than none (the owner's flood test, 2026-10-14).

var _settlement: Settlement
var _construction: ConstructionSystem
var _people: PersonRegistry
var _households: Households
var _traffic: Traffic
## What its people believe together (M17.2: a shrine for a myth many hold).
var faith: MythSystem
## What the settlement values: its culture's profile weighs its needs (F4).
var cultures: CultureSystem
## What is further than this from the fire is not this settlement's to build or keep.
const NEAR_REACH := 16.0
var _world: WorldData
var _pathfinder: Pathfinder
var _config: ConstructionConfig
var _day := -1_000_000
var _spoiled: Array = [] # [day, units]
## The crossing worked out today: [day, {tiles, turn}] (it takes a walk over the land).
var _crossing_today: Array = [[], {}]
var _crossing_day := -1_000_000


func bind(settlement: Settlement, construction: ConstructionSystem, people: PersonRegistry, world: WorldData,
		pathfinder: Pathfinder, now: int, config: ConstructionConfig = null, households: Households = null,
		traffic: Traffic = null) -> void:
	_settlement = settlement
	_households = households
	_traffic = traffic
	_construction = construction
	_people = people
	_world = world
	_pathfinder = pathfinder
	_config = config if config != null else Config.construction
	_day = Config.time.day_index(now)
	_spoiled.clear()
	if _settlement != null and not _settlement.spoiled.is_connected(_on_spoiled):
		_settlement.spoiled.connect(_on_spoiled)


## Once a game day (by daylight): what is needed, and whether to begin building it.
func advance_to(now: int) -> void:
	if _settlement == null or _construction == null:
		return
	var today := Config.time.day_index(now)
	if _day == -1_000_000 or today < _day:
		_day = today
		return
	# (The way over the water is worked out an hour before the plan, on a frame
	# of its own: the two together were the last regular stall on the phone —
	# profiling, 2026-10-14. `crossing` keeps what it found for the day.)
	var minute := Config.time.minute_of_day(now)
	if today != _day and _crossing_day != today and minute >= 7 * 60 + _stagger() and minute < 8 * 60 + _stagger():
		_crossing_day = today
		crossing(now)
		return
	# (Called once a day, after the hour — the time away: both at once, as before.)
	# (By daylight — each settlement at its own hour, so that their planning
	# does not all fall on one frame: profiling, 2026-10-06.)
	if today == _day or Config.time.minute_of_day(now) < 8 * 60 + _stagger():
		return
	_day = today
	if _households != null:
		_households.settle_empty_homes()
	plan(now)


## Weighs the needs now; begins the building the most pressing one calls for.
## Returns the project begun ({}: none).
func plan(now: int) -> Dictionary:
	var going := _construction.builds(_settlement.id)
	var others := going.filter(func(p: Dictionary) -> bool: return str(p["def"]) != "hut").size()
	for need: StringName in scored_needs(now):
		# One building at a time (two, with builders for two: F4) — but a home
		# does not wait for anything else.
		if need == &"home" and going.any(func(p: Dictionary) -> bool: return str(p["def"]) == "hut"):
			continue
		if need != &"home" and others >= builds_at_once():
			continue
		var def := _construction.buildings.with_tag(String(need))
		if def.is_empty() or (def[0].tech != &"" and not _settlement.knows_how(def[0].tech)):
			continue
		# Built in place of one that stands, if it is an upgrade (F4).
		if def[0].upgrade_of != &"":
			var upgrade := _upgrade(def[0], now)
			if not upgrade.is_empty():
				return upgrade
			continue
		if need == &"bridge":
			var across := crossing(now)
			for tile: Vector2i in across.get("tiles", []):
				if Crossing.is_bridge(_construction.props(), tile):
					continue # (built, or going up)
				return _construction.start(def[0].id, tile, now, int(across["turn"]), _settlement.id)
			continue
		if need == &"landing" or need == &"net_rack" or need == &"fish_trap":
			var bank: Variant = landing_site()
			if bank == null:
				continue
			return _construction.start(def[0].id, bank[0], now, int(bank[1]), _settlement.id)
		var site: Variant = shrine_site() if need == &"shrine" else site_for(def[0])
		if site == null:
			continue
		return _construction.start(def[0].id, site, now, 0, _settlement.id)
	return {}


## What calls for a building now, the most pressing first: "home", "storage", "water".
func needs(now: int) -> Array[StringName]:
	var out: Array[StringName] = []
	if homes_short():
		out.append(&"home")
	if storage_short(now):
		out.append(&"storage")
	if material_storage_short():
		out.append(&"material_storage")
	if water_far():
		out.append(&"water")
	if workshop_wanted():
		out.append(&"workshop")
	# (What knowing and believing call for before another bridge: a river
	# world always has more water to cross, and its kilns, stone circles and
	# shrines never had their turn — the 200-year soaks.)
	for tag: String in LANDMARKS:
		if landmark_wanted(tag):
			out.append(StringName(tag))
	if shrine_wanted():
		out.append(&"shrine")
	if not crossing(now).is_empty():
		out.append(&"bridge")
	if landing_wanted():
		out.append(&"landing")
	if net_rack_wanted():
		out.append(&"net_rack")
	if fish_trap_wanted():
		out.append(&"fish_trap")
	for need: StringName in [&"smokehouse", &"seed_store", &"granary"]:
		if food_building_wanted(need):
			out.append(need)
	return out


## A landing (M19.5): once they build rafts and someone fishes, by the water
## near the fire — one.
func landing_wanted() -> bool:
	return _settlement.knows_how(&"raft") and _settlement.fisher_count() > 0 and not _at_limit_of(&"landing")


func _at_limit_of(def_id: StringName) -> bool:
	var def := _construction.buildings.get_def(def_id) if _construction != null else null
	return def == null or at_limit(def)


## The food buildings of W1 (buildings & villagers): a smokehouse once meat or
## fish is brought in, to keep it past its few days; a seed store once there
## are fields; a granary in place of a storehouse once a farming settlement
## keeps grain enough to want it. The data says how big the settlement must
## be, what must be known, and how many it keeps.
func food_building_wanted(tag: StringName) -> bool:
	var defs := _construction.buildings.with_tag(String(tag)) if _construction != null else []
	if defs.is_empty():
		return false
	var def: BuildingDef = defs[0]
	if not big_enough(def) or at_limit(def) or (def.tech != &"" and not _settlement.knows_how(def.tech)):
		return false
	match tag:
		&"smokehouse":
			return float(_settlement.produced.get("fish", 0.0)) + float(_settlement.produced.get("meat", 0.0)) >= SMOKE_FROM
		&"seed_store":
			return _settlement.farming != null and _settlement.farming.plot_count() > 0
		&"granary":
			return _settlement.farming != null and _settlement.farming.farmer_count() >= 2 \
					and not standing_near(PropData.Kind.STOREHOUSE).is_empty()
	return false


## Meat and fish brought in of late (Settlement.produced) before a smokehouse is wanted.
const SMOKE_FROM := 20.0


## A rack to dry and mend the nets on (FB5): once they make nets and someone
## fishes — one, on the bank.
func net_rack_wanted() -> bool:
	return _settlement.knows_how(&"nets") and _settlement.fisher_count() > 0 and not _at_limit_of(&"net_rack")


## A fish trap at the bank (FB5): for a settlement that fishes and has no
## boats to go out in (no landing) — one.
func fish_trap_wanted() -> bool:
	return _settlement.fisher_count() > 0 and standing_near(PropData.Kind.LANDING).is_empty() \
			and not _at_limit_of(&"fish_trap")


## Where the landing goes: buildable ground on the bank nearest the fire, its
## jetty turned out over the water. [tile, rotation step] — null: no bank in reach.
func landing_site() -> Variant:
	var fire := _settlement.fire()
	if fire == null or _pathfinder == null or not _pathfinder.is_bound():
		return null
	var graves := _resting_tiles()
	var best: Variant = null
	var best_distance := INF
	for water in _pathfinder.shore_tiles():
		if Vector2(water - fire.tile).length() > NEAR_REACH:
			continue
		for step: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var bank := water - step
			var distance := Vector2(bank - fire.tile).length()
			if distance < best_distance and _world.get_water(bank) <= 0.0 and _buildable_on_bank(bank, graves):
				# (The jetty runs towards -Z unturned: turned to point at the water.)
				var angle := atan2(-float(step.x), -float(step.y))
				best = [bank, posmod(roundi(angle / TAU * 256.0), 256)]
				best_distance = distance
	return best


## Ground for a landing: like any building's, but the water beside it is wanted.
func _buildable_on_bank(tile: Vector2i, graves: Array[Vector2i]) -> bool:
	if not _world.is_in_bounds(tile) or _settlement.props().prop_at(tile) != null:
		return false
	if _pathfinder != null and _pathfinder.is_bound() and not _pathfinder.can_stand(tile):
		return false
	for grave in graves:
		if maxi(absi(grave.x - tile.x), absi(grave.y - tile.y)) < _config.site_grave_distance:
			return false
	return true


## Where to bridge the water (worked out once a day): land near the fire
## that cannot be reached on foot, and the shortest way over to it from
## land that can — straight across, at most `crossing_span_most` tiles of
## water, the near bank first; the bridges of a crossing already begun count
## as built (so it is carried on, and an old one-tile bridge is a start).
## {"tiles": [Vector2i…], "turn": rotation} — {} if there is none to make.
func crossing(now: int) -> Dictionary:
	# (Walking out all the land in reach costs dear — tens of milliseconds a
	# settlement, every day: profiling, 2026-10-06. The land seldom changes:
	# looked at again every few days, or at once when a bridge is begun,
	# built or lost, or what is wanted of one changes.)
	var key := [floori(float(Config.time.day_index(now) + _settlement.id) / CROSSING_EVERY_DAYS), _bridges_known(),
		_config.crossing_span_most, _config.cut_off_least, _config.crossing_from_people, _config.crossing_reach,
		_settlement.member_count() >= _config.crossing_from_people]
	if _crossing_today[0] != key:
		_crossing_today = [key, _find_crossing()]
	return _crossing_today[1]


## How often the land is walked out for a crossing (game days).
const CROSSING_EVERY_DAYS := 5


## Bridges standing or begun (a change means the land is looked at again).
func _bridges_known() -> int:
	var count := _construction.standing(PropData.Kind.BRIDGE).size()
	for p in _construction.builds(_settlement.id):
		if str(p["def"]) == "bridge":
			count += 1
	return count


## Minutes after 08:00 this settlement plans its day (0, 20 or 40).
func _stagger() -> int:
	return posmod(_settlement.id, 3) * 20 if _settlement != null else 0


func _find_crossing() -> Dictionary:
	if _pathfinder == null or _settlement == null or _settlement.member_count() < _config.crossing_from_people:
		return {}
	var fire := _settlement.start_info().settlement_tile
	var reach := _config.crossing_reach
	var area := Rect2i(fire - Vector2i(reach, reach), Vector2i(reach * 2 + 1, reach * 2 + 1)).intersection(_world.bounds)
	# What can be walked to from the fire — marked in a grid over the area (a
	# dictionary of tiles cost the phone a lost frame every five days, for land
	# that is seldom cut off: profiling, 2026-10-14).
	var start := fire
	if not _pathfinder.can_stand(start):
		var near := _pathfinder.standable_near(fire, 1, 3)
		if near.is_empty():
			return {}
		start = near[0]
	if not area.has_point(start):
		return {}
	var width := area.size.x
	var marks := _pathfinder.walk_out(start, area)
	var is_reached := func(tile: Vector2i) -> bool:
		return area.has_point(tile) and marks[(tile.y - area.position.y) * width + (tile.x - area.position.x)] != 0
	# A crossing begun is carried on to the far bank (even where the last of
	# it could be waded).
	var begun := _unfinished(fire, reach, is_reached)
	if not begun.is_empty():
		return begun
	# Land that cannot be walked to: enough of it to want a way over.
	var cut_off := 0
	for i in marks.size():
		if marks[i] == 0:
			@warning_ignore("integer_division")
			var tile := Vector2i(area.position.x + i % width, area.position.y + i / width)
			if _dry(tile) and _pathfinder.can_stand(tile):
				cut_off += 1
	if cut_off < _config.cut_off_least:
		return {}
	# (Only now, with land to reach, the tiles reached as a dictionary, and
	# where a step could not be taken.)
	var reached := {}
	var stopped := {}
	for i in marks.size():
		if marks[i] != 0:
			@warning_ignore("integer_division")
			var tile := Vector2i(area.position.x + i % width, area.position.y + i / width)
			reached[tile] = true
			if marks[i] == 2:
				stopped[tile] = true
	# The shortest way over, nearest the fire.
	var best := {}
	var best_cost := INF
	var props := _construction.props()
	# (Looking at every step from every tile reached costs dear — tens of
	# milliseconds: profiling, 2026-10-06. Tiles reached that are wet, or
	# bridges, are noted once; a way over begins only from dry land beside
	# one of them, or where a step could not be taken.)
	var dry := {}
	var opening := {}
	for tile: Vector2i in reached:
		var is_dry := _dry(tile)
		dry[tile] = is_dry
		if not is_dry or Crossing.is_bridge(props, tile):
			opening[tile] = true
	for from: Vector2i in reached:
		if not dry[from]:
			continue
		if not stopped.has(from) and not opening.has(from + Vector2i.LEFT) and not opening.has(from + Vector2i.RIGHT) \
				and not opening.has(from + Vector2i.UP) and not opening.has(from + Vector2i.DOWN):
			continue
		for step: Vector2i in _STEPS:
			var tiles: Array[Vector2i] = []
			var built := 0
			var at := from + step
			while tiles.size() < _config.crossing_span_most and _world.is_in_bounds(at) and (Crossing.is_bridge(props, at) or not _dry(at)):
				var there := props.prop_at(at) if props != null else null
				if there != null and there.kind != PropData.Kind.BRIDGE:
					tiles.clear()
					break
				tiles.append(at)
				if Crossing.deck_at(props, at) != null:
					built += 1
				at += step
			if tiles.is_empty() or not _world.is_in_bounds(at) or not _dry(at) or reached.has(at) or not _pathfinder.can_stand(at):
				continue
			var cost := (tiles.size() - built) * 10.0 + Vector2(from - fire).length()
			if cost < best_cost:
				best_cost = cost
				best = {"tiles": tiles, "turn": 64 if step.x != 0 else 0}
	return best


## A bridge begun that does not reach dry land on both sides yet (a crossing
## under way, or an old one-tile bridge): the whole way over it, from the bank
## that can be walked to — the nearest the fire; none within CROSSINGS_APART
## of a crossing that is finished (one way over a stretch of water is enough).
func _unfinished(fire: Vector2i, reach: int, is_reached: Callable) -> Dictionary:
	var props := _construction.props()
	if props == null:
		return {}
	var finished: Array[Vector2i] = []
	var open: Array[Dictionary] = []
	var seen := {}
	for prop in props.of_kind(PropData.Kind.BRIDGE):
		if prop.kind != PropData.Kind.BRIDGE or seen.has(prop.tile) or Vector2(prop.tile - fire).length() > reach:
			continue
		var axis := Crossing.axis_of(prop.rotation_step)
		var line := _line_through(prop.tile, axis)
		for tile: Vector2i in line.get("tiles", [prop.tile]):
			seen[tile] = true
		if line.is_empty():
			continue
		if int(line["open"]) == 0:
			finished.append_array(line["tiles"])
		else:
			line["turn"] = prop.rotation_step
			open.append(line)
	var best := {}
	var best_distance := INF
	for line in open:
		var tiles: Array[Vector2i] = line["tiles"]
		var beside := false
		for done in finished:
			for tile in tiles:
				if Vector2(done - tile).length() <= CROSSINGS_APART:
					beside = true
		if beside:
			continue
		if not bool(is_reached.call(line["from"])):
			if not bool(is_reached.call(line["to"])):
				continue
			tiles.reverse() # (from the bank they can walk to)
		var distance := Vector2(tiles[0] - fire).length()
		if distance < best_distance:
			best_distance = distance
			best = {"tiles": tiles, "turn": int(line["turn"])}
	return best


## The way over the water through `tile` along `axis`, bank to bank:
## {"tiles": the water tiles in order, "from"/"to": the dry banks, "open": how
## many have no deck yet} — {} if it does not reach dry land on both sides
## within `crossing_span_most` tiles.
func _line_through(tile: Vector2i, axis: Vector2i) -> Dictionary:
	var props := _construction.props()
	var at := tile
	var span := 0
	while span <= _config.crossing_span_most and _world.is_in_bounds(at) and (Crossing.is_bridge(props, at) or not _dry(at)):
		at -= axis
		span += 1
	if not _world.is_in_bounds(at) or span > _config.crossing_span_most:
		return {}
	var from := at
	var tiles: Array[Vector2i] = []
	var open := 0
	at += axis
	while tiles.size() <= _config.crossing_span_most and _world.is_in_bounds(at) and (Crossing.is_bridge(props, at) or not _dry(at)):
		tiles.append(at)
		if Crossing.deck_at(props, at) == null:
			open += 1
		at += axis
	if tiles.is_empty() or tiles.size() > _config.crossing_span_most or not _world.is_in_bounds(at):
		return {}
	return {"tiles": tiles, "from": from, "to": at, "open": open}


## Crossings closer than this (tiles) are one stretch of water's: one is enough.
const CROSSINGS_APART := 6.0
const _STEPS: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]


## Dry ground (not water, not a wet patch).
func _dry(tile: Vector2i) -> bool:
	return _world.is_in_bounds(tile) and _world.get_water(tile) <= Pathfinder.WET_DEPTH


## Are the homes full (or is someone without a roof)?
func homes_short() -> bool:
	var places := 0
	for home_id in _settlement.start_info().hut_ids:
		places += Config.life.home_room
	var living := _settlement.member_count()
	for person in _settlement.members():
		if person.home_building_id == 0 or not _settlement.start_info().hut_ids.has(person.home_building_id):
			return true # (without a roof)
	# (Not while a home stands empty: it is there to be lived in.)
	for home_id in _settlement.start_info().hut_ids:
		if _people.living_in(home_id).is_empty():
			return false
	# A home two households share with no room left for a child.
	if _households != null and _households.mover(0, true, _settlement.id) != 0:
		return true
	# (An ambitious leader plans homes with a place more to spare, M12.5.)
	var spare := _config.homes_spare_least
	if _settlement.leader_lean(Traits.Axis.AMBITION) >= Config.governance.ambition_homes_from:
		spare += 1
	return places - living < spare


## Are the stores overflowing, or has food been going bad (and no storehouse
## for it yet — or not enough of them)?
func storage_short(now: int) -> bool:
	var stores := standing_near(PropData.Kind.STOREHOUSE).size() + standing_near(PropData.Kind.GRANARY).size()
	var room := _settlement.stockpile.room(&"berries")
	var spoiled := 0
	var today := Config.time.day_index(now)
	for entry: Array in _spoiled:
		if today - int(entry[0]) < _config.spoiled_days:
			spoiled += int(entry[1])
	# (The first once there are a few households — not only once food overflows,
	# which a settlement always a little hungry never sees: the 200-year soaks.)
	if stores == 0 and _settlement.member_count() >= _config.first_store_from:
		return true
	return (room < _config.storage_room_least or spoiled >= _config.spoiled_from) and stores < 1 + _settlement.member_count() / 12


## A woodshed for wood and stone: once the food has a storehouse (wood is
## gathered as it is needed, so its piles seldom overflow — the soak), or
## when there is no room left for them; more of them as the stores fill in
## a bigger settlement.
func material_storage_short() -> bool:
	var sheds := standing_near(PropData.Kind.WOODSHED).size()
	if sheds == 0 and not (standing_near(PropData.Kind.STOREHOUSE).is_empty() and standing_near(PropData.Kind.GRANARY).is_empty()):
		return true
	var stockpile := _settlement.stockpile
	var short := stockpile.room(&"wood") < _config.storage_room_least or stockpile.room(&"stone") < _config.storage_room_least
	return short and sheds < 1 + _settlement.member_count() / 12


## Does it know how to make tools, and is big enough for a workshop, and has none (M12.4)?
func workshop_wanted() -> bool:
	return _settlement.knows_how(&"toolmaking") and _settlement.member_count() >= Config.trade.workshop_from \
		and not _at_limit_of(&"workshop")


## What knowing something calls for (M16.3): a kiln once they make pots, a
## herb rack once they heal, a record stone once they write, a stone circle
## once they watch the sky — one of each, once there are enough of them.
const LANDMARKS := {"kiln": PropData.Kind.KILN, "herbs": PropData.Kind.HERB_RACK,
	"records": PropData.Kind.RECORD_STONE, "observatory": PropData.Kind.STONE_CIRCLE}
## How many must live here before such a thing is built.
const LANDMARK_FROM := 6


func landmark_wanted(tag: String) -> bool:
	var def := _construction.buildings.with_tag(tag)
	if def.is_empty() or not big_enough(def[0]) or at_limit(def[0]):
		return false
	return def[0].tech != &"" and _settlement.knows_how(def[0].tech)


# --- what the data says of a building (F4) ---------------------------------------------------------

## Is the settlement big enough for it (its tier and people)?
func big_enough(def: BuildingDef) -> bool:
	return _settlement.member_count() >= def.min_population and int(_settlement.tier()) >= def.min_tier


## Has it as many of these standing near as it keeps: `limit_per_settlement`
## (0: no limit), or one for every `per_people` of its people if that is more?
func at_limit(def: BuildingDef) -> bool:
	var allowed := def.limit_per_settlement
	if def.per_people > 0:
		allowed = maxi(allowed, _settlement.member_count() / def.per_people)
	return allowed > 0 and standing_near(def.prop_kind).size() >= allowed


## How many buildings (besides homes) go up at once: two once there are two
## builders, or people enough to spare a second.
const TWO_BUILDS_FROM := 20


func builds_at_once() -> int:
	var builders := 0
	for person in _settlement.members():
		if person.occupation_id == &"builder":
			builders += 1
	return 2 if builders >= 2 or _settlement.member_count() >= TWO_BUILDS_FROM else 1


## The needs, the most pressing first (F4): each need has its weight (BASE),
## and more if its materials are in store, or if what the settlement values
## leans to it (the curious to craft and knowledge, the pious to faith, the
## close-knit to what is shared).
const BASE := {&"home": 100.0, &"storage": 90.0, &"material_storage": 85.0, &"water": 80.0, &"workshop": 70.0,
	&"kiln": 60.0, &"herbs": 60.0, &"records": 60.0, &"observatory": 60.0, &"shrine": 55.0, &"bridge": 50.0,
	&"landing": 45.0, &"net_rack": 40.0, &"fish_trap": 38.0, &"smokehouse": 66.0, &"seed_store": 64.0, &"granary": 62.0}
const MATERIALS_AT_HAND := 6.0
const VALUES := 8.0


func scored_needs(now: int) -> Array[StringName]:
	var listed := needs(now)
	var profile: Dictionary = cultures.profile_of(_settlement) if cultures != null else {}
	var scores := {}
	for i in listed.size():
		var need := listed[i]
		var score := float(BASE.get(need, 30.0 - i))
		var defs := _construction.buildings.with_tag(String(need))
		if not defs.is_empty():
			var def: BuildingDef = defs[0]
			var at_hand := true
			for resource: Variant in def.materials:
				at_hand = at_hand and _settlement.stockpile.available(StringName(str(resource))) >= int(def.materials[resource])
			if at_hand and not def.materials.is_empty():
				score += MATERIALS_AT_HAND
			for category in def.category:
				match category:
					"craft", "knowledge":
						score += VALUES * float(profile.get("innovation", 0.0))
					"faith":
						score += VALUES * float(profile.get("piety", 0.0))
					"social":
						score += VALUES * float(profile.get("collectivism", 0.0))
		scores[need] = score
	var out := listed.duplicate()
	out.sort_custom(func(a: StringName, b: StringName) -> bool:
		return float(scores[a]) > float(scores[b]) or (float(scores[a]) == float(scores[b]) and listed.find(a) < listed.find(b)))
	return out


## An upgrade (F4): `def` built in place of the oldest standing one it
## upgrades ({}: none stands, or one is being worked on).
func _upgrade(def: BuildingDef, now: int) -> Dictionary:
	var old := _construction.buildings.get_def(def.upgrade_of)
	if old == null:
		return {}
	for id in standing_near(old.prop_kind):
		var building := _settlement.props().get_prop(id)
		var p := _construction.start_upgrade(building, def, now, _settlement.id)
		if not p.is_empty():
			return p
	return {}


## Does a myth many of its people hold call for a shrine (and none stands)? (M17.2)
func shrine_wanted() -> bool:
	return faith != null and _settlement.member_count() >= LANDMARK_FROM \
		and not faith.shrine_myth(_settlement).is_empty() and standing_near(PropData.Kind.SHRINE).is_empty()


## Where the shrine goes: buildable ground by a sacred place of its myth (the
## nearest of them to the fire, within reach) — or, if there is none, where
## anything else would go.
func shrine_site() -> Variant:
	var fire := _settlement.fire()
	if faith == null or fire == null:
		return null
	var myth := faith.shrine_myth(_settlement)
	var graves := _resting_tiles()
	var best: Variant = null
	var best_distance := INF
	for place: Variant in myth.get("places", []):
		if typeof(place) != TYPE_VECTOR2:
			continue
		var sacred := WorldCoords.world2d_to_tile(place)
		if Vector2(sacred - fire.tile).length() > NEAR_REACH:
			continue
		for dy in range(-2, 3):
			for dx in range(-2, 3):
				var tile := sacred + Vector2i(dx, dy)
				var distance := Vector2(dx, dy).length() + Vector2(tile - fire.tile).length() * 0.05
				if distance < best_distance and _buildable(tile, graves):
					best = tile
					best_distance = distance
	return best if best != null else site_for(_construction.buildings.get_def(&"shrine"))


## Is water to drink far from the fire (and no well yet)?
func water_far() -> bool:
	if not standing_near(PropData.Kind.WELL).is_empty():
		return false
	var fire := _settlement.fire()
	if fire == null or _settlement.places() == null:
		return false
	var water: Variant = _settlement.places().water_tile(fire.tile)
	return water == null or Vector2(water - fire.tile).length() > _config.well_from


## Is `tile` this settlement's to see to (nearer its fire than any other's,
## and within reach of it)?
func _near(tile: Vector2i) -> bool:
	var fire := _settlement.fire()
	if fire == null or Vector2(tile - fire.tile).length() > NEAR_REACH:
		return false
	var settlements := _construction.settlements
	return settlements == null or settlements.nearest(tile) == _settlement


## The buildings of a kind that are this settlement's (near its fire).
func standing_near(kind: int) -> Array[int]:
	var out: Array[int] = []
	for id in _construction.standing(kind):
		var prop := _settlement.props().get_prop(id)
		if prop != null and _near(prop.tile):
			out.append(id)
	return out


## The best ground for a building (null: none in reach): never at the edge
## of a drop, where it would hang over the ledge (the owner, 2026-10-06) —
## unless there is no other ground at all.
func site_for(def: BuildingDef) -> Variant:
	var level: Variant = _site_for(def, true)
	if level != null:
		return level
	var site: Variant = _site_for(def, false)
	if site != null or not def.has_tag("home") or not roofless():
		return site
	# Nowhere above the flood mark, and someone without a roof: the highest
	# dry ground there is, the river's or not (`_buildable`, under the mark).
	level = _site_for(def, true, true)
	return level if level != null else _site_for(def, false, true)


## Is anyone of the settlement without a roof (no hut of theirs standing)?
func roofless() -> bool:
	for person in _settlement.members():
		if person.home_building_id == 0 or not _settlement.start_info().hut_ids.has(person.home_building_id):
			return true
	return false


## Ground none of whose neighbours lies lower: a building there does not hang
## over a ledge.
func on_level(tile: Vector2i) -> bool:
	var h := _world.get_height(tile)
	for y in range(-1, 2):
		for x in range(-1, 2):
			var at := tile + Vector2i(x, y)
			if _world.is_in_bounds(at) and _world.get_height(at) < h:
				return false
	return true


func _site_for(_def: BuildingDef, level_only: bool, under_mark: bool = false) -> Variant:
	var fire := _settlement.fire()
	if fire == null or _world == null:
		return null
	var grave_tiles := _resting_tiles()
	var taken := {}
	for person in _people.all_people():
		taken[person.position] = true
	var best: Variant = null
	var best_cost := INF
	var reach := _config.site_farthest
	for dy in range(-reach, reach + 1):
		for dx in range(-reach, reach + 1):
			var distance := Vector2(dx, dy).length()
			if distance < _config.site_nearest or distance > _config.site_farthest:
				continue
			var tile := fire.tile + Vector2i(dx, dy)
			if taken.has(tile) or not _buildable(tile, grave_tiles, under_mark) or (level_only and not on_level(tile)):
				continue
			var cost := distance * _config.site_distance_cost + _unevenness(tile) * _config.site_unevenness_cost
			if under_mark:
				var under := _settlement.flood_level - _world.get_height(tile) * _world.height_step
				if under > -0.01:
					cost += (under + 0.01) * _config.site_flood_cost # (the highest first)
			if _world.get_terrain(tile) == ChunkData.Terrain.ROAD or _world.get_terrain(tile) == ChunkData.Terrain.PAVED:
				cost += _config.site_path_cost
			cost += _growth_beside(tile) * _config.site_growth_cost
			if cost < best_cost:
				if _pathfinder != null and _pathfinder.is_bound() and not _pathfinder.is_reachable(fire.tile + Vector2i(1, 0), tile):
					continue
				best_cost = cost
				best = tile
	return best


## Where the dead lie: cemeteries (and an older save's graves) — built not too near.
func _resting_tiles() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for kind: int in [PropData.Kind.CEMETERY, PropData.Kind.GRAVE]:
		for id in _construction.standing(kind):
			out.append(_settlement.props().get_prop(id).tile)
	return out


## What grows by itself: a building may stand beside it (see `_buildable`).
const GROWS_WILD: Array[int] = [PropData.Kind.TREE, PropData.Kind.BUSH, PropData.Kind.MUSHROOM, PropData.Kind.ROOTS]
const BUILT_ON: Array[ChunkData.Terrain] = [ChunkData.Terrain.GRASS, ChunkData.Terrain.DIRT, ChunkData.Terrain.ROAD, ChunkData.Terrain.PAVED]


## Ground a building can stand on. `under_mark`: where the river has been too
## (a hut for the roofless when there is no other ground, `site_for`).
func _buildable(tile: Vector2i, graves: Array[Vector2i], under_mark: bool = false) -> bool:
	if not _world.is_in_bounds(tile) or _world.get_water(tile) > 0.0:
		return false
	if not under_mark and _world.get_height(tile) * _world.height_step <= _settlement.flood_level + 0.01:
		return false # (where the river has been: no)
	var terrain := _world.get_terrain(tile)
	# (A worn path is ground like any other: their own footpaths took all the
	# room about the fire — the 200-year soaks, 2026-10-11. One laid with stones
	# too, at the owner's word, 2026-10-12: paving took the room in its turn.)
	if not BUILT_ON.has(terrain):
		return false
	if _pathfinder != null and _pathfinder.is_bound() and not _pathfinder.can_stand(tile):
		return false
	var props := _settlement.props()
	for y in range(-_config.site_spacing, _config.site_spacing + 1):
		for x in range(-_config.site_spacing, _config.site_spacing + 1):
			var near := props.prop_at(tile + Vector2i(x, y))
			if near == null:
				continue
			if near.kind == PropData.Kind.GRAVE:
				continue
			# (What grows wild may stand beside a building, not under it: the
			# trees about the fire left a settlement of twelve with two huts and
			# no ground for a third, so none grew to a town: the soaks, 2026-10-12.)
			if (x == 0 and y == 0) or not GROWS_WILD.has(near.kind):
				return false
	for grave in graves:
		if maxi(absi(grave.x - tile.x), absi(grave.y - tile.y)) < _config.site_grave_distance:
			return false
	# Not where the stores are kept.
	var middle := Places.middle_of(tile)
	for resource: StringName in _settlement.stockpile.amounts():
		var place := _settlement.stockpile.place(resource)
		if place != Vector2.INF and middle.distance_to(place) < 2.0:
			return false
	return true


## How many of the tiles around `tile` have something growing wild on them.
func _growth_beside(tile: Vector2i) -> int:
	var count := 0
	var props := _settlement.props()
	for y in range(-_config.site_spacing, _config.site_spacing + 1):
		for x in range(-_config.site_spacing, _config.site_spacing + 1):
			var near := props.prop_at(tile + Vector2i(x, y))
			if near != null and GROWS_WILD.has(near.kind):
				count += 1
	return count


## Height levels between the highest and the lowest of the tile and its neighbours.
func _unevenness(tile: Vector2i) -> int:
	var low := 1 << 20
	var high := -(1 << 20)
	for y in range(-1, 2):
		for x in range(-1, 2):
			var at := tile + Vector2i(x, y)
			if not _world.is_in_bounds(at):
				continue
			var h := _world.get_height(at)
			low = mini(low, h)
			high = maxi(high, h)
	return high - low


func _on_spoiled(_resource: StringName, amount: int) -> void:
	_spoiled.append([_day, amount])
	while _spoiled.size() > 64:
		_spoiled.pop_front()


func to_dict() -> Dictionary:
	return {"day": _day, "spoiled": _spoiled.duplicate(true)}


func from_dict(data: Dictionary) -> void:
	if typeof(data.get("day")) == TYPE_INT:
		_day = data["day"]
	_spoiled.clear()
	if typeof(data.get("spoiled")) == TYPE_ARRAY:
		for entry: Variant in data["spoiled"]:
			if typeof(entry) == TYPE_ARRAY and (entry as Array).size() == 2:
				_spoiled.append([int(entry[0]), int(entry[1])])
