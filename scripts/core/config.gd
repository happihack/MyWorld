extends Node
## Autoload "Config": loads tunable resources from res://data/configuration/ (bible §33).
##
## Systems read tunables via typed accessors, e.g. Config.time.days_per_season.
## A missing or invalid file never crashes the game: defaults from the resource
## class are used and the problem is logged.

const CONFIG_DIR := "res://data/configuration/"

var time: TimeConfig
var world: WorldConfig
var save: SaveConfig
var interaction: InteractionConfig
var perf: PerfConfig
var terrain_palette: TerrainPalette
var camera: CameraConfig
var feedback: FeedbackConfig
var people: PeopleConfig
var needs: NeedsConfig
var sim: SimConfig
var reactions: ReactionTable
var memory: MemoryConfig
var day_night: DayNightConfig
var resources: ResourcesConfig
var settlement: SettlementConfig
var farming: FarmingConfig

## Every problem found while loading (used by tests and the debug panel).
var problems: PackedStringArray = []


func _ready() -> void:
	reload()


func reload() -> void:
	problems.clear()
	time = _load("time_config.tres", TimeConfig) as TimeConfig
	world = _load("world_config.tres", WorldConfig) as WorldConfig
	save = _load("save_config.tres", SaveConfig) as SaveConfig
	interaction = _load("interaction_config.tres", InteractionConfig) as InteractionConfig
	perf = _load("perf_config.tres", PerfConfig) as PerfConfig
	terrain_palette = _load("terrain_palette.tres", TerrainPalette) as TerrainPalette
	camera = _load("camera_config.tres", CameraConfig) as CameraConfig
	feedback = _load("feedback_config.tres", FeedbackConfig) as FeedbackConfig
	people = _load("people_config.tres", PeopleConfig) as PeopleConfig
	needs = _load("needs_config.tres", NeedsConfig) as NeedsConfig
	sim = _load("sim_config.tres", SimConfig) as SimConfig
	reactions = _load("reactions.tres", ReactionTable) as ReactionTable
	memory = _load("memory_config.tres", MemoryConfig) as MemoryConfig
	day_night = _load("day_night.tres", DayNightConfig) as DayNightConfig
	resources = _load("resources_config.tres", ResourcesConfig) as ResourcesConfig
	settlement = _load("settlement_config.tres", SettlementConfig) as SettlementConfig
	farming = _load("farming_config.tres", FarmingConfig) as FarmingConfig
	if problems.is_empty():
		Log.info(Log.Category.CORE, "Config loaded")
	else:
		Log.warn(Log.Category.CORE, "Config loaded with problems", {"count": problems.size()})


func _load(file_name: String, type: GDScript) -> ConfigBase:
	var path := CONFIG_DIR + file_name
	var res: Resource = null
	if ResourceLoader.exists(path):
		res = ResourceLoader.load(path)
	var cfg := res as ConfigBase
	if cfg == null or cfg.get_script() != type:
		_problem("%s missing or wrong type; using defaults" % path)
		cfg = type.new()
	for p in cfg.validate():
		_problem("%s: %s" % [file_name, p])
	return cfg


func _problem(message: String) -> void:
	problems.append(message)
	Log.error(Log.Category.CORE, "Config problem: " + message)
