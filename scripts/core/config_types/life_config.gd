class_name LifeConfig
extends ConfigBase
## A life from beginning to end (bible §16.2, M10.2): who becomes partners,
## when children come, what ails people and how they heal, and how and when
## they die. (A game year is TimeConfig.days_per_year() days; "per year"
## rates are spread over its days.)

@export_group("Partners")
## Two grown-ups (both free, not of one family) become partners once romance
## between them is at least this and they like each other at least this much …
@export_range(0.0, 1.0, 0.01) var partner_romance: float = 0.3
@export_range(-1.0, 1.0, 0.01) var partner_affinity: float = 0.1
## … and are no more than this many years apart; each day it may happen, it
## happens this often.
@export_range(0, 60) var partner_most_years_apart: int = 14
@export_range(0.0, 1.0, 0.01) var partner_chance_per_day: float = 0.25

@export_group("Children")
## A woman with a partner may be with child from adulthood until this age …
@export_range(1, 80) var fertile_until_years: int = 40
## … this often a day, when the household has a roof with room under it and
## the settlement has food for at least `food_days_for_child` days and no
## shortage; not again within `child_gap_days` of the last birth.
@export_range(0.0, 1.0, 0.001) var conceive_chance_per_day: float = 0.02
@export_range(0.0, 60.0, 0.5) var food_days_for_child: float = 1.0
@export_range(0, 500) var child_gap_days: int = 36
## How long a child is carried (game days).
@export_range(1, 200) var carry_days: int = 18
## How many live under one roof before it is crowded (no children are had
## in a crowded home, and crowding breeds illness).
@export_range(1, 30) var home_room: int = 6
## A child is named after a forebear (one of the same sex no one living
## bears the name of) this often.
@export_range(0.0, 1.0, 0.01) var named_after_forebear: float = 0.25
## A child takes its family name from the father (true) or the mother.
@export var family_name_from_father: bool = true

@export_group("Newcomers")
## A band is small: when a grown-up (no older than this) has nobody they could
## become partners with, and there is room under the roofs, someone from far
## away may come to live with them — this often a day.
@export_range(0, 150) var lonely_until_years: int = 40
@export_range(0.0, 1.0, 0.001) var newcomer_chance_per_day: float = 0.03
## What is between the newcomer and the one they came for, to begin with
## (familiarity, affinity and romance).
@export_range(0.0, 1.0, 0.01) var newcomer_spark: float = 0.2

@export_group("Death")
## The chance of dying in a year, apart from anything that ails them: a
## little for everyone, more for the very young …
@export_range(0.0, 1.0, 0.001) var base_death_per_year: float = 0.004
@export_range(0.0, 1.0, 0.001) var infant_death_per_year: float = 0.02
@export_range(0, 10) var infant_years: int = 2
## … and from this age on, for old age: this much at that age, doubling every
## `old_age_doubling_years`.
@export_range(1, 150) var old_age_from_years: int = 52
@export_range(0.0, 1.0, 0.001) var old_age_death_per_year: float = 0.05
@export_range(0.5, 50.0, 0.5) var old_age_doubling_years: float = 6.0
## Ill health makes all of it likelier: × (1 + frailty × (1 − health)²).
@export_range(0.0, 50.0, 0.5) var frailty: float = 6.0
## Weak with hunger, at the end of their strength, for longer than this
## (game days): they may starve, this often a day.
@export_range(0.0, 60.0, 0.5) var starving_after_days: float = 3.0
@export_range(0.0, 1.0, 0.005) var starve_chance_per_day: float = 0.06

@export_group("Injuries")
## How much health an injury of severity 1 takes at once, and how much of a
## severity heals in a day (twice as fast for someone resting).
@export_range(0.0, 1.0, 0.01) var injury_health: float = 0.5
@export_range(0.0, 1.0, 0.005) var injury_heal_per_day: float = 0.08
@export_range(1.0, 5.0, 0.1) var rest_heals: float = 2.0
## A severe injury (above this) may kill, this often a day for severity 1.
@export_range(0.0, 1.0, 0.01) var grave_injury_from: float = 0.6
@export_range(0.0, 1.0, 0.005) var injury_death_per_day: float = 0.03
## How badly a fight hurts (each of them), and how often a day at work ends in
## an accident (a fall, a cut: severity 0.15 … 0.7).
@export_range(0.0, 1.0, 0.01) var fight_injury: float = 0.2
@export_range(0.0, 0.1, 0.0005) var accident_per_work_day: float = 0.004

@export_group("Illness")
## Drinking from a puddle or floodwater makes someone ill this often; each
## day under a crowded roof, each one there falls ill this often for each
## person too many.
@export_range(0.0, 1.0, 0.01) var bad_water_chance: float = 0.15
@export_range(0.0, 1.0, 0.005) var crowding_chance_per_day: float = 0.01
## An illness takes this much health a day until it passes; it passes this
## often a day (more often for someone resting: `rest_heals`).
@export_range(0.0, 1.0, 0.005) var illness_health_per_day: float = 0.06
@export_range(0.0, 1.0, 0.005) var illness_passes_per_day: float = 0.2
## Health does not fall below this from illness alone, but someone this
## weak may die of it, this often a day.
@export_range(0.0, 1.0, 0.01) var illness_floor: float = 0.15
@export_range(0.0, 1.0, 0.005) var illness_death_per_day: float = 0.04

@export_group("Behaviour")
## Someone hurt or ill goes home to rest: this much more speaks for it
## (× how unwell, 0 … 1), and work and play speak this much less.
@export_range(0.0, 2.0, 0.01) var unwell_rest_weight: float = 0.5
@export_range(0.0, 1.0, 0.01) var unwell_work_cut: float = 0.6

@export_group("Mourning")
## Those close to someone who died grieve for this many days (× how close:
## 1 for a partner, child or parent), their mood this much lower at first.
@export_range(0.0, 120.0, 0.5) var grief_days: float = 12.0
@export_range(0.0, 1.0, 0.01) var grief_mood: float = 0.35
## How much grief draws them to the grave (× how much they grieve now).
@export_range(0.0, 2.0, 0.01) var visit_grave_weight: float = 0.5

@export_group("Inheritance")
## What a parent leaves their children (or partner, or brothers and sisters):
## their few most important memories, at this share of their weight.
@export_range(0, 20) var memories_left: int = 3
@export_range(0.0, 1.0, 0.01) var inherited_share: float = 0.6


func validate() -> PackedStringArray:
	var p := PackedStringArray()
	_check(p, carry_days < child_gap_days, "carry_days must be less than child_gap_days")
	_check(p, illness_floor < 1.0, "illness_floor must be below 1")
	return p
