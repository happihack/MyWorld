class_name MovementSystem
extends RefCounted
## Walks people along paths (bible §13.7). Someone who is told to walk asks
## the Pathfinder for a way, then advances along it a little every step, at a
## speed that depends on who they are and what they are walking through.
##
## Time is game minutes (one clock tick), in fractions: the session steps the
## system every frame, so people move evenly however fast the game runs.
## Where someone is going is runtime state here; PersonData only ever holds
## where they are. (What they are doing, and resuming it after a load, is
## M4.4 / M4.6.)

## The person reached the tile they were walking to.
signal arrived(person_id: int)
## The person cannot get there (no way, or the way closed and there is no other).
signal blocked(person_id: int)

## A way that closes is looked for again this many times before giving up.
const MAX_REPATHS := 3
## In the running game each walker is moved every this many frames, not all
## in the same one (see step_in_turns). Their views glide between positions,
## so nothing of it is seen.
const STRIDE_FRAMES := 3


class Walk:
	extends RefCounted
	var person_id := 0
	var target := Vector2i.ZERO
	var target_offset := Vector2(0.5, 0.5)
	var path: Array[Vector2i] = []
	## The tile of `path` being walked to.
	var index := 0
	## Waiting for the pathfinder (0 = not waiting).
	var request_id := 0
	## The graph version the path was found in.
	var version := 0
	var repaths := 0
	## Tiles per game minute on the stretch being walked (to path[index]), and
	## the index and graph version it was worked out for.
	var speed := 0.0
	var speed_index := -1
	var speed_version := -1
	var facing := 0.0
	## Game minutes not walked yet (see step_in_turns).
	var owed := 0.0


var _people: PersonRegistry
var _pathfinder: Pathfinder
var _clock: GameClock
var _walks: Dictionary = {} # person id -> Walk
var _order: Array[int] = [] # ids of everyone walking, sorted: the same order every time
var _frame := 0
## For the debug overlay.
var arrivals := 0
var blocks := 0


func bind(people: PersonRegistry, pathfinder: Pathfinder, clock: GameClock) -> void:
	if _people != null:
		_people.person_removed.disconnect(_on_person_removed)
	stop_all()
	_people = people
	_pathfinder = pathfinder
	_clock = clock
	if people != null:
		people.person_removed.connect(_on_person_removed)


## Sends a person walking to `tile` (to a tile beside it, if it cannot be
## stood on), ending at `offset` on that tile. Replaces wherever they were
## going. False if there is no such person or no such tile; whether there is a
## way is reported later (arrived / blocked).
func walk_to(person_id: int, tile: Vector2i, offset: Vector2 = Vector2(0.5, 0.5)) -> bool:
	var person := _people.get_person(person_id) if _people != null else null
	if person == null or _pathfinder == null or not _pathfinder.has_tile(tile):
		return false
	stop(person_id)
	var walk := Walk.new()
	walk.person_id = person_id
	walk.target = tile
	walk.target_offset = offset.clamp(Vector2(0.05, 0.05), Vector2(0.95, 0.95))
	_walks[person_id] = walk
	_order.insert(_order.bsearch(person_id), person_id)
	_ask(walk, person)
	return true


## Sends everyone in `ids` to stand around `tile`, each on a tile of their
## own. Returns how many set off.
func gather(ids: Array[int], tile: Vector2i) -> int:
	var places := _pathfinder.standable_near(tile, ids.size())
	var sent := 0
	for i in mini(ids.size(), places.size()):
		var person := _people.get_person(ids[i])
		if person != null and walk_to(ids[i], places[i], person.sub_tile_offset):
			sent += 1
	return sent


## Stops a person where they are.
func stop(person_id: int) -> void:
	var walk: Walk = _walks.get(person_id)
	if walk == null:
		return
	if walk.request_id != 0:
		_pathfinder.cancel(walk.request_id)
	_forget(person_id)


func stop_all() -> void:
	for id: int in _walks.keys():
		stop(id)


func is_walking(person_id: int) -> bool:
	return _walks.has(person_id)


## True while a person is waiting to be told the way.
func is_waiting(person_id: int) -> bool:
	var walk: Walk = _walks.get(person_id)
	return walk != null and walk.request_id != 0


## Where a walking person is going (the tile they asked for).
func target_of(person_id: int) -> Variant:
	var walk: Walk = _walks.get(person_id)
	return walk.target if walk != null else null


## The rest of a walking person's way (empty if not walking or still waiting).
func remaining_path(person_id: int) -> Array[Vector2i]:
	var walk: Walk = _walks.get(person_id)
	var out: Array[Vector2i] = []
	if walk != null:
		out.assign(walk.path.slice(walk.index))
	return out


func walking_count() -> int:
	return _walks.size()


## Tiles per game minute someone covers walking into `tile`.
func speed_of(person: PersonData, tile: Vector2i) -> float:
	var config := Config.people
	var stage := person.life_stage(_clock.tick if _clock != null else 0, Config.time.ticks_per_year(), config)
	return config.walk_tiles_per_minute * config.walk_factor(stage) * lerpf(0.5, 1.0, clampf(person.health, 0.0, 1.0)) \
		* _pathfinder.speed_factor(tile)


## Advances everyone who is walking by `minutes` of game time, now.
func step(minutes: float) -> void:
	_step(minutes, 1)


## The same for the running game, called every frame: each walker is moved
## every STRIDE_FRAMES frames by the time that has built up for them, and not
## all walkers in the same frame. Nobody loses time or goes a different way;
## they are only put down in fewer, larger steps.
func step_in_turns(minutes: float) -> void:
	_frame += 1
	_step(minutes, STRIDE_FRAMES)


func _step(minutes: float, stride: int) -> void:
	if minutes <= 0.0 or _walks.is_empty() or _people == null:
		return
	var count := _order.size()
	var i := 0
	while i < count:
		var id := _order[i]
		var walk: Walk = _walks.get(id)
		if walk != null and walk.request_id == 0:
			walk.owed += minutes
			if stride <= 1 or (_frame + id) % stride == 0:
				var person := _people.get_person(id)
				if person != null:
					var owed := walk.owed
					walk.owed = 0.0
					_advance(walk, person, owed)
		# (Someone who arrived or gave up has left the list.)
		if _order.size() < count:
			count = _order.size()
		else:
			i += 1


# --- internals ----------------------------------------------------------------------------------

func _ask(walk: Walk, person: PersonData) -> void:
	walk.path = []
	walk.index = 0
	walk.request_id = _pathfinder.request(person.position, walk.target, _on_path.bind(walk))


func _on_path(path: Array[Vector2i], walk: Walk) -> void:
	if _walks.get(walk.person_id) != walk:
		return # stopped or sent elsewhere in the meantime
	walk.request_id = 0
	if path.is_empty():
		_give_up(walk)
		return
	walk.path = path
	walk.version = _pathfinder.version
	walk.index = 1 if path.size() > 1 else 0 # path[0] is where they stand


func _advance(walk: Walk, person: PersonData, minutes: float) -> void:
	var at := person.world2d()
	var facing := person.facing
	var left := minutes
	while left > 0.0:
		var last := walk.index >= walk.path.size() - 1
		var tile := walk.path[walk.index]
		# The world may have changed since the way was found: look before stepping.
		var here := WorldCoords.world2d_to_tile(at)
		if walk.version != _pathfinder.version \
				and (not _pathfinder.can_stand(tile) or (here != tile and not _pathfinder.can_step(here, tile))):
			_put(person, at, facing)
			walk.repaths += 1
			if walk.repaths > MAX_REPATHS:
				_give_up(walk)
			else:
				_ask(walk, person)
			return
		var goal := Vector2(tile) + (walk.target_offset if last else Vector2(0.5, 0.5))
		var to_goal := goal - at
		var distance := to_goal.length()
		if walk.speed_index != walk.index or walk.speed_version != _pathfinder.version:
			walk.speed = speed_of(person, tile)
			walk.speed_index = walk.index
			walk.speed_version = _pathfinder.version
			# (The way to a tile centre is straight: the heading holds for the stretch.)
			walk.facing = to_goal.angle() if distance > 0.0001 else facing
		var speed := walk.speed
		facing = walk.facing
		if distance <= speed * left:
			at = goal
			left -= distance / speed
			if last:
				_put(person, at, facing)
				_forget(walk.person_id)
				arrivals += 1
				arrived.emit(walk.person_id)
				return
			walk.index += 1
		else:
			at += to_goal / distance * speed * left
			left = 0.0
	_put(person, at, facing)


func _put(person: PersonData, at: Vector2, facing: float) -> void:
	var tile := Vector2i(floori(at.x), floori(at.y))
	_people.place(person, tile, at - Vector2(tile), facing)


func _forget(person_id: int) -> void:
	_walks.erase(person_id)
	_order.erase(person_id)


func _give_up(walk: Walk) -> void:
	_forget(walk.person_id)
	blocks += 1
	blocked.emit(walk.person_id)


func _on_person_removed(id: int) -> void:
	stop(id)
