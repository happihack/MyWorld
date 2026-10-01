class_name LooseObjectSystem
extends Node
## Moves the loose objects that are not at rest (bible §10, §31.3). Lives in
## the WorldSession and works on its LooseObjectRegistry.
##
## v0 (M3.2): an object that is let go falls straight down and comes to rest.
## Bouncing, sliding down slopes and bumping into things arrive with the full
## integrator in M3.3.

## An object came to rest. `impact_speed` is how fast it was falling (tiles/s).
signal landed(id: int, impact_speed: float)

## Tiles per second squared. Stronger than life-size gravity would be at this
## scale, so drops feel quick and weighty rather than floaty.
const GRAVITY := 22.0
## A step never advances more than this, however long the frame took.
const MAX_STEP := 0.05

var _world: WorldData
var _registry: LooseObjectRegistry
var _falling: Dictionary = {} # id -> true


func bind(world: WorldData, registry: LooseObjectRegistry) -> void:
	_world = world
	_registry = registry
	_falling.clear()


## Takes an object in hand: it stops falling and stays where it is put.
func hold(id: int) -> bool:
	var object := _object(id)
	if object == null:
		return false
	_falling.erase(id)
	object.state = LooseObject.State.HELD
	object.velocity = Vector3.ZERO
	return true


## Lets an object go: it falls until it lands.
func drop(id: int) -> bool:
	var object := _object(id)
	if object == null:
		return false
	object.state = LooseObject.State.FALLING
	object.velocity = Vector3.ZERO
	_falling[id] = true
	return true


func is_falling(id: int) -> bool:
	return _falling.has(id)


func moving_count() -> int:
	return _falling.size()


## Height above the ground at which an object rests on its tile: on the ground,
## or on the water if it floats.
func rest_height(object: LooseObject) -> float:
	if _world == null or not object.floats():
		return 0.0
	var depth := _world.get_water(object.tile())
	return depth if depth > WaterMesher.MIN_DEPTH else 0.0


## Advances everything that is moving. Called every frame; tests call it directly.
func step(delta: float) -> void:
	if _falling.is_empty() or _registry == null:
		return
	var dt := minf(delta, MAX_STEP)
	for id: int in _falling.keys():
		var object := _registry.get_object(id)
		if object == null or object.state != LooseObject.State.FALLING:
			_falling.erase(id) # removed, or picked up again
			continue
		object.velocity.y -= GRAVITY * dt
		var height := object.height_offset + object.velocity.y * dt
		var floor_height := rest_height(object)
		if height <= floor_height:
			var impact := -object.velocity.y
			object.velocity = Vector3.ZERO
			object.state = LooseObject.State.RESTING
			_falling.erase(id)
			_registry.move(id, object.position, floor_height)
			landed.emit(id, impact)
		else:
			_registry.move(id, object.position, height)


func _process(delta: float) -> void:
	step(delta)


func _object(id: int) -> LooseObject:
	return _registry.get_object(id) if _registry != null else null
