class_name PileStore
extends RefCounted
## Resource piles (bible §11): what has been gathered lies in the world as
## heaps — loose objects (LooseObject.Kind.PILE) that hold an amount of one
## resource, grow and shrink with it, and can be moved by the player like
## anything else that lies about. A settlement's stores are the piles at its
## storage places: carry a pile away and it is no longer theirs.

## Something was put down on a pile.
signal stored(resource: StringName, amount: int, pile_id: int)
## Something was taken from a pile.
signal taken(resource: StringName, amount: int, pile_id: int)

## Where piles lie on a storage tile, from its middle.
const SLOTS: Array[Vector2] = [
	Vector2(-0.27, -0.27), Vector2(0.27, -0.27), Vector2(0.0, 0.05), Vector2(-0.27, 0.3), Vector2(0.27, 0.3),
	Vector2(0.0, -0.4), Vector2(-0.4, 0.0), Vector2(0.4, 0.0), Vector2(0.0, 0.42),
]
## Two piles are not put closer together than this.
const SLOT_CLEARANCE := 0.24

var _loose: LooseObjectRegistry
var _ids: IdAllocator
var _library: ResourceLibrary
var _config: ResourcesConfig


func bind(loose: LooseObjectRegistry, ids: IdAllocator, library: ResourceLibrary, config: ResourcesConfig = null) -> void:
	_loose = loose
	_ids = ids
	_library = library
	_config = config if config != null else Config.resources


## The piles of `resource` (&"" = of anything) within `radius` of `center`
## (everywhere, if no centre is given), the fullest first.
func piles(resource: StringName = &"", center: Vector2 = Vector2.INF, radius: float = INF) -> Array[LooseObject]:
	var out: Array[LooseObject] = []
	if _loose == null:
		return out
	for object in _loose.all_objects():
		if object.kind != LooseObject.Kind.PILE or (resource != &"" and object.resource != resource):
			continue
		if center != Vector2.INF and object.position.distance_to(center) > radius:
			continue
		out.append(object)
	out.sort_custom(func(a: LooseObject, b: LooseObject) -> bool:
		return a.amount > b.amount or (a.amount == b.amount and a.id < b.id))
	return out


## How much of `resource` lies in piles within `radius` of `center`.
func total(resource: StringName, center: Vector2 = Vector2.INF, radius: float = INF) -> int:
	var sum := 0
	for pile in piles(resource, center, radius):
		sum += pile.amount
	return sum


## Everything in piles within `radius` of `center`: resource -> amount.
func totals(center: Vector2 = Vector2.INF, radius: float = INF) -> Dictionary:
	var out := {}
	for pile in piles(&"", center, radius):
		out[pile.resource] = int(out.get(pile.resource, 0)) + pile.amount
	return out


## How much more of `resource` the storage place at `center` takes: it has
## room for so many piles (ResourcesConfig.piles_per_resource) — what its
## fullest ones still hold room for, and those not yet begun. (A pile put
## down beyond that makes no room for more.)
func room(resource: StringName, center: Vector2) -> int:
	var stack := _stack(resource)
	var there := piles(resource, center, _config.storage_radius)
	var free := maxi(_config.piles_per_resource - there.size(), 0) * stack
	for i in mini(there.size(), _config.piles_per_resource):
		free += maxi(stack - there[i].amount, 0)
	return free


## Puts `amount` of `resource` down at the storage place at `center`: onto
## piles that have room, then onto new ones. Nothing is ever lost — if the
## place is full, one more pile is made. Returns the ids of the piles it
## went onto.
func add(resource: StringName, amount: int, center: Vector2) -> Array[int]:
	var onto: Array[int] = []
	if _loose == null or resource == &"" or amount <= 0 or not is_finite(center.x) or not is_finite(center.y):
		return onto
	var stack := _stack(resource)
	var left := amount
	for pile in piles(resource, center, _config.storage_radius):
		if left <= 0:
			break
		var fits := mini(stack - pile.amount, left)
		if fits <= 0:
			continue
		pile.amount += fits
		left -= fits
		_refresh(pile)
		onto.append(pile.id)
		stored.emit(resource, fits, pile.id)
	while left > 0:
		var pile := LooseObject.new()
		pile.id = _ids.next_id()
		pile.kind = LooseObject.Kind.PILE
		pile.resource = resource
		pile.variant = LooseObject.pile_variant(resource)
		pile.amount = mini(left, stack)
		pile.scale_percent = scale_for(pile.amount, stack, _config)
		pile.position = _free_slot(center)
		pile.yaw = fposmod(float(pile.id) * 2.399963, TAU) # (each a little differently turned)
		left -= pile.amount
		if not _loose.add(pile):
			break
		onto.append(pile.id)
		stored.emit(resource, pile.amount, pile.id)
	return onto


## Takes up to `amount` of `resource` from the piles within `radius` of
## `center`, the smallest piles first (so that heaps are used up, not all
## nibbled at). Returns how much it got.
func take(resource: StringName, amount: int, center: Vector2 = Vector2.INF, radius: float = INF) -> int:
	var got := 0
	var there := piles(resource, center, radius)
	there.reverse()
	for pile in there:
		if got >= amount:
			break
		var share := mini(pile.amount, amount - got)
		got += share
		take_from(pile.id, share)
	return got


## Takes up to `amount` from one pile; an emptied pile is gone. Returns how
## much it got.
func take_from(pile_id: int, amount: int) -> int:
	var pile := _loose.get_object(pile_id) if _loose != null else null
	if pile == null or pile.kind != LooseObject.Kind.PILE or amount <= 0:
		return 0
	var share := mini(pile.amount, amount)
	pile.amount -= share
	var resource := pile.resource
	if pile.amount <= 0:
		_loose.remove(pile.id)
	else:
		_refresh(pile)
	taken.emit(resource, share, pile_id)
	return share


## How big a pile of `amount` lies there, in percent.
static func scale_for(amount: int, stack: int, config: ResourcesConfig = null) -> int:
	if config == null:
		config = Config.resources
	var share := clampf(float(amount) / float(maxi(stack, 1)), 0.0, 1.0)
	return roundi(lerpf(config.pile_scale_min, config.pile_scale_max, sqrt(share)))


func debug_text(center: Vector2 = Vector2.INF, radius: float = INF) -> String:
	var all := totals()
	var here := totals(center, radius) if center != Vector2.INF else all
	var parts := PackedStringArray()
	var names: Array = all.keys()
	names.sort_custom(func(a: StringName, b: StringName) -> bool: return String(a) < String(b))
	for resource: StringName in names:
		parts.append("%s %d/%d" % [resource, int(here.get(resource, 0)), int(all[resource])])
	return "stores (at the settlement/anywhere): %s  in %d piles" % [" ".join(parts) if not parts.is_empty() else "nothing", piles().size()]


func _stack(resource: StringName) -> int:
	var def := _library.get_def(resource) if _library != null else null
	return maxi(def.stack, 1) if def != null else 20


func _refresh(pile: LooseObject) -> void:
	pile.scale_percent = scale_for(pile.amount, _stack(pile.resource), _config)
	_loose.changed(pile.id)


## A place on the storage tile where no pile lies yet.
func _free_slot(center: Vector2) -> Vector2:
	var there := piles(&"", center, 1.5)
	for slot in SLOTS:
		var at := center + slot
		var taken_already := false
		for pile in there:
			if pile.position.distance_to(at) < SLOT_CLEARANCE:
				taken_already = true
				break
		if not taken_already:
			return at
	# All taken: beside the last one.
	return center + SLOTS[there.size() % SLOTS.size()] * 1.6
