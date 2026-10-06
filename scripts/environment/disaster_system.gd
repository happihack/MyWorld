class_name DisasterSystem
extends RefCounted
## The disasters the player can bring down (the owner's design, 2026-10-05;
## bible §10.5, §23.4): an earthquake, an eclipse, a storm, a flood, a
## whirlwind, the waters turned to blood, a storm of falling stars. Chosen
## from the Disaster button, each after a warning; one at a time, and then
## the world rests a day before the next.
##
## Some do harm: the quake, the whirlwind and the falling stars damage what
## is built, bring down trees, and can hurt those caught right in them —
## rarely, kill one. The storm and the flood are the weather's and the
## river's own (as they would be anyway). The eclipse and the blood harm
## nobody: they are only seen — and made of what people make of them. While
## the waters are blood nobody drinks (thirst does not kill).
##
## Struck where the camera looks (`at`); the eclipse and the blood are
## everywhere. Goes by the clock (advance_to), so it goes on while the
## player is away, and is saved with the world.

## A disaster has begun at `at` (world X/Z).
signal started(kind: StringName, at: Vector2)
## It is over.
signal ended(kind: StringName)
## Something to be seen where it happens: a star come down, the ground
## jolting, the whirlwind passing over a place. `size` 0 … 1.
signal struck(kind: StringName, at: Vector2, size: float)

const EARTHQUAKE := &"earthquake"
const ECLIPSE := &"eclipse"
const STORM := &"storm"
const FLOOD := &"flood"
const TORNADO := &"tornado"
const BLOOD := &"blood"
const METEORS := &"meteors"
## In the order of the buttons.
const KINDS: Array[StringName] = [EARTHQUAKE, ECLIPSE, STORM, FLOOD, TORNADO, BLOOD, METEORS]

## How long each goes on (game minutes; a game hour is half a minute at
## the usual speed).
const LASTS := {EARTHQUAKE: 6, ECLIPSE: 70, STORM: 360, FLOOD: 180, TORNADO: 40, BLOOD: 1440, METEORS: 24}
## How long the world rests after one before the next can be brought down.
const REST_MINUTES := 1440
## What each is written down as (data/events/<id>.tres; the storm and the
## flood write themselves, as they always do).
const EVENTS := {EARTHQUAKE: &"earthquake", ECLIPSE: &"eclipse", TORNADO: &"tornado", BLOOD: &"blood_water",
	METEORS: &"meteor_storm"}

## The earthquake: how far it reaches (tiles), the damage it does to what is
## built at its heart and at its edge, the chance a tree there falls, and
## how near the heart people are in danger.
const QUAKE_REACH := 9.0
const QUAKE_DAMAGE_HEART := 460
const QUAKE_DAMAGE_EDGE := 120
const QUAKE_TREE_FALLS := 0.22
const QUAKE_DANGER := 4.5
## The whirlwind: how far it travels (tiles, through `at`), how wide it is,
## what it does to what it passes over.
const TORNADO_TRAVEL := 18.0
const TORNADO_WIDTH := 1.4
const TORNADO_DAMAGE := 360
const TORNADO_TREE_FALLS := 0.7
## The falling stars: how many, how far from `at` they come down, how much
## around each burns, what each does to what stands there.
const METEOR_COUNT := 10
const METEOR_REACH := 10.0
const METEOR_BURN := 0
const METEOR_DAMAGE := 650
## Caught right in one: the chance of being hurt, and (rarely) of dying.
const HURT := {EARTHQUAKE: 0.35, TORNADO: 0.6, METEORS: 0.7}
const KILLED := {EARTHQUAKE: 0.03, TORNADO: 0.06, METEORS: 0.1}

## What is going on now (&"": nothing), where, since and until when.
var kind: StringName = &""
var at := Vector2.ZERO
var began := 0
var until := 0
## No other before this tick.
var rest_until := 0

var _s: WorldSession
var _rng := RandomNumberGenerator.new()
## The whirlwind's way (unit) and the last minute of it that was done.
var _heading := Vector2.RIGHT
var _done_minute := 0
## The falling stars still to come: [tick, x, y], the soonest first.
var _stars: Array = []
## The event it was written down as (causes for what it does).
var _event_id := 0


func bind(session: WorldSession) -> void:
	_s = session


func is_active() -> bool:
	return kind != &""


## Can `which` be brought down now (nothing going on, the world rested)?
func can_start(now: int) -> bool:
	return kind == &"" and now >= rest_until


## Game minutes until the next can be brought down (0: now).
func rest_left(now: int) -> int:
	if kind != &"":
		return maxi(until - now, 0) + REST_MINUTES
	return maxi(rest_until - now, 0)


## Brings `which` down around `where` (world X/Z). False if it cannot be
## now (see can_start) or there is no such disaster.
func start(which: StringName, where: Vector2, now: int) -> bool:
	if not KINDS.has(which) or not can_start(now) or _s == null:
		return false
	kind = which
	at = _inside(where)
	began = now
	until = now + int(LASTS[which])
	_rng.seed = hash([_s.world_seed, now, String(which)])
	_done_minute = now
	_stars.clear()
	_event_id = 0
	if EVENTS.has(which) and _s.events != null:
		var event := _s.events.record(EVENTS[which], {"position": at})
		_event_id = event.id if event != null else 0
	match which:
		EARTHQUAKE:
			_quake(now)
		STORM:
			_s.weather.hold(WeatherSystem.STORM, until)
		FLOOD:
			# The rain comes down in sheets, and the river over its banks.
			_s.weather.hold(WeatherSystem.HEAVY_RAIN, until)
			_s.hydrology.add(Config.hydrology.highest * 2.0)
			_s.hydrology.settle(now)
		TORNADO:
			_heading = Vector2.from_angle(_rng.randf() * TAU)
		METEORS:
			for n in METEOR_COUNT:
				var where_it_falls := at + Vector2.from_angle(_rng.randf() * TAU) * sqrt(_rng.randf()) * METEOR_REACH
				_stars.append([now + 1 + _rng.randi_range(0, int(LASTS[METEORS]) - 2), _inside(where_it_falls).x, _inside(where_it_falls).y])
			_stars.sort_custom(func(a: Array, b: Array) -> bool: return int(a[0]) < int(b[0]))
	Log.info(Log.Category.WORLD, "A disaster is brought down", {"kind": which, "at": at, "until": until})
	started.emit(which, at)
	return true


## Brings it up to the clock: the whirlwind moves on, the stars fall, and
## when its time is up it is over.
func advance_to(now: int) -> void:
	if kind == &"" or _s == null:
		return
	match kind:
		TORNADO:
			while _done_minute < mini(now, until):
				_done_minute += 1
				_whirl(tornado_at(_done_minute), _done_minute)
		METEORS:
			while not _stars.is_empty() and int(_stars[0][0]) <= now:
				var star: Array = _stars.pop_front()
				_star(Vector2(float(star[1]), float(star[2])), int(star[0]))
	if now >= until:
		var was := kind
		kind = &""
		rest_until = until + REST_MINUTES
		_stars.clear()
		Log.info(Log.Category.WORLD, "The disaster is over", {"kind": was})
		ended.emit(was)


## Where the whirlwind is at `tick` (world X/Z).
func tornado_at(tick: int) -> Vector2:
	var share := clampf(float(tick - began) / maxf(float(until - began), 1.0), 0.0, 1.0)
	return _inside(at + _heading * TORNADO_TRAVEL * (share - 0.5))


## How dark the eclipse makes the day now, 0 … 1: the moon slides over the
## sun, stays, slides away.
func eclipse_amount(now: int) -> float:
	if kind != ECLIPSE:
		return 0.0
	var share := clampf(float(now - began) / maxf(float(until - began), 1.0), 0.0, 1.0)
	return smoothstep(0.0, 0.3, share) * (1.0 - smoothstep(0.7, 1.0, share))


## How much the waters are blood now, 0 … 1 (it comes and goes over an hour).
func blood_amount(now: int) -> float:
	if kind != BLOOD:
		return 0.0
	return clampf(float(now - began) / 60.0, 0.0, 1.0) * clampf(float(until - now) / 60.0, 0.0, 1.0)


## Is there no water to drink (it is blood)?
func water_is_blood() -> bool:
	return kind == BLOOD


## The falling stars still to come (for what shows them: [tick, x, y]).
func stars_to_come() -> Array:
	return _stars.duplicate(true)


# --- what they do -------------------------------------------------------------------------------

func _quake(now: int) -> void:
	struck.emit(EARTHQUAKE, at, 1.0)
	for building in _buildings_near(at, QUAKE_REACH):
		var near := 1.0 - building.position2d().distance_to(at) / QUAKE_REACH
		_s.construction.damage(building.id, roundi(lerpf(QUAKE_DAMAGE_EDGE, QUAKE_DAMAGE_HEART, near)), EARTHQUAKE, now)
	for tree in _trees_near(at, QUAKE_REACH):
		var near := 1.0 - tree.position2d().distance_to(at) / QUAKE_REACH
		if _rng.randf() < QUAKE_TREE_FALLS * near * 1.6:
			_s.interactions.fell_tree(tree.id, _rng.randf() * TAU)
	_shake_loose(at, QUAKE_REACH, 2.2)
	_endanger(at, QUAKE_DANGER, EARTHQUAKE, now)


func _whirl(where: Vector2, now: int) -> void:
	struck.emit(TORNADO, where, 0.6)
	for building in _buildings_near(where, TORNADO_WIDTH):
		_s.construction.damage(building.id, TORNADO_DAMAGE / 3, TORNADO, now)
	for tree in _trees_near(where, TORNADO_WIDTH):
		if _rng.randf() < TORNADO_TREE_FALLS:
			_s.interactions.fell_tree(tree.id, _heading.angle() + _rng.randf_range(-0.6, 0.6))
	_ruin_crops(where, TORNADO_WIDTH, now)
	_shake_loose(where, TORNADO_WIDTH + 0.8, 3.5)
	# (Each place is passed over for a minute or so: a share of the danger each minute.)
	_endanger(where, TORNADO_WIDTH * 0.8, TORNADO, now, 0.35)


func _star(where: Vector2, now: int) -> void:
	struck.emit(METEORS, where, 1.0)
	for building in _buildings_near(where, 1.2):
		_s.construction.damage(building.id, METEOR_DAMAGE, METEORS, now)
	var tile := WorldCoords.world2d_to_tile(where)
	if _s.vegetation != null:
		for y in range(-METEOR_BURN, METEOR_BURN + 1):
			for x in range(-METEOR_BURN, METEOR_BURN + 1):
				var burnt := tile + Vector2i(x, y)
				if _s.world.is_in_bounds(burnt) and _s.world.get_water(burnt) <= 0.0:
					_s.vegetation.burn(burnt, true)
	_ruin_crops(where, 1.2, now)
	_shake_loose(where, 2.5, 2.8)
	# What came down lies there: a stone from the sky.
	_s.interactions.drop_stone(where)
	_endanger(where, 1.3, METEORS, now)


## Those within `reach` of `where` may be hurt (and rarely die); `share` of
## the chance (the whirlwind: each minute).
func _endanger(where: Vector2, reach: float, which: StringName, now: int, share: float = 1.0) -> void:
	if _s.people == null:
		return
	for person in _s.people.all_people():
		if person.world2d().distance_to(where) > reach:
			continue
		if _rng.randf() < float(KILLED[which]) * share:
			_s.lifecycle.die(person, Lifecycle.CAUSE_DISASTER, now, [_event_id] if _event_id != 0 else [])
			continue
		if _rng.randf() < float(HURT[which]) * share:
			Health.injure(person, Health.FALL, _rng.randf_range(0.3, 0.75), now)
			_s.lifecycle.remember_life(person, &"life_hurt", now, 0.5)
			_s.lifecycle.injured.emit(person.id, Health.FALL)


## What lies about is thrown around.
func _shake_loose(where: Vector2, reach: float, speed: float) -> void:
	if _s.loose == null or _s.loose.spatial_index == null:
		return
	for id in _s.loose.spatial_index.query_radius(where, reach, SpatialIndex.KIND_LOOSE_OBJECT):
		var object := _s.loose.get_object(id)
		if object == null or object.state == LooseObject.State.HELD or object.kind == LooseObject.Kind.PILE:
			continue
		var away := Vector2.from_angle(_rng.randf() * TAU)
		_s.loose_system.push(id, Vector3(away.x, _rng.randf_range(0.6, 1.4), away.y) * speed)


func _ruin_crops(where: Vector2, reach: float, now: int) -> void:
	if _s.farming == null:
		return
	for crop in _s.farming.crops():
		if crop.position2d().distance_to(where) <= reach:
			_s.farming.ruin(crop, now)


func _buildings_near(where: Vector2, reach: float) -> Array[PropData]:
	var out: Array[PropData] = []
	for prop in _s.props.all_props():
		if prop.is_building() and prop.kind != PropData.Kind.BRIDGE and prop.position2d().distance_to(where) <= reach:
			out.append(prop)
	return out


func _trees_near(where: Vector2, reach: float) -> Array[PropData]:
	var out: Array[PropData] = []
	for prop in _s.props.all_props():
		if prop.kind == PropData.Kind.TREE and not prop.felled and prop.position2d().distance_to(where) <= reach:
			out.append(prop)
	return out


## Within the box.
func _inside(where: Vector2) -> Vector2:
	if _s == null or _s.world == null:
		return where
	var inner := Rect2(_s.world.bounds).grow(-1.0)
	return Vector2(clampf(where.x, inner.position.x, inner.end.x), clampf(where.y, inner.position.y, inner.end.y))


# --- saved with the world ----------------------------------------------------------------------

func to_dict() -> Dictionary:
	return {"kind": String(kind), "at": [at.x, at.y], "began": began, "until": until, "rest_until": rest_until,
		"heading": [_heading.x, _heading.y], "done_minute": _done_minute, "stars": _stars.duplicate(true),
		"event": _event_id}


func from_dict(data: Dictionary) -> void:
	kind = StringName(str(data.get("kind", "")))
	if not KINDS.has(kind):
		kind = &""
	var where: Variant = data.get("at", [0.0, 0.0])
	at = Vector2(float(where[0]), float(where[1])) if typeof(where) == TYPE_ARRAY and (where as Array).size() == 2 else Vector2.ZERO
	began = int(data.get("began", 0))
	until = int(data.get("until", 0))
	rest_until = int(data.get("rest_until", 0))
	var way: Variant = data.get("heading", [1.0, 0.0])
	_heading = Vector2(float(way[0]), float(way[1])).normalized() if typeof(way) == TYPE_ARRAY and (way as Array).size() == 2 else Vector2.RIGHT
	if not _heading.is_finite() or _heading.length() < 0.5:
		_heading = Vector2.RIGHT
	_done_minute = int(data.get("done_minute", began))
	_stars.clear()
	var stars: Variant = data.get("stars", [])
	if typeof(stars) == TYPE_ARRAY:
		for star: Variant in stars:
			if typeof(star) == TYPE_ARRAY and (star as Array).size() == 3:
				_stars.append([int(star[0]), float(star[1]), float(star[2])])
	_event_id = int(data.get("event", 0))
	_rng.seed = hash([_s.world_seed if _s != null else 0, began, String(kind)])
