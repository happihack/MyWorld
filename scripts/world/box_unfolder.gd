class_name BoxUnfolder
extends RefCounted
## The Box Unfolds (M13.2, bible §8.6, D-05): when the civilization presses
## against the walls of its box — explorers have reached the wall band again
## and again, *and* the box is crowded or a settlement stands near a wall —
## and the box is below its largest size, a ring of chunks is added: the
## walls move outward (WorldSession.unfold). Looked at once a day; not again
## for `unfold_rest_days` after it happened.

## How wide the band along the walls is that counts as "at the wall" (tiles).
const WALL_BAND := 4

var _config: WorldConfig
## The day it last unfolded, and how many times it has.
var last_day := -1_000_000
var count := 0


func _init(config: WorldConfig = null) -> void:
	_config = config


func config() -> WorldConfig:
	return _config if _config != null else Config.world


## What presses against the walls now: {"edge": share of the wall band
## explored, "crowded": bool, "near": bool (a fire near a wall), "people": int}.
func pressure(world: WorldData, settlements: Settlements, people_count: int) -> Dictionary:
	var cfg := config()
	var bounds := world.bounds
	# The wall band, cell by cell (in the cells explorers mark: Places.VISIT_CELL).
	var band := {}
	var inner := bounds.grow(-WALL_BAND)
	var cell := Places.VISIT_CELL
	for y in range(bounds.position.y, bounds.end.y, cell):
		for x in range(bounds.position.x, bounds.end.x, cell):
			var tile := Vector2i(x, y)
			if not inner.has_point(tile) or not inner.has_point(tile + Vector2i(cell - 1, cell - 1)):
				band[Places.cell_of(tile)] = true
	var visited := 0
	var seen := {}
	if settlements != null:
		for own in settlements.all():
			if own.places() == null:
				continue
			for c in own.places().visited_cells():
				if band.has(c) and not seen.has(c):
					seen[c] = true
					visited += 1
	var near := false
	if settlements != null:
		for fire in settlements.fire_tiles():
			var to_wall := mini(mini(fire.x - bounds.position.x, bounds.end.x - 1 - fire.x),
				mini(fire.y - bounds.position.y, bounds.end.y - 1 - fire.y))
			if to_wall <= cfg.unfold_near_wall_tiles:
				near = true
	var area := float(bounds.size.x * bounds.size.y)
	return {"edge": float(visited) / maxf(band.size(), 1.0), "near": near, "people": people_count,
		"crowded": people_count >= cfg.unfold_people_per_1000_tiles * area / 1000.0}


## Is it time to unfold (`now`: a game tick)?
func due(world: WorldData, settlements: Settlements, people_count: int, now: int) -> bool:
	var cfg := config()
	if world.bounds.size.x + 2 * world.chunk_size > cfg.max_world_tiles or world.bounds.size.y + 2 * world.chunk_size > cfg.max_world_tiles:
		return false
	if Config.time.day_index(now) - last_day < cfg.unfold_rest_days:
		return false
	var push := pressure(world, settlements, people_count)
	return float(push["edge"]) >= cfg.unfold_edge_share and (bool(push["crowded"]) or bool(push["near"]))


## It has unfolded today.
func note(now: int) -> void:
	last_day = Config.time.day_index(now)
	count += 1


func to_dict() -> Dictionary:
	return {"last_day": last_day, "count": count}


func from_dict(data: Dictionary) -> void:
	last_day = int(data.get("last_day", -1_000_000)) if typeof(data.get("last_day")) == TYPE_INT else -1_000_000
	count = maxi(int(data.get("count", 0)), 0) if typeof(data.get("count")) == TYPE_INT else 0
