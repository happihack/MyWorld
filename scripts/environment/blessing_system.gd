class_name BlessingSystem
extends RefCounted
## The blessings the player can give (the owner and Josh, 2026-10-16; the
## plan's BLESSINGS section; bible §10.5, §23.4, §24): the other hand of the
## Presence, a twin of the disasters (DisasterSystem). Chosen from the
## Blessing button, each offered on a card first; given where the camera
## looks (the lights are everywhere).
##
## One rest for both hands: the Presence acts once a day, whichever way.
## The rest after a blessing is the disasters' rest, and neither can begin
## while the other goes on. Goes by the clock (advance_to), so it goes on
## while the player is away, and is saved with the world while one goes on.
##
## Every blessing lasts a while and fades — a season at the most — so that
## the people can make a story of it (a before and an after).

## A blessing has begun at `at` (world X/Z).
signal started(kind: StringName, at: Vector2)
## It is over.
signal ended(kind: StringName)

## Lights in the sky: an hour of lights over the box — the night lit green
## and violet, the day's sun ringed pale gold. Harms nothing, changes
## nothing: made of what people make of it.
const LIGHTS := &"lights"
## Bounty of the bushes: every berry bush within reach filled, and for a
## season the bushes there spread and grow back faster (VegetationSystem).
const BOUNTY := &"bounty"
## Rich soil: silt on the land within reach, as a flood leaves it
## (SoilSystem), fading as silt does; the fields there heavier at harvest.
const SOIL := &"soil"
## Teeming waters: the water within reach filled with fish, and a run begun
## out of season (FishWaters).
const WATERS := &"waters"
## Healing: everyone ill, injured or sick from cold or hunger within reach
## recovers over the day. Nobody made younger, nobody brought back.
const HEALING := &"healing"
## The drought broken: a day of soft rain over the world, the drought ended,
## the river back to where it was made. The weather's own, as the storm and
## the flood are the disasters': the weather tells of it.
const RAIN := &"rain"
## The herds return: a herd of deer comes to the land within reach.
const HERDS := &"herds"
## The lasting ones (the workshop: later and rarer; the owner, 2026-10-17,
## "in order"). A spring: water rises on the tile under the camera's eye and
## does not stop — a pool that feeds a stream downhill, kept by the blessing
## for good (the only blessing that reshapes the world), and water to drink.
const SPRING := &"spring"
## A forest: every felled tree and sapling within reach grows up, and
## saplings sprout on the open grass there. For good.
const FOREST := &"forest"
## In the order of the buttons.
const KINDS: Array[StringName] = [LIGHTS, BOUNTY, SOIL, WATERS, HEALING, RAIN, HERDS, SPRING, FOREST]

## How long each goes on (game minutes): the act itself, watched — what it
## leaves behind (silt, a run, a season's bounty, a day's rain, a spring)
## lasts by its own rules.
const LASTS := {LIGHTS: 70, BOUNTY: 60, SOIL: 60, WATERS: 60, HEALING: 60, RAIN: 60, HERDS: 60, SPRING: 60, FOREST: 60}
## How long of each is there to be watched (game minutes from its start):
## the world goes at its usual speed meanwhile, as for a disaster.
const WATCH := {LIGHTS: 70, BOUNTY: 60, SOIL: 60, WATERS: 60, HEALING: 60, RAIN: 60, HERDS: 60, SPRING: 60, FOREST: 60}
## How long the rain of the drought broken goes on.
const RAIN_MINUTES := 1440
## How long the world rests after one before the Presence's next act — the
## same as after a disaster, and the same rest.
const REST_MINUTES := DisasterSystem.REST_MINUTES
## What each is written down as (data/events/<id>.tres).
const EVENTS := {LIGHTS: &"lights_in_sky", BOUNTY: &"bounty_of_bushes", SOIL: &"rich_soil", WATERS: &"teeming_waters",
	HEALING: &"healing", RAIN: &"drought_broken", HERDS: &"herds_returned", SPRING: &"spring_rose", FOREST: &"forest_grew"}
## The herds that return.
const HERD_SPECIES := &"deer"
## A spring: what rises an hour (depth) until the pool stands this deep; how
## many springs the world may hold.
const SPRING_FLOW := 0.08
const SPRING_DEPTH := 0.6
const SPRINGS_MOST := 3
## A forest: how many saplings are planted on the open grass within reach.
const FOREST_SAPLINGS := 10
## How far a blessing of the land or the water reaches (tiles) from where
## the camera looks — a little more than a quake.
const REACH := 10.0

## What is going on now (&"": nothing), where, since and until when.
var kind: StringName = &""
var at := Vector2.ZERO
var began := 0
var until := 0

var _s: WorldSession
var _rng := RandomNumberGenerator.new()
## The event it was written down as.
var _event_id := 0
## Who the last healing mended (person ids; for what tells of it).
var healed: Array[int] = []
## The springs the Presence opened (tiles), for good: each flows every hour.
var springs: Array[Vector2i] = []
var _flowed_hour := -1


func bind(session: WorldSession) -> void:
	_s = session


func is_active() -> bool:
	return kind != &""


## Can a blessing be given now (nothing going on — of either hand — and the
## world rested)?
func can_start(now: int) -> bool:
	if kind != &"":
		return false
	if _s != null and _s.disasters != null:
		return _s.disasters.can_start(now)
	return true


## Game minutes until the Presence's next act (0: now).
func rest_left(now: int) -> int:
	if kind != &"":
		return maxi(until - now, 0) + REST_MINUTES
	if _s != null and _s.disasters != null:
		return _s.disasters.rest_left(now)
	return 0


## Gives `which` around `where` (world X/Z). False if it cannot be now (see
## can_start) or there is no such blessing.
func start(which: StringName, where: Vector2, now: int) -> bool:
	if not KINDS.has(which) or not can_start(now) or _s == null:
		return false
	kind = which
	at = _inside(where)
	began = now
	until = now + int(LASTS[which])
	_rng.seed = hash([_s.world_seed, now, String(which)])
	_event_id = 0
	if EVENTS.has(which) and _s.events != null:
		var event := _s.events.record(EVENTS[which], {"position": at})
		_event_id = event.id if event != null else 0
	var day := Config.time.day_index(now)
	healed = []
	match which:
		BOUNTY:
			_fill_bushes()
			if _s.vegetation != null:
				_s.vegetation.bless_bushes(at, REACH, day + Config.time.days_per_season)
		SOIL:
			if _s.soil != null:
				_s.soil.enrich(_land_within(REACH))
		WATERS:
			if _s.fauna != null and _s.fauna.waters != null:
				_s.fauna.waters.fill_near(WorldCoords.world2d_to_tile(at), REACH, day)
		HEALING:
			healed = _heal_near(now)
		RAIN:
			if _s.weather != null:
				_s.weather.hold(WeatherSystem.RAIN, now + RAIN_MINUTES)
				_s.weather.break_drought(now)
			if _s.hydrology != null:
				# (Back to where it was made, if it stands below it; never over its banks.)
				if _s.hydrology.level < 0.0:
					_s.hydrology.add(-_s.hydrology.level)
				_s.hydrology.settle(now)
		HERDS:
			if _s.fauna != null:
				_s.fauna.bring_herd(HERD_SPECIES, at, now, REACH)
		SPRING:
			_open_spring(now)
		FOREST:
			_grow_forest(now)
	Log.info(Log.Category.WORLD, "A blessing is given", {"kind": which, "at": at, "until": until})
	started.emit(which, at)
	return true


## Brings it up to the clock: the springs flow (every hour, for good); when
## the act's time is up it is over, and the world rests — the one rest,
## kept by the disasters.
func advance_to(now: int) -> void:
	if _s == null:
		return
	@warning_ignore("integer_division")
	var hour := now / 60
	if hour != _flowed_hour and not springs.is_empty():
		_flowed_hour = hour
		_flow()
	if kind == &"":
		return
	if now >= until:
		var was := kind
		kind = &""
		if _s.disasters != null:
			_s.disasters.rest_until = maxi(_s.disasters.rest_until, until + REST_MINUTES)
		Log.info(Log.Category.WORLD, "The blessing is over", {"kind": was})
		ended.emit(was)


## Is one going on that is to be watched now (see WATCH)?
func watching(now: int) -> bool:
	return kind != &"" and now < began + int(WATCH[kind])


## How much the lights fill the sky now, 0 … 1: they come, stay, and go.
func lights_amount(now: int) -> float:
	if kind != LIGHTS:
		return 0.0
	var share := clampf(float(now - began) / maxf(float(until - began), 1.0), 0.0, 1.0)
	return smoothstep(0.0, 0.25, share) * (1.0 - smoothstep(0.75, 1.0, share))


# --- what they do -------------------------------------------------------------------------------

## Every berry bush within reach, filled as it was made.
func _fill_bushes() -> void:
	if _s.nodes == null or _s.props == null:
		return
	for prop in _s.props.of_kind(PropData.Kind.BUSH):
		if prop.kind == PropData.Kind.BUSH and prop.position2d().distance_to(at) <= REACH:
			_s.nodes.fill(prop)


## Everyone within reach who is hurt or ill is mended: injuries give back
## the health they took and are gone; an illness has passed, and the health
## it took comes back over the day as it does after any illness; the weak
## with hunger stand up (still hungry); the cold-sick are warmed through.
## Nobody made younger, nobody brought back. Returns who was mended.
func _heal_near(now: int) -> Array[int]:
	var mended: Array[int] = []
	if _s.people == null:
		return mended
	var ctx: AiContext = _s.behavior.ctx if _s.behavior != null else null
	for person in _s.people.all_people():
		if person.world2d().distance_to(at) > REACH:
			continue
		var was_mended := false
		for injury: Variant in person.injuries:
			if typeof(injury) == TYPE_DICTIONARY:
				person.health = minf(person.health + float((injury as Dictionary).get("took", 0.0)), 1.0)
				was_mended = true
		person.injuries.clear()
		var illness := Health.illness_of(person)
		if not illness.is_empty() and not bool(illness.get("fed", false)):
			illness["fed"] = true
			if ctx != null:
				ctx.ailments.append([person.id, Health.ILLNESS, false])
			was_mended = true
		var hunger := Hardship.condition_of(person, Hardship.HUNGER)
		if not hunger.is_empty() and bool(hunger.get("sick", false)) and not bool(hunger.get("fed", false)):
			hunger["sick"] = false
			hunger["since"] = now
			if ctx != null:
				ctx.ailments.append([person.id, Hardship.HUNGER, false])
			was_mended = true
		var cold := Hardship.condition_of(person, Exposure.COLD)
		if not cold.is_empty():
			if bool(cold.get("sick", false)) and not bool(cold.get("fed", false)):
				person.health = maxf(person.health, float(cold.get("well", person.health)))
				if ctx != null:
					ctx.ailments.append([person.id, Exposure.COLD, false])
				was_mended = true
			person.conditions.erase(cold)
		if was_mended:
			mended.append(person.id)
	return mended


## A spring on the tile under the camera's eye (dry land in the box; at most
## SPRINGS_MOST in the world): it rises now, and every hour after.
func _open_spring(now: int) -> void:
	var tile := WorldCoords.world2d_to_tile(at)
	if _s.world == null or not _s.world.is_in_bounds(tile) or springs.has(tile) or springs.size() >= SPRINGS_MOST:
		return
	if _s.world.get_water(tile) > 0.0:
		return # (water already: nothing to open)
	springs.append(tile)
	@warning_ignore("integer_division")
	_flowed_hour = now / 60
	_flow()


## Every spring gives its hour's water, until its pool stands deep enough;
## what overflows runs downhill as water does (WaterSim).
func _flow() -> void:
	if _s.water == null or _s.world == null:
		return
	for tile in springs:
		if _s.world.is_in_bounds(tile) and _s.world.get_water(tile) < SPRING_DEPTH:
			_s.water.add_water(tile, SPRING_FLOW)


## Every felled tree and sapling within reach grows up, and saplings are
## planted on the open grass there (VegetationSystem.plant_near).
func _grow_forest(now: int) -> void:
	if _s.nodes != null and _s.props != null:
		for prop in _s.props.of_kind(PropData.Kind.TREE):
			if prop.kind == PropData.Kind.TREE and prop.position2d().distance_to(at) <= REACH:
				_s.nodes.grow_tree(prop)
	if _s.vegetation != null:
		var middle := WorldCoords.world2d_to_tile(at)
		for n in FOREST_SAPLINGS:
			_s.vegetation.plant_near(middle, 1.5, REACH, now)


## The land (not water) within `reach` of where it was given.
func _land_within(reach: float) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var middle := WorldCoords.world2d_to_tile(at)
	var r := ceili(reach)
	for dy in range(-r, r + 1):
		for dx in range(-r, r + 1):
			var tile := middle + Vector2i(dx, dy)
			if Vector2(dx, dy).length() > reach or not _s.world.is_in_bounds(tile) or _s.world.get_water(tile) > 0.0:
				continue
			out.append(tile)
	return out


## Within the box.
func _inside(where: Vector2) -> Vector2:
	if _s == null or _s.world == null:
		return where
	var inner := Rect2(_s.world.bounds).grow(-1.0)
	return Vector2(clampf(where.x, inner.position.x, inner.end.x), clampf(where.y, inner.position.y, inner.end.y))


# --- saved with the world ----------------------------------------------------------------------

## Only while one goes on, or while the world has springs: a world without
## saves no more.
func to_dict() -> Dictionary:
	var out := {}
	if kind != &"":
		out = {"kind": String(kind), "at": [at.x, at.y], "began": began, "until": until, "event": _event_id}
	if not springs.is_empty():
		var tiles: Array = []
		for tile in springs:
			tiles.append([tile.x, tile.y])
		out["springs"] = tiles
	return out


func from_dict(data: Dictionary) -> void:
	springs.clear()
	_flowed_hour = -1
	if typeof(data.get("springs")) == TYPE_ARRAY:
		for pair: Variant in data["springs"]:
			if typeof(pair) == TYPE_ARRAY and (pair as Array).size() == 2:
				springs.append(Vector2i(int(pair[0]), int(pair[1])))
	kind = StringName(str(data.get("kind", "")))
	if not KINDS.has(kind):
		kind = &""
	var where: Variant = data.get("at", [0.0, 0.0])
	at = Vector2(float(where[0]), float(where[1])) if typeof(where) == TYPE_ARRAY and (where as Array).size() == 2 else Vector2.ZERO
	began = int(data.get("began", 0))
	until = int(data.get("until", 0))
	_event_id = int(data.get("event", 0))
