class_name Chronicler
extends RefCounted
## Writes the world's events into the EventLog as they happen (M7.5): it
## listens to the systems (the fields, the settlement, the people, the
## player's hand) and records what they report — with what brought it
## about. A dry spell is remembered while it lasts, so that the crop that
## withers in it names it as its cause; a shortage looks back at the days
## before it; what the settlement does about a shortage names the shortage.
##
## It owns no rules: whether there is a shortage is the settlement's
## business. It only knows what leads to what. What it keeps between
## events (which dry spell, which shortage is going on) is saved, so that
## the chain goes on across a save.

const TYPE_FOUNDED := &"settlement_founded"
const TYPE_FIRST_FARM := &"first_farm"
const TYPE_FIRST_STORAGE := &"first_storage"
const TYPE_DISCOVERED := &"resource_discovered"
const TYPE_TOOK_UP := &"occupation_taken_up"
const TYPE_HUNTED := &"animal_hunted"
const TYPE_DRY_SPELL := &"dry_spell"
const TYPE_CROP_FAILURE := &"crop_failure"
const TYPE_SPOILED := &"food_spoiled"
const TYPE_FORAGE := &"forage_depleted"
const TYPE_SHORTAGE := &"food_shortage"
const TYPE_RATIONING := &"rationing"
const TYPE_FURTHER := &"foraging_further"
const TYPE_EMPTY := &"stores_empty"
const TYPE_SEED_EATEN := &"seed_grain_eaten"
const TYPE_THIN_SOWING := &"thin_sowing"
const TYPE_POOR_HARVEST := &"poor_harvest"
const TYPE_OVER := &"shortage_over"
const TYPE_SICK := &"person_hungry_sick"
const TYPE_RECOVERED := &"person_recovered"
const TYPE_FIRE_OUT := &"fire_out"
const TYPE_FIRE_RELIT := &"fire_relit"
const TYPE_PLAYER := &"player_intervention"
const TYPE_STORM := &"storm"
const TYPE_DROUGHT := &"drought"
const TYPE_HEAT_WAVE := &"heat_wave"
const TYPE_COLD_SNAP := &"cold_snap"
const TYPE_CROP_FROZEN := &"crop_frozen"
const TYPE_HERD_MOVED := &"herd_moved"
const TYPE_HIGH_WATER := &"high_water"
const TYPE_LOW_WATER := &"low_water"
const TYPE_FLOOD := &"flood"
const TYPE_BANK_ERODED := &"bank_eroded"
const TYPE_TREE_WITHERED := &"tree_withered"
const TYPE_STORES_FLOODED := &"stores_flooded"
const TYPE_HOME_MOVED := &"home_moved"
const TYPE_COLD_SICK := &"person_cold_sick"
const TYPE_FRIENDS := &"became_friends"
const TYPE_FELL_OUT := &"fell_out"
const TYPE_ENEMIES := &"became_enemies"
const TYPE_RECONCILED := &"reconciled"
const TYPE_FIGHT := &"fight"
const TYPE_BORN := &"person_born"
const TYPE_DIED := &"person_died"
const TYPE_PARTNERS := &"became_partners"
const TYPE_CAME_OF_AGE := &"came_of_age"
const TYPE_INJURED := &"person_injured"
const TYPE_ILL := &"person_ill"
const TYPE_TAKEN_IN := &"taken_in"
const TYPE_ARRIVED := &"newcomer_arrived"
## How much a death matters: this, and this much more for someone who mattered (HistoricalPerson.significance).
const OBITUARY_BASE := 0.45
const OBITUARY_WEIGHT := 0.5

## How much what the player does matters, by how severe it is.
const PLAYER_SIGNIFICANCE: Array[float] = [0.1, 0.35, 0.6]
## A crop that withers up to this many days after a dry spell ended still
## withered because of it.
const DRY_SPELL_LINGERS_DAYS := 4.0
## Whoever stands within this many tiles of where something was put in
## store is who put it there.
const STORER_RADIUS := 2.0

## Off: nothing is written down (while a new world is being set up).
var listening := true

var _log: EventLog
var _people: PersonRegistry
var _props: PropRegistry
var _loose: LooseObjectRegistry
var _resources: ResourceLibrary
var _settlement: Settlement
var _farming: Farming
var _config: EventsConfig

## The dry spell that is going on (0 = none).
var _dry_spell_id := 0
## The shortage that is going on, and its being out of food altogether.
var _shortage_id := 0
var _empty_id := 0
## The eating of the seed grain, until a harvest has made up for it.
var _seed_eaten_id := 0
## The bushes being picked bare, while they are.
var _forage_id := 0
## The fire being out, while it is.
var _fire_out_id := 0
## The weather's conditions going on: condition -> the event of its beginning.
var _condition_ids: Dictionary = {}
## Has anything ever been put in store by someone?
var _stored_once := false
## The resources the settlement has had in store: id (String) -> true.
var _known: Dictionary = {}


func bind(log: EventLog, people: PersonRegistry, props: PropRegistry, loose: LooseObjectRegistry, resources: ResourceLibrary,
		settlement: Settlement, farming: Farming, config: EventsConfig = null) -> void:
	_log = log
	_people = people
	_props = props
	_loose = loose
	_resources = resources
	_settlement = settlement
	_farming = farming
	_config = config if config != null else Config.events


func unbind() -> void:
	_log = null
	_people = null
	_props = null
	_loose = null
	_settlement = null
	_farming = null


func reset() -> void:
	_dry_spell_id = 0
	_shortage_id = 0
	_empty_id = 0
	_seed_eaten_id = 0
	_forage_id = 0
	_fire_out_id = 0
	_condition_ids.clear()
	_stored_once = false
	_known.clear()


## The shortage that is going on (0 = none): what a system that makes
## something happen because of it passes as the cause.
func shortage_id() -> int:
	return _shortage_id


func dry_spell_id() -> int:
	return _dry_spell_id


# --- a world begins -------------------------------------------------------------------------------

## A new settlement has been set up (and stocked): the first entry.
func founded() -> void:
	_know_what_is_in_store()
	if not _writing() or _settlement == null:
		return
	var members := PackedInt64Array()
	for person in _settlement.members():
		members.append(person.id)
	_log.record(TYPE_FOUNDED, {"people": members.size(), "participants": members, "position": _fire_place(),
		"settlement": _settlement.id})


## A world from before there was an event log: nothing of its past is
## known, but what it has in store is no discovery.
func adopt() -> void:
	_know_what_is_in_store()
	_stored_once = not _known.is_empty()


# --- the fields -----------------------------------------------------------------------------------

func on_first_field(tile: Vector2i) -> void:
	if not _writing():
		return
	var farmers := PackedInt64Array()
	if _people != null and _settlement != null and _settlement.occupations != null:
		for person in _settlement.members():
			var def := _settlement.occupations.get_def(person.occupation_id)
			if def != null and def.work_target == &"field":
				farmers.append(person.id)
	_log.record(TYPE_FIRST_FARM, {"position": Places.middle_of(tile), "participants": farmers, "settlement": _settlement_id()})


func on_dry_spell(began: bool, days: int) -> void:
	if not _writing():
		return
	if began:
		var event := _log.record(TYPE_DRY_SPELL, {"days": days})
		_dry_spell_id = event.id if event != null else 0
	else:
		if _dry_spell_id != 0:
			_log.note_effect(_dry_spell_id, "ended", _now())
			_log.note_effect(_dry_spell_id, "days", days)
		_dry_spell_id = 0


## A crop has withered: because of the dry spell, if there is (or just
## was) one.
func on_crop_failed(crop_id: int) -> void:
	if not _writing():
		return
	var causes: Array = []
	var dry := _dry_spell_id
	if dry == 0:
		# (One that has only just ended did it all the same.)
		var spell := _log.latest(TYPE_DRY_SPELL)
		if spell != null and _now() - int(spell.effects.get("ended", -1_000_000_000)) 				<= DRY_SPELL_LINGERS_DAYS * TimeConfig.MINUTES_PER_DAY:
			dry = spell.id
	if dry != 0:
		causes.append(dry)
	# (Or the ground dried out because the river stands so low.)
	var low := condition_id(TYPE_LOW_WATER)
	if low != 0:
		causes.append(low)
	# (And behind both, the drought, if there is one.)
	var drought := condition_id(WeatherSystem.DROUGHT)
	if drought != 0:
		causes.append(drought)
	var crop := _props.get_prop(crop_id) if _props != null else null
	var params := {"settlement": _settlement_id()}
	if crop != null:
		params["position"] = Places.middle_of(crop.tile)
	_log.record(TYPE_CROP_FAILURE, params, causes)


## A crop was killed by frost: because of the cold snap, if there is one.
func on_crop_frozen(crop_id: int) -> void:
	if not _writing():
		return
	var crop := _props.get_prop(crop_id) if _props != null else null
	var params := {"settlement": _settlement_id()}
	if crop != null:
		params["position"] = Places.middle_of(crop.tile)
	_log.record(TYPE_CROP_FROZEN, params, [condition_id(WeatherSystem.COLD_SNAP)])


## A herd has set out for other ground.
func on_migrated(species: StringName, _group: int, to: Vector2) -> void:
	if not _writing():
		return
	_log.record(TYPE_HERD_MOVED, {"species": String(species), "position": to})


## A plot was sown without seed: because the seed was eaten, if it was.
func on_sown_thin(crop_id: int) -> void:
	if not _writing():
		return
	var crop := _props.get_prop(crop_id) if _props != null else null
	var params := {"settlement": _settlement_id()}
	if crop != null:
		params["position"] = Places.middle_of(crop.tile)
	_log.record(TYPE_THIN_SOWING, params, [_seed_eaten_id])


## Such a plot has ripened: a poor harvest, because of the thin sowing.
func on_harvest_thin(crop_id: int) -> void:
	if not _writing():
		return
	var crop := _props.get_prop(crop_id) if _props != null else null
	var params := {"settlement": _settlement_id()}
	if crop != null:
		params["position"] = Places.middle_of(crop.tile)
	_log.record(TYPE_POOR_HARVEST, params, [_log.recent_id(TYPE_THIN_SOWING, 60 * TimeConfig.MINUTES_PER_DAY, _now())])
	# The harvest that follows will have seed again.
	_seed_eaten_id = 0


# --- the weather ----------------------------------------------------------------------------------

## The weather has changed: a storm is worth a line.
func on_weather_changed(_old: StringName, now: StringName) -> void:
	if not _writing() or now != WeatherSystem.STORM:
		return
	_log.record(TYPE_STORM, {})


## A drought, a heat wave or a cold snap has begun (or is over).
func on_condition_changed(condition: StringName, active: bool) -> void:
	if not _writing():
		return
	var key := String(condition)
	if active:
		var event := _log.record(StringName(key), {})
		_condition_ids[key] = event.id if event != null else 0
	else:
		var began := int(_condition_ids.get(key, 0))
		if began != 0:
			_log.note_effect(began, "ended", _now())
		_condition_ids.erase(key)


# --- the river ----------------------------------------------------------------------------------------

## The river is at its banks' edge or over them — because of the storm, if
## there was one in the last two days — or back in its bed.
func on_high_water(active: bool) -> void:
	if not _writing():
		return
	var causes: Array = []
	if active and _log != null:
		var now := _now()
		var storms := _log.of_type(TYPE_STORM, now - 2 * TimeConfig.MINUTES_PER_DAY, now)
		if not storms.is_empty():
			causes.append(storms[-1].id)
	_going(TYPE_HIGH_WATER, active, {}, causes)


## The banks lie dry — because of the drought, if there is one — or are
## under water again.
func on_low_water(active: bool) -> void:
	if not _writing():
		return
	_going(TYPE_LOW_WATER, active, {}, [condition_id(WeatherSystem.DROUGHT)])


## Where people live is under water — because the river is over its banks —
## or no longer.
func on_flood(active: bool, tiles: int, at: Vector2) -> void:
	if not _writing():
		return
	_going(TYPE_FLOOD, active, {"position": at, "tiles": tiles, "settlement": _settlement_id()}, [condition_id(TYPE_HIGH_WATER)])


## The river took a piece of its bank (in high water).
func on_bank_eroded(tile: Vector2i) -> void:
	if not _writing():
		return
	_log.record(TYPE_BANK_ERODED, {"position": Places.middle_of(tile)}, [condition_id(TYPE_HIGH_WATER)])


## A tree has died where the ground dried out — because of the drought or
## the low river, if there is one — or a young one in the cold. (What burns
## is the fire's to tell.)
func on_tree_died(tile: Vector2i, cause: StringName) -> void:
	if not _writing() or cause == VegetationSystem.CAUSE_FIRE:
		return
	var causes: Array = []
	var because: Array = [condition_id(WeatherSystem.COLD_SNAP)] if cause == VegetationSystem.CAUSE_COLD \
		else [condition_id(WeatherSystem.DROUGHT), condition_id(TYPE_LOW_WATER)]
	for id: int in because:
		if id != 0:
			causes.append(id)
	_log.record(TYPE_TREE_WITHERED, {"position": Places.middle_of(tile)}, causes)


## The flood going on — or the last one, if it is not long over (0 = none).
func flood_id() -> int:
	var going := condition_id(TYPE_FLOOD)
	if going != 0 or _log == null:
		return going
	var last := _log.latest(TYPE_FLOOD)
	if last != null and _now() - int(last.effects.get("ended", last.tick)) <= 30 * TimeConfig.MINUTES_PER_DAY:
		return last.id
	return 0


## A crop has drowned: because of the flood.
func on_crop_drowned(crop_id: int) -> void:
	if not _writing():
		return
	var crop := _props.get_prop(crop_id) if _props != null else null
	var params := {"settlement": _settlement_id()}
	if crop != null:
		params["position"] = Places.middle_of(crop.tile)
	_log.record(TYPE_CROP_FAILURE, params, [flood_id()] if flood_id() != 0 else [])


## The flood has taken of what lay in store.
func on_flood_took(resource: StringName, amount: int) -> void:
	if not _writing() or amount <= 0:
		return
	# One event for a flood: what it goes on to take is added to it.
	var flood := flood_id()
	var known := _log.latest(TYPE_STORES_FLOODED)
	if known != null and flood != 0 and Array(known.causes).has(flood):
		_log.note_effect(known.id, "lost", int(known.effects.get("lost", 0)) + amount)
		return
	var event := _log.record(TYPE_STORES_FLOODED, {"position": _fire_place(), "settlement": _settlement_id()},
		[flood] if flood != 0 else [])
	if event != null:
		_log.note_effect(event.id, "lost", int(event.effects.get("lost", 0)) + amount)


## A hut has been rebuilt on higher ground: because of the flood.
func on_home_moved(_hut_id: int, _from: Vector2i, to: Vector2i) -> void:
	if not _writing():
		return
	_log.record(TYPE_HOME_MOVED, {"position": Places.middle_of(to), "settlement": _settlement_id()},
		[flood_id()] if flood_id() != 0 else [])


# --- people and each other --------------------------------------------------------------------------

## What two people are to each other has changed: friends, fallen out,
## enemies — or made it up. Returns the event (null: nothing worth telling).
func on_kind_changed(a: int, b: int, kind: int, gained: bool) -> WorldEvent:
	if not _writing():
		return null
	var params := {"participants": [a, b], "position": _place_of(a), "settlement": _settlement_id()}
	match kind:
		Relationship.Kind.FRIEND:
			return _log.record(TYPE_FRIENDS, params) if gained else null
		Relationship.Kind.RIVAL:
			if gained:
				return _log.record(TYPE_FELL_OUT, params, _between(a, b, TYPE_FIGHT))
			return _log.record(TYPE_RECONCILED, params, _between(a, b, TYPE_FELL_OUT))
		Relationship.Kind.ENEMY:
			return _log.record(TYPE_ENEMIES, params, _between(a, b, TYPE_FELL_OUT)) if gained else null
	return null


## Two came to blows: because they had fallen out, if they had.
func on_social(act: StringName, a: int, b: int) -> WorldEvent:
	if not _writing() or act != SocialActs.FIGHT:
		return null
	return _log.record(TYPE_FIGHT, {"participants": [a, b], "position": _place_of(a), "settlement": _settlement_id()},
		_between(a, b, TYPE_FELL_OUT))


# --- lives -----------------------------------------------------------------------------------------

## A child is born (to its mother and father; the father may be dead).
func on_born(child_id: int, mother_id: int, father_id: int) -> void:
	if not _writing():
		return
	var who: Array = [child_id, mother_id]
	if father_id > 0:
		who.append(father_id)
	_log.record(TYPE_BORN, {"participants": who, "position": _place_of(child_id), "settlement": _settlement_id()},
		_between(mother_id, father_id, TYPE_PARTNERS) if father_id > 0 else [])


## Someone has died (they are still in the registry, and already in the
## archive): of what, and because of what. Their obituary: the more they
## mattered, the more it matters. Returns the event (null: none).
func on_died(person_id: int, cause: StringName, causes: Array) -> WorldEvent:
	if not _writing():
		return null
	var why: Array = causes.duplicate()
	match cause:
		Lifecycle.CAUSE_STARVATION:
			why.append(_empty_id if _empty_id != 0 else _shortage_id)
		Lifecycle.CAUSE_ILLNESS:
			why.append_array(_latest_of(person_id, [TYPE_ILL, TYPE_COLD_SICK]))
		Lifecycle.CAUSE_INJURY:
			why.append_array(_latest_of(person_id, [TYPE_FIGHT]))
		Lifecycle.CAUSE_ACCIDENT:
			why.append_array(_latest_of(person_id, [TYPE_INJURED]))
	var params := {"participants": [person_id], "cause": String(cause), "position": _place_of(person_id),
		"settlement": _settlement_id()}
	var record := _people.archive.get_record(person_id) if _people != null and _people.archive != null else null
	if record != null:
		params["significance"] = clampf(OBITUARY_BASE + OBITUARY_WEIGHT * record.significance, 0.0, 1.0)
	return _log.record(TYPE_DIED, params, why)


func on_partnered(a: int, b: int) -> void:
	if not _writing():
		return
	_log.record(TYPE_PARTNERS, {"participants": [a, b], "position": _place_of(a), "settlement": _settlement_id()},
		_between(a, b, TYPE_FRIENDS))


func on_came_of_age(person_id: int, stage: int) -> void:
	if not _writing():
		return
	_log.record(TYPE_CAME_OF_AGE, {"participants": [person_id], "kind": "elder" if stage == PersonData.LifeStage.ELDER else "adult",
		"position": _place_of(person_id), "settlement": _settlement_id()})


## Hurt in an accident at work (`kind` "fall", "cut") — or ill of a crowded roof ("crowding").
func on_injured(person_id: int, kind: StringName) -> void:
	if not _writing():
		return
	if kind == Health.CROWDING:
		_log.record(TYPE_ILL, {"participants": [person_id], "kind": String(kind), "position": _place_of(person_id),
			"settlement": _settlement_id()})
		return
	_log.record(TYPE_INJURED, {"participants": [person_id], "kind": String(kind), "position": _place_of(person_id),
		"settlement": _settlement_id()})


## Children left without a grown-up (or an elder left alone) taken in by
## family: by whoever is the eldest grown-up of the household.
func on_taken_in(person_id: int, household_id: int) -> void:
	if not _writing():
		return
	var eldest: PersonData = null
	for member in _people.in_household(household_id):
		if member.id != person_id and (eldest == null or member.birth_tick < eldest.birth_tick):
			eldest = member
	var who: Array = [person_id]
	if eldest != null:
		who.append(eldest.id)
	var deaths := _log.of_type(TYPE_DIED)
	_log.record(TYPE_TAKEN_IN, {"participants": who, "position": _place_of(person_id), "settlement": _settlement_id()},
		[deaths[-1].id] if not deaths.is_empty() else [])


## Someone from far away has come to live here.
func on_arrived(person_id: int) -> void:
	if not _writing():
		return
	_log.record(TYPE_ARRIVED, {"participants": [person_id], "position": _place_of(person_id), "settlement": _settlement_id()})


## The latest event of any of `types` that involves the person (as a list of causes).
func _latest_of(person_id: int, types: Array) -> Array:
	var best: WorldEvent = null
	for type: StringName in types:
		var found := _log.of_type(type)
		for n in range(found.size() - 1, -1, -1):
			if found[n].involves(person_id):
				if best == null or found[n].id > best.id:
					best = found[n]
				break
	return [best.id] if best != null else []


## The latest event of a type between two people (as a list of causes: [] if none).
func _between(a: int, b: int, type: StringName) -> Array:
	var found := _log.of_type(type)
	for n in range(found.size() - 1, -1, -1):
		if found[n].involves(a) and found[n].involves(b):
			return [found[n].id]
	return []


## Something that goes on for a while begins (an event) or ends (noted on it).
func _going(type: StringName, active: bool, params: Dictionary, causes: Array) -> void:
	var key := String(type)
	if active:
		var real: Array = []
		for cause: int in causes:
			if cause != 0:
				real.append(cause)
		var event := _log.record(type, params, real)
		_condition_ids[key] = event.id if event != null else 0
	else:
		var began := int(_condition_ids.get(key, 0))
		if began != 0:
			_log.note_effect(began, "ended", _now())
		_condition_ids.erase(key)


## The event of a weather condition that is going on (0 = it is not).
func condition_id(condition: StringName) -> int:
	return int(_condition_ids.get(String(condition), 0))


# --- the stores -----------------------------------------------------------------------------------

## Something was put on a pile. (Not written down while the world is being
## set up — see `listening`.)
func on_stored(resource: StringName, _amount: int, pile_id: int) -> void:
	if not _writing():
		return
	var pile := _loose.get_object(pile_id) if _loose != null else null
	var at := pile.position if pile != null else Vector2.INF
	var who := _who_is_at(at)
	if not _stored_once:
		_stored_once = true
		_log.record(TYPE_FIRST_STORAGE, {"resource": String(resource), "position": at, "participants": who,
			"settlement": _settlement_id()})
	if not _known.has(String(resource)):
		_known[String(resource)] = true
		_log.record(TYPE_DISCOVERED, {"resource": String(resource), "position": at, "participants": who,
			"settlement": _settlement_id()})


func on_spoiled(resource: StringName, amount: int) -> void:
	if not _writing() or amount <= 0:
		return
	_log.record(TYPE_SPOILED, {"resource": String(resource), "units": amount, "position": _fire_place(),
		"settlement": _settlement_id()})


func on_forage_changed(low: bool) -> void:
	if not _writing():
		return
	if low:
		var event := _log.record(TYPE_FORAGE, {"position": _fire_place(), "settlement": _settlement_id()})
		_forage_id = event.id if event != null else 0
	else:
		if _forage_id != 0:
			_log.note_effect(_forage_id, "ended", _now())
		_forage_id = 0


func on_fire_changed(lit: bool) -> void:
	if not _writing():
		return
	if lit:
		_log.record(TYPE_FIRE_RELIT, {"position": _fire_place(), "settlement": _settlement_id()}, [_fire_out_id])
		_fire_out_id = 0
	else:
		var event := _log.record(TYPE_FIRE_OUT, {"position": _fire_place(), "settlement": _settlement_id()},
			[condition_id(TYPE_FLOOD)] if condition_id(TYPE_FLOOD) != 0 else [])
		_fire_out_id = event.id if event != null else 0


# --- short of food ----------------------------------------------------------------------------------

## The settlement is short of food, out of it, or has enough again.
func on_shortage_changed(stage: int, was: int) -> void:
	if not _writing() or _settlement == null:
		return
	var here := {"position": _fire_place(), "settlement": _settlement_id()}
	if stage == Settlement.Shortage.NONE:
		_log.record(TYPE_OVER, here, [_shortage_id])
		if _shortage_id != 0:
			_log.note_effect(_shortage_id, "ended", _now())
		_shortage_id = 0
		_empty_id = 0
		return
	if was == Settlement.Shortage.NONE:
		var params := here.duplicate()
		params["days"] = snappedf(_settlement.days_of_food(), 0.01)
		var event := _log.record(TYPE_SHORTAGE, params, shortage_causes())
		_shortage_id = event.id if event != null else 0
		# What it does about it: because of it.
		_log.record(TYPE_RATIONING, here, [_shortage_id])
		_log.record(TYPE_FURTHER, here, [_shortage_id])
	if stage == Settlement.Shortage.EMPTY:
		var event := _log.record(TYPE_EMPTY, here, [_shortage_id])
		_empty_id = event.id if event != null else 0


func on_seed_released(units: int) -> void:
	if not _writing():
		return
	var event := _log.record(TYPE_SEED_EATEN, {"units": units, "position": _fire_place(), "settlement": _settlement_id()},
		[_empty_id if _empty_id != 0 else _shortage_id])
	_seed_eaten_id = event.id if event != null else 0


## What has brought a shortage about, as far as anyone can say: what went
## wrong with the food in the days before it — crops that failed, a poor
## harvest, food gone bad, bushes picked bare, stores carried off by the
## player. (Their ids.)
func shortage_causes() -> Array:
	var causes: Array = []
	if _log == null:
		return causes
	var now := _now()
	var window := roundi(_config.cause_window_days * TimeConfig.MINUTES_PER_DAY)
	for type: StringName in [TYPE_CROP_FAILURE, TYPE_CROP_FROZEN, TYPE_POOR_HARVEST, TYPE_SPOILED, TYPE_STORES_FLOODED]:
		for event in _log.of_type(type, now - window, now):
			causes.append(event.id)
	if _forage_id != 0:
		causes.append(_forage_id)
	for event in _log.of_type(TYPE_PLAYER, now - window, now):
		if bool(event.text_params.get("food", false)):
			causes.append(event.id)
	return causes


# --- people -----------------------------------------------------------------------------------------

func on_took_up(person_id: int, occupation: StringName) -> void:
	if not _writing():
		return
	_log.record(TYPE_TOOK_UP, {"occupation": String(occupation), "participants": [person_id], "position": _place_of(person_id),
		"settlement": _settlement_id()})


func on_hunted(person_id: int, species: StringName) -> void:
	if not _writing():
		return
	_log.record(TYPE_HUNTED, {"species": String(species), "participants": [person_id], "position": _place_of(person_id),
		"settlement": _settlement_id()})


## Someone is weak with hunger: because of the shortage, if there is one —
## or ill with the cold: because of the bitter cold, or the fire gone out.
func on_fell_ill(person_id: int, condition: StringName) -> void:
	if not _writing():
		return
	if condition == Exposure.COLD:
		var causes: Array = []
		for id: int in [condition_id(WeatherSystem.COLD_SNAP), _fire_out_id]:
			if id != 0:
				causes.append(id)
		_log.record(TYPE_COLD_SICK, {"participants": [person_id], "position": _place_of(person_id),
			"settlement": _settlement_id()}, causes)
		return
	if condition == Health.ILLNESS:
		var illness := Health.illness_of(_people.get_person(person_id)) if _people.get_person(person_id) != null else {}
		_log.record(TYPE_ILL, {"participants": [person_id], "kind": str(illness.get("kind", "")),
			"position": _place_of(person_id), "settlement": _settlement_id()})
		return
	if condition != Hardship.HUNGER:
		return
	_log.record(TYPE_SICK, {"participants": [person_id], "position": _place_of(person_id), "settlement": _settlement_id()},
		[_empty_id if _empty_id != 0 else _shortage_id])


func on_recovered(person_id: int, condition: StringName) -> void:
	if not _writing() or (condition != Hardship.HUNGER and condition != Exposure.COLD and condition != Health.ILLNESS):
		return
	var sick := 0
	var kind := TYPE_SICK
	if condition == Exposure.COLD:
		kind = TYPE_COLD_SICK
	elif condition == Health.ILLNESS:
		kind = TYPE_ILL
	for event in _log.of_type(kind):
		if event.involves(person_id):
			sick = event.id
	_log.record(TYPE_RECOVERED, {"participants": [person_id], "position": _place_of(person_id),
		"settlement": _settlement_id()}, [sick])


# --- the player -------------------------------------------------------------------------------------

## Everything the player does to the world (bible §21.1 "player
## interventions"). Gentle things done over and over are one event.
func on_intervention(iv: Intervention) -> void:
	if not _writing() or iv == null or not iv.applied or not iv.recorded:
		return
	var params := {"kind": String(iv.type), "subject": String(iv.subject), "intervention": iv.id,
		"position": Vector2(iv.position.x, iv.position.z),
		"significance": PLAYER_SIGNIFICANCE[clampi(iv.severity, 0, PLAYER_SIGNIFICANCE.size() - 1)]}
	if iv.subject == &"person" and iv.target_id != 0:
		params["participants"] = [iv.target_id]
	# Food carried away from where the settlement keeps it: what a shortage
	# that follows is put down to.
	if iv.type == Intervention.MOVE_OBJECT and _loose != null and _settlement != null:
		var object := _loose.get_object(iv.target_id)
		if object != null and object.kind == LooseObject.Kind.PILE:
			params["resource"] = String(object.resource)
			var def := _resources.get_def(object.resource) if _resources != null else null
			var store := _settlement.stockpile.place(object.resource)
			var from: Variant = iv.params.get("from")
			if def != null and def.is_food() and store != Vector2.INF and typeof(from) == TYPE_VECTOR2 \
					and (from as Vector2).distance_to(store) <= Config.resources.storage_radius \
					and object.position.distance_to(store) > Config.resources.storage_radius:
				params["food"] = true
				params["significance"] = maxf(float(params["significance"]), PLAYER_SIGNIFICANCE[1])
	_log.record(TYPE_PLAYER, params)


# --- saving -----------------------------------------------------------------------------------------

func to_dict() -> Dictionary:
	var known: Array = _known.keys()
	known.sort()
	return {"dry_spell": _dry_spell_id, "shortage": _shortage_id, "empty": _empty_id, "seed_eaten": _seed_eaten_id,
		"forage": _forage_id, "fire_out": _fire_out_id, "stored_once": _stored_once, "known": known,
		"conditions": _condition_ids.duplicate()}


func from_dict(data: Dictionary) -> void:
	reset()
	_dry_spell_id = _id(data.get("dry_spell"))
	_shortage_id = _id(data.get("shortage"))
	_empty_id = _id(data.get("empty"))
	_seed_eaten_id = _id(data.get("seed_eaten"))
	_forage_id = _id(data.get("forage"))
	_fire_out_id = _id(data.get("fire_out"))
	_stored_once = bool(data["stored_once"]) if typeof(data.get("stored_once")) == TYPE_BOOL else false
	var going: Variant = data.get("conditions")
	if typeof(going) == TYPE_DICTIONARY:
		for condition: Variant in going:
			if _id((going as Dictionary)[condition]) != 0:
				_condition_ids[str(condition)] = _id(going[condition])
	var known: Variant = data.get("known")
	if typeof(known) == TYPE_ARRAY:
		for resource: Variant in known:
			_known[str(resource)] = true


# --- internals --------------------------------------------------------------------------------------

func _writing() -> bool:
	return listening and _log != null


func _now() -> int:
	return _log.now() if _log != null else 0


func _settlement_id() -> int:
	return _settlement.id if _settlement != null else 0


func _fire_place() -> Vector2:
	var fire := _settlement.fire() if _settlement != null else null
	return fire.position2d() if fire != null else Vector2.INF


func _place_of(person_id: int) -> Vector2:
	var person := _people.get_person(person_id) if _people != null else null
	return person.world2d() if person != null else Vector2.INF


## Whoever stands nearest to a place (within STORER_RADIUS), as a list of
## one — or of none.
func _who_is_at(at: Vector2) -> PackedInt64Array:
	var out := PackedInt64Array()
	if _people == null or at == Vector2.INF:
		return out
	var best: PersonData = null
	for person in _people.all_people():
		var distance := person.world2d().distance_to(at)
		if distance <= STORER_RADIUS and (best == null or distance < best.world2d().distance_to(at)):
			best = person
	if best != null:
		out.append(best.id)
	return out


func _know_what_is_in_store() -> void:
	if _settlement == null:
		return
	for resource: StringName in _settlement.stockpile.amounts():
		_known[String(resource)] = true


static func _id(value: Variant) -> int:
	return maxi(int(value), 0) if typeof(value) == TYPE_INT else 0
