class_name Settlement
extends RefCounted
## A settlement (bible §17.1): the people who live around one fire, their
## households and buildings, what they have in store and what needs doing.
## An aggregate over what is in the registries — it owns only its stockpile's
## books, its job board and its fire's burning. One settlement for now.

## The fire went out, or was lit again.
signal fire_changed(lit: bool)
## Food went bad in a pile (anywhere in the world).
signal spoiled(resource: StringName, amount: int)
## Someone took up another occupation (the first farmer).
signal took_up(person_id: int, occupation: StringName)
## It is short of food, or out of it, or has enough again (see Shortage).
signal shortage_changed(stage: int, was: int)
## Out of food, it has begun to eat the grain it kept for seed.
signal seed_released(units: int)
## The bushes around it are picked bare (or have berries again).
signal forage_changed(low: bool)

## How short of food it is.
enum Shortage {
	NONE,
	## Too little in store: it rations what there is, and people go further
	## for berries.
	SHORT,
	## Nothing in store for hours: the seed grain is eaten.
	EMPTY,
}

## What the first farmer knows of farming when they take it up (a skill, 0 … 1).
const FIRST_FARMER_SKILL := 0.2
## How often it is looked at whether someone should take up farming.
const FARMER_CHECK_MINUTES := 60
## At most this many days are made up for at once (a clock set far ahead).
const MAX_DAYS_AT_ONCE := 30
const MAX_LOGS_AT_ONCE := 64

var id := 0
var stockpile: Stockpile
var jobs: JobBoard
## Its fields (null: this settlement cannot farm).
var farming: Farming
## The animals around it (null: nothing to hunt).
var fauna: AnimalSystem
## What people can be (null: nobody changes what they are).
var occupations: OccupationLibrary
## What the world's nodes still hold (null: the bushes are not looked at).
var nodes: ResourceNodes
var shortage: Shortage = Shortage.NONE
## The grain kept for seed has been given out to be eaten (until the
## shortage is over).
var seed_eaten := false
## Are the bushes around it picked bare?
var forage_low := false

var _start: WorldSetup.StartInfo
var _people: PersonRegistry
var _props: PropRegistry
var _piles: PileStore
var _library: ResourceLibrary
var _config: SettlementConfig
var _places: Places
## Since when there has been too little in store (-1: there is enough),
## and nothing at all (-1: there is something).
var _low_since := -1
var _empty_since := -1
## Rationing: what each person has had from the stores today (person id ->
## bellies), and which day that is.
var _served: Dictionary = {}
var _served_day := -1_000_000
## The tick at which the fire wants its next piece of wood (-1 = not begun).
var _burn_tick := -1
## The game day up to which the days' housekeeping (spoilage) is done.
var _day := -1_000_000
var _farmer_check_tick := -1_000_000


func _init() -> void:
	stockpile = Stockpile.new()
	jobs = JobBoard.new()


func bind(start: WorldSetup.StartInfo, people: PersonRegistry, props: PropRegistry, piles: PileStore, places: Places,
		library: ResourceLibrary, loose: LooseObjectRegistry, config: SettlementConfig = null) -> void:
	_start = start
	id = start.settlement_id if start != null else 0
	_people = people
	_props = props
	_piles = piles
	_library = library
	_config = config if config != null else Config.settlement
	_places = places
	jobs = JobBoard.new(_config)
	stockpile.bind(piles, places, library, loose)
	_burn_tick = -1
	_day = -1_000_000
	shortage = Shortage.NONE
	seed_eaten = false
	forage_low = false
	_low_since = -1
	_empty_since = -1
	_served.clear()
	_served_day = -1_000_000


func unbind() -> void:
	stockpile.unbind()
	_people = null
	_props = null


# --- who and what ---------------------------------------------------------------------------------

## Everyone who lives here.
func members() -> Array[PersonData]:
	var out: Array[PersonData] = []
	if _people == null:
		return out
	for person in _people.all_people():
		if person.settlement_id == id:
			out.append(person)
	return out


func member_count() -> int:
	return members().size()


## Its households: household id -> the ids of who belongs to it.
func households() -> Dictionary:
	var out := {}
	for person in members():
		var household: PackedInt64Array = out.get(person.household_id, PackedInt64Array())
		household.append(person.id)
		out[person.household_id] = household # (packed arrays are values: put it back)
	return out


## What it has built: the huts and the fire (those still standing).
func buildings() -> Array[PropData]:
	var out: Array[PropData] = []
	if _props == null or _start == null:
		return out
	for prop_id: int in [_start.campfire_id] + _start.hut_ids:
		var prop := _props.get_prop(prop_id)
		if prop != null:
			out.append(prop)
	return out


func fire() -> PropData:
	return _props.get_prop(_start.campfire_id) if _props != null and _start != null else null


## Is the fire burning? (A fire that has gone out is marked on its prop:
## stock 0, drawn without a flame.)
func fire_lit() -> bool:
	var prop := fire()
	return prop != null and prop.stock != 0


# --- housekeeping ---------------------------------------------------------------------------------

## What its people eat in a day, in bellies.
func food_need_per_day() -> float:
	return member_count() * _config.food_per_person_day


## How many days the food in store lasts.
func days_of_food() -> float:
	var need := food_need_per_day()
	return stockpile.food() / need if need > 0.0 else INF


# --- short of food ------------------------------------------------------------------------------------

func is_short() -> bool:
	return shortage != Shortage.NONE


## Bellies of food each person gets from the stores in a day while it rations.
func ration() -> float:
	return _config.food_per_person_day * _config.ration_share


## May this person take (more) food from the stores today? Always, unless
## it is short of food and they have had their share.
func serves(person_id: int) -> bool:
	return shortage == Shortage.NONE or float(_served.get(person_id, 0.0)) < ration()


## Someone has taken food from the stores: `bellies` of it.
func note_served(person_id: int, bellies: float) -> void:
	_served[person_id] = float(_served.get(person_id, 0.0)) + bellies


## What a person has had from the stores today, in bellies.
func served_today(person_id: int) -> float:
	return float(_served.get(person_id, 0.0))


## The share of the bushes around the settlement that have nothing on
## them (0 if there are none, or nobody keeps count).
func bare_share() -> float:
	if nodes == null or _props == null or _start == null:
		return 0.0
	var bushes := 0
	var bare := 0
	for prop in _props.all_props():
		if prop.kind != PropData.Kind.BUSH or Vector2(prop.tile - _start.settlement_tile).length() > Places.WORK_RADIUS:
			continue
		bushes += 1
		if nodes.available(prop) <= 0:
			bare += 1
	return float(bare) / float(bushes) if bushes > 0 else 0.0


## How many of its people hunt.
func hunter_count() -> int:
	var count := 0
	if occupations == null:
		return 0
	for person in members():
		var def := occupations.get_def(person.occupation_id)
		if def != null and def.work_target == &"game":
			count += 1
	return count


## A settlement of gatherers with nobody farming: in a season for sowing,
## the one of them best suited to it takes it up (from the trade that has
## the most people, so that no work is left without anyone). Returns who,
## or null.
func ensure_farmer(now: int) -> PersonData:
	if farming == null or occupations == null or not occupations.has_def(&"farmer") or not farming.sowing_time(now) \
			or farming.farmer_count() > 0:
		return null
	return _take_up(&"farmer", _config.farmer_from_gatherers, now)


## Likewise with game about and nobody hunting.
func ensure_hunter(now: int) -> PersonData:
	if fauna == null or occupations == null or not occupations.has_def(&"hunter") or hunter_count() > 0 or not fauna.has_game():
		return null
	return _take_up(&"hunter", _config.hunter_from_gatherers, now)


## One of the gatherers takes up `occupation`: the one it suits best, from
## the trade with the most people (which keeps at least one). Null if
## there are fewer than `least` gatherers or no trade can spare anyone.
func _take_up(occupation: StringName, least: int, now: int) -> PersonData:
	var farmer := occupations.get_def(occupation)
	var by_trade := {}
	for person in members():
		var def := occupations.get_def(person.occupation_id)
		if def == null or def.placeholder or not farmer.allows(person.life_stage(now, Config.time.ticks_per_year(), Config.people)):
			continue
		if def.work_target != &"tree" and def.work_target != &"bush":
			continue
		if not by_trade.has(person.occupation_id):
			by_trade[person.occupation_id] = []
		(by_trade[person.occupation_id] as Array).append(person)
	var gatherers := 0
	var largest: Array = []
	var trades: Array = by_trade.keys()
	trades.sort_custom(func(a: StringName, b: StringName) -> bool: return String(a) < String(b))
	for trade: StringName in trades:
		var people: Array = by_trade[trade]
		gatherers += people.size()
		if people.size() > largest.size():
			largest = people
	if gatherers < least or largest.size() < 2:
		return null
	var best: PersonData = null
	for person: PersonData in largest:
		if best == null or farmer.affinity(person.traits) > farmer.affinity(best.traits) \
				or (farmer.affinity(person.traits) == farmer.affinity(best.traits) and person.id < best.id):
			best = person
	best.occupation_id = farmer.id
	# (They have seen things grow: not quite a beginner.)
	best.skills[String(farmer.id)] = maxf(float(best.skills.get(String(farmer.id), 0.0)), FIRST_FARMER_SKILL)
	took_up.emit(best.id, farmer.id)
	jobs.refresh(self, now)
	return best


## What a new settlement begins with: some food and some wood by the fire.
func stock_up(now: int) -> void:
	var berries := _library.get_def(&"berries") if _library != null else null
	if berries != null and berries.nutrition > 0.0:
		var units := ceili(food_need_per_day() * _config.starting_food_days / berries.nutrition)
		if units > 0:
			stockpile.add(&"berries", units)
	if _config.starting_wood > 0:
		stockpile.add(&"wood", _config.starting_wood)
	jobs.refresh(self, now)


## Time passes for the settlement: the fire burns its wood, food goes bad
## day by day, and the job board is kept up to date. Cheap to call often.
func step(now: int) -> void:
	if _props == null:
		return
	_burn(now)
	var today := Config.time.day_index(now)
	if _day == -1_000_000 or today < _day:
		_day = today
	var made_up := 0
	while _day < today and made_up < MAX_DAYS_AT_ONCE:
		_day += 1
		made_up += 1
		_spoil()
	_day = today
	if farming != null:
		farming.settle(now)
	if today != _served_day:
		_served_day = today
		_served.clear() # a new day: everyone's share anew
	if now - _farmer_check_tick >= FARMER_CHECK_MINUTES or now < _farmer_check_tick:
		_farmer_check_tick = now
		ensure_farmer(now)
		ensure_hunter(now)
		_check_forage()
	if now - jobs.last_refresh_tick >= _config.job_check_minutes or now < jobs.last_refresh_tick:
		_keep_seed()
		jobs.refresh(self, now)
		_check_shortage(now)


func debug_text() -> String:
	return "settlement %d: %d people in %d households, %d buildings  food for %.1f days%s  fire %s\nin store: %s   jobs: %s" % [
		id, member_count(), households().size(), buildings().size(), minf(days_of_food(), 99.0),
		["", "  SHORT OF FOOD (rationing)", "  OUT OF FOOD"][shortage] + ("  bushes bare" if forage_low else ""),
		"burning" if fire_lit() else "OUT", stockpile.debug_text(), jobs.debug_text()]


func to_dict() -> Dictionary:
	return {"burn_tick": _burn_tick, "day": _day, "jobs": jobs.to_dict(), "shortage": shortage, "seed_eaten": seed_eaten,
		"forage_low": forage_low, "low_since": _low_since, "empty_since": _empty_since,
		"served": _served.duplicate(), "served_day": _served_day}


func from_dict(data: Dictionary) -> void:
	_burn_tick = int(data["burn_tick"]) if typeof(data.get("burn_tick")) == TYPE_INT else -1
	_day = int(data["day"]) if typeof(data.get("day")) == TYPE_INT else -1_000_000
	var board: Variant = data.get("jobs")
	jobs.from_dict(board if typeof(board) == TYPE_DICTIONARY else {})
	shortage = clampi(int(data["shortage"]), 0, Shortage.size() - 1) as Shortage if typeof(data.get("shortage")) == TYPE_INT \
		else Shortage.NONE
	seed_eaten = bool(data["seed_eaten"]) if typeof(data.get("seed_eaten")) == TYPE_BOOL else false
	forage_low = bool(data["forage_low"]) if typeof(data.get("forage_low")) == TYPE_BOOL else false
	_low_since = int(data["low_since"]) if typeof(data.get("low_since")) == TYPE_INT else -1
	_empty_since = int(data["empty_since"]) if typeof(data.get("empty_since")) == TYPE_INT else -1
	_served_day = int(data["served_day"]) if typeof(data.get("served_day")) == TYPE_INT else -1_000_000
	_served.clear()
	var served: Variant = data.get("served")
	if typeof(served) == TYPE_DICTIONARY:
		for person_id: Variant in served:
			var had: Variant = (served as Dictionary)[person_id]
			if typeof(person_id) == TYPE_INT and (typeof(had) == TYPE_FLOAT or typeof(had) == TYPE_INT):
				_served[person_id] = float(had)
	_keep_seed()
	_apply_reach()


# --- internals ------------------------------------------------------------------------------------

## The grain for the next sowing is kept back from what is eaten — until
## hunger has the settlement eat it.
func _keep_seed() -> void:
	var wanted := farming.seed_wanted() if farming != null and not seed_eaten else 0
	stockpile.set_reserve(&"grain", wanted)


## Short of food, people go further for berries.
func _apply_reach() -> void:
	if _places != null:
		_places.forage_reach = _config.forage_further_factor if shortage != Shortage.NONE else 1.0


## Looks at what is in store: too little for some hours is a shortage
## (rationing, foraging further); nothing at all for some hours and the
## seed grain is eaten; enough again and it is over.
func _check_shortage(now: int) -> void:
	if member_count() == 0:
		return
	var days := days_of_food()
	if days < _config.shortage_below_days:
		if _low_since < 0 or now < _low_since:
			_low_since = now
	else:
		_low_since = -1
	if stockpile.food_units() <= 0:
		if _empty_since < 0 or now < _empty_since:
			_empty_since = now
	else:
		_empty_since = -1
	match shortage:
		Shortage.NONE:
			if _low_since >= 0 and now - _low_since >= _config.shortage_after_minutes:
				_set_shortage(Shortage.SHORT)
		Shortage.SHORT:
			if days >= _config.shortage_over_days:
				_set_shortage(Shortage.NONE)
			elif _empty_since >= 0 and now - _empty_since >= _config.empty_after_minutes:
				_set_shortage(Shortage.EMPTY)
		Shortage.EMPTY:
			if days >= _config.shortage_over_days:
				_set_shortage(Shortage.NONE)
			elif days >= _config.shortage_below_days:
				_set_shortage(Shortage.SHORT)


func _set_shortage(stage: Shortage) -> void:
	var was := shortage
	if stage == was:
		return
	shortage = stage
	# (Out of food altogether counts from when the shortage began.)
	if was == Shortage.NONE and _empty_since >= 0:
		_empty_since = maxi(_empty_since, jobs.last_refresh_tick)
	_apply_reach()
	if stage == Shortage.NONE:
		seed_eaten = false
		_keep_seed()
	shortage_changed.emit(stage, was)
	if stage == Shortage.EMPTY and not seed_eaten:
		# Nothing left but the seed: it is eaten (and the next sowing is the poorer for it).
		var seed := stockpile.reserved(&"grain")
		if seed > 0:
			seed_eaten = true
			_keep_seed()
			seed_released.emit(seed)


## Are the bushes around the settlement picked bare — or do they have
## berries again?
func _check_forage() -> void:
	if nodes == null:
		return
	var share := bare_share()
	if not forage_low and share >= _config.forage_low_share:
		forage_low = true
		forage_changed.emit(true)
	elif forage_low and share <= _config.forage_recovered_share:
		forage_low = false
		forage_changed.emit(false)


## The fire takes a piece of wood from the stores every so often; with none
## to take it goes out, and is lit again as soon as there is wood.
func _burn(now: int) -> void:
	var prop := fire()
	if prop == null or _config.fire_wood_per_day <= 0.0:
		return
	var minutes_per_log := maxi(roundi(Config.time.MINUTES_PER_DAY / _config.fire_wood_per_day), 1)
	if _burn_tick < 0 or now < _burn_tick - minutes_per_log:
		_burn_tick = now + minutes_per_log # (a new fire, or the clock set back)
	var lit := prop.stock != 0
	var logs := 0
	while now >= _burn_tick and logs < MAX_LOGS_AT_ONCE:
		logs += 1
		_burn_tick += minutes_per_log
		lit = stockpile.take(&"wood", 1) == 1
		if not lit:
			break
	if now >= _burn_tick:
		_burn_tick = now + minutes_per_log
	# A cold fire is lit again as soon as there is something to burn.
	if not lit and stockpile.amount(&"wood") > 0:
		stockpile.take(&"wood", 1)
		_burn_tick = now + minutes_per_log
		lit = true
	if lit != (prop.stock != 0):
		prop.stock = -1 if lit else 0
		_props.changed(prop.id)
		fire_changed.emit(lit)


func _spoil() -> void:
	if _piles == null:
		return
	var lost := _piles.spoil(1.0)
	for resource: StringName in lost:
		spoiled.emit(resource, int(lost[resource]))
