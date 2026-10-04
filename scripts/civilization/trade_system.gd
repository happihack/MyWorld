class_name TradeSystem
extends RefCounted
## Trade between settlements (bible §17.3, M12.4).
##
## Once a game day each settlement looks at what it has more of than it keeps
## (food for some days, a few of anything else) and at what another — within
## reach, on foot — lacks; the best such exchange is its offer for the day:
## its surplus taken there, and on the way back what the other has to spare
## that it lacks (or nothing, if it has nothing to give). Its trader carries
## it (a pack basket: more than anyone else carries), on foot, along the paths.
## Every load delivered is counted: by route and by resource.

## A load has been delivered: {"from", "to", "resource", "units", "trader"}.
signal traded(record: Dictionary)
## The first load ever carried between two settlements (either way).
signal route_opened(record: Dictionary)

var settlements: Settlements
var resources: ResourceLibrary
var pathfinder: Pathfinder
var config: TradeConfig

var _offers: Dictionary = {} # settlement id -> offer
var _day := -1_000_000
## Statistics: "a>b" -> {"trips", "units": {resource -> units}}, resource -> units, loads delivered.
var routes: Dictionary = {}
var totals: Dictionary = {}
var trips := 0


func bind(now: int, cfg: TradeConfig = null) -> void:
	config = cfg if cfg != null else Config.trade
	_offers.clear()
	_day = Config.time.day_index(now)
	routes.clear()
	totals.clear()
	trips = 0


## Once a game day (from seven in the morning): the day's offers.
func advance_to(now: int) -> void:
	if settlements == null:
		return
	var today := Config.time.day_index(now)
	if _day == -1_000_000 or today < _day:
		_day = today
		return
	if today == _day or Config.time.minute_of_day(now) < 7 * 60:
		return
	_day = today
	plan_offers()


## Works out every settlement's offer for now.
func plan_offers() -> void:
	_offers.clear()
	if settlements == null or settlements.size() < 2:
		return
	for own in settlements.all():
		var best := {}
		for other in settlements.all():
			if other == own or not _within_reach(own, other):
				continue
			var offer := exchange(own, other)
			if not offer.is_empty() and (best.is_empty() or int(offer["units"]) > int(best["units"])):
				best = offer
		if not best.is_empty():
			_offers[own.id] = best
	return


## What `own` would take to `other` and bring back: {"from", "to", "out",
## "units", "back", "back_units"} ({}: nothing worth the walk).
func exchange(own: Settlement, other: Settlement) -> Dictionary:
	var out := &""
	var units := 0
	for resource in _kinds(own, other):
		var can := mini(surplus(own, resource), need(other, resource))
		if can > units:
			units = can
			out = resource
	if units < config.least_load:
		return {}
	var back := &""
	var back_units := 0
	for resource in _kinds(other, own):
		if resource == out:
			continue
		var can := mini(surplus(other, resource), need(own, resource))
		if can > back_units:
			back_units = can
			back = resource
	if back_units < config.least_load:
		back = &""
		back_units = 0
	return {"from": own.id, "to": other.id, "out": String(out), "units": units, "back": String(back), "back_units": back_units}


## How much of `resource` a settlement has beyond what it keeps (0: none).
func surplus(own: Settlement, resource: StringName) -> int:
	if _is_food(resource):
		var spare := own.stockpile.food_units() - _food_kept(own)
		return clampi(spare, 0, own.stockpile.available(resource))
	return maxi(own.stockpile.available(resource) - config.keep_units, 0)


## How much of `resource` a settlement lacks of what it keeps (0: nothing).
func need(own: Settlement, resource: StringName) -> int:
	if _is_food(resource):
		return maxi(_food_kept(own) - own.stockpile.food_units(), 0)
	return maxi(config.keep_units - own.stockpile.available(resource), 0)


func has_offer(settlement_id: int) -> bool:
	return _offers.has(settlement_id)


func offer_for(settlement_id: int) -> Dictionary:
	return (_offers.get(settlement_id, {}) as Dictionary).duplicate()


## A trader sets out with a load of the offer (at most `out_units` there and
## `back_units` back): what is left of it stays on offer, for the next run.
func claim(settlement_id: int, out_units: int = 1_000_000, back_units: int = 1_000_000) -> Dictionary:
	var offer: Dictionary = _offers.get(settlement_id, {})
	if offer.is_empty():
		return {}
	var load := offer.duplicate()
	load["units"] = mini(int(offer["units"]), out_units)
	load["back_units"] = mini(int(offer["back_units"]), back_units)
	offer["units"] = int(offer["units"]) - int(load["units"])
	offer["back_units"] = int(offer["back_units"]) - int(load["back_units"])
	if int(offer["units"]) < config.least_load:
		_offers.erase(settlement_id)
	return load


## A load has been delivered at `to` (from `from`).
func delivered(from: int, to: int, resource: StringName, units: int, trader_id: int) -> void:
	if units <= 0:
		return
	var record := {"from": from, "to": to, "resource": String(resource), "units": units, "trader": trader_id}
	var key := "%d>%d" % [from, to]
	var first := not routes.has(key) and not routes.has("%d>%d" % [to, from])
	var route: Dictionary = routes.get(key, {"trips": 0, "units": {}})
	route["trips"] = int(route["trips"]) + 1
	var by: Dictionary = route["units"]
	by[String(resource)] = int(by.get(String(resource), 0)) + units
	routes[key] = route
	totals[String(resource)] = int(totals.get(String(resource), 0)) + units
	trips += 1
	if first:
		route_opened.emit(record)
	traded.emit(record)


## What a settlement sends most and gets most: [sent, got] (resource ids, "" when none).
func balance_of(settlement_id: int) -> Array:
	var sent := {}
	var got := {}
	for key: String in routes:
		var ends := key.split(">")
		var by: Dictionary = routes[key]["units"]
		for resource: String in by:
			if int(ends[0]) == settlement_id:
				sent[resource] = int(sent.get(resource, 0)) + int(by[resource])
			if int(ends[1]) == settlement_id:
				got[resource] = int(got.get(resource, 0)) + int(by[resource])
	return [_most(sent), _most(got)]


func debug_text() -> String:
	var parts := PackedStringArray()
	var kinds := totals.keys()
	kinds.sort()
	for resource: String in kinds:
		parts.append("%s %d" % [resource, totals[resource]])
	return "trade: %d loads on %d routes (%s)" % [trips, routes.size(), ", ".join(parts) if not parts.is_empty() else "nothing"]


func _most(by: Dictionary) -> String:
	var best := ""
	var most := 0
	var kinds := by.keys()
	kinds.sort()
	for resource: String in kinds:
		if int(by[resource]) > most:
			most = by[resource]
			best = resource
	return best


func _within_reach(a: Settlement, b: Settlement) -> bool:
	var from := a.start_info().settlement_tile
	var to := b.start_info().settlement_tile
	if Vector2(to - from).length() > config.route_reach:
		return false
	return pathfinder == null or not pathfinder.is_bound() or pathfinder.is_reachable(from + Vector2i(1, 0), to + Vector2i(1, 0))


## The kinds of thing there might be to trade: whatever either has in store.
func _kinds(a: Settlement, b: Settlement) -> Array[StringName]:
	var out: Array[StringName] = []
	for own in [a, b]:
		for resource: StringName in (own as Settlement).stockpile.amounts():
			if not out.has(resource):
				out.append(resource)
	for resource: StringName in [&"wood", &"stone", &"tools"]:
		if not out.has(resource):
			out.append(resource)
	out.sort()
	return out


func _is_food(resource: StringName) -> bool:
	var def := resources.get_def(resource) if resources != null else null
	return def != null and def.is_food()


func _food_kept(own: Settlement) -> int:
	var berries := resources.get_def(&"berries") if resources != null else null
	var nutrition := berries.nutrition if berries != null and berries.nutrition > 0.0 else 1.0
	var gov := Config.governance
	var tilt := 1.0 + gov.caution_keep * maxf(-own.leader_lean(Traits.Axis.CURIOSITY), 0.0) \
		- gov.generosity_keep * maxf(own.leader_lean(Traits.Axis.GENEROSITY), 0.0)
	return ceili(own.food_need_per_day() * config.keep_food_days * maxf(tilt, 0.1) / nutrition)


# --- saving ---------------------------------------------------------------------------------------

func to_dict() -> Dictionary:
	return {"day": _day, "routes": routes.duplicate(true), "totals": totals.duplicate(), "trips": trips,
		"offers": _offers.duplicate(true)}


func from_dict(data: Dictionary) -> void:
	if typeof(data.get("day")) == TYPE_INT:
		_day = data["day"]
	routes.clear()
	if typeof(data.get("routes")) == TYPE_DICTIONARY:
		for key: Variant in data["routes"]:
			var route: Variant = data["routes"][key]
			if typeof(key) == TYPE_STRING and typeof(route) == TYPE_DICTIONARY and typeof(route.get("units")) == TYPE_DICTIONARY:
				routes[key] = {"trips": int(route.get("trips", 0)), "units": (route["units"] as Dictionary).duplicate()}
	totals.clear()
	if typeof(data.get("totals")) == TYPE_DICTIONARY:
		for resource: Variant in data["totals"]:
			totals[str(resource)] = int(data["totals"][resource])
	trips = maxi(int(data.get("trips", 0)), 0)
	_offers.clear()
	if typeof(data.get("offers")) == TYPE_DICTIONARY:
		for id: Variant in data["offers"]:
			if typeof(data["offers"][id]) == TYPE_DICTIONARY:
				_offers[int(id)] = (data["offers"][id] as Dictionary).duplicate()
