class_name AiContext
extends RefCounted
## What people's decisions and actions can see and use: the world, each other,
## the systems that move them, the dice. One per world (owned by the
## BehaviorSystem).

var world: WorldData
var props: PropRegistry
var people: PersonRegistry
var pathfinder: Pathfinder
var movement: MovementSystem
var clock: GameClock
var start: WorldSetup.StartInfo
var occupations: OccupationLibrary
var activities: ActivityLibrary
var places: Places
## The world's "ai" stream.
var rng: RandomNumberGenerator
## Strokes of work done since the BehaviorSystem last announced them: each
## [person id, kind, target id]. (Plain data rather than a callback: a callback
## into the system that owns this context would keep both alive for ever.)
var strokes: Array = []
## The seed of the world (what a settlement's people lean toward comes from it).
var world_seed := 0
## What people have noticed and not yet considered: person id -> Array of
## {"stimulus": Stimulus, "salience": float, "direct": bool, "witnesses": int}
## (see PerceptionSystem; considered by the BehaviorSystem at their next turn).
var perceptions: Dictionary = {}
## People who should take their next turn at once (someone is talking to them).
var nudges: Array[int] = []
## What everyone remembers (may be null: nobody remembers anything).
var memories: MemoryStore
## The things lying about (for coming upon what the player moved; may be null).
var loose: LooseObjectRegistry
## The number the next stimulus gets (saved with the world: memories refer
## to the stimulus they came from).
var next_stimulus_id := 1

# How each person's last walk ended, until the step that asked for it has
# looked: person id -> &"arrived" / &"blocked".
var _walk_results: Dictionary = {}
var _stages: Dictionary = {} # person id -> Vector2i(game day, stage)


func take_stimulus_id() -> int:
	next_stimulus_id += 1
	return next_stimulus_id - 1


func now() -> int:
	return clock.tick if clock != null else 0


## The person's stage of life (looked up once per game day and person:
## everything a person does asks for it).
func stage_of(person: PersonData) -> PersonData.LifeStage:
	@warning_ignore("integer_division")
	var day := now() / TimeConfig.MINUTES_PER_DAY
	var known: Variant = _stages.get(person.id)
	if known != null and (known as Vector2i).x == day:
		return (known as Vector2i).y as PersonData.LifeStage
	var stage := person.life_stage(now(), Config.time.ticks_per_year(), Config.people)
	_stages[person.id] = Vector2i(day, stage)
	return stage


func note_walk(person_id: int, result: StringName) -> void:
	_walk_results[person_id] = result


## How the person's walk ended (&"" if it has not), forgetting it.
func take_walk_result(person_id: int) -> StringName:
	var result: StringName = _walk_results.get(person_id, &"")
	_walk_results.erase(person_id)
	return result


func forget(person_id: int) -> void:
	_walk_results.erase(person_id)
	_stages.erase(person_id)


## Turns a person to look at a point of the world.
func face(person: PersonData, at: Vector2) -> void:
	var to := at - person.world2d()
	if to.length_squared() > 0.0001:
		people.move(person.id, person.position, person.sub_tile_offset, to.angle())
