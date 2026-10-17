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
## In the order of the buttons.
const KINDS: Array[StringName] = [LIGHTS, BOUNTY, SOIL, WATERS, HEALING]

## How long each goes on (game minutes): the act itself, watched — what it
## leaves behind (silt, a run, a season's bounty) lasts by its own rules.
const LASTS := {LIGHTS: 70, BOUNTY: 60, SOIL: 60, WATERS: 60, HEALING: 60}
## How long of each is there to be watched (game minutes from its start):
## the world goes at its usual speed meanwhile, as for a disaster.
const WATCH := {LIGHTS: 70, BOUNTY: 60, SOIL: 60, WATERS: 60, HEALING: 60}
## How long the world rests after one before the Presence's next act — the
## same as after a disaster, and the same rest.
const REST_MINUTES := DisasterSystem.REST_MINUTES
## What each is written down as (data/events/<id>.tres).
const EVENTS := {LIGHTS: &"lights_in_sky", BOUNTY: &"bounty_of_bushes", SOIL: &"rich_soil", WATERS: &"teeming_waters",
	HEALING: &"healing"}
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
	Log.info(Log.Category.WORLD, "A blessing is given", {"kind": which, "at": at, "until": until})
	started.emit(which, at)
	return true


## Brings it up to the clock: when its time is up it is over, and the world
## rests — the one rest, kept by the disasters.
func advance_to(now: int) -> void:
	if kind == &"" or _s == null:
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

## Only while one goes on: a world without a blessing saves no more.
func to_dict() -> Dictionary:
	if kind == &"":
		return {}
	return {"kind": String(kind), "at": [at.x, at.y], "began": began, "until": until, "event": _event_id}


func from_dict(data: Dictionary) -> void:
	kind = StringName(str(data.get("kind", "")))
	if not KINDS.has(kind):
		kind = &""
	var where: Variant = data.get("at", [0.0, 0.0])
	at = Vector2(float(where[0]), float(where[1])) if typeof(where) == TYPE_ARRAY and (where as Array).size() == 2 else Vector2.ZERO
	began = int(data.get("began", 0))
	until = int(data.get("until", 0))
	_event_id = int(data.get("event", 0))
