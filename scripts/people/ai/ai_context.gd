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

# How each person's last walk ended, until the step that asked for it has
# looked: person id -> &"arrived" / &"blocked".
var _walk_results: Dictionary = {}


func now() -> int:
	return clock.tick if clock != null else 0


func stage_of(person: PersonData) -> PersonData.LifeStage:
	return person.life_stage(now(), Config.time.ticks_per_year(), Config.people)


func note_walk(person_id: int, result: StringName) -> void:
	_walk_results[person_id] = result


## How the person's walk ended (&"" if it has not), forgetting it.
func take_walk_result(person_id: int) -> StringName:
	var result: StringName = _walk_results.get(person_id, &"")
	_walk_results.erase(person_id)
	return result


func forget(person_id: int) -> void:
	_walk_results.erase(person_id)


## Turns a person to look at a point of the world.
func face(person: PersonData, at: Vector2) -> void:
	var to := at - person.world2d()
	if to.length_squared() > 0.0001:
		people.move(person.id, person.position, person.sub_tile_offset, to.angle())
