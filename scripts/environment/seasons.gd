class_name Seasons
extends RefCounted
## Where in the year it is, and what that means for things that change
## with the seasons (bible §10.2). Pure functions of the game tick.
##
## Values "by season" stand for the middle of each season; `blend` goes
## over from one to the next, so that nothing jumps when a season turns.

enum { SPRING, SUMMER, AUTUMN, WINTER }


## Where in the year a tick is: 0 … 4 (0 = the first moment of spring,
## 1.5 = the middle of summer).
static func position(tick: int) -> float:
	var time := Config.time
	var minutes := float(time.days_per_season * TimeConfig.MINUTES_PER_DAY)
	return fposmod(float(tick + roundi(time.start_hour * 60.0)) / minutes, 4.0)


## A value by season (four entries) at a place in the year.
static func blend(values: PackedFloat32Array, at: float) -> float:
	if values.size() < 4:
		return 0.0
	var shifted := fposmod(at - 0.5, 4.0)
	var from := floori(shifted) % 4
	return lerpf(values[from], values[(from + 1) % 4], shifted - floorf(shifted))


## The same for colours.
static func blend_color(values: PackedColorArray, at: float) -> Color:
	if values.size() < 4:
		return Color.WHITE
	var shifted := fposmod(at - 0.5, 4.0)
	var from := floori(shifted) % 4
	return values[from].lerp(values[(from + 1) % 4], shifted - floorf(shifted))


## How many game days until winter begins (0 in winter).
static func days_until_winter(tick: int) -> float:
	var at := position(tick)
	return maxf(3.0 - at, 0.0) * Config.time.days_per_season if at < 3.0 else 0.0


static func is_winter(tick: int) -> bool:
	return Config.time.season_of(tick) == WINTER
