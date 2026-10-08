class_name Exposure
extends RefCounted
## What the weather does to a person (bible §10.1, M9.6): it drives them
## indoors, the heat slows their work, and the cold gets into those who are
## not warm — after long enough they are ill with it, and get well again in
## the warmth.
##
## Being cold is plain data on the person, in PersonData.conditions (like
## going hungry — see Hardship):
##   {"id": "cold", "exposed": minutes of cold in them, "sick": bool,
##    "well": float (their health before), "fed": bool (warm again: recovering)}

const COLD := &"cold"
const RAIN := &"rain"
const STORM := &"storm"
const BLIZZARD := &"blizzard"
const SNOW := &"snow"


## How strongly the weather drives people indoors now, 0 … 1.
static func pull(weather: WeatherSystem, now: int, config: ExposureConfig = null) -> float:
	if weather == null:
		return 0.0
	if config == null:
		config = Config.exposure
	var by_weather := float(config.pull_by_weather.get(weather.state, config.pull_by_weather.get(String(weather.state), 0.0)))
	return clampf(maxf(by_weather, cold_pull(weather.temperature(now), config)), 0.0, 1.0)


static func cold_pull(temperature: float, config: ExposureConfig = null) -> float:
	if config == null:
		config = Config.exposure
	return clampf((config.cold_pull_from - temperature) / config.cold_pull_span, 0.0, 1.0) * config.cold_pull_most


## What they take shelter from ("storm", "rain", "snow", "cold"); &"" if the
## weather keeps nobody in.
static func reason(weather: WeatherSystem, now: int, config: ExposureConfig = null) -> StringName:
	if config == null:
		config = Config.exposure
	if pull(weather, now, config) < config.shelter_from:
		return &""
	var by_weather := float(config.pull_by_weather.get(weather.state, config.pull_by_weather.get(String(weather.state), 0.0)))
	if by_weather < cold_pull(weather.temperature(now), config):
		return COLD
	match weather.state:
		WeatherSystem.STORM:
			return STORM
		WeatherSystem.BLIZZARD:
			return BLIZZARD
		WeatherSystem.SNOW:
			return SNOW
	return RAIN


## How fast work goes for the heat, 0 … 1 (1 = as usual).
static func work_pace(temperature: float, config: ExposureConfig = null) -> float:
	if config == null:
		config = Config.exposure
	return 1.0 - config.heat_slow * clampf((temperature - config.heat_from) / config.heat_span, 0.0, 1.0)


## How many times as much wood the fire burns for the cold (1 = as usual).
static func fire_factor(temperature: float, config: ExposureConfig = null) -> float:
	if config == null:
		config = Config.exposure
	return 1.0 + config.fire_cold_extra * clampf((config.fire_cold_from - temperature) / config.fire_cold_span, 0.0, 1.0)


## Is the person warm where they are: indoors (unless the fire is out in a
## deep cold), or by the burning fire?
static func is_warm(person: PersonData, ctx: AiContext, temperature: float, config: ExposureConfig = null) -> bool:
	if config == null:
		config = Config.exposure
	var lit := ctx.settlement != null and ctx.settlement.fire_lit()
	if person.has_flag(PersonData.FLAG_INDOORS):
		return lit or temperature >= config.deep_cold
	if lit and ctx.settlement.fire() != null:
		return person.world2d().distance_to(ctx.settlement.fire().position2d()) <= config.fire_radius
	return false


## Is the person ill with the cold?
static func is_sick(person: PersonData) -> bool:
	var condition := Hardship.condition_of(person, COLD)
	return bool(condition.get("sick", false)) and not bool(condition.get("fed", false))


## Lets `minutes` pass for what the cold does to a person.
static func live(person: PersonData, ctx: AiContext, minutes: float, config: ExposureConfig = null) -> void:
	if ctx.weather == null:
		return
	if config == null:
		config = Config.exposure
	var temperature := ctx.temperature()
	if temperature >= config.cold_from and person.conditions.is_empty():
		return # (nearly everyone, nearly always)
	var condition := Hardship.condition_of(person, COLD)
	var getting_cold := temperature < config.cold_from and not is_warm(person, ctx, temperature, config)
	if condition.is_empty():
		if getting_cold:
			person.conditions.append({"id": String(COLD), "exposed": minutes, "sick": false, "well": person.health, "fed": false})
		return
	var needs := Config.needs
	var day := float(TimeConfig.MINUTES_PER_DAY)
	if getting_cold:
		condition["fed"] = false
		condition["exposed"] = minf(float(condition.get("exposed", 0.0)) + minutes, config.cold_sick_after_minutes * 2.0)
		if not bool(condition.get("sick", false)):
			if float(condition["exposed"]) >= config.cold_sick_after_minutes:
				condition["sick"] = true
				ctx.ailments.append([person.id, COLD, true])
			return
		person.health = maxf(person.health - needs.sick_health_per_day * minutes / day, minf(needs.sick_health_floor, person.health))
		return
	# Warm (or the cold has passed): it goes out of them, and they get well.
	condition["exposed"] = maxf(float(condition.get("exposed", 0.0)) - minutes * config.warm_recover_factor, 0.0)
	if not bool(condition.get("sick", false)):
		if float(condition["exposed"]) <= 0.0:
			person.conditions.erase(condition)
		return
	if not bool(condition.get("fed", false)):
		if float(condition["exposed"]) > config.cold_sick_after_minutes * 0.5:
			return # (still chilled through)
		condition["fed"] = true
		ctx.ailments.append([person.id, COLD, false])
	var well := float(condition.get("well", 1.0))
	person.health = minf(person.health + needs.recover_health_per_day * Health.recovery(person) * minutes / day, maxf(well, person.health))
	if person.health >= well - 0.0001 and float(condition["exposed"]) <= 0.0:
		person.conditions.erase(condition)
