class_name Dependence
extends RefCounted
## What a settlement has come to expect of the Presence (bible §24: repeated
## help → dependence; the plan's BLESSINGS section, steps 5 and 6). Derived,
## never a counter: from the blessings its land lived through in the last
## year, as the world wrote them down (EventLog). A settlement blessed with
## the same gift twice in a year expects it — and (step 6) plants fewer
## fields after a bounty, takes up no nets after a full river, and goes
## hungry when the gifts stop.

## Blessed this often with one kind in a year, a settlement expects it.
const EXPECTS_FROM := 2
## The gifts that can be expected (the lights change nothing to live by).
const GIFTS: Array[StringName] = [&"bounty_of_bushes", &"rich_soil", &"teeming_waters", &"healing"]
## How far from its fire a gift counts as the settlement's (the blessing's
## reach, and the walk to the bushes and the bank beyond it).
const NEAR := BlessingSystem.REACH + 6.0


## How many times each gift fell on `own`'s land in the year before `now`:
## {event type: count}, only the kinds that did.
static func gifts_in_year(s: WorldSession, own: Settlement, now: int) -> Dictionary:
	var out := {}
	if s == null or s.events == null or own == null:
		return out
	var fire := own.fire()
	if fire == null:
		return out
	var there := fire.position2d()
	for gift in GIFTS:
		var count := 0
		for event in s.events.of_type(gift, now - Config.time.ticks_per_year(), now):
			if event.position.is_finite() and event.position.distance_to(there) <= NEAR:
				count += 1
		if count > 0:
			out[gift] = count
	return out


## The gifts `own` has come to expect: those that fell EXPECTS_FROM times or
## more in the year before `now`, in the order of GIFTS.
static func expects(s: WorldSession, own: Settlement, now: int) -> Array[StringName]:
	var out: Array[StringName] = []
	var counts := gifts_in_year(s, own, now)
	for gift in GIFTS:
		if int(counts.get(gift, 0)) >= EXPECTS_FROM:
			out.append(gift)
	return out


## In words, for the Beliefs page: "Ama's camp has come to expect the fruit".
static func lines(s: WorldSession, now: int) -> PackedStringArray:
	var out := PackedStringArray()
	if s == null or s.settlements == null:
		return out
	for own in s.settlements.all():
		for gift in expects(s, own, now):
			out.append(MemoryText.translate("DEPEND_" + String(gift).to_upper()).format({"place": own.display_name()}))
	return out
