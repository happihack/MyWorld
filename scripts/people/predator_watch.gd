class_name PredatorWatch
extends RefCounted
## Seen and feared (PR2, the owner 2026-10-08). A big predator near people:
## whoever sees it — and anyone it is close to — runs for the fire,
## shouting; the first time a beast (a pack) is seen, the settlement knows
## of it, and the player is told ("A bear has been seen near Stapa — a
## hunting party is gathering"). While it is about, the children and the old
## are called back near the fire. (Nobody takes it for a spirit: a bear is a
## bear — this is not the Perception system's way with the uncanny.)

## A beast (a pack) was seen for the first time: by whom, where, of which settlement.
signal spotted(species: StringName, group: int, at: Vector2, by_id: int, settlement_id: int)
## Someone was attacked (PR3): how badly (0 … 1), and whether it killed them.
signal attacked(person_id: int, species: StringName, severity: float, killed: bool, settlement_id: int)

## How often the watch looks (game minutes).
const CHECK_MINUTES := 10
## How far a beast is seen: by day, at night; among trees, this much less.
const SIGHT_DAY := 10.0
const SIGHT_NIGHT := 4.0
const IN_TREES := 0.6
const DAY_FROM := 6.0
const DAY_TO := 20.0
## Anyone this near it runs too, seen or not (they hear it, the others shout).
const SCARE := 8.0
## How fast they run (times walking), and how long the shout lasts (minutes).
const RUN_PACE := 2.2
const SHOUT_MINUTES := 2.0
## While a beast is known to be within ALARM_REACH of its fire, children and
## the old further out than KEEP_NEAR are called back.
const ALARM_REACH := 45.0
const KEEP_NEAR := 10.0
## Attacks (PR3, the owner: mostly wounds, death rare): every CHECK_MINUTES a
## beast that is awake may go for the nearest one alone (nobody else awake
## within ALONE) within STALK — ATTACK_PER_CHECK times its aggression and its
## hour, twice as likely a child or one of the old. The wound: its danger,
## somewhat less or more; the worst (KILL_FROM and over) kill one in
## KILL_SHARE outright — the rest may yet die of them (Lifecycle).
const STALK := 12.0
const ALONE := 8.0
const ATTACK_PER_CHECK := 0.035
const FRAIL_FACTOR := 2.0
const KILL_FROM := 0.9
const KILL_SHARE := 0.25

## Why they run, and why they come back (BehaviorSystem reasons).
const REASON_RUN := &"predator"
const REASON_KEEP_NEAR := &"keep_near"

var fauna: AnimalSystem
var people: PersonRegistry
var behavior: BehaviorSystem
var settlements: Settlements
var props: PropRegistry
var day_log: DayLog
var rng: RandomNumberGenerator
## Callable(person: PersonData, cause: StringName): someone dies (Lifecycle.die).
var kill: Callable
## Callable(person: PersonData, subject: StringName, importance: float): a memory (Lifecycle.remember_life).
var remember: Callable

## The beasts known about: group -> {"species", "at" (last seen), "seen" (tick),
## "settlement" (whose), "by" (who first saw it)}.
var _known: Dictionary = {}
var _last := -1_000_000


func bind(now: int) -> void:
	_known.clear()
	_last = now


## Looks every CHECK_MINUTES (cheap when no beast is about).
func advance_to(now: int) -> void:
	if fauna == null or people == null or now - _last < CHECK_MINUTES:
		return
	_last = now
	var about := fauna.visitors()
	_forget_gone(about)
	if about.is_empty():
		return
	var hour := Config.time.minute_of_day(now) / 60.0
	var daylight := hour >= DAY_FROM and hour < DAY_TO
	for beast in about:
		var sight := SIGHT_DAY if daylight else SIGHT_NIGHT
		if PredatorHabitat.tree_share(props, beast.tile()) > 0.5:
			sight *= IN_TREES
		var seers: Array[PersonData] = []
		var near: Array[PersonData] = []
		for id in people.spatial_index.query_radius(beast.position, maxf(sight, SCARE), SpatialIndex.KIND_PERSON):
			var person := people.get_person(id)
			if person == null or person.has_flag(PersonData.FLAG_INDOORS) or person.aboard != 0:
				continue
			var distance := person.world2d().distance_to(beast.position)
			if distance <= sight and person.pose != PersonData.Pose.SLEEP:
				seers.append(person)
			elif distance <= SCARE:
				near.append(person)
		if seers.is_empty():
			continue
		seers.sort_custom(func(a: PersonData, b: PersonData) -> bool:
			return a.world2d().distance_squared_to(beast.position) < b.world2d().distance_squared_to(beast.position))
		_seen(beast, seers[0], now)
		for person in seers + near:
			run_home(person, beast, now)
	_attacks(about, now, hour)
	_keep_near(now)


## Is a beast known to be about near this settlement (the alarm is up)?
func alarm(settlement_id: int) -> bool:
	for group: int in _known:
		if int(_known[group]["settlement"]) == settlement_id:
			return true
	return false


## What is known of a beast (a pack): {} if it has not been seen.
func known(group: int) -> Dictionary:
	return _known.get(group, {})


func known_groups() -> Array:
	return _known.keys()


## Someone runs for the fire from `beast` (a shout first). Not those already
## running from one, nor (PR4) those out to hunt it.
func run_home(person: PersonData, beast: AnimalData, now: int) -> void:
	var doing := person.current_action
	if str(doing.get("reason", "")) == String(REASON_RUN) or str(doing.get("reason", "")) == "hunting_party":
		return
	var fire: Variant = _fire_of(person)
	if fire == null:
		return
	var to := Planner._beside(fire, person.position, behavior.ctx)
	var steps := [ReactStep.make(PersonData.Pose.STARTLE, &"exclaim", SHOUT_MINUTES, beast.position),
		WalkToStep.make(to, Vector2(0.5, 0.5), RUN_PACE, &"exclaim")]
	behavior.set_plan(person, BehaviorSystem.ACTIVITY_REACT, REASON_RUN, steps, 9.0)
	if day_log != null:
		day_log.note(person.id, now, "life", "saw_" + String(beast.species))


## A beast that is awake may go for someone alone near it (one try a check
## for each beast or pack).
func _attacks(about: Array[AnimalData], now: int, hour: float) -> void:
	if rng == null:
		return
	var tried := {}
	for beast in about:
		if tried.has(beast.group) or beast.state == AnimalData.State.SLEEP or beast.state == AnimalData.State.FLEE:
			continue
		var def := fauna.species.get_def(beast.species)
		if def == null or def.aggression <= 0.0:
			continue
		var victim := _lone_one_near(beast)
		if victim == null:
			continue
		tried[beast.group] = true
		var frail := _frail(victim, now)
		var chance := ATTACK_PER_CHECK * def.aggression * hour_factor(beast.species, hour) * (FRAIL_FACTOR if frail else 1.0)
		if rng.randf() < chance:
			attack(beast, victim, now)


## The beast goes for `victim`: a wound (rarely death); it makes off after;
## the victim runs for the fire, if they can.
func attack(beast: AnimalData, victim: PersonData, now: int) -> void:
	var def := fauna.species.get_def(beast.species)
	var severity := clampf(def.danger * rng.randf_range(0.5, 1.15) * (1.3 if _frail(victim, now) else 1.0), 0.05, 1.0)
	# (Upon them, then off.)
	var side := (victim.world2d() - beast.position).normalized()
	fauna.registry.move(beast.id, victim.world2d() - side * 0.4, side.angle())
	_seen(beast, victim, now)
	Health.injure(victim, Health.MAULED, severity, now)
	var killed := severity >= KILL_FROM and rng.randf() < KILL_SHARE
	var own := settlements.of(victim) if settlements != null else null
	attacked.emit(victim.id, beast.species, severity, killed, own.id if own != null else 0)
	fauna.startle_one(beast.id, victim.world2d(), now)
	if killed and kill.is_valid():
		kill.call(victim, Lifecycle.CAUSE_MAULED)
		return
	run_home(victim, beast, now)
	if day_log != null:
		day_log.note(victim.id, now, "life", "mauled")
	if remember.is_valid():
		remember.call(victim, &"life_mauled", 0.85)


## How much readier a beast is at this hour: a bear or a boar by day, a
## mountain lion at dusk and dawn, wolves at night.
static func hour_factor(species: StringName, hour: float) -> float:
	match species:
		&"wolf":
			return 1.5 if hour >= 20.0 or hour < 6.0 else 0.4
		&"lion":
			return 1.5 if (hour >= 17.0 and hour < 21.0) or (hour >= 4.0 and hour < 7.0) else 0.5
		_:
			return 1.0 if hour >= 6.0 and hour < 20.0 else 0.3


## The nearest one out alone within STALK of the beast (null: none).
func _lone_one_near(beast: AnimalData) -> PersonData:
	var best: PersonData = null
	var best_distance := INF
	for id in people.spatial_index.query_radius(beast.position, STALK, SpatialIndex.KIND_PERSON):
		var person := people.get_person(id)
		if person == null or person.has_flag(PersonData.FLAG_INDOORS) or person.aboard != 0:
			continue
		if str(person.current_action.get("reason", "")) == "hunting_party":
			continue # (they are fought with: PR4)
		var distance := person.world2d().distance_to(beast.position)
		if distance >= best_distance:
			continue
		var alone := true
		for other_id in people.spatial_index.query_radius(person.world2d(), ALONE, SpatialIndex.KIND_PERSON):
			var other := people.get_person(other_id)
			if other != null and other.id != person.id and not other.has_flag(PersonData.FLAG_INDOORS) and other.pose != PersonData.Pose.SLEEP:
				alone = false
				break
		if alone:
			best = person
			best_distance = distance
	return best


func _frail(person: PersonData, now: int) -> bool:
	var stage := person.life_stage(now, Config.time.ticks_per_year(), Config.people)
	return stage == PersonData.LifeStage.CHILD or stage == PersonData.LifeStage.ELDER


## Seen by `by` (away: no one was there to watch it happen).
func seen(beast: AnimalData, by: PersonData, now: int) -> void:
	_seen(beast, by, now)


func _seen(beast: AnimalData, by: PersonData, now: int) -> void:
	var first := not _known.has(beast.group)
	var own := settlements.of(by) if settlements != null else null
	var entry: Dictionary = _known.get(beast.group, {"species": beast.species, "by": by.id,
		"settlement": own.id if own != null else 0})
	entry["at"] = beast.position
	entry["seen"] = now
	_known[beast.group] = entry
	if first:
		spotted.emit(beast.species, beast.group, beast.position, by.id, int(entry["settlement"]))


## Gone (killed, back to the wilds): no longer known about.
func _forget_gone(about: Array[AnimalData]) -> void:
	if _known.is_empty():
		return
	var groups := {}
	for beast in about:
		groups[beast.group] = true
	for group: int in _known.keys():
		if not groups.has(group):
			_known.erase(group)


## The children and the old out beyond KEEP_NEAR of their fire, while a beast
## is about: called back.
func _keep_near(now: int) -> void:
	if settlements == null:
		return
	for own in settlements.all():
		if not alarm(own.id) or own.fire() == null:
			continue
		var fire := own.fire().tile
		for person in own.members():
			var stage := person.life_stage(now, Config.time.ticks_per_year(), Config.people)
			if stage != PersonData.LifeStage.CHILD and stage != PersonData.LifeStage.ELDER:
				continue
			if person.has_flag(PersonData.FLAG_INDOORS) or Vector2(person.position - fire).length() <= KEEP_NEAR:
				continue
			var reason := str(person.current_action.get("reason", ""))
			if reason == String(REASON_RUN) or reason == String(REASON_KEEP_NEAR):
				continue
			var to := Planner._beside(fire, person.position, behavior.ctx)
			behavior.set_plan(person, BehaviorSystem.ACTIVITY_REACT, REASON_KEEP_NEAR, [WalkToStep.make(to)], 6.0)


func _fire_of(person: PersonData) -> Variant:
	var own := settlements.of(person) if settlements != null else null
	return own.fire().tile if own != null and own.fire() != null else null


func to_dict() -> Dictionary:
	var out := {}
	for group: int in _known:
		var entry: Dictionary = _known[group]
		out[str(group)] = {"species": String(entry["species"]), "x": (entry["at"] as Vector2).x, "z": (entry["at"] as Vector2).y,
			"seen": entry["seen"], "settlement": entry["settlement"], "by": entry["by"]}
	return {"known": out, "last": _last}


func from_dict(data: Dictionary) -> void:
	_known.clear()
	var known_saved: Variant = data.get("known")
	if typeof(known_saved) == TYPE_DICTIONARY:
		for key: Variant in known_saved:
			var entry: Variant = known_saved[key]
			if typeof(entry) != TYPE_DICTIONARY:
				continue
			_known[int(str(key))] = {"species": StringName(str(entry.get("species", ""))),
				"at": Vector2(float(entry.get("x", 0.0)), float(entry.get("z", 0.0))), "seen": int(entry.get("seen", 0)),
				"settlement": int(entry.get("settlement", 0)), "by": int(entry.get("by", 0))}
	_last = int(data.get("last", _last))
