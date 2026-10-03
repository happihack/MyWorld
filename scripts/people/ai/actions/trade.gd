class_name TradeStep
extends ActionStep
## Trade and craft (M12.4), in three kinds of step:
##   {"type": "trade_load", "settlement": int, "resource", "units", "minutes", "elapsed"} — take a load
##     out of a settlement's stores (one's own, or the one traded with);
##   {"type": "trade_unload", "settlement": int, "from": int, "minutes", "elapsed"} — put it into a
##     settlement's stores (counted as trade when it is not one's own);
##   {"type": "craft", "workshop": prop id, "at": Vector2i, "minutes", "elapsed", "strokes"} — make a tool at the workshop,
##     from wood and stone of the stores.

const LOAD := &"trade_load"
const UNLOAD := &"trade_unload"
const CRAFT := &"craft"
const HANDLING_MINUTES := 4.0
const STROKE_MINUTES := 3.0


static func load_at(settlement_id: int, resource: StringName, units: int) -> Dictionary:
	return {"type": String(LOAD), "settlement": settlement_id, "resource": String(resource), "units": units,
		"minutes": HANDLING_MINUTES, "elapsed": 0.0}


static func unload_at(settlement_id: int, from_id: int) -> Dictionary:
	return {"type": String(UNLOAD), "settlement": settlement_id, "from": from_id, "minutes": HANDLING_MINUTES, "elapsed": 0.0}


static func craft(workshop_id: int, at: Vector2i, minutes: float) -> Dictionary:
	return {"type": String(CRAFT), "workshop": workshop_id, "at": at, "minutes": minutes, "elapsed": 0.0, "strokes": 0}


func begin(ctx: AiContext, person: PersonData, step: Dictionary) -> void:
	person.pose = PersonData.Pose.WORK
	if typeof(step.get("at")) == TYPE_VECTOR2I:
		ctx.face(person, middle(step["at"]))


func update(ctx: AiContext, person: PersonData, step: Dictionary, minutes: float) -> Status:
	match StringName(str(step.get("type", ""))):
		LOAD:
			if not tick(step, minutes):
				return Status.RUNNING
			var there := _settlement(ctx, int(step.get("settlement", 0)))
			var resource := StringName(str(step.get("resource", "")))
			if there == null or (person.carrying_amount > 0 and person.carrying != resource):
				return Status.FAILED
			var room := floori(ctx.carry_capacity(resource) * Config.trade.pack_factor) - person.carrying_amount
			var taken := there.stockpile.take(resource, mini(int(step.get("units", 0)), room)) if room > 0 else 0
			if taken <= 0:
				return Status.DONE # (nothing to take after all: they go on without it)
			person.carrying = resource
			person.carrying_amount += taken
			return Status.DONE
		UNLOAD:
			if not tick(step, minutes):
				return Status.RUNNING
			var there := _settlement(ctx, int(step.get("settlement", 0)))
			if there == null or person.carrying_amount <= 0:
				return Status.DONE
			var resource := person.carrying
			var units := person.carrying_amount
			there.stockpile.add(resource, units)
			person.carrying = &""
			person.carrying_amount = 0
			Needs.satisfy(person.needs, Needs.Need.PURPOSE, Config.resources.load_purpose)
			var from := int(step.get("from", 0))
			if ctx.trade != null and from != there.id:
				ctx.trade.delivered(from, there.id, resource, units, person.id)
			return Status.DONE
	# Crafting at the workshop.
	Needs.satisfy(person.needs, Needs.Need.PURPOSE, minutes / Config.needs.full_work_minutes)
	var time_up := tick(step, minutes)
	var strokes := int(float(step["elapsed"]) / STROKE_MINUTES)
	if strokes > int(step.get("strokes", 0)):
		step["strokes"] = strokes
		ctx.strokes.append([person.id, &"craft", int(step.get("workshop", 0))])
	if not time_up:
		return Status.RUNNING
	if ctx.settlement != null:
		ctx.settlement.make_tool(person)
	return Status.DONE


func needs_state(_step: Dictionary) -> Needs.State:
	return Needs.State.WORKING


func patience(step: Dictionary) -> int:
	return 1 if str(step.get("type", "")) == String(CRAFT) else 2


static func _settlement(ctx: AiContext, id: int) -> Settlement:
	if ctx.settlements != null:
		return ctx.settlements.get_settlement(id)
	return ctx.settlement if ctx.settlement != null and ctx.settlement.id == id else null
