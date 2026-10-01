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
## What people can be (null: nobody changes what they are).
var occupations: OccupationLibrary

var _start: WorldSetup.StartInfo
var _people: PersonRegistry
var _props: PropRegistry
var _piles: PileStore
var _library: ResourceLibrary
var _config: SettlementConfig
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
	jobs = JobBoard.new(_config)
	stockpile.bind(piles, places, library, loose)
	_burn_tick = -1
	_day = -1_000_000


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


## A settlement of gatherers with nobody farming: in a season for sowing,
## the one of them best suited to it takes it up (from the trade that has
## the most people, so that no work is left without anyone). Returns who,
## or null.
func ensure_farmer(now: int) -> PersonData:
	if farming == null or occupations == null or not occupations.has_def(&"farmer") or not farming.sowing_time(now) \
			or farming.farmer_count() > 0:
		return null
	var farmer := occupations.get_def(&"farmer")
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
	if gatherers < _config.farmer_from_gatherers or largest.size() < 2:
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
		if now - _farmer_check_tick >= FARMER_CHECK_MINUTES or now < _farmer_check_tick:
			_farmer_check_tick = now
			ensure_farmer(now)
	if now - jobs.last_refresh_tick >= _config.job_check_minutes or now < jobs.last_refresh_tick:
		jobs.refresh(self, now)


func debug_text() -> String:
	return "settlement %d: %d people in %d households, %d buildings  food for %.1f days  fire %s\nin store: %s   jobs: %s" % [
		id, member_count(), households().size(), buildings().size(), minf(days_of_food(), 99.0),
		"burning" if fire_lit() else "OUT", stockpile.debug_text(), jobs.debug_text()]


func to_dict() -> Dictionary:
	return {"burn_tick": _burn_tick, "day": _day, "jobs": jobs.to_dict()}


func from_dict(data: Dictionary) -> void:
	_burn_tick = int(data["burn_tick"]) if typeof(data.get("burn_tick")) == TYPE_INT else -1
	_day = int(data["day"]) if typeof(data.get("day")) == TYPE_INT else -1_000_000
	var board: Variant = data.get("jobs")
	jobs.from_dict(board if typeof(board) == TYPE_DICTIONARY else {})


# --- internals ------------------------------------------------------------------------------------

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
