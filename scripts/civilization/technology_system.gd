class_name TechnologySystem
extends RefCounted
## How technologies come about (bible §18.1, M16.2): never by the calendar.
## Once a game day, for every settlement and every technology it does not
## know: if everything has come together — what it must know first, what the
## land offers, enough people, the trade it takes, enough known of its
## domain — there is a chance, and if it comes, **someone** works it out: the
## one whose knowing, curiosity and wits fit it best (the inventor, whom
## history remembers). The settlement knows it from then on (Settlement.learn:
## the chronicle tells of it, and the player is told).
##
## What one settlement knows travels: along trade routes, with every load
## (a little chance each time), and with those who set out to found a new
## settlement (they take it with them).
##
## Deterministic: every roll is a hash of the world's numbers, not a stream.

## A settlement has worked something out, or been shown it: settlement, technology, by whom.
signal discovered(settlement_id: int, tech_id: StringName, person_id: int)
## It came from elsewhere: settlement, technology, by whom, from which settlement.
signal spread(settlement_id: int, tech_id: StringName, person_id: int, from_id: int)
## The world has entered a phase it never had (CivilizationPhase.Phase): an age begins.
signal era_entered(phase: int)

## Clay is found where there is water this near the fire (tiles); plants
## for fibre and herbs where bushes grow this near.
const CLAY_REACH := 12
const PLANTS_REACH := 14
const PLANTS_LEAST := 3
## Past its threshold, a domain known this many times over makes it this much likelier (at most).
const KNOWING_MOST := 3.0
## A load carried to a settlement that does not know something its sender
## does: the chance it learns it, if it could use it.
const SPREAD_PER_LOAD := 0.06

var library: TechnologyLibrary
var settlements: Settlements
var learning: Knowledge
var world: WorldData
var props: PropRegistry
var buildings: BuildingLibrary
var trade: TradeSystem
## The furthest phase the world has reached (CivilizationPhase.Phase) — and the phase it is in now.
var phase_reached := 0
var phase_now := 0
var _day := -1_000_000
## For the debug overlay and the soak: how many were worked out, and spread.
var discoveries := 0
var spreads := 0


func bind(techs: TechnologyLibrary, all: Settlements, knowing: Knowledge, now: int) -> void:
	library = techs
	settlements = all
	learning = knowing
	_day = Config.time.day_index(now)
	if learning != null:
		learning.writes = func(own: Settlement) -> bool: return own.knows_how(&"writing")
	know_the_beginning()
	apply_effects()


## Every settlement knows what everyone knew from the start (fire, foraging,
## planting) — without telling of it.
func know_the_beginning() -> void:
	if library == null or settlements == null:
		return
	for own in settlements.all():
		for id in library.ids():
			var def := library.get_def(id)
			if def.known_from_start and not own.knows_how(id):
				own.knows[String(id)] = 0


## Once a game day: what may be worked out today.
func advance_to(now: int) -> void:
	var today := Config.time.day_index(now)
	if _day == -1_000_000 or today < _day:
		_day = today
		return
	if today == _day:
		return
	_day = today
	each_day(today, now)


## Which phase the world is in; the first time it is in a new one, an age begins.
func look_at_the_age() -> void:
	phase_now = CivilizationPhase.evaluate(settlements, props, trade)
	while phase_reached < phase_now:
		phase_reached += 1
		era_entered.emit(phase_reached)


## What knowing something does to the world, kept up daily (M16.3): the
## people of a settlement that knows which herbs heal are tended (they
## recover faster); those of one that weaves wear dyed cloth; a record stone
## gets rows of tallies once they count.
func apply_effects() -> void:
	if settlements == null:
		return
	for own in settlements.all():
		var tended := own.knows_how(&"medicine")
		var dyed := own.knows_how(&"weaving")
		for person in own.members():
			person.set_flag(PersonData.FLAG_TENDED, tended)
			person.set_flag(PersonData.FLAG_DYED, dyed)
		if own.knows_how(&"mathematics") and props != null and own.fire() != null:
			for prop in props.all_props():
				if prop.kind == PropData.Kind.RECORD_STONE and prop.variant == 0 \
						and Vector2(prop.tile - own.fire().tile).length() <= SettlementPlanner.NEAR_REACH:
					prop.variant = 1
					props.changed(prop.id)


func each_day(day: int, now: int) -> void:
	if library == null or settlements == null:
		return
	know_the_beginning()
	apply_effects()
	look_at_the_age()
	for own in settlements.all():
		for id in library.ids():
			var def := library.get_def(id)
			if not def.implemented or def.own_rule or own.knows_how(id) or not missing(own, def).is_empty():
				continue
			if roll(own.id, day, id) < chance(own, def):
				var inventor := inventor_for(own, def, day)
				if inventor != null:
					discover(own, def, inventor, now)


## A roll 0 … 1 for a settlement, a day and a technology.
static func roll(settlement_id: int, day: int, what: StringName) -> float:
	return float(posmod(hash([settlement_id, day, String(what), "invent"]), 100000)) / 100000.0


## What keeps a settlement from it ([]: nothing — it may come any day). Each
## entry: "tech:<id>", "resource:<id>", "people", "trade:<id>",
## "building:<id>", "knowledge", "not_yet" (nothing in the world brings it yet).
func missing(own: Settlement, def: TechnologyDef) -> PackedStringArray:
	var out := PackedStringArray()
	if not def.implemented:
		out.append("not_yet")
	for before in def.prerequisites:
		if not own.knows_how(StringName(before)):
			out.append("tech:" + before)
	for what in def.required_resources:
		if not resource_known(own, what):
			out.append("resource:" + what)
	if own.member_count() < def.min_population:
		out.append("people")
	if def.specialist_occupation != &"" and not own.members().any(func(p: PersonData) -> bool:
			return p.occupation_id == def.specialist_occupation):
		out.append("trade:" + String(def.specialist_occupation))
	for building in def.required_buildings:
		if not building_stands(own, StringName(building)):
			out.append("building:" + building)
	if learning != null and learning.of_settlement(own, def.domain) < def.knowledge_threshold:
		out.append("knowledge")
	return out


## The chance a day, everything having come together: the more is known of
## its domain beyond what it takes, the likelier.
func chance(own: Settlement, def: TechnologyDef) -> float:
	var known := learning.of_settlement(own, def.domain) if learning != null else 0.0
	var beyond := clampf(known / maxf(def.knowledge_threshold, 1.0), 1.0, KNOWING_MOST) if def.knowledge_threshold > 0.0 else 1.0
	return def.base_daily_chance * beyond


## Is `what` at hand for a settlement? Clay where there is water near the
## fire; fibre and herbs where bushes grow (herbs: and someone forages); fat
## from what is hunted or fished; anything else: what it has had in its
## stores or brought in.
func resource_known(own: Settlement, what: String) -> bool:
	var fire := own.fire()
	var at := fire.tile if fire != null else own.start_info().settlement_tile
	match what:
		"clay":
			return world != null and _water_near(at, CLAY_REACH)
		"fibre":
			return _bushes_near(at) >= PLANTS_LEAST
		"herbs":
			return _bushes_near(at) >= PLANTS_LEAST and own.members().any(func(p: PersonData) -> bool:
				return p.occupation_id == &"forager")
		"fat":
			return _has_had(own, &"meat") or _has_had(own, &"fish") or own.hunter_count() > 0
		"stone":
			# (Stones lie about everywhere: rocks near the fire are at hand.)
			return _has_had(own, &"stone") or _near(at, PropData.Kind.ROCK) >= PLANTS_LEAST
	return _has_had(own, StringName(what))


func _has_had(own: Settlement, resource: StringName) -> bool:
	return own.stockpile.amount(resource) > 0 or own.produced.has(String(resource)) or own.produced.has(resource)


func _water_near(at: Vector2i, reach: int) -> bool:
	for dy in range(-reach, reach + 1, 2):
		for dx in range(-reach, reach + 1, 2):
			var tile := at + Vector2i(dx, dy)
			if world.is_in_bounds(tile) and world.get_water(tile) > 0.05:
				return true
	return false


func _bushes_near(at: Vector2i) -> int:
	return _near(at, PropData.Kind.BUSH)


## How many props of a kind are within PLANTS_REACH of `at` (counted to PLANTS_LEAST).
func _near(at: Vector2i, kind: int) -> int:
	if props == null:
		return 0
	var count := 0
	for prop in props.all_props():
		if prop.kind == kind and Vector2(prop.tile - at).length() <= PLANTS_REACH:
			count += 1
			if count >= PLANTS_LEAST:
				return count
	return count


## Does a building of the kind stand near the settlement's fire?
func building_stands(own: Settlement, building: StringName) -> bool:
	var def := buildings.get_def(building) if buildings != null else null
	var fire := own.fire()
	if def == null or fire == null or props == null:
		return false
	for prop in props.all_props():
		# (A building going up is a site until it is done.)
		if prop.kind == def.prop_kind and Vector2(prop.tile - fire.tile).length() <= SettlementPlanner.NEAR_REACH:
			return true
	return false


## Who works it out: the one whose knowing of its domain, curiosity and wits
## (and the trade it takes) fit it best — weighed, and drawn by the day's roll.
func inventor_for(own: Settlement, def: TechnologyDef, day: int) -> PersonData:
	var year := Config.time.ticks_per_year()
	var now := day * TimeConfig.MINUTES_PER_DAY
	var weighed: Array = [] # [person, weight]
	var total := 0.0
	for person in own.members():
		if person.life_stage(now, year, Config.people) == PersonData.LifeStage.CHILD:
			continue
		var weight := (1.0 + Knowledge.points(person, def.domain)) \
			* lerpf(0.5, 1.5, Traits.value(person.traits, Traits.Axis.CURIOSITY) * 0.5 + 0.5) \
			* lerpf(0.5, 1.5, Traits.value(person.traits, Traits.Axis.INTELLIGENCE) * 0.5 + 0.5)
		if def.specialist_occupation != &"" and person.occupation_id == def.specialist_occupation:
			weight *= 2.0
		weighed.append([person, weight])
		total += weight
	if weighed.is_empty():
		return null
	var pick := float(posmod(hash([own.id, day, String(def.id), "inventor"]), 100000)) / 100000.0 * total
	for entry: Array in weighed:
		pick -= float(entry[1])
		if pick <= 0.0:
			return entry[0]
	return weighed[-1][0]


## `own` knows `def` now, thanks to `inventor`.
func discover(own: Settlement, def: TechnologyDef, inventor: PersonData, now: int) -> void:
	if own.knows_how(def.id):
		return
	discoveries += 1
	# (The chronicle tells of it; the inventor is remembered through that event.)
	own.learn(def.id, inventor.id, now)
	discovered.emit(own.id, def.id, inventor.id)


## A load came from one settlement to another (TradeSystem.traded): the
## carrier may bring along how something is done.
func on_traded(record: Dictionary) -> void:
	if library == null or settlements == null:
		return
	var from := settlements.get_settlement(int(record.get("from", 0)))
	var to := settlements.get_settlement(int(record.get("to", 0)))
	if from == null or to == null:
		return
	var day := _day
	for id in library.ids():
		var def := library.get_def(id)
		if not from.knows_how(id) or to.knows_how(id) or not def.implemented or def.own_rule:
			continue
		if not _could_use(to, def):
			continue
		var draw := float(posmod(hash([to.id, from.id, day, String(id), int(record.get("units", 0)), "spread"]), 100000)) / 100000.0
		if draw < SPREAD_PER_LOAD:
			var carrier := int(record.get("trader", 0))
			spreads += 1
			to.knows[String(id)] = day * TimeConfig.MINUTES_PER_DAY
			spread.emit(to.id, id, carrier, from.id)


## A new settlement takes with it what its founders' settlement knew.
func on_founded(own: Settlement, journey: Dictionary) -> void:
	var from := settlements.get_settlement(int(journey.get("from", 0))) if settlements != null else null
	if from == null:
		return
	for key: String in from.knows:
		if not own.knows.has(key):
			own.knows[key] = from.knows[key]


## Taught by others, it still needs what it is made with, and what comes before it.
func _could_use(own: Settlement, def: TechnologyDef) -> bool:
	for before in def.prerequisites:
		if not own.knows_how(StringName(before)):
			return false
	for what in def.required_resources:
		if not resource_known(own, what):
			return false
	return true


## What a settlement knows, in the order of the chain: [[id, tick]].
func known_by(own: Settlement) -> Array:
	var out: Array = []
	for id in library.ids():
		if own.knows_how(id):
			out.append([id, int(own.knows[String(id)])])
	return out


## What a settlement is close to: everything has come together but enough
## knowing, and it knows at least `share` of what it takes.
func close_to(own: Settlement, share: float = 0.5) -> Array[StringName]:
	var out: Array[StringName] = []
	for id in library.ids():
		var def := library.get_def(id)
		if own.knows_how(id) or not def.implemented or def.own_rule:
			continue
		var gaps := missing(own, def)
		if gaps.size() == 1 and gaps[0] == "knowledge" \
				and learning.of_settlement(own, def.domain) >= def.knowledge_threshold * share:
			out.append(id)
	return out


func to_dict() -> Dictionary:
	return {"day": _day, "discoveries": discoveries, "spreads": spreads, "phase": phase_reached}


func from_dict(data: Dictionary) -> void:
	if typeof(data.get("day")) == TYPE_INT:
		_day = int(data["day"])
	discoveries = maxi(int(data.get("discoveries", 0)), 0)
	spreads = maxi(int(data.get("spreads", 0)), 0)
	phase_reached = clampi(int(data.get("phase", 0)), 0, CivilizationPhase.Phase.size() - 1)


func debug_text() -> String:
	var home := settlements.home() if settlements != null else null
	if home == null or library == null:
		return "technology: -"
	var known := PackedStringArray()
	for entry: Array in known_by(home):
		known.append(String(entry[0]))
	return "technology: %s  (found %d, spread %d)  age %s  close: %s" % [", ".join(known), discoveries, spreads,
		CivilizationPhase.NAMES[phase_now],
		", ".join(close_to(home)) if not close_to(home).is_empty() else "-"]
