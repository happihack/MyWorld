class_name PersonData
extends RefCounted
## One inhabitant, as data (bible §13.1). Never a node: people who need to be
## seen get a pooled view (M4.2); everyone else is only this.
##
## Fields that later milestones fill (needs, memories, beliefs, knowledge,
## goals, the current action) exist already and are saved empty, so that the
## save format does not change shape when they come alive.

enum Sex { FEMALE, MALE }
enum LifeStage { CHILD, ADOLESCENT, ADULT, ELDER }

const FLAG_MARKED_IMPORTANT := 1 << 0
const FLAG_FOLLOWED := 1 << 1
const FLAG_TOUCHED_BY_PLAYER := 1 << 2
const FLAG_QUARANTINED := 1 << 3
## Inside a building (asleep at home): there, but not to be seen.
const FLAG_INDOORS := 1 << 4

## How someone holds themselves while doing something (what the view shows).
enum Pose { IDLE, WORK, EAT, TALK, SLEEP }

## How many skin, hair and clothing colours an appearance can index (the
## palettes themselves belong to the rendering, M4.2).
const SKIN_TONES := 6
const HAIR_COLOURS := 5
const CLOTH_COLOURS := 6

## Persistent, never reused.
var id := 0
var given_name := ""
var family_name := ""
## Age is always derived from this and the clock (it is negative for people
## born before the world's first tick).
var birth_tick := 0
var sex: Sex = Sex.FEMALE
var health := 1.0
var injuries: Array = []
var conditions: Array = []
## One value per Traits.Axis.
var traits: PackedFloat32Array = Traits.neutral()
## One value 0 … 1 per need (M4.4).
var needs: PackedFloat32Array = PackedFloat32Array()
var mood := 0.5
var stress := 0.0
var occupation_id: StringName = &""
## occupation or skill id (String) -> level 0 … 1.
var skills: Dictionary = {}
var household_id := 0
var home_building_id := 0
var workplace_id := 0
var settlement_id := 0
## Mother and father, if known. Lineage outlives the people themselves.
var parents: PackedInt64Array = PackedInt64Array()
var children: PackedInt64Array = PackedInt64Array()
var partner_id := 0
var memory_ids: PackedInt64Array = PackedInt64Array()
var beliefs: PackedFloat32Array = PackedFloat32Array()
var knowledge: Dictionary = {}
var goals: Array = []
## What they are doing: the activity, why, and its steps, as plain data
## (see BehaviorSystem). Empty = nothing decided yet.
var current_action: Dictionary = {}
## Activity id (String) -> the tick they last finished doing it.
var activity_log: Dictionary = {}
## The tile stood on, where on it (0 … 1 across the tile) and the direction
## faced (radians; 0 looks along +X, a quarter turn looks along +Z).
var position := Vector2i.ZERO
var sub_tile_offset := Vector2(0.5, 0.5)
var facing := 0.0
## How closely this person is simulated right now. Runtime only, never saved.
var sim_tier := 3
## Runtime only: set by whatever they are doing, shown by their view.
var pose: Pose = Pose.IDLE
var significance := 0.0
var flags := 0
## Body and colours: "height" and "build" (scale factors), "skin", "hair" and
## "cloth" (palette indices).
var appearance: Dictionary = {}


func full_name() -> String:
	return given_name if family_name == "" else "%s %s" % [given_name, family_name]


## Position on the world's XZ plane (x = world X, y = world Z).
func world2d() -> Vector2:
	return Vector2(position) + sub_tile_offset


## Whole years lived at `now_tick`.
func age_years(now_tick: int, ticks_per_year: int) -> int:
	return maxi(now_tick - birth_tick, 0) / maxi(ticks_per_year, 1)


func life_stage(now_tick: int, ticks_per_year: int, config: PeopleConfig) -> LifeStage:
	return config.stage_for_age(age_years(now_tick, ticks_per_year))


func has_flag(flag: int) -> bool:
	return (flags & flag) != 0


func set_flag(flag: int, enabled: bool) -> void:
	flags = (flags | flag) if enabled else (flags & ~flag)


func to_dict() -> Dictionary:
	return {
		"id": id, "given_name": given_name, "family_name": family_name,
		"birth_tick": birth_tick, "sex": sex,
		"health": health, "injuries": injuries.duplicate(true), "conditions": conditions.duplicate(true),
		"traits": traits.duplicate(), "needs": needs.duplicate(),
		"mood": mood, "stress": stress,
		"occupation_id": String(occupation_id), "skills": skills.duplicate(),
		"household_id": household_id, "home_building_id": home_building_id,
		"workplace_id": workplace_id, "settlement_id": settlement_id,
		"parents": parents.duplicate(), "children": children.duplicate(), "partner_id": partner_id,
		"memory_ids": memory_ids.duplicate(), "beliefs": beliefs.duplicate(),
		"knowledge": knowledge.duplicate(true), "goals": goals.duplicate(true),
		"current_action": current_action.duplicate(true),
		"activity_log": activity_log.duplicate(),
		"position": position, "sub_tile_offset": sub_tile_offset, "facing": facing,
		"significance": significance, "flags": flags,
		"appearance": appearance.duplicate(),
	}


## Null if the record is unusable (no id or no place in the world). Everything
## else falls back to a harmless default.
static func from_dict(data: Dictionary) -> PersonData:
	if typeof(data.get("id")) != TYPE_INT or int(data["id"]) <= 0 \
			or typeof(data.get("position")) != TYPE_VECTOR2I:
		return null
	var p := PersonData.new()
	p.id = data["id"]
	p.given_name = str(data.get("given_name", ""))
	p.family_name = str(data.get("family_name", ""))
	p.birth_tick = int(data.get("birth_tick", 0))
	p.sex = Sex.MALE if int(data.get("sex", 0)) == Sex.MALE else Sex.FEMALE
	p.health = _unit(data.get("health"), 1.0)
	p.injuries = _array(data.get("injuries"))
	p.conditions = _array(data.get("conditions"))
	p.traits = Traits.sanitized(_floats(data.get("traits")))
	p.needs = _floats(data.get("needs"))
	for i in p.needs.size():
		p.needs[i] = clampf(p.needs[i], 0.0, 1.0) if is_finite(p.needs[i]) else 0.0
	p.mood = _unit(data.get("mood"), 0.5)
	p.stress = _unit(data.get("stress"), 0.0)
	p.occupation_id = StringName(str(data.get("occupation_id", "")))
	p.skills = _dict(data.get("skills"))
	p.household_id = maxi(int(data.get("household_id", 0)), 0)
	p.home_building_id = maxi(int(data.get("home_building_id", 0)), 0)
	p.workplace_id = maxi(int(data.get("workplace_id", 0)), 0)
	p.settlement_id = maxi(int(data.get("settlement_id", 0)), 0)
	p.parents = _ids(data.get("parents"))
	p.children = _ids(data.get("children"))
	p.partner_id = maxi(int(data.get("partner_id", 0)), 0)
	p.memory_ids = _ids(data.get("memory_ids"))
	p.beliefs = _floats(data.get("beliefs"))
	p.knowledge = _dict(data.get("knowledge"))
	p.goals = _array(data.get("goals"))
	p.current_action = _dict(data.get("current_action"))
	p.activity_log = _dict(data.get("activity_log"))
	p.position = data["position"]
	var offset: Variant = data.get("sub_tile_offset")
	if typeof(offset) == TYPE_VECTOR2 and is_finite((offset as Vector2).x) and is_finite((offset as Vector2).y):
		p.sub_tile_offset = (offset as Vector2).clamp(Vector2.ZERO, Vector2(0.999, 0.999))
	var turn := float(data.get("facing", 0.0))
	p.facing = turn if is_finite(turn) else 0.0
	var weight := float(data.get("significance", 0.0))
	p.significance = maxf(weight, 0.0) if is_finite(weight) else 0.0
	p.flags = int(data.get("flags", 0))
	p.appearance = _dict(data.get("appearance"))
	return p


static func _unit(value: Variant, fallback: float) -> float:
	if typeof(value) != TYPE_FLOAT and typeof(value) != TYPE_INT:
		return fallback
	var number := float(value)
	return clampf(number, 0.0, 1.0) if is_finite(number) else fallback


static func _array(value: Variant) -> Array:
	return (value as Array).duplicate(true) if typeof(value) == TYPE_ARRAY else []


static func _dict(value: Variant) -> Dictionary:
	return (value as Dictionary).duplicate(true) if typeof(value) == TYPE_DICTIONARY else {}


static func _floats(value: Variant) -> PackedFloat32Array:
	return (value as PackedFloat32Array).duplicate() if typeof(value) == TYPE_PACKED_FLOAT32_ARRAY else PackedFloat32Array()


static func _ids(value: Variant) -> PackedInt64Array:
	var out := PackedInt64Array()
	if typeof(value) == TYPE_PACKED_INT64_ARRAY:
		for id_value: int in value:
			if id_value > 0:
				out.append(id_value)
	return out
