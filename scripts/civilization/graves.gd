class_name Graves
extends RefCounted
## Where the dead are laid (bible §16.3: "graves are physical, tappable
## places"). Each settlement has one cemetery (PropData.Kind.CEMETERY): a
## fenced plot a little way from its fire, opened at its first death; all its
## dead are laid there, its headstones growing with them, and reading it lists
## them all. (300-year soaks: a grave each overran the ground near the fire —
## the dead of centuries went unburied.)
##
## Older saves laid each in a grave of their own (PropData.Kind.GRAVE): on
## loading, those are gathered into cemeteries (`gather_old`).

## The cemetery is this many tiles (at least, at most) from the fire — further, if need be.
const NEAREST := 6
const FURTHEST := 12
const FURTHEST_FULL := 20
## Its plot: the tiles within this many of where it stands (kept clear).
const PLOT := 1
## Headstones shown, at most (its variant: one per death, up to this).
const MOST_STONES := 9

var _props: PropRegistry
var _world: WorldData
var _pathfinder: Pathfinder
var _start: WorldSetup.StartInfo
var _ids: IdAllocator
var _archive: HistoryArchive
var _loose: LooseObjectRegistry
## Every settlement's start (its cemetery among them): () -> Array of
## WorldSetup.StartInfo; may be unset (then only the first settlement's).
var starts: Callable
## Looking for level ground only (see site()).
var _level_only := false
## A settlement of an older save takes the cemetery within this many tiles of
## its fire for its own, if no other settlement has (M12.3).
const GRAVEYARD_REACH := 14.0


func bind(props: PropRegistry, world: WorldData, pathfinder: Pathfinder, start: WorldSetup.StartInfo, ids: IdAllocator,
		archive: HistoryArchive, loose: LooseObjectRegistry = null) -> void:
	_props = props
	_world = world
	_pathfinder = pathfinder
	_start = start
	_ids = ids
	_archive = archive
	_loose = loose


## Every place the dead lie — the cemeteries (and any single grave of an older
## save not yet gathered) — ids, in order.
func all_graves() -> Array[int]:
	var out: Array[int] = []
	if _props == null:
		return out
	for prop in _props.all_props():
		if prop.kind == PropData.Kind.CEMETERY or prop.kind == PropData.Kind.GRAVE:
			out.append(prop.id)
	out.sort()
	return out


## The cemeteries (ids, in order).
func cemeteries() -> Array[int]:
	var out: Array[int] = []
	if _props == null:
		return out
	for prop in _props.all_props():
		if prop.kind == PropData.Kind.CEMETERY:
			out.append(prop.id)
	out.sort()
	return out


## How many of the dead lie somewhere that is still there.
func laid_count() -> int:
	if _archive == null or _props == null:
		return 0
	var count := 0
	for record in _archive.all_records():
		if record.grave_id != 0 and _props.get_prop(record.grave_id) != null:
			count += 1
	return count


## Lays someone who has died (they are in the archive) in their settlement's
## cemetery — opening one, if it has none. Returns its id (0: nowhere to lay them).
## (`start`: the settlement the dead belonged to — the first, if not given.)
func bury(person_id: int, start: WorldSetup.StartInfo = null) -> int:
	if _props == null or _start == null or _archive == null or _archive.get_record(person_id) == null:
		return 0
	var own := start if start != null else _start
	var cemetery := cemetery_of(own)
	if cemetery == null:
		var tile: Variant = site(own)
		if tile == null:
			return 0
		cemetery = _open(tile)
		if cemetery == null:
			return 0
		own.cemetery_id = cemetery.id
	_lay(person_id, cemetery)
	return cemetery.id


## The cemetery of the settlement of `start` (null: none yet). One for each
## settlement, all its dead laid there, however far its fire has moved since;
## never another settlement's (the owner, 2026-10-06). A settlement of an
## older save takes the one near its fire that no other has.
func cemetery_of(start: WorldSetup.StartInfo = null) -> PropData:
	var own := start if start != null else _start
	if own == null or _props == null:
		return null
	if own.cemetery_id != 0:
		var kept := _props.get_prop(own.cemetery_id)
		if kept != null and kept.kind == PropData.Kind.CEMETERY:
			return kept
		own.cemetery_id = 0 # (gone: a new one is opened)
	var taken := {}
	for other: WorldSetup.StartInfo in _all_starts():
		if other != own and other.cemetery_id != 0:
			taken[other.cemetery_id] = true
	var best: PropData = null
	var best_distance := GRAVEYARD_REACH
	for id in cemeteries():
		if taken.has(id):
			continue
		var cemetery := _props.get_prop(id)
		var distance := Vector2(cemetery.tile - own.settlement_tile).length()
		if distance <= best_distance:
			best = cemetery
			best_distance = distance
	if best != null:
		own.cemetery_id = best.id
	return best


func _all_starts() -> Array:
	if starts.is_valid():
		return starts.call()
	return [_start] if _start != null else []


## Where the dead of `start` are laid: its cemetery, or where one would be opened (null: nowhere).
func site(start: WorldSetup.StartInfo = null) -> Variant:
	var own := start if start != null else _start
	var cemetery := cemetery_of(own)
	if cemetery != null:
		return cemetery.tile
	# Level ground first (no plot hanging over a ledge: the owner, 2026-10-06),
	# further if need be; at the last, any ground — the dead are not left unburied.
	for level_only: bool in [true, false]:
		_level_only = level_only
		var fresh: Variant = _first_site(own.settlement_tile)
		if fresh == null:
			fresh = _first_site(own.settlement_tile, FURTHEST_FULL)
		if fresh != null:
			_level_only = false
			return fresh
	_level_only = false
	return null


## Gathers the single graves of an older save into cemeteries: each into the
## cemetery near it, or a new one opened where the graves were. Returns how
## many were gathered.
func gather_old() -> int:
	if _props == null or _archive == null:
		return 0
	var old: Array[PropData] = []
	for prop in _props.all_props():
		if prop.kind == PropData.Kind.GRAVE:
			old.append(prop)
	if old.is_empty():
		return 0
	old.sort_custom(func(a: PropData, b: PropData) -> bool: return a.id < b.id)
	var laid: Array = [] # [person ids, tile] per grave
	for grave in old:
		var ids: Array[int] = []
		for record in _archive.all_records():
			if record.grave_id == grave.id:
				ids.append(record.id)
		laid.append([ids, grave.tile])
		_props.remove(grave.id)
	for entry: Array in laid:
		var at: Vector2i = entry[1]
		var cemetery := _cemetery_near(at, GRAVEYARD_REACH)
		if cemetery == null:
			var tile: Variant = _first_site(at, FURTHEST, 0)
			if tile == null:
				tile = _first_site(at, FURTHEST_FULL, 0)
			cemetery = _open(tile) if tile != null else null
		for id: int in entry[0]:
			if cemetery != null:
				_lay(id, cemetery)
			else:
				_archive.set_grave(id, 0, at)
	return old.size()


func _open(tile: Vector2i) -> PropData:
	var cemetery := PropData.new()
	cemetery.id = _ids.next_id()
	cemetery.kind = PropData.Kind.CEMETERY
	cemetery.tile = tile
	cemetery.variant = 0
	cemetery.scale_percent = 100
	return cemetery if _props.add(cemetery) else null


func _lay(person_id: int, cemetery: PropData) -> void:
	_archive.set_grave(person_id, cemetery.id, cemetery.tile)
	var stones := mini(_archive.buried_count(cemetery.id), MOST_STONES)
	if cemetery.variant != stones:
		cemetery.variant = stones
		_props.changed(cemetery.id)


func _cemetery_near(tile: Vector2i, reach: float) -> PropData:
	var best: PropData = null
	var best_distance := INF
	for id in cemeteries():
		var cemetery := _props.get_prop(id)
		var distance := Vector2(cemetery.tile - tile).length()
		if distance <= reach and distance < best_distance:
			best = cemetery
			best_distance = distance
	return best


## A quiet place a little way from `center` (a fire), with room for the plot.
func _first_site(center: Vector2i, furthest: int = FURTHEST, nearest: int = NEAREST) -> Variant:
	for reach in range(nearest, furthest + 1):
		var ring: Array[Vector2i] = []
		for dy in range(-reach, reach + 1):
			for dx in range(-reach, reach + 1):
				if maxi(absi(dx), absi(dy)) == reach:
					ring.append(center + Vector2i(dx, dy))
		ring.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
			var da := (a - center).length_squared()
			var db := (b - center).length_squared()
			return da < db if da != db else (a.y < b.y or (a.y == b.y and a.x < b.x)))
		for tile in ring:
			if _room(tile):
				return tile
	return null


## The whole plot is free ground, and no other cemetery's plot touches it.
func _room(tile: Vector2i) -> bool:
	var h := _world.get_height(tile)
	for dy in range(-PLOT, PLOT + 1):
		for dx in range(-PLOT, PLOT + 1):
			if not _free(tile + Vector2i(dx, dy)):
				return false
	if _level_only:
		# The plot all one level, and nothing lower round it.
		for dy in range(-PLOT - 1, PLOT + 2):
			for dx in range(-PLOT - 1, PLOT + 2):
				var at := tile + Vector2i(dx, dy)
				if not _world.bounds.has_point(at):
					continue
				var there := _world.get_height(at)
				if there < h or (absi(dx) <= PLOT and absi(dy) <= PLOT and there != h):
					return false
	for id in cemeteries():
		var other := _props.get_prop(id)
		if maxi(absi(other.tile.x - tile.x), absi(other.tile.y - tile.y)) <= PLOT * 2 + 1:
			return false
	return true


## Ground where the dead can lie: dry, standable, nothing on it.
func _free(tile: Vector2i) -> bool:
	if not _world.bounds.has_point(tile) or not WorldSetup.is_walkable(_world, tile) or _world.get_water(tile) > 0.0:
		return false
	if _props.prop_at(tile) != null:
		return false
	if _pathfinder != null and _pathfinder.is_bound() and not _pathfinder.can_stand(tile):
		return false
	if _loose != null:
		for object in _loose.all_objects():
			if object.tile() == tile:
				return false
	return true


## Is `tile` on the plot of a cemetery (kept clear of fields and buildings)?
static func on_plot(props: PropRegistry, tile: Vector2i) -> bool:
	for dy in range(-PLOT, PLOT + 1):
		for dx in range(-PLOT, PLOT + 1):
			var near := props.prop_at(tile + Vector2i(dx, dy))
			if near != null and near.kind == PropData.Kind.CEMETERY:
				return true
	return false
