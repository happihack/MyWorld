class_name Weapons
extends RefCounted
## Weapons as made things (PR6; the owner, 2026-10-08: W1 made things, W2 they
## count in war, W3 bows now, W4 metal points wait for ore). The toolmaker
## makes them at the workshop — spears of wood and stone, and once Archery is
## known, bows of wood and hide — and they are kept in the stores like tools.
## Hunters and hunting parties take the best there is when they go out (a
## party carries them off and brings them back; a hunter's throw borrows one);
## they break now and then. Without one, a person makes do with a sharpened
## stick of their own (NONE).
##
## Each kind: "hit" (added to the chance of a throw or a thrust), "damage" (a
## blow, in a beast's strength), "guard" (the share of a wound it keeps off —
## a bow keeps a beast furthest off), "reach" (tiles a hunter throws or shoots
## from), "arms" (what it counts for in war, 0 … 1), "breaks" (the chance a
## use), "carried" (how it is drawn: PersonMeshLibrary).

const NONE := &""
const SPEARS := &"spears"
const BOWS := &"bows"
## Best first.
const KINDS: Array[StringName] = [BOWS, SPEARS]

const STATS := {
	&"": {"hit": 0.0, "damage": 0.7, "guard": 0.15, "reach": 2.6, "arms": 0.0, "breaks": 0.0, "carried": &"spear"},
	&"spears": {"hit": 0.1, "damage": 1.0, "guard": 0.3, "reach": 2.6, "arms": 0.7, "breaks": 0.02, "carried": &"spear"},
	&"bows": {"hit": 0.15, "damage": 0.9, "guard": 0.55, "reach": 5.0, "arms": 1.0, "breaks": 0.015, "carried": &"bow"},
}
## What one is made of.
const MATERIALS := {&"spears": {&"wood": 1, &"stone": 1}, &"bows": {&"wood": 2, &"hide": 1}}
## How many are wanted: one for every hunter and PARTY_PLACES more (a party's
## worth, PR4); bows (Archery) for the hunters and BOW_PARTY_PLACES of a party.
const PARTY_PLACES := 4
const BOW_PARTY_PLACES := 2
## A battle (FC6 to come; ConflictSystem now): a side's fall chance is
## FALL × (1 + WAR_EDGE × (their arms − ours)), arms the share of its grown
## armed, by what with. Each battle costs a side this share of its weapons.
const WAR_EDGE := 0.6
const WAR_WEAR := 0.1


static func stat(kind: StringName, what: String) -> Variant:
	return (STATS.get(kind, STATS[NONE]) as Dictionary)[what]


## The best kind in `own`'s stores (NONE: none there).
static func best_in(own: Settlement) -> StringName:
	if own == null:
		return NONE
	for kind in KINDS:
		if own.stockpile.available(kind) > 0:
			return kind
	return NONE


## Takes the best `count` weapons out of the stores (best first; NONE for each
## that is not there).
static func take(own: Settlement, count: int) -> Array[StringName]:
	var out: Array[StringName] = []
	for i in count:
		var kind := best_in(own)
		if kind != NONE:
			own.stockpile.take(kind, 1)
		out.append(kind)
	return out


## Puts weapons back into the stores.
static func give_back(own: Settlement, kinds: Array) -> void:
	if own == null:
		return
	for kind: Variant in kinds:
		if StringName(str(kind)) != NONE:
			own.stockpile.add(StringName(str(kind)), 1)


## How many of `kind` `own` wants in store.
static func wanted(own: Settlement, kind: StringName) -> int:
	if own == null or not own.knows_how(&"toolmaking"):
		return 0
	match kind:
		SPEARS:
			return own.hunter_count() + PARTY_PLACES - (BOW_PARTY_PLACES if own.knows_how(&"archery") else 0)
		BOWS:
			return own.hunter_count() + BOW_PARTY_PLACES if own.knows_how(&"archery") else 0
	return 0


## The kind most short of what is wanted, whose wood and hide are in store
## (stone is fetched for it if need be); NONE: none wanted, or nothing to make it of.
static func most_wanted(own: Settlement) -> StringName:
	var best := NONE
	var short := 0
	for kind in KINDS:
		var lacking := wanted(own, kind) - own.stockpile.amount(kind)
		if lacking > short and can_make(own, kind, false):
			best = kind
			short = lacking
	return best


## Are its materials in store? (`with_stone` false: stone can be fetched.)
static func can_make(own: Settlement, kind: StringName, with_stone: bool = true) -> bool:
	var needs: Dictionary = MATERIALS.get(kind, {})
	if needs.is_empty():
		return false
	for resource: StringName in needs:
		if resource == &"stone" and not with_stone:
			continue
		if own.stockpile.available(resource) < int(needs[resource]):
			return false
	return true


## Makes one from the stores. False when the materials are not there.
static func make(own: Settlement, kind: StringName) -> bool:
	if not can_make(own, kind):
		return false
	var needs: Dictionary = MATERIALS[kind]
	for resource: StringName in needs:
		own.stockpile.take(resource, int(needs[resource]))
	own.stockpile.add(kind, 1)
	return true


## A weapon used once: perhaps it breaks (out of the stores, or out of the
## hands it is in). True: it broke.
static func used(kind: StringName, rng: RandomNumberGenerator) -> bool:
	return kind != NONE and rng != null and rng.randf() < float(stat(kind, "breaks"))


## How well armed `own`'s grown are, 0 … 1: the best weapons in store shared
## out among them (a bow counts 1, a spear 0.7, nothing 0).
static func arms_of(own: Settlement, grown: int) -> float:
	if own == null or grown <= 0:
		return 0.0
	var left := grown
	var sum := 0.0
	for kind in KINDS:
		var have := mini(own.stockpile.amount(kind), left)
		sum += have * float(stat(kind, "arms"))
		left -= have
	return sum / grown


## A battle has worn a side's weapons: WAR_WEAR of each kind lost (the
## fraction by `roll`, 0 … 1: one more, or not).
static func worn_in_battle(own: Settlement, roll: float) -> void:
	for kind in KINDS:
		var have := own.stockpile.amount(kind)
		if have <= 0:
			continue
		var lost := floori(have * WAR_WEAR)
		if roll < have * WAR_WEAR - lost:
			lost += 1
		if lost > 0:
			own.stockpile.take(kind, lost)
