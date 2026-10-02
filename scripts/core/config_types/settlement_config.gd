class_name SettlementConfig
extends ConfigBase
## A settlement's housekeeping: what it wants in store, what its fire burns,
## and how its job board calls people to work (bible §17).

@export_group("Stores")
## What a person eats in a day, in "bellies" (a belly = hunger from empty to
## full; see ResourceDef.nutrition). From how fast hunger runs down
## (NeedsConfig): about 1.5 awake and at work, a little asleep.
@export_range(0.1, 10.0, 0.05) var food_per_person_day: float = 1.7
## How many days of food the settlement wants in store; below it, the job
## board calls for foraging.
@export_range(0.1, 30.0, 0.1) var food_days_wanted: float = 2.0
## Likewise for the wood its fire burns.
@export_range(0.1, 30.0, 0.1) var wood_days_wanted: float = 3.0
## What a new settlement starts with.
@export_range(0.0, 30.0, 0.1) var starting_food_days: float = 1.0
@export_range(0, 1000) var starting_wood: int = 6

@export_group("Before winter")
## From this many days before winter the settlement wants more in store:
## by winter's first day this many times as much food, and wood. (In
## winter itself: half way between that and the usual.)
@export_range(0.0, 60.0, 0.5) var winter_prepare_days: float = 6.0
@export_range(1.0, 10.0, 0.1) var winter_food_factor: float = 2.0
@export_range(1.0, 10.0, 0.1) var winter_wood_factor: float = 2.0

@export_group("Shortage")
## With less than this many days of food in store for this many game
## minutes, the settlement is short of food: it rations, and forages further.
@export_range(0.0, 10.0, 0.05) var shortage_below_days: float = 0.4
@export_range(0, 10000) var shortage_after_minutes: int = 180
## The shortage is over with this many days of food in store again.
@export_range(0.1, 30.0, 0.05) var shortage_over_days: float = 1.0
## With nothing at all in store for this many game minutes it eats what
## it kept for seed.
@export_range(0, 10000) var empty_after_minutes: int = 180
## Rationing: the share of a day's food each person gets from the stores.
@export_range(0.05, 1.0, 0.01) var ration_share: float = 0.6
## Short of food, people go this many times as far for berries.
@export_range(1.0, 4.0, 0.05) var forage_further_factor: float = 1.75
## The bushes around the settlement are "picked bare" when this share of
## them has nothing on it, and have recovered at this share.
@export_range(0.0, 1.0, 0.01) var forage_low_share: float = 0.6
@export_range(0.0, 1.0, 0.01) var forage_recovered_share: float = 0.3

@export_group("Farming")
## A settlement with at least this many grown people who gather for a
## living, and nobody farming, has one of them take up farming (in a
## season for sowing).
@export_range(1, 100) var farmer_from_gatherers: int = 3
## How pressing the field work is for a farmer with nothing particular to
## do on it (so that there is always a reason to look after the field).
@export_range(0.0, 1.0, 0.01) var field_job_floor: float = 0.0

@export_group("Hunting")
## A settlement with at least this many grown gatherers, game to hunt and
## nobody hunting has one of them take it up.
@export_range(1, 100) var hunter_from_gatherers: int = 4
## Hunters go after game within this many tiles of the fire.
@export_range(4.0, 128.0, 1.0) var hunt_radius: float = 28.0

@export_group("Fire")
## Pieces of wood the fire burns in a day. Without wood it goes out.
@export_range(0.0, 100.0, 0.5) var fire_wood_per_day: float = 6.0

@export_group("Job board")
## How often the board is brought up to date, in game minutes.
@export_range(1, 1440) var job_check_minutes: int = 30
## How much a job that is not one's own trade counts, and how pressing
## (priority 0 … 1) it must be before others take it up at all.
@export_range(0.0, 1.0, 0.01) var other_trade_factor: float = 0.5
@export_range(0.0, 1.0, 0.01) var urgent_from: float = 0.8
## Keeping the fire is always there to do, this pressing.
@export_range(0.0, 1.0, 0.01) var fire_job_priority: float = 0.5
## What work is worth to someone when the board has nothing for them, and
## when it has something as pressing as can be (multiplies the work
## activity's score; in between by how pressing).
@export_range(0.0, 2.0, 0.01) var work_without_jobs: float = 0.8
@export_range(0.0, 2.0, 0.01) var work_with_urgent_job: float = 1.1


func validate() -> PackedStringArray:
	var p := PackedStringArray()
	_check(p, food_per_person_day > 0.0, "food_per_person_day must be more than nothing")
	_check(p, food_days_wanted > 0.0 and wood_days_wanted > 0.0, "the days wanted in store must be more than nothing")
	_check(p, work_without_jobs <= work_with_urgent_job, "work_without_jobs must not be more than work_with_urgent_job")
	_check(p, job_check_minutes >= 1, "job_check_minutes must be at least 1")
	_check(p, shortage_below_days < shortage_over_days, "shortage_below_days must be less than shortage_over_days")
	_check(p, forage_recovered_share < forage_low_share, "forage_recovered_share must be less than forage_low_share")
	return p
