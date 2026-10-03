class_name SignificanceConfig
extends ConfigBase
## How much people matter to the world's history (bible §21.5, M11.2).
## A person's significance is a sum of points: what they took part in, as
## much as each event matters (EventDef.significance, data/events), and the
## firsts among them.

## The first of an event's participants (who did it, to whom it happened
## most) gains this share of its significance; the others this.
@export_range(0.0, 2.0, 0.01) var principal_share: float = 1.0
@export_range(0.0, 2.0, 0.01) var other_share: float = 0.4
## Being the first of something (an event marked "first": the first child
## born, the first touch …) is worth this much more to its principal.
@export_range(0.0, 3.0, 0.05) var first_bonus: float = 0.5
## From this many points someone is one of the Important People (spoken of
## in the settlement, listed in the menu).
@export_range(0.1, 50.0, 0.1) var important_from: float = 2.5
## What matters less than this adds nothing (a day's hunt, a chat): history
## is made of what stands out.
@export_range(0.0, 1.0, 0.01) var least_counted: float = 0.35
## The same kind of thing again counts less each time: the n-th time,
## 1 / (1 + `repeat_wear` × (n − 1)) of it.
@export_range(0.0, 5.0, 0.05) var repeat_wear: float = 0.5
## Being touched by the Presence is worth this much, each time (bible §16.3:
## "touched by the Presence 20 times may become a historical figure").
@export_range(0.0, 1.0, 0.01) var presence_touch: float = 0.15
## What adds nothing: what merely happened to someone, or what is told of
## their life elsewhere (being born, coming of age, a scratch, an illness,
## their own death) — and a person's own life with others (friends, quarrels,
## fights, partners, making up, being taken in): theirs, not history's.
@export var not_counted: PackedStringArray = PackedStringArray(["person_born", "came_of_age", "person_injured",
	"person_ill", "person_hungry_sick", "person_cold_sick", "person_recovered", "person_died", "became_important",
	"food_spoiled", "became_friends", "fell_out", "became_enemies", "reconciled", "fight", "became_partners", "taken_in"])


func validate() -> PackedStringArray:
	var p := PackedStringArray()
	_check(p, important_from > 0.0, "important_from must be above 0")
	return p
