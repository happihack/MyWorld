class_name OfflineSimulator
extends RefCounted
## The world goes on while the player is away (bible §9.4, §31.8; M20). What
## people do minute by minute — walking, picking, chopping, eating — is lived
## a day at a time instead, at the rates a world left to itself shows (each
## trade's day's work, measured: see M20 in the plan), from what is really
## there (bushes with berries on them, trees, the fish in the water, the game
## about, the room in the stores). Everything that goes by the clock — births,
## deaths, the weather, discoveries, building, wars, stories — goes on as it
## does while the player watches, so what happened is real and named, with its
## causes. The result: the world as it is now, and what to tell the player
## (`summary`, for WHILE YOU WERE GONE, bible §26.8).
##
## Deterministic: the same world, the same time away — the same return.

## A day's work of each trade, in units brought home (bible §31.8 Tier 1;
## measured over two game years of two worlds, 2026-10-05). What else a trade
## does when its own work is done (berries) comes with it.
const RATES := {
	&"bush": {&"berries": 4.8},
	&"tree": {&"wood": 3.9},
	&"game": {&"meat": 0.85, &"berries": 4.5},
	&"field": {&"berries": 4.0},
	&"fish": {&"berries": 3.1},
	&"site": {&"wood": 1.5},
}
## Fish a fisher brings home a day from the bank with a line (more from a boat,
## with nets: WorkStep.catch_factor); field tasks a farmer gets through a day;
## the minutes a builder builds.
const FISH_PER_DAY := 14.0
## What a person eats from the stores in a day, in bellies (measured: 2.47 —
## more than the stores plan for, SettlementConfig.food_per_person_day).
const EAT_PER_DAY := 2.45
## Each day-step ends at this hour (minute of the day): late enough that what
## waits for the morning (the planner's day, setting out) has had its turn.
const STEP_AT_MINUTE := 12 * 60
const FIELD_TASKS_PER_DAY := 6
const BUILD_MINUTES_PER_DAY := 300.0
## The units of their own work a day that make someone better at it (WorkStep:
## Config.trade.skill_per_unit for each).
const SKILL_UNITS_PER_DAY := 4.0
## How many times a day two who are drawn to each other flirt (and what it does:
## RelationshipConfig.flirt_romance).
const FLIRTS_PER_DAY := 1.5
## A long absence with nothing notable in it: the Surprise Director (bible §25.3)
## raises the chance of something natural — a storm — after this many days, once.
const QUIET_DAYS := 3
const NOTABLE_FROM := 0.6
## A real gap below this is not an absence worth telling of (seconds; bible §26.8).
const TELL_FROM_SECONDS := 600

var _s: WorldSession
var _rng: RandomNumberGenerator
var _events: Array[int] = []
var _surprised := false
## What was lived through (filled by `run`): see `summary()`.
var start_tick := 0
var end_tick := 0
var days := 0


func _init(session: WorldSession) -> void:
	_s = session
	_rng = RandomNumberGenerator.new()
	_rng.seed = hash([session.world_seed, session.clock.tick, "offline"])


# --- how long --------------------------------------------------------------------------------------

## Game minutes for `real_seconds` away (D-09): at Normal speed, in full up to
## `full_hours`, then less and less, to at most `cap_hours`' worth — someone away
## a month comes back to an older world, not a dead one.
static func game_minutes_for(real_seconds: float, full_hours: float = 24.0, cap_hours: float = 72.0) -> int:
	if real_seconds <= 0.0:
		return 0
	var hours := real_seconds / 3600.0
	var lived := hours
	if hours > full_hours:
		var beyond := cap_hours - full_hours
		lived = full_hours + beyond * (1.0 - exp(-(hours - full_hours) / maxf(beyond, 0.001)))
	lived = minf(lived, cap_hours)
	return floori(lived * 3600.0 / Config.time.real_seconds_per_game_minute)


## Seconds away, between the save and now — never less than nothing, and not
## to be fooled by a clock set back (`last_seen`: the latest time the game has
## seen; a "now" before it counts from it).
static func seconds_away(saved_unix: int, now_unix: int, last_seen_unix: int = 0) -> int:
	if saved_unix <= 0:
		return 0
	var now := now_unix
	if last_seen_unix > 0 and now < last_seen_unix:
		return 0 # (the clock was set back: no time has passed, as far as the box knows)
	return maxi(now - saved_unix, 0)


# --- living it ---------------------------------------------------------------------------------------

## Lives `minutes` of game time in day-steps, all at once. Returns `summary()`.
func run(minutes: int) -> Dictionary:
	begin(minutes)
	while not step(1 << 62):
		pass
	return finish()


## Begins living `minutes` of game time (then `step` until it is done, and `finish`).
func begin(minutes: int) -> void:
	start_tick = _s.clock.tick
	end_tick = start_tick + maxi(minutes, 0)
	_quiet_since = start_tick
	if minutes <= 0 or not _s.is_active:
		end_tick = start_tick
		return
	_s.events.recorded.connect(_heard)
	# (Nothing is toasted while the player is away: what happened is told on return.)
	_telling = NotificationManager.enabled
	NotificationManager.enabled = false
	_begun = true
	_s.movement.stop_all()


## Lives day-steps until `budget_usec` has gone by (a frame's worth: the box
## settles while the screen keeps moving). True once the time away is lived.
func step(budget_usec: int) -> bool:
	var started := Time.get_ticks_usec()
	while _s.clock.tick < end_tick:
		_day_step()
		if Time.get_ticks_usec() - started >= budget_usec:
			break
	return _s.clock.tick >= end_tick


## How far through the time away it is, 0 … 1.
func progress() -> float:
	return 1.0 if end_tick <= start_tick else clampf(float(_s.clock.tick - start_tick) / float(end_tick - start_tick), 0.0, 1.0)


## Done: people back to their days; what happened. Returns `summary()`.
func finish() -> Dictionary:
	if _begun:
		_settle_people()
		_s.events.recorded.disconnect(_heard)
		NotificationManager.enabled = _telling
		_begun = false
	return summary()


var _begun := false
var _telling := true
var _quiet_since := 0


func _heard(event: WorldEvent) -> void:
	_events.append(event.id)


## One day-step: to the next noon (or the end of the time away).
func _day_step() -> void:
	var now := _s.clock.tick
	var to_noon := posmod(STEP_AT_MINUTE - Config.time.minute_of_day(now), TimeConfig.MINUTES_PER_DAY)
	var next := mini(now + (to_noon if to_noon > 0 else TimeConfig.MINUTES_PER_DAY), end_tick)
	var share := float(next - now) / float(TimeConfig.MINUTES_PER_DAY)
	for own in _s.settlements.all().duplicate():
		_work(own, share, now)
	_s.clock.jump_to(next)
	_s.fauna.skip_to(next) # (only the herds' days: nobody watches them graze)
	for own in _s.settlements.all().duplicate():
		_eat(own, share)
	_court(share)
	_arrive()
	_s.advance_systems()
	_s.behavior.announce()
	days += 1
	if _notable_since(_quiet_since):
		_quiet_since = _s.clock.tick
	elif not _surprised and _s.clock.tick - _quiet_since >= QUIET_DAYS * TimeConfig.MINUTES_PER_DAY:
		_surprise()


## A day's work (`share` of it) for everyone of a settlement who has a trade.
func _work(own: Settlement, share: float, now: int) -> void:
	if own.occupations == null:
		return
	# (What everyone gathers is added up and taken from the land once a
	# resource: each gathering asks the stores for room, and that looks at
	# every pile — a thousand times a day was seconds: M21.)
	var gathered := {} # [kind, resource] -> amount
	for person in own.members():
		var def := own.occupations.get_def(person.occupation_id)
		if def == null or def.work_target == &"" or not def.allows(person.life_stage(now, Config.time.ticks_per_year(), Config.people)):
			continue
		var target := def.work_target
		match target:
			&"bush":
				_add_to(gathered, PropData.Kind.BUSH, &"berries", RATES[&"bush"][&"berries"] * share)
			&"tree":
				_add_to(gathered, PropData.Kind.TREE, &"wood", RATES[&"tree"][&"wood"] * share)
			&"game":
				_hunt(own, share)
			&"fish":
				_fish(own, share)
			&"field":
				_farm(own, person, share, now)
			&"site":
				_build(own, person, share, now)
		# Better at it for the day's work (as they would be, a unit at a time: WorkStep).
		var key := String(person.occupation_id)
		person.skills[key] = minf(float(person.skills.get(key, 0.0)) + Config.trade.skill_per_unit * SKILL_UNITS_PER_DAY * share, 1.0)
		# What else they gather when their own work is done.
		var also: Dictionary = RATES.get(target, {})
		if target != &"bush" and also.has(&"berries"):
			_add_to(gathered, PropData.Kind.BUSH, &"berries", float(also[&"berries"]) * share)
	for key: Array in gathered:
		_gather(own, key[0], key[1], float(gathered[key]), now)


static func _add_to(gathered: Dictionary, kind: PropData.Kind, resource: StringName, amount: float) -> void:
	var key := [kind, resource]
	gathered[key] = float(gathered.get(key, 0.0)) + amount


## `amount` (in units, a fraction carried over by the dice) of `resource` from
## the nodes of `kind` near the settlement, nearest first, into its stores.
func _gather(own: Settlement, kind: PropData.Kind, resource: StringName, amount: float, now: int) -> void:
	var units := _whole(amount)
	units = mini(units, own.stockpile.room(resource))
	if units <= 0 or own.fire() == null:
		return
	var got := 0
	for prop: PropData in _nodes_near(own, kind):
		if got >= units:
			break
		if _s.nodes.available(prop) <= 0:
			continue
		got += _s.nodes.take(prop.id, units - got, now)
	if got > 0:
		own.stockpile.add(resource, got)
		own.note_produced(resource, got)


## The nodes of `kind` within a day's walk of the fire, nearest first (kept for the run).
var _near: Dictionary = {}
func _nodes_near(own: Settlement, kind: PropData.Kind) -> Array:
	var key := [own.id, kind]
	if _near.has(key):
		return _near[key]
	var fire := own.fire().tile
	var found: Array = []
	for prop in _s.props.of_kind(kind):
		if prop.kind == kind and Vector2(prop.tile - fire).length() <= Places.WORK_RADIUS:
			found.append(prop)
	found.sort_custom(func(a: PropData, b: PropData) -> bool:
		var da := (a.tile - fire).length_squared()
		var db := (b.tile - fire).length_squared()
		return da < db or (da == db and a.id < b.id))
	_near[key] = found
	return found


func _hunt(own: Settlement, share: float) -> void:
	if own.fauna == null or own.fire() == null or own.stockpile.room(&"meat") <= 0:
		return
	if Config.settlement.winter_no_game and Config.time.season_of(_s.clock.tick) == Config.time.seasons_per_year - 1:
		return
	var at := own.fire().position2d()
	var quarry := own.fauna.quarry_for(at, at, Config.settlement.hunt_radius)
	if quarry == null:
		return
	var def := own.fauna.species.get_def(quarry.species)
	var meat := maxf(float(def.meat) if def != null else 1.0, 1.0)
	if _rng.randf() < RATES[&"game"][&"meat"] * share / meat:
		var got := mini(own.fauna.hunted(quarry.id), own.stockpile.room(&"meat"))
		if got > 0:
			own.stockpile.add(&"meat", got)
			own.note_produced(&"meat", got)


func _fish(own: Settlement, share: float) -> void:
	if own.fauna == null or not own.fish_near():
		return
	var landing := not _s.construction.standing(PropData.Kind.LANDING).is_empty()
	var iced := _s.pathfinder != null and _s.pathfinder.is_frozen()
	var amount := FISH_PER_DAY * share * WorkStep.catch_factor(own, landing) / (WorkStep.ICE_FACTOR if iced else 1.0)
	var units := mini(_whole(amount), own.stockpile.room(&"fish"))
	var got := own.fauna.take_fish(units) if units > 0 else 0
	if got > 0:
		own.stockpile.add(&"fish", got)
		own.note_produced(&"fish", got)


## A farmer's day: the field's tasks as they come (sowing, tending, clearing),
## and the reaping of what is ripe — into the stores.
func _farm(own: Settlement, person: PersonData, share: float, now: int) -> void:
	var farming := own.farming
	if farming == null:
		return
	for n in maxi(roundi(FIELD_TASKS_PER_DAY * share), 1):
		var task := farming.task_for(person, now)
		if task.is_empty():
			return
		if StringName(task["task"]) == Farming.HARVEST:
			var room := own.stockpile.room(&"grain")
			var got := _s.nodes.take(int(task["id"]), maxi(room, 0), now) if room > 0 else 0
			if got <= 0:
				return
			own.stockpile.add(&"grain", got)
			own.note_produced(&"grain", got)
		elif not farming.finish(StringName(task["task"]), task["tile"], int(task["id"]), now):
			return


## A builder's day: what the sites need, from the stores, and the work.
func _build(own: Settlement, person: PersonData, share: float, now: int) -> void:
	if _s.construction == null:
		return
	for project in _s.construction.projects_of(own.id):
		var needed := _s.construction.still_needed(project)
		for resource: StringName in needed:
			var units := own.stockpile.take(resource, int(needed[resource]))
			if units > 0:
				_s.construction.deliver(project, resource, units)
		if _s.construction.can_work(project):
			_s.construction.work(project, person, BUILD_MINUTES_PER_DAY * share, now)
			return
	# Nothing to build: they bring in wood for what is to come.
	_gather(own, PropData.Kind.TREE, &"wood", RATES[&"site"][&"wood"] * share, now)


## Everyone eats their share of the day from the stores (what goes bad soonest
## first), shared out evenly as the stores ration it; whoever goes without goes
## hungry — and that takes its course.
func _eat(own: Settlement, share: float) -> void:
	var ctx := _s.behavior.ctx
	var members := own.members()
	if members.is_empty():
		return
	var need := EAT_PER_DAY * share
	var wanted := need * members.size()
	var eaten := 0.0
	# (Taken a kind at a time, not a unit at a time: the stores count their piles anew at each change.)
	var kinds: Array = []
	for resource: StringName in own.stockpile.amounts():
		var def := _s.resources.get_def(resource)
		if def != null and def.nutrition > 0.0 and own.stockpile.available(resource) > 0:
			kinds.append(def)
	kinds.sort_custom(func(a: ResourceDef, b: ResourceDef) -> bool:
		return a.spoil_days < b.spoil_days or (a.spoil_days == b.spoil_days and String(a.id) < String(b.id)))
	for def: ResourceDef in kinds:
		if eaten >= wanted:
			break
		var units := mini(ceili((wanted - eaten) / def.nutrition), own.stockpile.available(def.id))
		eaten += own.stockpile.take(def.id, units) * def.nutrition
	var fed := clampf(eaten / maxf(wanted, 0.0001), 0.0, 1.0)
	for person in members:
		var hunger := person.needs[Needs.Need.HUNGER] if person.needs.size() == Needs.COUNT else 1.0
		person.needs = Needs.full()
		person.needs[Needs.Need.HUNGER] = fed if fed < 0.999 else maxf(hunger, 0.85)
		if ctx != null:
			ctx.enter(person)
			Hardship.live(person, ctx, TimeConfig.MINUTES_PER_DAY * share)


## Two grown-ups, both free, drawn to each other: they flirt, as they would.
func _court(share: float) -> void:
	var store := _s.relationships
	var ctx := _s.behavior.ctx
	if store == null or ctx == null:
		return
	var config := Config.relationships
	for own in _s.settlements.all():
		var free: Array[PersonData] = []
		for person in own.members():
			if person.partner_id == 0 and ctx.stage_of(person) == PersonData.LifeStage.ADULT:
				free.append(person)
		for pair in _meetings(free):
			var a: PersonData = pair[0]
			var b: PersonData = pair[1]
			if not SocialActs.may_flirt(a, b, ctx):
				continue
			var record := store.between(a.id, b.id)
			var feeling := record.affinity if record != null else 0.0
			var drawn := SocialActs.chemistry(a, b)
			if (feeling > 0.15 or drawn >= config.chemistry_from) and feeling > -0.2:
				store.modify(a.id, b.id, {"romance": config.flirt_romance * (0.5 + drawn) * FLIRTS_PER_DAY * share,
					"affinity": config.talk_affinity * FLIRTS_PER_DAY * share}, 0, _s.clock.tick)


## Who meets whom, a day: in a small settlement every free pair (as on
## screen, where everyone runs into everyone); in a large one each meets those
## they already know and the same few others every day — their neighbours in
## the order of their ids, as at a long table — so that what grows between
## two people has the days to grow (M21: every pair of a few hundred free
## people was seconds a day). Each pair once, in a fixed order.
const EVERYONE_MEETS_UP_TO := 24
const NEIGHBOURS_A_DAY := 6


func _meetings(free: Array[PersonData]) -> Array:
	var out: Array = []
	if free.size() <= EVERYONE_MEETS_UP_TO:
		for i in free.size():
			for j in range(i + 1, free.size()):
				out.append([free[i], free[j]])
		return out
	var index := {}
	for i in free.size():
		index[free[i].id] = i
	var seen := {}
	for i in free.size():
		var a := free[i]
		var others: Array[int] = []
		for other_id: int in _s.relationships.of(a.id):
			if index.has(other_id):
				others.append(int(index[other_id]))
		for k in range(1, NEIGHBOURS_A_DAY + 1):
			others.append((i + k) % free.size())
		for j in others:
			if j == i:
				continue
			var key := Vector2i(mini(i, j), maxi(i, j))
			if seen.has(key):
				continue
			seen[key] = true
			out.append([free[key.x], free[key.y]])
	return out


## Those setting out to found (or join) a settlement are where they were going.
func _arrive() -> void:
	for journey in _s.migration.journeys.duplicate():
		var to: Vector2i = journey["to"]
		for id: int in journey["members"]:
			var person := _s.people.get_person(id)
			if person != null:
				_s.people.place(person, to, person.sub_tile_offset, person.facing)


## The Surprise Director (bible §25.3): a long stretch with nothing notable —
## a storm, if the sky can bring one (never something that did not happen).
func _surprise() -> void:
	_surprised = true
	if _s.weather == null or not WeatherSystem.STATES.has(&"storm"):
		return
	_s.weather.hold(&"storm", _s.clock.tick + 6 * 60)


func _notable_since(since: int) -> bool:
	for id in _events:
		var event := _s.events.get_event(id)
		if event != null and event.tick >= since and event.significance >= NOTABLE_FROM:
			return true
	return false


## Back from the day-steps: everyone at home, no plan half-done; the behaviour
## takes it from here.
func _settle_people() -> void:
	for person in _s.people.all_people():
		person.current_action = {}
		var home: Variant = _s.behavior.ctx.places.home_tile(person) if _s.behavior.ctx != null else null
		if home != null and _s.migration.journeys.is_empty():
			_s.people.place(person, home, person.sub_tile_offset, person.facing)


## A fraction of a unit counts by the dice.
func _whole(amount: float) -> int:
	var units := floori(amount)
	if _rng.randf() < amount - units:
		units += 1
	return units


# --- what to tell --------------------------------------------------------------------------------------

## What happened while the player was away (bible §26.8):
##   {days, minutes, counts: {births, deaths, settlements, discoveries, storms, buildings, observations},
##    hook: {text, position (Vector2.INF: nowhere), event_id} or {}, events: [ids]}
func summary() -> Dictionary:
	var counts := {"births": 0, "deaths": 0, "settlements": 0, "discoveries": 0, "storms": 0, "buildings": 0, "observations": 0}
	var hook: WorldEvent = null
	for id in _events:
		var event := _s.events.get_event(id)
		if event == null:
			continue
		match event.type:
			&"person_born":
				counts["births"] += 1
			&"person_died":
				counts["deaths"] += 1
			&"settlement_founded":
				counts["settlements"] += 1
			&"knowledge_learned", &"era_entered":
				counts["discoveries"] += 1
			&"storm", &"flood", &"drought":
				counts["storms"] += 1
			&"building_built":
				counts["buildings"] += 1
			&"box_research", &"hypothesis", &"mystery_clue":
				counts["observations"] += 1
		# The hook: the most intriguing thing that happened somewhere — the
		# strange first, then whatever mattered most.
		if event.position != Vector2.INF and (hook == null or _intrigue(event) > _intrigue(hook)):
			hook = event
	var told := {}
	if hook != null:
		told = {"text": EventText.text(hook, _s.people, _s.events), "position": hook.position, "event_id": hook.id}
	return {"days": roundi(float(end_tick - start_tick) / TimeConfig.MINUTES_PER_DAY), "minutes": end_tick - start_tick,
		"counts": counts, "hook": told, "events": _events.duplicate()}


func _intrigue(event: WorldEvent) -> float:
	var strange := 1.0 if [&"box_research", &"hypothesis", &"mystery_clue", &"anomaly"].has(event.type) else 0.0
	return strange + event.significance
