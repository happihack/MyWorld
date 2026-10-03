class_name RelationshipsConfig
extends ConfigBase
## What people are to each other and how that changes (bible §16.1, M10.1).

@export_group("The store")
## Nobody keeps more relationships than this (the weakest are forgotten; never family).
@export_range(4, 200) var most_per_person: int = 30

@export_group("What the values make of a pair")
## Acquaintances from this familiarity.
@export_range(0.0, 1.0, 0.01) var acquaintance_from: float = 0.2
## Friends from this affinity (knowing each other at least this well), no longer below `friend_until`.
@export_range(0.0, 1.0, 0.01) var friend_from: float = 0.45
@export_range(0.0, 1.0, 0.01) var friend_familiarity: float = 0.5
@export_range(0.0, 1.0, 0.01) var friend_until: float = 0.3
## Rivals from this affinity down, no longer above `rival_until`; enemies likewise.
@export_range(-1.0, 0.0, 0.01) var rival_from: float = -0.35
@export_range(-1.0, 0.0, 0.01) var rival_until: float = -0.2
@export_range(-1.0, 0.0, 0.01) var enemy_from: float = -0.7
@export_range(-1.0, 0.0, 0.01) var enemy_until: float = -0.5

@export_group("Time")
## Feelings go this share of the way back to where they began in a day
## (nothing for strangers, `family_affinity` for family).
@export_range(0.0, 1.0, 0.005) var affinity_fade_per_day: float = 0.03
## Who has not met for this many days knows the other this much less each day.
@export_range(0.0, 60.0, 0.5) var strange_after_days: float = 6.0
@export_range(0.0, 0.2, 0.001) var familiarity_fade_per_day: float = 0.01

@export_group("A new band")
## Family (and one household) know each other this well and like each other this
## much; everyone else in the band knows everyone a little.
@export_range(0.0, 1.0, 0.01) var family_familiarity: float = 0.9
@export_range(0.0, 1.0, 0.01) var family_affinity: float = 0.35
@export_range(0.0, 1.0, 0.01) var band_familiarity: float = 0.4

@export_group("What happens when they are together")
## Each time two talk they know each other this much better.
@export_range(0.0, 0.5, 0.005) var familiarity_per_talk: float = 0.04
## A good talk, a hand at work, a gift, a lesson, a flirt: affinity (and the
## rest) gained, before compatibility (×0.5 for those who could not be
## less alike … ×1.5 for those who could not be more).
@export_range(0.0, 0.5, 0.005) var talk_affinity: float = 0.03
## A talk brings people closer only if they suit each other at least this
## well (compatibility); below, it wears on them.
@export_range(0.0, 1.0, 0.01) var talk_suits_from: float = 0.7
@export_range(0.0, 0.5, 0.005) var help_affinity: float = 0.05
@export_range(0.0, 0.5, 0.005) var gift_affinity: float = 0.08
@export_range(0.0, 0.5, 0.005) var teach_respect: float = 0.06
@export_range(0.0, 0.5, 0.005) var flirt_romance: float = 0.1
## A quarrel, a fight: affinity lost (more between those unlike each other),
## and the health a fight costs each of them.
@export_range(0.0, 1.0, 0.005) var argue_affinity: float = 0.16
@export_range(0.0, 1.0, 0.005) var fight_affinity: float = 0.22
@export_range(0.0, 0.5, 0.005) var fight_health: float = 0.04
## How much a lesson teaches (skill, 0 … 1).
@export_range(0.0, 0.2, 0.001) var teach_skill: float = 0.02
## A quarrel turns into a fight only between those who dislike each other
## this much (and one of them aggressive), this often.
@export_range(-1.0, 0.0, 0.01) var fight_below: float = -0.35
@export_range(0.0, 1.0, 0.01) var fight_chance: float = 0.25


func validate() -> PackedStringArray:
	var p := PackedStringArray()
	_check(p, friend_until < friend_from, "friend_until must be below friend_from")
	_check(p, rival_until > rival_from and enemy_until > enemy_from, "rivals and enemies need some give: _until above _from")
	_check(p, enemy_from < rival_from, "enemies must be further down than rivals")
	return p
