class_name InteractionManager
extends Node
## The one place where the player changes the world (bible §10, §14.6, §23).
## Lives in the WorldSession: it knows the world, not the screen.
##
## Everything the player does is an Intervention and goes through
## apply_intervention(), which
##   1. validates it (is there such a target? is it allowed?),
##   2. has the owning system carry it out (props, loose objects, water),
##   3. announces what the world did in answer (`responded`: effects, sound,
##      haptics; later also the stimulus the inhabitants perceive),
##   4. writes it into the player's history and statistics.
## No tool changes world state by itself. tap(), uproot(), grab(), release(),
## scoop() and pour() are conveniences that build the Intervention.
##
## Looking is not an intervention: long_press(), describe() and inspect()
## change nothing and are not recorded.

signal responded(response: InteractionResponse)
## An intervention was carried out (and, unless it is part of a longer act,
## recorded in the history).
signal intervention_applied(intervention: Intervention)
## What an intervention gives off for the inhabitants to notice (bible §14.1).
signal stimulus_emitted(stimulus: Stimulus)

## Things the player can choose to do with a target (context menu).
const ACTION_INSPECT := &"inspect"
const ACTION_TOUCH := &"touch"
const ACTION_FOCUS := &"focus"
const ACTION_REMOVE := &"remove"
## A grave: who lies there, and their family (M10.3).
const ACTION_READ := &"read"
const ACTION_VIEW_FAMILY := &"view_family"

## The first shake of a tree only rustles it; each further shake drops one of
## what it bears with this chance.
const SHAKE_DROP_CHANCE := 0.6
## A touch on water pushes floating things within this many tiles, the
## nearest by this speed (tiles/s).
const RIPPLE_REACH := 1.6
const RIPPLE_PUSH := 1.6
## An object counts as moved if it is put down at least this far (tiles) from
## where it was picked up.
const MOVED_MIN_DISTANCE := 0.2
## Moving something lighter than this (kg) is a Gentle intervention; heavier
## things (rocks, boulders, logs) are Moderate (bible §23.4).
const SMALL_OBJECT_KG := 5.0
## An object the player put down within this many tiles of the settlement is
## marked for its inhabitants to discover (M4+).
const DISCOVER_RADIUS := 14.0
## Random stream for what touches bring about (which shake drops a fruit).
const RNG_STREAM := &"interaction"

const _PROP_EFFECTS := {
	PropData.Kind.TREE: InteractionResponse.TREE_SHAKE,
	PropData.Kind.BUSH: InteractionResponse.BUSH_RUSTLE,
	PropData.Kind.ROCK: InteractionResponse.ROCK_WOBBLE,
	PropData.Kind.HUT: InteractionResponse.BUILDING_KNOCK,
	PropData.Kind.CAMPFIRE: InteractionResponse.FIRE_FLARE,
	PropData.Kind.RUIN: InteractionResponse.RUIN_HUM,
	PropData.Kind.CROP: InteractionResponse.BUSH_RUSTLE,
	PropData.Kind.GRAVE: InteractionResponse.DUST,
	PropData.Kind.SITE: InteractionResponse.BUILDING_KNOCK,
	PropData.Kind.STOREHOUSE: InteractionResponse.BUILDING_KNOCK,
	PropData.Kind.WELL: InteractionResponse.ROCK_WOBBLE,
	PropData.Kind.WORKSHOP: InteractionResponse.BUILDING_KNOCK,
	PropData.Kind.BRIDGE: InteractionResponse.BUILDING_KNOCK,
}

## Touches and long presses since this world was opened (debug overlay).
var interaction_count := 0
## What the player has done to this world. The session supplies its saved
## history; on its own the manager keeps a private one.
var history := PlayerHistory.new()

var _world: WorldData
var _props: PropRegistry
var _loose: LooseObjectRegistry
var _motion: LooseObjectSystem
var _ids: IdAllocator
var _rng: RngStreams
var _water: WaterSim
var _clock: GameClock
var _settlement := Vector2.INF
## What is being built (M12.1), for the inspect card of a site.
var construction: ConstructionSystem
## Footfall, for the inspect card of the ground (M12.2).
var traffic: Traffic
## The settlements, for the card of a fire (M12.3).
var settlements: Settlements
## Who leads them (M12.5).
var governance: Governance
var _people: PersonRegistry
var _fauna: AnimalSystem
var _weather: WeatherSystem
var _hydrology: Hydrology
## The height the ground was made with (Callable(tile) -> int); not set: as it is now.
var _made_height := Callable()
var _rain_carry := 0.0 # moisture not yet given to the soil (less than one)
var _rain_clear := true # the sky was clear when the rain going on began
## How tall a person is taken to be where the manager has no view to ask.
const PERSON_HEIGHT := 0.5
var _shakes: Dictionary = {} # tree id -> shakes since the world was opened
var _in_hand: Dictionary = {} # object id -> where it was picked up (Vector2)
var _awaiting_rest: Dictionary = {} # object id -> true: moved by the player, still on its way


## `motion`, `ids` and `rng` let touches bring new things into the world
## (fruit from a shaken tree); without them touches only produce feedback.
func bind(world: WorldData, props: PropRegistry, loose: LooseObjectRegistry = null,
		motion: LooseObjectSystem = null, ids: IdAllocator = null, rng: RngStreams = null) -> void:
	if _motion != null and _motion.settled.is_connected(_on_object_settled):
		_motion.settled.disconnect(_on_object_settled)
	_world = world
	_props = props
	_loose = loose
	_motion = motion
	_ids = ids
	_rng = rng
	_water = null
	_clock = null
	_settlement = Vector2.INF
	_shakes.clear()
	_in_hand.clear()
	_awaiting_rest.clear()
	interaction_count = 0
	history = PlayerHistory.new()
	if _motion != null:
		_motion.settled.connect(_on_object_settled)


## The rest of what a session offers: its water, its clock (for the tick of
## each intervention), its saved history and where its settlement is.
func bind_session(water: WaterSim, clock: GameClock, saved_history: PlayerHistory, settlement: Vector2 = Vector2.INF) -> void:
	_water = water
	_clock = clock
	_settlement = settlement
	if saved_history != null:
		history = saved_history


## The people of the world: they can be touched too.
func bind_people(people: PersonRegistry) -> void:
	_people = people


## The animals (so that they can be touched and looked at).
func bind_animals(fauna: AnimalSystem) -> void:
	_fauna = fauna


## The weather and the river (for the powers over them), and the height the
## ground was made with (a channel goes only so far below it).
func bind_environment(weather: WeatherSystem, hydrology: Hydrology, made_height: Callable = Callable()) -> void:
	_weather = weather
	_hydrology = hydrology
	_made_height = made_height


# --- the choke point ----------------------------------------------------------------------

## Carries out an intervention. Returns it with `applied` (and `rejected`,
## `severity`, `subject`, `response`, `id`) filled in.
func apply_intervention(iv: Intervention) -> Intervention:
	if iv == null:
		return null
	iv.applied = false
	iv.rejected = &""
	iv.tick = _clock.tick if _clock != null else 0
	if _world == null:
		iv.rejected = &"no_world"
		return iv
	var done := false
	match iv.type:
		Intervention.TOUCH:
			done = _do_touch(iv)
		Intervention.UPROOT:
			done = _do_uproot(iv)
		Intervention.GRAB:
			done = _do_grab(iv)
		Intervention.MOVE_OBJECT:
			done = _do_move_object(iv)
		Intervention.SCOOP_WATER, Intervention.POUR_WATER:
			done = _do_water(iv)
		Intervention.MAKE_RAIN:
			done = _do_rain(iv)
		Intervention.MAKE_WIND:
			done = _do_gust(iv)
		Intervention.CARVE:
			done = _do_carve(iv)
		_:
			iv.rejected = &"unknown_type"
	if not done:
		if iv.rejected == &"":
			iv.rejected = &"invalid"
		return iv
	iv.applied = true
	if iv.recorded:
		history.record(iv)
		EventBus.intervention_applied.emit(iv.id)
		for achievement in history.take_unlocked():
			Log.info(Log.Category.WORLD, "Achievement unlocked", {"achievement": achievement, "tick": iv.tick})
			EventBus.achievement_unlocked.emit(achievement)
	intervention_applied.emit(iv)
	var stimulus := Stimulus.from_intervention(iv, Config.reactions)
	if stimulus != null:
		stimulus_emitted.emit(stimulus)
	return iv


## Is an intervention of this severity allowed? "Gentle hands" (a player
## setting, on by default) keeps Major ones from happening by accident.
static func severity_allowed(severity: Intervention.Severity, gentle_hands: bool) -> bool:
	return severity != Intervention.Severity.MAJOR or not gentle_hands


## Sets what the intervention is done to and how severe it is; refuses it if
## the player's settings do not allow that. Call before changing anything.
func _admit(iv: Intervention, subject: StringName, severity: Intervention.Severity) -> bool:
	iv.subject = subject
	iv.severity = severity
	if not severity_allowed(severity, bool(Settings.get_value(&"gameplay/gentle_hands"))):
		iv.rejected = &"gentle_hands"
		return false
	return true


# --- what the player can do -------------------------------------------------------------------

## A tap on `target`. Returns the response, or null if nothing was touched.
func tap(target: Picker.Result, tool: StringName = &"hand") -> InteractionResponse:
	return apply_intervention(Intervention.create(Intervention.TOUCH, tool, target)).response


## Uproots the tree at `target`: the tree is gone for good and its trunk is
## left lying as a log. Null if the target is not a tree.
func uproot(target: Picker.Result, tool: StringName = &"hand") -> InteractionResponse:
	var iv := apply_intervention(Intervention.create(Intervention.UPROOT, tool, target))
	return iv.response if iv.applied else null


## Takes a loose object in hand. False if there is no such object, or it is
## already held.
func grab(object_id: int, tool: StringName = &"hand") -> bool:
	var iv := Intervention.create(Intervention.GRAB, tool)
	iv.target_id = object_id
	return apply_intervention(iv).applied


## Moves the object in hand to `position`, `height_offset` above the ground.
## False if it is not in hand.
func carry(object_id: int, position: Vector2, height_offset: float) -> bool:
	if not _in_hand.has(object_id) or _loose == null:
		return false
	var object := _loose.get_object(object_id)
	if object == null or object.state != LooseObject.State.HELD:
		return false
	return _loose.move(object_id, position, height_offset)


## Lets go of the object in hand, with `velocity` if it is thrown. Returns the
## MOVE_OBJECT intervention if it ended up somewhere else than it was picked
## up, or null if it was only put back (which is no intervention).
func release(object_id: int, velocity: Vector3 = Vector3.ZERO, tool: StringName = &"hand") -> Intervention:
	if not _in_hand.has(object_id):
		return null
	var object := _loose.get_object(object_id) if _loose != null else null
	if object == null or object.position.distance_to(_in_hand[object_id]) < MOVED_MIN_DISTANCE:
		_in_hand.erase(object_id)
		if object != null and _motion != null:
			_motion.drop(object_id, velocity)
		return null
	var iv := Intervention.create(Intervention.MOVE_OBJECT, tool)
	iv.target_id = object_id
	iv.params["velocity"] = velocity
	return apply_intervention(iv)


## Is this object in the player's hand?
func is_in_hand(object_id: int) -> bool:
	return _in_hand.has(object_id)


## Takes up to `amount` of water from a tile into what the player carries
## (WaterSim.carried). Returns how much was taken.
func scoop(tile: Vector2i, amount: float, tool: StringName = &"water") -> float:
	var iv := Intervention.create(Intervention.SCOOP_WATER, tool)
	iv.tile = tile
	iv.magnitude = amount
	apply_intervention(iv)
	return iv.magnitude if iv.applied else 0.0


## Pours up to `amount` of the water the player carries onto a tile. Returns
## how much was poured.
func pour(tile: Vector2i, amount: float, tool: StringName = &"water") -> float:
	var iv := Intervention.create(Intervention.POUR_WATER, tool)
	iv.tile = tile
	iv.magnitude = amount
	apply_intervention(iv)
	return iv.magnitude if iv.applied else 0.0


## Rain on the land around `at` (world X/Z). It comes in phases: BEGIN when
## the cloud forms, MORE with `units` of rain each time some reaches the
## ground, END with all that fell (which is what the history keeps).
func rain(at: Vector2, units: float, phase: StringName = Intervention.PHASE_END, tool: StringName = &"rain") -> Intervention:
	var iv := Intervention.create(Intervention.MAKE_RAIN, tool)
	iv.tile = WorldCoords.world2d_to_tile(at)
	iv.position = Vector3(at.x, 0.0, at.y)
	iv.magnitude = units
	iv.params = {"phase": phase}
	return apply_intervention(iv)


## A gust from `from` towards `to` (world X/Z), `strength` 0 … 1.
func gust(from: Vector2, to: Vector2, strength: float, tool: StringName = &"wind") -> Intervention:
	var iv := Intervention.create(Intervention.MAKE_WIND, tool)
	iv.tile = WorldCoords.world2d_to_tile(from)
	iv.position = Vector3(from.x, 0.0, from.y)
	iv.magnitude = strength
	iv.params = {"from": from, "to": to}
	return apply_intervention(iv)


## Carves a tile of a channel (BEGIN for a stroke's first, MORE for the
## rest); END, with how many tiles were carved, ends the stroke.
func carve(tile: Vector2i, phase: StringName = Intervention.PHASE_BEGIN, tool: StringName = &"water", tiles: int = 1) -> Intervention:
	var iv := Intervention.create(Intervention.CARVE, tool)
	iv.tile = tile
	iv.magnitude = float(tiles)
	iv.params = {"phase": phase}
	return apply_intervention(iv)


## Can a channel be carved through a tile: open ground with nothing standing
## on it, not yet as deep as a channel goes?
func can_carve(tile: Vector2i) -> bool:
	if _world == null or not _world.is_in_bounds(tile) or _world.get_water(tile) > WaterMesher.MIN_DEPTH:
		return false
	var terrain := _world.get_terrain(tile)
	if terrain != ChunkData.Terrain.GRASS and terrain != ChunkData.Terrain.DIRT and terrain != ChunkData.Terrain.SAND \
			and terrain != ChunkData.Terrain.FARMLAND and terrain != ChunkData.Terrain.MUD and terrain != ChunkData.Terrain.ASH:
		return false
	if _props != null and _props.has_prop_at(tile):
		return false
	var height := _world.get_height(tile)
	var made: int = int(_made_height.call(tile)) if _made_height.is_valid() else height
	return height > 1 and height > made - Config.tools.carve_depth_levels


## Is the sky clear (rain out of it is uncanny)?
func sky_is_clear() -> bool:
	return _weather == null or _weather.cloud_cover() < Config.tools.clear_sky_below


# --- carrying out ---------------------------------------------------------------------------

func _do_touch(iv: Intervention) -> bool:
	var response := _respond(iv.target, InteractionResponse.Action.TAP, false)
	if response == null:
		iv.rejected = &"nothing_there"
		return false
	if not _admit(iv, subject_of(response), Intervention.Severity.GENTLE):
		return false
	if response.person_id != 0:
		var touched := _people.get_person(response.person_id)
		if touched != null:
			touched.set_flag(PersonData.FLAG_TOUCHED_BY_PLAYER, true)
	elif response.animal_id != 0:
		# A hand out of nowhere: it bolts.
		_fauna.startle_one(response.animal_id, Vector2(response.position.x, response.position.z), iv.tick)
	elif response.prop_kind == PropData.Kind.TREE:
		_shake_tree(response)
	elif response.effect == InteractionResponse.RIPPLE:
		_disturb_water(response)
	iv.response = response
	iv.position = response.position
	iv.tile = response.tile
	iv.target_id = response.entity_id
	_announce(response)
	return true


func _do_uproot(iv: Intervention) -> bool:
	var response := _respond(iv.target, InteractionResponse.Action.TAP, false)
	if response == null or response.prop_kind != PropData.Kind.TREE or _props == null:
		iv.rejected = &"not_a_tree"
		return false
	if not _admit(iv, &"tree", Intervention.Severity.MODERATE):
		return false
	var tree := _props.get_prop(response.entity_id)
	response.effect = InteractionResponse.TREE_UPROOT
	response.description = "TREE uprooted at %s" % tree.tile
	var size := tree.scale_percent
	# (A stump or a sapling has no trunk to leave lying.)
	var has_trunk := not tree.felled
	_props.remove(tree.id)
	if can_spawn() and has_trunk:
		var rng := _rng.stream(RNG_STREAM)
		var heading := rng.randf() * TAU
		var log := _spawn(LooseObject.Kind.LOG, Vector2(response.position.x, response.position.z), 0.35, size)
		log.yaw = heading
		_motion.drop(log.id, Vector3(cos(heading), 0.0, sin(heading)) * 0.9)
		response.dropped.append(log.id)
	iv.response = response
	iv.position = response.position
	iv.tile = response.tile
	iv.target_id = response.entity_id
	_announce(response)
	return true


func _do_grab(iv: Intervention) -> bool:
	iv.recorded = false # the move is history once the object is put down
	var object := _loose.get_object(iv.target_id) if _loose != null else null
	if object == null or _motion == null or _in_hand.has(object.id) or object.state == LooseObject.State.HELD:
		iv.rejected = &"cannot_grab"
		return false
	if not _admit(iv, loose_subject(object.kind), Intervention.Severity.GENTLE):
		return false
	_motion.hold(object.id)
	_in_hand[object.id] = object.position
	_awaiting_rest.erase(object.id)
	iv.position = object.world_position(_world)
	iv.tile = object.tile()
	return true


func _do_move_object(iv: Intervention) -> bool:
	var object := _loose.get_object(iv.target_id) if _loose != null else null
	if object == null or _motion == null or not _in_hand.has(object.id):
		iv.rejected = &"not_in_hand"
		return false
	var severity := Intervention.Severity.GENTLE if object.mass() < SMALL_OBJECT_KG else Intervention.Severity.MODERATE
	if not _admit(iv, loose_subject(object.kind), severity):
		return false
	var from: Vector2 = _in_hand[object.id]
	_in_hand.erase(object.id)
	var velocity: Vector3 = iv.params.get("velocity", Vector3.ZERO)
	iv.magnitude = object.position.distance_to(from)
	iv.position = object.world_position(_world)
	iv.tile = object.tile()
	iv.params = {"from": from, "to": object.position, "thrown": velocity.length() > 0.0}
	object.moved_count += 1
	object.moved_tick = iv.tick
	object.placed_by_player = true
	object.discovered_by = PackedInt64Array() # somewhere new: to be come upon anew
	_loose.touch(object.id)
	_awaiting_rest[object.id] = true # where it comes to rest decides whether it can be discovered
	_motion.drop(object.id, velocity)
	return true


func _do_water(iv: Intervention) -> bool:
	if _water == null or not _world.is_in_bounds(iv.tile) or iv.magnitude <= 0.0 or not is_finite(iv.magnitude):
		iv.rejected = &"no_water"
		return false
	if not _admit(iv, &"water", Intervention.Severity.MODERATE):
		return false
	# Scooped water is carried, and only carried water can be poured: none is
	# made and none is lost.
	var moved := 0.0
	if iv.type == Intervention.SCOOP_WATER:
		moved = _water.take_water(iv.tile, iv.magnitude)
		_water.carried += moved
	else:
		moved = _water.add_water(iv.tile, minf(iv.magnitude, _water.carried))
		_water.carried = maxf(_water.carried - moved, 0.0)
	if moved <= 0.0:
		iv.rejected = &"nothing_moved"
		return false
	iv.magnitude = moved
	iv.position = Vector3(iv.tile.x + 0.5, _world.get_height(iv.tile) * _world.height_step + _world.get_water(iv.tile), iv.tile.y + 0.5)
	return true


func _do_rain(iv: Intervention) -> bool:
	if not _world.is_in_bounds(iv.tile) or not is_finite(iv.magnitude) or iv.magnitude < 0.0:
		iv.rejected = &"no_ground"
		return false
	var config := Config.tools
	var phase: StringName = iv.params.get("phase", Intervention.PHASE_END)
	var much := phase == Intervention.PHASE_END and iv.magnitude >= config.rain_moderate_units
	if not _admit(iv, &"rain", Intervention.Severity.MODERATE if much else Intervention.Severity.GENTLE):
		return false
	var at := Vector2(iv.position.x, iv.position.z)
	iv.position.y = _world.get_height(iv.tile) * _world.height_step + _world.get_water(iv.tile)
	if phase == Intervention.PHASE_BEGIN:
		_rain_clear = sky_is_clear()
		_rain_carry = 0.0
	iv.params["clear_sky"] = _rain_clear
	if phase == Intervention.PHASE_END:
		if iv.magnitude <= 0.0:
			iv.rejected = &"nothing_fell"
			return false
		# What it added to the river shows on the tiles now.
		if _hydrology != null and _clock != null:
			_hydrology.settle(_clock.tick)
		return true
	iv.recorded = false # (the whole of it is recorded when it ends)
	if iv.magnitude > 0.0:
		_wet(at, iv.magnitude)
	return true


## `units` of rain on the ground within the cloud's radius of `at`: the soil
## takes it, and the river rises with what falls on it and what runs off.
func _wet(at: Vector2, units: float) -> void:
	var config := Config.tools
	var radius := config.rain_radius
	var soaked := units * config.rain_moisture_per_unit + _rain_carry
	var whole := floori(soaked)
	_rain_carry = soaked - whole
	var tiles := 0
	var on_water := 0
	for y in range(floori(at.y - radius), ceili(at.y + radius) + 1):
		for x in range(floori(at.x - radius), ceili(at.x + radius) + 1):
			var tile := Vector2i(x, y)
			if not _world.is_in_bounds(tile) or (Vector2(tile) + Vector2(0.5, 0.5)).distance_to(at) > radius:
				continue
			tiles += 1
			var chunk := _world.chunk_at_tile(tile)
			var i := _world.index_at_tile(tile)
			if chunk.water[i] > 0.0:
				on_water += 1
			elif whole > 0 and chunk.moisture[i] < 255:
				chunk.moisture[i] = mini(int(chunk.moisture[i]) + whole, 255)
				chunk.mark_changed()
	if _hydrology != null and tiles > 0:
		_hydrology.add(units * config.rain_river_rise * lerpf(config.rain_runoff_share, 1.0, float(on_water) / tiles))


func _do_gust(iv: Intervention) -> bool:
	var from: Variant = iv.params.get("from")
	var to: Variant = iv.params.get("to")
	if typeof(from) != TYPE_VECTOR2 or typeof(to) != TYPE_VECTOR2 or not (from as Vector2).is_finite() or not (to as Vector2).is_finite() \
			or (from as Vector2).distance_to(to) < 0.01 or not is_finite(iv.magnitude):
		iv.rejected = &"no_direction"
		return false
	if not _admit(iv, &"wind", Intervention.Severity.MODERATE):
		return false
	var config := Config.tools
	var strength := clampf(iv.magnitude, 0.0, 1.0)
	var direction := ((to as Vector2) - (from as Vector2)).normalized()
	var middle := (from as Vector2) + direction * config.wind_reach * 0.5
	var middle_tile := WorldCoords.world2d_to_tile(middle)
	iv.magnitude = strength
	iv.position = Vector3(middle.x, _world.get_height(middle_tile) * _world.height_step + _world.get_water(middle_tile), middle.y)
	iv.params["direction"] = direction
	iv.params["ordinary"] = _weather != null and _weather.wind_speed >= config.wind_ordinary_from
	# Light things lying in its way are blown along.
	var pushed := 0
	if _loose != null and _motion != null and _loose.spatial_index != null:
		for id in _loose.spatial_index.query_radius(middle, config.wind_reach * 0.5 + config.wind_width, SpatialIndex.KIND_LOOSE_OBJECT):
			var object := _loose.get_object(id)
			if object == null or object.state == LooseObject.State.HELD or object.mass() >= config.wind_light_kg:
				continue
			var offset := object.position - (from as Vector2)
			var along := offset.dot(direction)
			if along < -0.5 or along > config.wind_reach or absf(offset.cross(direction)) > config.wind_width:
				continue
			var speed := config.wind_push * strength * (1.0 - object.mass() / config.wind_light_kg)
			if _motion.push(id, Vector3(direction.x, 0.0, direction.y) * speed):
				pushed += 1
	iv.params["pushed"] = pushed
	return true


func _do_carve(iv: Intervention) -> bool:
	var phase: StringName = iv.params.get("phase", Intervention.PHASE_END)
	if phase == Intervention.PHASE_END:
		if not _world.is_in_bounds(iv.tile) or iv.magnitude < 1.0:
			iv.rejected = &"nothing_carved"
			return false
		if not _admit(iv, &"ground", Intervention.Severity.MODERATE):
			return false
		iv.position = Vector3(iv.tile.x + 0.5, _world.get_height(iv.tile) * _world.height_step, iv.tile.y + 0.5)
		# The river finds what now lies open to it.
		if _hydrology != null:
			_hydrology.apply(true)
		return true
	if not can_carve(iv.tile):
		iv.rejected = &"cannot_carve"
		return false
	if not _admit(iv, &"ground", Intervention.Severity.MODERATE):
		return false
	iv.recorded = false # (the stroke is recorded when it ends)
	iv.magnitude = 1.0
	if _world.get_terrain(iv.tile) == ChunkData.Terrain.GRASS:
		_world.set_terrain(iv.tile, ChunkData.Terrain.DIRT)
	_world.set_height(iv.tile, _world.get_height(iv.tile) - 1)
	if _water != null:
		_water.wake(iv.tile) # (water beside it runs in)
	iv.position = Vector3(iv.tile.x + 0.5, _world.get_height(iv.tile) * _world.height_step, iv.tile.y + 0.5)
	return true


## An object the player moved has come to rest: near the settlement it is
## something its inhabitants may come upon (hook for M4/M5).
func _on_object_settled(id: int) -> void:
	if not _awaiting_rest.erase(id) or _loose == null:
		return
	var object := _loose.get_object(id)
	if object == null:
		return
	var near := _settlement != Vector2.INF and object.position.distance_to(_settlement) <= DISCOVER_RADIUS
	if object.discoverable != near:
		object.discoverable = near
		_loose.touch(id)


## What a touch landed on, as the history names it: "tree", "water", "rock", ...
static func subject_of(response: InteractionResponse) -> StringName:
	if response.person_id != 0:
		return &"person"
	if response.animal_id != 0:
		return response.animal_species
	if response.loose_kind >= 0:
		return loose_subject(response.loose_kind)
	if response.prop_kind >= 0:
		return StringName(String(PropData.Kind.keys()[response.prop_kind]).to_lower())
	if response.touch_effect == InteractionResponse.RIPPLE:
		return &"water"
	return &"ground"


static func loose_subject(kind: int) -> StringName:
	return StringName(String(LooseObject.Kind.keys()[kind]).to_lower())


## True if touches can bring new loose objects into the world.
func can_spawn() -> bool:
	return _loose != null and _motion != null and _ids != null and _rng != null


## How often a tree has been shaken since the world was opened.
func shakes_of(tree_id: int) -> int:
	return int(_shakes.get(tree_id, 0))


## A long press: asks to inspect the target (the context panel arrives in M2.4).
func long_press(target: Picker.Result) -> InteractionResponse:
	var response := _respond(target, InteractionResponse.Action.LONG_PRESS, false)
	if response != null:
		response.effect = InteractionResponse.INSPECT
		_announce(response)
	return response


## Describes what a target is without touching it (double tap, UI).
func describe(target: Picker.Result) -> InteractionResponse:
	return _respond(target, InteractionResponse.Action.DOUBLE_TAP, false)


## What the player can do with a target right now, in menu order (bible §26.6
## lists more per target; an action appears here once it works). Empty for a miss.
func actions_for(target: Picker.Result) -> Array[StringName]:
	var actions: Array[StringName] = []
	if target == null or not target.is_hit() or _world == null:
		return actions
	# A grave is read, not touched (bible §26.6).
	if target.kind == Picker.Kind.ENTITY and _props != null and _props.get_prop(target.entity_id) != null \
			and _props.get_prop(target.entity_id).kind == PropData.Kind.GRAVE:
		actions.append_array([ACTION_READ, ACTION_VIEW_FAMILY, ACTION_FOCUS])
		return actions
	actions.append(ACTION_INSPECT)
	actions.append(ACTION_TOUCH)
	if target.kind == Picker.Kind.ENTITY and _props != null:
		var prop := _props.get_prop(target.entity_id)
		if prop != null and prop.kind == PropData.Kind.TREE:
			actions.append(ACTION_REMOVE)
	actions.append(ACTION_FOCUS)
	return actions


## The facts about a target (the inspect card). Null for a miss. Looking does
## not touch the world: nothing is announced.
func inspect(target: Picker.Result) -> InspectReport:
	if target == null or not target.is_hit() or _world == null:
		return null
	var report := InspectReport.new()
	var prop: PropData = null
	var object: LooseObject = null
	var animal: AnimalData = null
	if target.kind == Picker.Kind.ENTITY:
		prop = _props.get_prop(target.entity_id) if _props != null else null
		object = _loose.get_object(target.entity_id) if _loose != null and prop == null else null
		if prop == null and object == null and _fauna != null and _fauna.registry != null:
			animal = _fauna.registry.get_animal(target.entity_id)
	report.tile = target.tile
	if prop != null:
		report.tile = prop.tile
	elif object != null:
		report.tile = object.tile()
	elif animal != null:
		report.tile = animal.tile()
	var chunk := _world.chunk_at_tile(report.tile)
	if chunk == null:
		return null
	var i := _world.index_at_tile(report.tile)
	report.terrain = chunk.terrain[i]
	report.height_level = chunk.height[i]
	report.moisture = chunk.moisture[i]
	report.fertility = chunk.fertility[i]
	report.vegetation = chunk.vegetation[i]
	report.water_depth = chunk.water[i]
	if traffic != null:
		report.footfall = traffic.level(report.tile)
		report.path = traffic.is_path(report.tile)
	if prop != null:
		report.subject = InspectReport.Subject.PROP
		report.entity_id = prop.id
		report.prop_kind = prop.kind
		report.prop_variant = prop.variant
		report.scale_percent = prop.scale_percent
		report.generated = prop.is_generated()
		# (A site, or a bridge going up where it stands; a repair: the condition says it.)
		var project := construction.project_at(prop.id) if construction != null else {}
		if not project.is_empty() and str(project["kind"]) == ConstructionSystem.BUILD:
			report.building = StringName(str(project["def"]))
			report.build_progress = construction.progress(project)
			report.still_needed = construction.still_needed(project)
		elif prop.is_building():
			report.condition = prop.condition
		if prop.kind == PropData.Kind.CAMPFIRE and settlements != null:
			for own in settlements.all():
				if own.start_info().campfire_id == prop.id:
					report.settlement_name = own.display_name()
					report.settlement_tier = own.tier()
					report.settlement_people = own.member_count()
					report.known_for = String(own.specialty())
					if governance != null and governance.leader_of(own.id) != 0 and _people != null:
						report.leader_name = _people.name_of(governance.leader_of(own.id))
					if own.trade != null:
						var balance := own.trade.balance_of(own.id)
						report.sends = balance[0]
						report.gets = balance[1]
					for what: String in own.knows:
						report.knows.append(what)
		if prop.kind == PropData.Kind.TREE:
			report.bears = prop.bears()
			report.bears_left = prop.bears_left()
		report.resource = ResourceNodes.resource_for(prop)
		report.look = ResourceNodes.look_of(prop)
		if prop.kind == PropData.Kind.CROP:
			report.crop_stage = Farming.stage_of(prop)
			report.crop_growth = prop.growth
			report.crop_vigor = prop.vigor
			report.crop_dry = Farming.looks_dry(prop)
		if report.resource != &"":
			report.resource_capacity = ResourceNodes.capacity_of(prop)
			report.resource_left = ResourceNodes.left_of(prop)
	elif object != null:
		report.subject = InspectReport.Subject.LOOSE
		report.entity_id = object.id
		report.loose_kind = object.kind
		report.scale_percent = object.scale_percent
		report.generated = object.is_generated()
		report.mass = object.mass()
		report.moved_count = object.moved_count
		report.placed_by_player = object.placed_by_player
		if object.is_pile():
			report.resource = object.resource
			report.resource_left = object.amount
	elif animal != null:
		report.subject = InspectReport.Subject.ANIMAL
		report.entity_id = animal.id
		report.species = animal.species
		report.animal_state = animal.state
		report.animal_age_days = animal.age_days(_clock.tick if _clock != null else 0)
		report.species_count = _fauna.count(animal.species)
		var kind := _fauna.species.get_def(animal.species)
		report.animal_grown = kind == null or report.animal_age_days >= kind.adult_days
	elif target.kind == Picker.Kind.WATER:
		report.subject = InspectReport.Subject.WATER
	return report


func _respond(target: Picker.Result, action: InteractionResponse.Action, announce: bool = true) -> InteractionResponse:
	if target == null or not target.is_hit() or _world == null:
		return null
	var response := InteractionResponse.new()
	response.action = action
	response.tile = target.tile
	response.position = target.position
	response.terrain = _world.get_terrain(target.tile)

	var prop: PropData = null
	var object: LooseObject = null
	var person: PersonData = null
	if target.kind == Picker.Kind.ENTITY:
		prop = _props.get_prop(target.entity_id) if _props != null else null
		object = _loose.get_object(target.entity_id) if _loose != null and prop == null else null
		person = _people.get_person(target.entity_id) if _people != null and prop == null and object == null else null

	var animal: AnimalData = null
	if target.kind == Picker.Kind.ENTITY and prop == null and object == null and person == null and _fauna != null \
			and _fauna.registry != null:
		animal = _fauna.registry.get_animal(target.entity_id)
	if animal != null:
		var kind := _fauna.species.get_def(animal.species)
		response.entity_id = animal.id
		response.animal_id = animal.id
		response.animal_species = animal.species
		response.tile = animal.tile()
		response.terrain = _world.get_terrain(response.tile)
		response.position = Vector3(animal.position.x, _world.get_height(response.tile) * _world.height_step, animal.position.y)
		response.body = Vector2(kind.height, kind.radius) if kind != null else Vector2(0.4, 0.2)
		response.effect = InteractionResponse.NUDGE
		response.strength = 1.2
		response.description = "%s at %s" % [String(animal.species).to_upper(), response.tile]
	elif person != null:
		var at := person.world2d()
		response.entity_id = person.id
		response.person_id = person.id
		response.tile = person.position
		response.terrain = _world.get_terrain(response.tile)
		response.position = Vector3(at.x, _world.get_height(person.position) * _world.height_step, at.y)
		response.body = Vector2(PERSON_HEIGHT, PERSON_HEIGHT * 0.4)
		response.effect = InteractionResponse.PERSON_TOUCH
		response.description = "PERSON %s at %s" % [person.given_name, person.position]
	elif object != null:
		response.entity_id = object.id
		response.loose_kind = object.kind
		response.strength = object.give()
		response.body = object.pick_shape()
		response.tile = object.tile()
		response.terrain = _world.get_terrain(response.tile)
		response.position = object.world_position(_world)
		if object.is_stone():
			response.effect = InteractionResponse.ROCK_WOBBLE
		elif object.kind == LooseObject.Kind.LOG:
			response.effect = InteractionResponse.LOG_KNOCK
		else:
			response.effect = InteractionResponse.NUDGE
		response.description = "%s at %s" % [LooseObject.Kind.keys()[object.kind], response.tile]
	elif prop != null:
		var at := prop.position2d()
		response.entity_id = prop.id
		response.prop_kind = prop.kind
		response.prop_variant = prop.variant
		response.body = prop.pick_shape()
		response.tile = prop.tile
		response.position = Vector3(at.x, _world.get_height(prop.tile) * _world.height_step, at.y)
		response.effect = _PROP_EFFECTS.get(prop.kind, InteractionResponse.DUST)
		response.description = "%s at %s" % [PropData.Kind.keys()[prop.kind], prop.tile]
	elif target.kind == Picker.Kind.WATER:
		response.effect = InteractionResponse.RIPPLE
		# On the surface, even if the finger caught the side of the water.
		response.position.y = _world.get_height(target.tile) * _world.height_step + _world.get_water(target.tile)
		response.description = "WATER at %s  depth %.2f" % [target.tile, _world.get_water(target.tile)]
	else:
		# Plain ground — also where a picked entity has vanished in the meantime.
		response.effect = InteractionResponse.DUST
		response.description = "%s at %s  height %d" % [
			ChunkData.Terrain.keys()[response.terrain], target.tile, _world.get_height(target.tile)]

	response.touch_effect = response.effect
	if announce:
		_announce(response)
	return response


## A shaken tree may let go of what it bears: never on the first shake, then
## by chance, until nothing is left.
func _shake_tree(response: InteractionResponse) -> void:
	var tree := _props.get_prop(response.entity_id)
	if tree == null:
		return
	var shakes := shakes_of(tree.id) + 1
	_shakes[tree.id] = shakes
	if shakes < 2 or tree.bears_left() <= 0 or not can_spawn():
		return
	var rng := _rng.stream(RNG_STREAM)
	if rng.randf() >= SHAKE_DROP_CHANCE:
		return
	tree.taken += 1
	_props.touch(tree.id)
	# It lets go somewhere in the crown and falls a little outward.
	var body := tree.pick_shape()
	var angle := rng.randf() * TAU
	var outward := Vector2(cos(angle), sin(angle))
	var kind := LooseObject.Kind.SEED if tree.is_conifer() else LooseObject.Kind.FRUIT
	var at := tree.position2d() + outward * body.y * rng.randf_range(0.45, 0.85)
	var fruit := _spawn(kind, at, body.x * rng.randf_range(0.5, 0.75), 100 + rng.randi_range(0, 30))
	var speed := rng.randf_range(0.3, 1.1)
	_motion.drop(fruit.id, Vector3(outward.x * speed, 0.0, outward.y * speed))
	response.dropped.append(fruit.id)


## A touch on water pushes what floats nearby away from the finger.
func _disturb_water(response: InteractionResponse) -> void:
	if _loose == null or _motion == null or _loose.spatial_index == null:
		return
	var center := Vector2(response.position.x, response.position.z)
	for id in _loose.spatial_index.query_radius(center, RIPPLE_REACH, SpatialIndex.KIND_LOOSE_OBJECT):
		var object := _loose.get_object(id)
		if object == null or _motion.rest_height(object) <= 0.0:
			continue # not afloat
		var away := object.position - center
		var distance := away.length()
		var direction := away / distance if distance > 0.001 else Vector2.RIGHT
		var strength := RIPPLE_PUSH * (1.0 - distance / RIPPLE_REACH) * clampf(object.give(), 0.3, 1.5)
		_motion.push(id, Vector3(direction.x, 0.0, direction.y) * strength)


## A new loose object at `at`, `height` above the ground.
func _spawn(kind: LooseObject.Kind, at: Vector2, height: float, scale_percent: int) -> LooseObject:
	var object := LooseObject.new()
	object.id = _ids.next_id()
	object.kind = kind
	object.scale_percent = scale_percent
	# Inside the box, whatever the tree's crown overhangs.
	var inner := Rect2(_world.bounds).grow(-0.1)
	object.position = Vector2(clampf(at.x, inner.position.x, inner.end.x), clampf(at.y, inner.position.y, inner.end.y))
	object.height_offset = maxf(height, 0.0)
	_loose.add(object)
	return object


func _announce(response: InteractionResponse) -> void:
	interaction_count += 1
	responded.emit(response)
