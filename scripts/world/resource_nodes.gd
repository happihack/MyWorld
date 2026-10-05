class_name ResourceNodes
extends RefCounted
## Resource nodes (bible §11): the trees, bushes and rocks of the world as
## things that hold a quantity of something, give it up to work, and grow it
## back. What a node holds is kept on its prop (PropData.stock); this class
## knows the rules.
##
## An untouched node is full and costs nothing: it is not saved and not
## looked at. Only nodes that have given something up are kept track of,
## until they have grown back.

## A node has nothing left (a tree falls; a bush is bare).
signal depleted(prop_id: int)
## A node is full again.
signal regrown(prop_id: int)

## How a node looks for what is left of it.
enum Look { FULL, SPARSE, BARE, STUMP, SAPLING }

const TREE := &"tree"
const BUSH := &"bush"
const ROCK := &"rock"
const SHOAL := &"shoal"
const CROP := &"crop"

## A ripe crop's last grain was taken (the plot is stubble: see Farming).
signal reaped(prop_id: int)

var last_settle_tick := -1_000_000

var _props: PropRegistry
var _config: ResourcesConfig
var _tracked: Dictionary = {} # prop id -> true: has given something up


# --- the rules (static: they need only the prop and the numbers) ---------------------------------

## Which node a prop is ("tree", "bush", "rock"), or &"" for anything else.
static func key_of(prop: PropData) -> StringName:
	if prop == null:
		return &""
	match prop.kind:
		PropData.Kind.TREE:
			return TREE
		PropData.Kind.BUSH:
			return BUSH
		PropData.Kind.ROCK:
			return ROCK
		PropData.Kind.CROP:
			return CROP
	return &""


## What a prop yields (&"" if nothing).
static func resource_for(prop: PropData, config: ResourcesConfig = null) -> StringName:
	return StringName(str(_settings(prop, config).get("resource", "")))


## How much a prop holds when nothing has been taken: more for a big one.
static func capacity_of(prop: PropData, config: ResourcesConfig = null) -> int:
	var settings := _settings(prop, config)
	if settings.is_empty():
		return 0
	# (A crop holds what it bears when it is ripe — see Farming — and nothing before.)
	if prop.kind == PropData.Kind.CROP:
		return maxi(prop.stock, 0)
	return maxi(roundi(int(settings.get("quantity", 0)) * prop.scale_percent / 100.0), 1)


## How much is left on it (as of the last time it was looked at: see settle()).
static func left_of(prop: PropData, config: ResourcesConfig = null) -> int:
	if prop != null and prop.kind == PropData.Kind.CROP:
		return maxi(prop.stock, 0) if Farming.stage_of(prop) == Farming.Stage.RIPE else 0
	var capacity := capacity_of(prop, config)
	return capacity if prop.stock < 0 else mini(prop.stock, capacity)


## What is left as a share of what it holds, 0 … 1.
static func fraction_of(prop: PropData, config: ResourcesConfig = null) -> float:
	var capacity := capacity_of(prop, config)
	return float(left_of(prop, config)) / float(capacity) if capacity > 0 else 1.0


## How the prop looks for what is left of it. A tree stands whole while it is
## being cut and falls when the last of it is taken; then it is a stump, and
## a sapling as it grows back. A bush thins out and goes bare.
static func look_of(prop: PropData, config: ResourcesConfig = null) -> Look:
	if prop == null or prop.stock < 0:
		return Look.FULL
	if config == null:
		config = Config.resources
	match prop.kind:
		PropData.Kind.TREE:
			if not prop.felled:
				return Look.FULL
			return Look.STUMP if fraction_of(prop, config) < config.sapling_from else Look.SAPLING
		PropData.Kind.BUSH:
			if prop.stock == 0:
				return Look.BARE
			return Look.SPARSE if fraction_of(prop, config) < config.sparse_below else Look.FULL
		PropData.Kind.CAMPFIRE:
			# (Not a node: a fire that has gone out is marked with stock 0.)
			return Look.BARE if prop.stock == 0 else Look.FULL
	return Look.FULL


## How big it is drawn, as a share of its own size.
static func look_scale(prop: PropData, config: ResourcesConfig = null) -> float:
	if config == null:
		config = Config.resources
	match look_of(prop, config):
		Look.SAPLING:
			var grown := inverse_lerp(config.sapling_from, 1.0, fraction_of(prop, config))
			return lerpf(config.sapling_scale, 1.0, clampf(grown, 0.0, 1.0))
		Look.BARE:
			return config.bare_scale
	return 1.0


static func _settings(prop: PropData, config: ResourcesConfig) -> Dictionary:
	if config == null:
		config = Config.resources
	var key := key_of(prop)
	return config.node(key) if key != &"" and config != null else {}


# --- the world's nodes ---------------------------------------------------------------------------

## Takes charge of the props' quantities. Call when the props are in place
## (those that had given something up when the world was saved are found).
func bind(props: PropRegistry, config: ResourcesConfig = null) -> void:
	_props = props
	_config = config if config != null else Config.resources
	_tracked.clear()
	last_settle_tick = -1_000_000
	if _props == null:
		return
	for prop in _props.all_props():
		if prop.stock >= 0 and key_of(prop) != &"" and prop.kind != PropData.Kind.CROP:
			_tracked[prop.id] = true


func unbind() -> void:
	_props = null
	_tracked.clear()


func resource_of(prop: PropData) -> StringName:
	return resource_for(prop, _config)


func capacity(prop: PropData) -> int:
	return capacity_of(prop, _config)


func left(prop: PropData) -> int:
	return left_of(prop, _config)


## How much can be gathered from it now: what is left — but nothing from a
## felled tree until it has grown back whole.
func available(prop: PropData) -> int:
	if prop == null or (prop.kind == PropData.Kind.TREE and prop.felled):
		return 0
	if bare_in_winter(prop):
		return 0
	return left(prop)


## Is it winter now (as of the last settling)? Set by `settle`.
var winter := false


## A bush in winter, when the winter is bare (ResourcesConfig.winter_no_berries).
func bare_in_winter(prop: PropData) -> bool:
	return winter and prop != null and prop.kind == PropData.Kind.BUSH and _config != null and _config.winter_no_berries


## How many strokes of work one unit takes.
func strokes_per_unit(prop: PropData) -> int:
	return maxi(int(_settings(prop, _config).get("strokes_per_unit", 1)), 1)


## Takes up to `units` from a node. Returns how many it gave.
func take(prop_id: int, units: int, now: int) -> int:
	var prop := _props.get_prop(prop_id) if _props != null else null
	if prop == null or units <= 0 or key_of(prop) == &"":
		return 0
	_settle_one(prop, now)
	var there := available(prop)
	var given := mini(units, there)
	if given <= 0:
		return 0
	if prop.kind == PropData.Kind.CROP:
		# Grain off a ripe crop; with the last of it the plot is reaped.
		prop.stock -= given
		_props.touch(prop.id)
		if prop.stock <= 0:
			reaped.emit(prop.id)
		return given
	var before := look_of(prop, _config)
	if prop.stock < 0:
		prop.stock = capacity(prop)
		prop.stock_tick = now # what is taken starts to grow back from now
	prop.stock -= given
	_tracked[prop.id] = true
	if prop.stock == 0:
		prop.stock_tick = now
		if prop.kind == PropData.Kind.TREE:
			prop.felled = true
	if look_of(prop, _config) != before:
		_props.changed(prop.id)
	else:
		_props.touch(prop.id)
	if prop.stock == 0:
		depleted.emit(prop.id)
	return given


## A sapling: a tree newly seeded is a felled one with the first of its
## growth, and grows up like a felled one growing back.
func plant(prop: PropData, now: int) -> void:
	if prop == null or prop.kind != PropData.Kind.TREE:
		return
	prop.felled = true
	prop.stock = maxi(ceili(capacity(prop) * _config.sapling_from), 1)
	prop.stock_tick = now
	_tracked[prop.id] = true
	if _props != null:
		_props.changed(prop.id)


## Is it time to work out regrowth again?
func due(now: int) -> bool:
	return _config != null and now - last_settle_tick >= _config.regrow_check_minutes


## Lets everything that has given something up grow back for the time that
## has passed. Returns how many nodes changed how they look.
func settle(now: int) -> int:
	last_settle_tick = now
	winter = Config.time.season_of(now) == Config.time.seasons_per_year - 1
	if _props == null:
		return 0
	var changed := 0
	for id: int in _tracked.keys():
		var prop := _props.get_prop(id)
		if prop == null:
			_tracked.erase(id) # uprooted, or gone with its chunk
			continue
		if _settle_one(prop, now):
			changed += 1
	return changed


## How many nodes have given something up and not grown back yet.
func tracked_count() -> int:
	return _tracked.size()


## How many of them have nothing left to give right now.
func exhausted_count() -> int:
	var count := 0
	for id: int in _tracked:
		var prop := _props.get_prop(id) if _props != null else null
		if prop != null and available(prop) == 0:
			count += 1
	return count


func debug_text() -> String:
	return "nodes: %d regrowing, %d of them with nothing to give" % [tracked_count(), exhausted_count()]


## Regrowth of one node up to `now`. True if it looks different for it.
func _settle_one(prop: PropData, now: int) -> bool:
	if prop.kind == PropData.Kind.CROP:
		return false # (crops grow by Farming's rules, not by regrowth)
	if prop.stock < 0:
		_tracked.erase(prop.id)
		return false
	var days := float(_settings(prop, _config).get("regrow_days", 0.0))
	var full := capacity(prop)
	if days <= 0.0 or full <= 0:
		return false
	# (A bare winter: nothing grows back until the spring.)
	if bare_in_winter(prop):
		prop.stock_tick = now
		return false
	var minutes_per_unit := maxi(roundi(days * Config.time.MINUTES_PER_DAY / float(full)), 1)
	@warning_ignore("integer_division")
	var units := (now - prop.stock_tick) / minutes_per_unit
	if units <= 0:
		return false
	var before := look_of(prop, _config)
	var size_before := look_scale(prop, _config)
	prop.stock = mini(prop.stock + units, full)
	prop.stock_tick += units * minutes_per_unit
	var whole := prop.stock >= full
	if whole:
		# As it was made: nothing to remember about it any more.
		prop.stock = -1
		prop.stock_tick = 0
		prop.felled = false
		_tracked.erase(prop.id)
	var looks_different := look_of(prop, _config) != before or not is_equal_approx(look_scale(prop, _config), size_before)
	if looks_different:
		_props.changed(prop.id)
	else:
		_props.touch(prop.id)
	if whole:
		regrown.emit(prop.id)
	return looks_different
