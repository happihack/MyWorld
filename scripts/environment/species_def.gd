class_name SpeciesDef
extends Resource
## A kind of animal (bible §12). One file per species in res://data/species/.

enum Diet { GRAZER, PREDATOR, FISH }

## Stable id (saved with animals; never rename).
@export var id: StringName = &""
@export var diet: Diet = Diet.GRAZER
## Kept as one number for a whole water, not as animals one by one (fish).
@export var aggregate: bool = false

@export_group("Numbers")
## How many the box holds (the population levels off towards it). For a
## predator also bounded by its prey: see `per_prey`.
@export_range(1, 500) var capacity: int = 10
## How many groups a new world starts with, and how many in each.
@export_range(0, 20) var starting_groups: int = 1
@export_range(1, 50) var group_min: int = 3
@export_range(1, 50) var group_max: int = 5
## Young per grown animal per day when there is plenty of room.
@export_range(0.0, 2.0, 0.005) var birth_rate: float = 0.05
## The seasons in which young are born (0 = spring). As many are born in
## a year as if they came all year round.
@export var mating_seasons: PackedInt32Array = PackedInt32Array([0])
## Does the group move to other ground when autumn and spring come?
@export var migrates: bool = false
## Game days until a young one is grown, and how long one lives.
@export_range(1, 2000) var adult_days: int = 24
@export_range(1, 5000) var lifespan_days: int = 240

@export_group("Movement")
## Tiles per game minute, ambling and running.
@export_range(0.05, 10.0, 0.05) var walk_speed: float = 0.5
@export_range(0.05, 10.0, 0.05) var run_speed: float = 1.6
## How far from where the group lives they stray, in tiles.
@export_range(1.0, 64.0, 0.5) var home_range: float = 9.0
## People and predators nearer than this make them run (someone stalking
## them is noticed from much nearer: AnimalSystem.STALKED_SHARE).
@export_range(0.0, 32.0, 0.25) var fear_radius: float = 5.0
## Sleeps from this hour to that hour (a fox sleeps by day).
@export_range(0.0, 24.0, 0.25) var sleep_from: float = 21.0
@export_range(0.0, 24.0, 0.25) var sleep_to: float = 5.0

@export_group("Hunted")
## Units of meat one gives (0 = not hunted by people).
@export_range(0, 100) var meat: int = 0
## People leave them alone when there are fewer than this share of what
## the box holds.
@export_range(0.0, 1.0, 0.01) var hunt_above: float = 0.5

@export_group("Hunting")
## Species it preys on, how often it needs a kill (game days), how likely a
## pounce succeeds where prey is plentiful, and how many of it one prey
## animal's presence supports.
@export var prey: PackedStringArray = PackedStringArray()
@export_range(0.25, 30.0, 0.25) var hunts_every_days: float = 2.0
@export_range(0.0, 1.0, 0.01) var pounce_success: float = 0.6
@export_range(0.0, 5.0, 0.01) var per_prey: float = 0.25

@export_group("Body")
## Height and radius in tiles of a grown one (for drawing and for a finger).
@export_range(0.05, 3.0, 0.01) var height: float = 0.6
@export_range(0.05, 2.0, 0.01) var radius: float = 0.3
@export var color: Color = Color(0.6, 0.45, 0.3)
## Which shape it is drawn with (AnimalMeshLibrary): "deer", "rabbit", "fox".
@export var shape: StringName = &""


## Are young born in this season?
func mates_in(season: int) -> bool:
	return mating_seasons.is_empty() or mating_seasons.has(season)


## How many times the yearly rate births come at in a mating season (they
## are all the year's births).
func mating_boost() -> float:
	return 4.0 / mating_seasons.size() if not mating_seasons.is_empty() else 1.0


func is_hunted() -> bool:
	return meat > 0 and not aggregate


func preys_on(species: StringName) -> bool:
	return prey.has(String(species))


## Is it the hour for sleeping?
func sleeps_at(hour: float) -> bool:
	if sleep_from == sleep_to:
		return false
	if sleep_from < sleep_to:
		return hour >= sleep_from and hour < sleep_to
	return hour >= sleep_from or hour < sleep_to


func validate() -> PackedStringArray:
	var problems := PackedStringArray()
	if id == &"":
		problems.append("a species without an id")
	if group_min > group_max:
		problems.append("%s: group_min must not be more than group_max" % id)
	if walk_speed > run_speed:
		problems.append("%s: it cannot amble faster than it runs" % id)
	if adult_days >= lifespan_days:
		problems.append("%s: it must live longer than it takes to grow up" % id)
	if diet == Diet.PREDATOR and prey.is_empty():
		problems.append("%s: a predator needs prey" % id)
	return problems
