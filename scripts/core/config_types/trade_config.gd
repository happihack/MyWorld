class_name TradeConfig
extends ConfigBase
## Specialization, trade and tools (bible §17, M12.4).

@export_group("Specialization")
## Of what a settlement has brought in (a resource's units), this much is
## remembered the next day.
@export_range(0.5, 0.999, 0.001) var produced_kept_per_day: float = 0.95
## A settlement is known for a resource that is at least this share of what it brings in…
@export_range(0.0, 1.0, 0.01) var specialty_share: float = 0.35
## …once it brings in this much at all (remembered units).
@export_range(0.0, 1000.0) var specialty_from: float = 40.0
## Gathering makes one better at it: skill gained for each unit brought in,
## and how much faster the most skilled works (1 + this).
@export_range(0.0, 0.1, 0.0001) var skill_per_unit: float = 0.004
@export_range(0.0, 2.0, 0.01) var skill_speed: float = 0.5
## The young lean toward the trade their settlement is known for (its weight × 1 + this).
@export_range(0.0, 10.0, 0.1) var specialty_pull: float = 1.5

@export_group("Trade")
## What a settlement keeps: food for this many days, and of anything else this many units.
@export_range(0.0, 60.0, 0.5) var keep_food_days: float = 5.0
@export_range(0, 200) var keep_units: int = 10
## A load is worth carrying from this many units.
@export_range(1, 50) var least_load: int = 3
## A trader carries this much more than anyone else (a pack basket).
@export_range(1.0, 5.0, 0.1) var pack_factor: float = 2.0
## How pressing a trade run is (for the job board), and how far apart
## settlements may be to trade at all (tiles).
@export_range(0.0, 1.0, 0.01) var trade_priority: float = 0.5
@export_range(4.0, 400.0) var route_reach: float = 60.0
## A trader is taken up once there is trade to be done and this many could be spared.
@export_range(1, 20) var trader_from: int = 3

@export_group("Tools")
## Someone this skilled at their work may work out how to make good tools,
## with this chance a day.
@export_range(0.0, 1.0, 0.01) var toolmaking_skill: float = 0.6
@export_range(0.0, 1.0, 0.001) var toolmaking_chance: float = 0.02
## A workshop is wanted from this many people.
@export_range(1, 100) var workshop_from: int = 6
## A tool takes this much wood and stone and this many game minutes to make.
@export_range(0, 10) var tool_wood: int = 1
@export_range(0, 10) var tool_stone: int = 1
@export_range(5.0, 600.0) var craft_minutes: float = 60.0
## Tools wanted in store: this many for each worker.
@export_range(0.0, 5.0, 0.1) var tools_per_worker: float = 1.0
## With a tool for every worker, work goes this much faster (1 + this) …
@export_range(0.0, 2.0, 0.01) var tool_bonus: float = 0.5
## … and each unit brought in wears a tool out with this chance.
@export_range(0.0, 1.0, 0.001) var tool_wear: float = 0.005


func validate() -> PackedStringArray:
	return PackedStringArray()
