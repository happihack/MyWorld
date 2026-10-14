class_name FishGear
extends RefCounted
## Fishing gear (FB5, bible §18.2a): nets, the racks they dry on, and fish
## traps at the bank.
##
## Nets (once a settlement knows them) are things in the stores, a fisher's
## work to make — from wood fibre, as the technology knows (no fibre or cloth
## of their own yet). A fisher with a net in store catches more; nets wear out
## with the fish they take, twice as slowly where a rack stands to dry and
## mend them on. A trap (a weir of stakes at the bank) is for a settlement
## without boats: it fills by itself through the day, a few fish, and a fisher
## empties it into the stores.

const NETS := &"nets"
## What a net is made of, and how long making one takes (game minutes).
const NET_MATERIALS := {&"wood": 2}
const NET_MINUTES := 90.0
## Fish a net takes before it is worn out (on average), and how much longer it
## lasts where a rack stands.
const NET_LIFE := 40.0
const RACK_LIFE_FACTOR := 2.0
## A trap: the fish it takes from the water before it in a day (none while the
## water is frozen), and the most it holds.
const TRAP_CATCH := 3
const TRAP_HOLDS := 8


## Nets wanted in store: one for each fisher, once nets are known.
static func nets_wanted(own: Settlement) -> int:
	if own == null or not own.knows_how(NETS):
		return 0
	return own.fisher_count()


## Should a net be made now (wanted, and the wood is there)?
static func net_to_make(own: Settlement) -> bool:
	if own == null or own.stockpile.amount(NETS) >= nets_wanted(own):
		return false
	for resource: StringName in NET_MATERIALS:
		if own.stockpile.available(resource) < int(NET_MATERIALS[resource]):
			return false
	return true


## Makes a net from the stores. False: nothing to make it of.
static func make_net(own: Settlement) -> bool:
	if own == null or not own.knows_how(NETS):
		return false
	for resource: StringName in NET_MATERIALS:
		if own.stockpile.available(resource) < int(NET_MATERIALS[resource]):
			return false
	for resource: StringName in NET_MATERIALS:
		own.stockpile.take(resource, int(NET_MATERIALS[resource]))
	own.stockpile.add(NETS, 1)
	return true


## Do the fishers of `own` fish with nets (known, and one in store)?
static func has_nets(own: Settlement) -> bool:
	return own != null and own.knows_how(NETS) and own.stockpile.amount(NETS) > 0


## `fish` caught with a net: perhaps it wears out (out of the stores). Returns
## how many nets were worn out.
static func wear_nets(own: Settlement, fish: int, rng: RandomNumberGenerator) -> int:
	if fish <= 0 or rng == null or not has_nets(own):
		return 0
	var life := NET_LIFE * (RACK_LIFE_FACTOR if has_rack(own) else 1.0)
	var worn := 0
	for i in fish:
		if rng.randf() < 1.0 / life and own.stockpile.take(NETS, 1) > 0:
			worn += 1
	return worn


static func has_rack(own: Settlement) -> bool:
	return own != null and own.planner != null and not own.planner.standing_near(PropData.Kind.NET_RACK).is_empty()


## The water a trap stands in: the deepest beside it (the planner sets it on
## the bank, facing the water). Its own tile if there is none.
static func trap_water(trap: PropData, world: WorldData) -> Vector2i:
	var best := trap.tile
	var deepest := 0.0
	for step: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
		var at := trap.tile + step
		if world != null and world.is_in_bounds(at) and world.get_water(at) > deepest:
			best = at
			deepest = world.get_water(at)
	return best


## A day of the traps: each takes fish from the water before it (as its
## fish allow), up to what it holds.
static func fill_traps(props: PropRegistry, waters: FishWaters, world: WorldData, frozen: bool) -> int:
	if props == null or waters == null or frozen:
		return 0
	var caught := 0
	for trap in props.of_kind(PropData.Kind.FISH_TRAP):
		if trap.kind != PropData.Kind.FISH_TRAP:
			continue
		var room := TRAP_HOLDS - maxi(trap.stock, 0)
		if room <= 0:
			continue
		var got := waters.take(mini(TRAP_CATCH, room), trap_water(trap, world))
		if got > 0:
			trap.stock = maxi(trap.stock, 0) + got
			props.changed(trap.id)
			caught += got
	return caught


## The trap of `own` with the most fish in it (null: none with any).
static func fullest_trap(own: Settlement, props: PropRegistry) -> PropData:
	if own == null or own.planner == null or props == null:
		return null
	var best: PropData = null
	for id in own.planner.standing_near(PropData.Kind.FISH_TRAP):
		var trap := props.get_prop(id)
		if trap != null and trap.stock > 0 and (best == null or trap.stock > best.stock):
			best = trap
	return best


## Fish taken out of a trap, up to `room`. Returns how many.
static func empty_trap(trap: PropData, props: PropRegistry, room: int) -> int:
	if trap == null or trap.stock <= 0 or room <= 0:
		return 0
	var taken := mini(trap.stock, room)
	trap.stock -= taken
	if props != null:
		props.changed(trap.id)
	return taken
