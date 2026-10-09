class_name MigrationConfig
extends ConfigBase
## Migration and new settlements (bible §17.1, M12.3): what drives people to
## leave, who goes, where, and how a new settlement begins.

@export_group("What drives people away")
## Only a settlement of at least this many sends anyone away.
@export_range(2, 200) var least_people: int = 24 # (10 split every hamlet before it could grow: the 200-year soaks)
## The roofs: from this few places left under them, crowding drives people
## (at no place left, as much as `crowding`).
@export_range(0, 20) var crowded_from_spare: int = 2
@export_range(0.0, 2.0, 0.01) var crowding: float = 0.6
## A settlement this big feels it whatever its roofs: as much as `size`.
@export_range(2, 1000) var big_from: int = 60
@export_range(0.0, 2.0, 0.01) var size: float = 0.4
## Food short this many days on end, as much as `scarcity`.
@export_range(1, 60) var scarce_days: int = 4
@export_range(0.0, 2.0, 0.01) var scarcity: float = 0.5
## Rivals or enemies within the settlement (each pair), as much as this, up to `conflict_most`.
@export_range(0.0, 1.0, 0.01) var conflict_per_pair: float = 0.15
@export_range(0.0, 2.0, 0.01) var conflict_most: float = 0.5
## Floods lived through in the last `disaster_days` days (each), as much as this.
@export_range(0.0, 1.0, 0.01) var disaster_per_flood: float = 0.2
@export_range(1, 1000) var disaster_days: int = 72
## The adventurous: a household as adventurous as can be adds this much.
@export_range(0.0, 2.0, 0.01) var adventure: float = 0.4
## From this much (all of the above) a group may set out; then, each day,
## with this chance for each unit of it.
@export_range(0.0, 5.0, 0.01) var leave_from: float = 0.6
@export_range(0.0, 1.0, 0.001) var chance_per_day: float = 0.06
## After people have set out from a settlement, nobody does again for this many days.
@export_range(0, 10000) var rest_days: int = 96
## At most this many settlements in the world.
@export_range(1, 64) var most_settlements: int = 4

@export_group("Who goes")
## A group that founds a settlement is at least `households_least`
## households (at most `most_households`) and `group_least` people, with a
## man and a woman grown among them; at least `stay_least` stay behind.
## (Founded camps are to last: one family alone does not.)
@export_range(1, 4) var most_households: int = 3
@export_range(1, 4) var households_least: int = 2
@export_range(2, 30) var group_least: int = 5
@export_range(1, 100) var stay_least: int = 6

@export_group("Young camps and the last few")
## A settlement of fewer than this many is a young camp: those who leave a
## crowded settlement join it rather than found yet another, and newcomers
## come to its lonely `newcomer_boost` times as readily.
@export_range(1, 100) var small_from: int = 10
@export_range(1.0, 20.0, 0.5) var newcomer_boost: float = 3.0
## A settlement cannot grow when it has no grown-up under elder age, or fewer
## than this many and no couple young enough for children: its last few go
## to live at the nearest settlement that can.
@export_range(1, 50) var viable_least: int = 4

@export_group("Where to")
## Only ground someone has explored. At least this far from every
## settlement's fire, at most this far from the one they leave.
@export_range(4.0, 200.0) var nearest_settlement: float = 14.0
@export_range(4.0, 400.0) var farthest_journey: float = 40.0
## Water within this many tiles (but not on the bank), trees within `tree_reach`.
@export_range(1.0, 40.0) var water_within: float = 10.0
@export_range(1, 20) var tree_reach: int = 6
## Its ground at least this far above the highest water near it (world units).
@export_range(0.0, 4.0, 0.01) var flood_clear: float = 0.1
## A settlement that would send people out but knows of nowhere for them
## scouts: its grown explore this many tiles further.
@export_range(0.0, 60.0) var scout_further: float = 16.0

@export_group("The journey and the founding")
## A journey that takes longer than this (game minutes) ends where they are.
@export_range(60, 10000) var longest_journey: int = 720
## What they take: this many days of food for each of them (at most
## `food_share` of what is in store), and this much wood.
@export_range(0.0, 30.0, 0.1) var food_days: float = 3.0
@export_range(0.0, 1.0, 0.01) var food_share: float = 0.4
@export_range(0, 100) var wood: int = 14


func validate() -> PackedStringArray:
	var p := PackedStringArray()
	_check(p, nearest_settlement < farthest_journey, "nearest_settlement must be below farthest_journey")
	return p
