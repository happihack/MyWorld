class_name JobBoard
extends RefCounted
## A settlement's job board (bible §17.3): what needs doing, posted from
## simple rules — food running low, wood running low, the fire to be kept.
## Nobody is assigned: each person weighs what is posted when they think of
## working (a job of their own trade counts for more; others take up what is
## pressing), and what is posted is how much work there is to want.

const GATHER := &"gather"
const TEND := &"tend"
const FARM := &"farm"
const HUNT := &"hunt"

class Job:
	extends RefCounted
	var id := 0
	## GATHER (bring `resource` in from `node`s), TEND (keep the fire) or
	## FARM (whatever the field needs).
	var kind: StringName = GATHER
	var resource: StringName = &""
	## What is worked at: "tree", "bush", "fire" (OccupationDef.work_target).
	var node: StringName = &""
	## How pressing, 0 … 1.
	var priority := 0.0
	## What is in store and what is wanted (in the resource's units; food in bellies).
	var have := 0.0
	var wanted := 0.0
	var posted_tick := 0

	func describe() -> String:
		if kind == TEND:
			return "keep the %s %.2f" % [node, priority]
		if kind == FARM:
			return "the field %.2f" % priority
		if kind == HUNT:
			return "hunting %.2f" % priority
		return "%s %.2f (%.0f of %.0f)" % [resource, priority, have, wanted]


## A job was put up / taken down.
signal posted(job: Job)
signal closed(job: Job)

var last_refresh_tick := -1_000_000
var _jobs: Array[Job] = []
var _next_id := 1
var _config: SettlementConfig


func _init(config: SettlementConfig = null) -> void:
	_config = config if config != null else Config.settlement


## What is posted now, the most pressing first.
func jobs() -> Array[Job]:
	return _jobs


func job_for(resource: StringName) -> Job:
	for job in _jobs:
		if job.kind == GATHER and job.resource == resource:
			return job
	return null


## Is more of `resource` wanted?
func wants(resource: StringName) -> bool:
	return job_for(resource) != null


## Brings the board up to date with what the settlement has and needs.
func refresh(settlement: Settlement, now: int) -> void:
	last_refresh_tick = now
	var wanted: Array = [] # [kind, resource, node, priority, have, wanted]
	if settlement != null:
		var stock := settlement.stockpile
		# Food: so many days of it in store.
		# (More before winter: see Settlement.winter_factor.)
		var food_wanted := settlement.food_need_per_day() * _config.food_days_wanted \
			* settlement.winter_factor(now, _config.winter_food_factor)
		var food := stock.food()
		if food_wanted > 0.0 and food < food_wanted:
			wanted.append([GATHER, &"berries", ResourceNodes.BUSH, 1.0 - food / food_wanted, food, food_wanted])
			# ...and meat, where there are hunters and game enough to take from.
			if settlement.fauna != null and settlement.hunter_count() > 0 and settlement.fauna.has_game():
				wanted.append([HUNT, &"meat", &"game", 1.0 - food / food_wanted, food, food_wanted])
		# Wood: so many days of what the fire burns.
		# (More in the cold, whatever the calendar says; and what rebuilding a flooded hut takes.)
		var wood_wanted := _config.fire_wood_per_day * _config.wood_days_wanted \
			* maxf(settlement.winter_factor(now, _config.winter_wood_factor), settlement.cold_factor(now)) \
			+ settlement.pending_moves() * Config.exposure.move_wood
		var wood := float(stock.amount(&"wood"))
		if wood_wanted > 0.0 and wood < wood_wanted:
			wanted.append([GATHER, &"wood", ResourceNodes.TREE, 1.0 - wood / wood_wanted, wood, wood_wanted])
		# The fire is always there to be kept.
		if settlement.fire() != null:
			wanted.append([TEND, &"", &"fire", _config.fire_job_priority, 0.0, 0.0])
		# The field, as pressing as what it needs (ripe grain above all).
		if settlement.farming != null and settlement.farming.farmer_count() > 0:
			var field := maxf(settlement.farming.pressing(now), _config.field_job_floor)
			if field > 0.0:
				wanted.append([FARM, &"", &"field", field, 0.0, 0.0])
	# What was posted and is wanted still keeps its number and its date.
	var kept: Array[Job] = []
	for entry: Array in wanted:
		var job: Job = null
		for old in _jobs:
			if old.kind == entry[0] and old.resource == entry[1] and old.node == entry[2]:
				job = old
		var is_new := job == null
		if is_new:
			job = Job.new()
			job.id = _next_id
			_next_id += 1
			job.kind = entry[0]
			job.resource = entry[1]
			job.node = entry[2]
			job.posted_tick = now
		job.priority = clampf(float(entry[3]), 0.0, 1.0)
		job.have = entry[4]
		job.wanted = entry[5]
		kept.append(job)
		if is_new:
			posted.emit(job)
	for old in _jobs:
		if not kept.has(old):
			closed.emit(old)
	kept.sort_custom(func(a: Job, b: Job) -> bool: return a.priority > b.priority or (a.priority == b.priority and a.id < b.id))
	_jobs = kept


## How much a job is one for someone of `trade` (an occupation's
## work_target): fully if it is their own; partly if it is something they
## also do (`also`: OccupationDef.helps_with) or pressing enough for anyone
## to lend a hand; not at all otherwise. Keeping the fire and working the
## field are nobody else's work.
func affinity(job: Job, trade: StringName, also: PackedStringArray = PackedStringArray()) -> float:
	if job == null or trade == &"":
		return 0.0
	if job.node == trade:
		return 1.0
	if job.kind != GATHER:
		return 0.0
	if also.has(String(job.node)) or job.priority >= _config.urgent_from:
		return _config.other_trade_factor
	return 0.0


## How strongly the board calls someone of `trade`, 0 … 1: the most
## pressing thing on it that is theirs to do.
func pull_for(trade: StringName, also: PackedStringArray = PackedStringArray()) -> float:
	var strongest := 0.0
	for job in _jobs:
		strongest = maxf(strongest, job.priority * affinity(job, trade, also))
	return strongest


## What work is worth to someone of `trade`, as a factor on how much they
## want to work at all (see SettlementConfig.work_without_jobs).
func work_factor(trade: StringName, also: PackedStringArray = PackedStringArray()) -> float:
	return lerpf(_config.work_without_jobs, _config.work_with_urgent_job, pull_for(trade, also))


## The job someone of `trade` takes up now: one of those that are theirs to
## do, by weighted dice (never simply the top one). Null if there is none.
func choose(trade: StringName, rng: RandomNumberGenerator, also: PackedStringArray = PackedStringArray()) -> Job:
	var open: Array[Job] = []
	var weights := PackedFloat32Array()
	var total := 0.0
	for job in _jobs:
		var weight := job.priority * affinity(job, trade, also)
		if weight <= 0.0:
			continue
		open.append(job)
		weights.append(weight)
		total += weight
	if open.is_empty():
		return null
	var roll := (rng.randf() if rng != null else 0.0) * total
	for i in open.size():
		roll -= weights[i]
		if roll <= 0.0:
			return open[i]
	return open[-1]


func debug_text() -> String:
	var parts := PackedStringArray()
	for job in _jobs:
		parts.append(job.describe())
	return ", ".join(parts) if not parts.is_empty() else "nothing posted"


func to_dict() -> Dictionary:
	var saved: Array = []
	for job in _jobs:
		saved.append({"id": job.id, "kind": String(job.kind), "resource": String(job.resource), "node": String(job.node),
			"priority": job.priority, "have": job.have, "wanted": job.wanted, "posted": job.posted_tick})
	return {"next_id": _next_id, "jobs": saved}


func from_dict(data: Dictionary) -> void:
	_jobs = []
	_next_id = maxi(int(data.get("next_id", 1)), 1)
	last_refresh_tick = -1_000_000
	var saved: Variant = data.get("jobs")
	if typeof(saved) != TYPE_ARRAY:
		return
	for record: Variant in saved:
		if typeof(record) != TYPE_DICTIONARY or typeof((record as Dictionary).get("id")) != TYPE_INT:
			continue
		var job := Job.new()
		job.id = int(record["id"])
		job.kind = StringName(str((record as Dictionary).get("kind", GATHER)))
		job.resource = StringName(str((record as Dictionary).get("resource", "")))
		job.node = StringName(str((record as Dictionary).get("node", "")))
		job.priority = clampf(float((record as Dictionary).get("priority", 0.0)), 0.0, 1.0)
		job.have = float((record as Dictionary).get("have", 0.0))
		job.wanted = float((record as Dictionary).get("wanted", 0.0))
		job.posted_tick = int((record as Dictionary).get("posted", 0))
		_jobs.append(job)
		_next_id = maxi(_next_id, job.id + 1)
