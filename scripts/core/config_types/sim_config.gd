class_name SimConfig
extends ConfigBase
## How closely who is simulated, and how much time that may take (bible §9.3,
## §31.6, §33).

@export_group("Tiers")
## Most people simulated in full (tier 3) at once: on capable devices / on
## low-end ones. Whoever is beyond that, furthest from where the player looks,
## is simulated more coarsely (tier 2).
@export_range(1, 512) var tier3_cap_high: int = 64
@export_range(1, 512) var tier3_cap_low: int = 32
## Next nearest, after them: simulated coarsely (tier 2). Whoever is beyond
## both — the furthest from where the player looks — lives an hour at a time
## (tier 1, M21).
@export_range(0, 4096) var tier2_cap_high: int = 128
@export_range(0, 4096) var tier2_cap_low: int = 64
## How many people can be in the player's focus (tier 4) at once.
@export_range(1, 8) var tier4_cap: int = 2

@export_group("Cadence (in ticks = game minutes)")
## How often someone busy looks up from what they are doing, by tier.
@export_range(1, 240) var think_ticks_tier4: int = 1
@export_range(1, 240) var think_ticks_tier3: int = 3
@export_range(1, 240) var think_ticks_tier2: int = 15
@export_range(1, 1440) var think_ticks_tier1: int = 60
## A look up is a glance (has any need grown louder?). Everything is weighed
## up again only if one has — or after this many looks anyway, since the hour
## moves on. Deciding is the dearest thing a person does.
@export_range(1, 20) var relaxed_think_factor: int = 5
## How often needs and actions move on, by tier (4 and 3: every tick).
@export_range(1, 240) var live_ticks_tier2: int = 15
@export_range(1, 1440) var live_ticks_tier1: int = 60

## Let people at something steady (asleep, resting, at work) take fewer,
## larger turns. No time is lost either way; off = everyone every tick.
@export var patient_steps: bool = true

@export_group("Budget")
## Time per frame for people living (needs, actions, decisions). When it is
## used up, whoever has not had their turn has it first in the next frame —
## nobody loses time, their steps just get coarser.
@export_range(0.0, 16.0, 0.05) var ai_budget_ms_per_frame: float = 1.5


func tier3_cap(low_end: bool) -> int:
	return tier3_cap_low if low_end else tier3_cap_high


func tier2_cap(low_end: bool) -> int:
	return tier2_cap_low if low_end else tier2_cap_high


## Ticks between two looks up from work, for a tier.
func think_ticks(tier: int) -> int:
	if tier >= 4:
		return think_ticks_tier4
	if tier == 3:
		return think_ticks_tier3
	return think_ticks_tier2 if tier == 2 else think_ticks_tier1


## Ticks between two steps of living, for a tier.
func live_ticks(tier: int) -> int:
	if tier >= 3:
		return 1
	return live_ticks_tier2 if tier == 2 else live_ticks_tier1


func validate() -> PackedStringArray:
	var p := PackedStringArray()
	_check(p, tier3_cap_low <= tier3_cap_high, "tier3_cap_low must be <= tier3_cap_high")
	_check(p, tier2_cap_low <= tier2_cap_high, "tier2_cap_low must be <= tier2_cap_high")
	_check(p, think_ticks_tier2 <= think_ticks_tier1 and live_ticks_tier2 <= live_ticks_tier1,
		"tier 1 must think and live no more often than tier 2")
	_check(p, think_ticks_tier4 <= think_ticks_tier3 and think_ticks_tier3 <= think_ticks_tier2,
		"closer tiers must think at least as often (tier 4 <= tier 3 <= tier 2)")
	return p
