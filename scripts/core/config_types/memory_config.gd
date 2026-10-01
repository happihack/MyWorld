class_name MemoryConfig
extends ConfigBase
## What people remember, for how long, and what it does to them (bible §15).

@export_group("Remembering")
## The most personal memories one person holds; beyond it the least
## important go.
@export_range(1, 256) var max_per_person: int = 32
## What is noticed less than this is not remembered (what happens to oneself
## always is).
@export_range(0.0, 1.0, 0.01) var remember_threshold: float = 0.2
## Importance = intensity × feeling × relevance × novelty. How much each
## way of coming by it counts as "relevance".
@export_range(0.0, 1.0, 0.01) var relevance_direct: float = 1.0
@export_range(0.0, 1.0, 0.01) var relevance_witnessed: float = 0.65
@export_range(0.0, 1.0, 0.01) var relevance_told: float = 0.45
## After n earlier times it is 1 / (1 + n · this) as new.
@export_range(0.0, 2.0, 0.01) var novelty_wear: float = 0.25
## The same thing again adds this much (of what is left to 1) to how much
## the memory of it matters.
@export_range(0.0, 1.0, 0.01) var repeat_gain: float = 0.25

@export_group("Forgetting")
## Every game day a memory loses this much importance — less the more it
## matters (something that matters fully loses a twentieth of it).
@export_range(0.0, 1.0, 0.001) var daily_fade: float = 0.04
## Below this it is forgotten.
@export_range(0.0, 1.0, 0.01) var forget_below: float = 0.05

@export_group("Telling")
## How much of a memory's fidelity survives a retelling.
@export_range(0.0, 1.0, 0.01) var retelling_fidelity: float = 0.85
## A memory has to matter this much to be told to someone in passing, be
## this true to what happened, and not have been told in the last so many
## game minutes.
@export_range(0.0, 1.0, 0.01) var tell_importance: float = 0.3
@export_range(0.0, 1.0, 0.01) var tell_fidelity: float = 0.4
@export_range(0, 100000) var tell_again_minutes: int = 720
## ...and to have happened within the last so many game days.
@export_range(0, 1000) var tell_recent_days: int = 6

@export_group("What memories do")
## A memory with at least this much fear in it makes its place one to keep
## away from, this many tiles around.
@export_range(0.0, 1.0, 0.01) var fear_matters_from: float = 0.35
@export_range(0.5, 40.0, 0.5) var fear_radius: float = 6.0
## A place feared more than this is not chosen (for work, for a look around)
## if there is another.
@export_range(0.0, 1.0, 0.01) var avoid_from: float = 0.25
## How much wonder at something (curiosity and awe, less the fear) speaks for
## taking a closer look the next time, and for a friendly wave.
@export_range(0.0, 3.0, 0.05) var wonder_weight: float = 0.6

@export_group("Finding things")
## Someone comes upon a thing the player moved if it lies this near (tiles)...
@export_range(0.5, 10.0, 0.1) var find_radius: float = 2.6
## ...and has lain there at least this long (game minutes): what is seen to
## land is not "found".
@export_range(0, 10000) var find_after_minutes: int = 30


func validate() -> PackedStringArray:
	var p := PackedStringArray()
	_check(p, forget_below < tell_importance, "forget_below must be below tell_importance")
	_check(p, max_per_person >= 1, "max_per_person must be >= 1")
	return p
