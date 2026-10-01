class_name ActionStep
extends RefCounted
## One kind of step in a plan (bible §13.4): walk somewhere, eat, sleep, ...
##
## A step in progress is **plain data** — a Dictionary such as
## `{"type": "eat", "minutes": 25.0, "elapsed": 3.5}` — stored in
## PersonData.current_action, so that a world saved in the middle of anything
## is restored exactly. The classes in actions/ hold no state of their own:
## they are what to do with such a Dictionary.

enum Status { RUNNING, DONE, FAILED }


## The step becomes the one being carried out — also again after a load, so
## it must be safe to call twice. Sets what is not saved (pose, walking).
func begin(_ctx: AiContext, _person: PersonData, _step: Dictionary) -> void:
	pass


## Carries the step on for `minutes` of game time.
func update(_ctx: AiContext, _person: PersonData, _step: Dictionary, _minutes: float) -> Status:
	return Status.DONE


## The step is over, however it ended (done, failed, dropped for something
## else): leave nothing behind.
func end(_ctx: AiContext, person: PersonData, _step: Dictionary) -> void:
	person.pose = PersonData.Pose.IDLE


## How much more than usual something else must press before the person
## drops this (0 = nothing special; a sleeper is not woken by a little thirst).
func reluctance(_step: Dictionary) -> float:
	return 0.0


## How many ticks may pass between two turns of someone at this step without
## anything being missed (1 = every tick). A sleeper's night is the same
## lived in ten-minute steps; someone walking must be seen to arrive.
func patience(_step: Dictionary) -> int:
	return 1


## What the person's needs are subject to while at it.
func needs_state(_step: Dictionary) -> Needs.State:
	return Needs.State.AWAKE


## Counts `minutes` on the step's clock. True once its time is up.
static func tick(step: Dictionary, minutes: float) -> bool:
	step["elapsed"] = float(step.get("elapsed", 0.0)) + minutes
	return float(step["elapsed"]) >= float(step.get("minutes", 0.0))


## Has the step been going long enough to end early (the need it serves is
## met)? Nothing is over in no time: a plan always takes a moment of game
## time, so deciding can never go round in circles within one frame.
static func may_end_early(step: Dictionary) -> bool:
	return float(step.get("elapsed", 0.0)) >= 1.0


## A point of a tile in the world (its middle).
static func middle(tile: Vector2i) -> Vector2:
	return Vector2(tile) + Vector2(0.5, 0.5)
