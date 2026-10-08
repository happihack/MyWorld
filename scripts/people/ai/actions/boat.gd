class_name BoatStep
extends ActionStep
## Out in a boat (FB3–FB4, bible §18.2a): aboard at the landing, paddled out
## to good water (where the fish are thick), fishing there a while, and back
## to the landing — when the arms are full, the time is up, at dusk, or ahead
## of a storm. Out in a storm a boat may be swamped: the catch lost, the crew
## ashore as best they can (only in the worst of it — a storm on high water —
## may someone drown: the owner, D1).
##   {"type": "boat", "landing": int (prop id), "boat": int (0 until aboard),
##    "at": Vector2i (the water fished; Vector2i.MAX until chosen),
##    "minutes": float (fishing), "elapsed": float, "strokes": int, "effort": float,
##    "phase": "out" | "fish" | "back", "fish": true}

const TYPE := &"boat"
## Home before dark.
const DUSK_HOUR := 18.5
## Out in a storm, a boat is swamped this often an hour.
const SWAMP_PER_HOUR := 0.25
## How high in the boat one sits (above the water).
const SEAT := 0.04
## Too long on the way (a way that cannot be made): home.
const MOST_MINUTES_OUT := 240.0


static func make(landing_id: int, minutes: float) -> Dictionary:
	return {"type": String(TYPE), "landing": landing_id, "boat": 0, "at": Vector2i.MAX, "minutes": minutes,
		"elapsed": 0.0, "strokes": 0, "effort": 0.0, "phase": "out", "fish": true, "way": 0.0}


## Taking the catch out of a boat tied up at `landing_id` (as much as the arms
## hold), to carry to the stores (FB4).
static func unload(landing_id: int) -> Dictionary:
	return {"type": String(TYPE), "landing": landing_id, "boat": 0, "unload": true}


## A boat tied up at this landing with fish in it (null: none).
static func laden_at(boats: BoatSystem, landing_id: int) -> BoatData:
	if boats == null:
		return null
	for boat in boats.boats_of(landing_id):
		if boat.state == BoatData.State.MOORED and boat.load_resource == &"fish" and boat.load_amount > 0:
			return boat
	return null


func begin(ctx: AiContext, person: PersonData, step: Dictionary) -> void:
	if bool(step.get("unload", false)):
		person.pose = PersonData.Pose.CROUCH
		var laden := laden_at(ctx.boats, int(step.get("landing", 0)))
		if laden != null and (person.carrying_amount == 0 or person.carrying == &"fish"):
			var room := ctx.carry_capacity(&"fish") - person.carrying_amount
			var taken := mini(room, laden.load_amount)
			laden.load_amount -= taken
			if laden.load_amount == 0:
				laden.load_resource = &""
			if taken > 0:
				person.carrying = &"fish"
				person.carrying_amount += taken
		step["phase"] = "unloaded"
		return
	person.pose = PersonData.Pose.SEATED
	var boats := ctx.boats
	if boats == null:
		step["phase"] = "fail"
		return
	var boat := boats.get_boat(int(step.get("boat", 0))) if int(step.get("boat", 0)) != 0 else boats.boat_to_take(int(step.get("landing", 0)))
	if boat == null:
		step["phase"] = "fail"
		return
	# (Where to, before going aboard: nowhere worth going, no going out.)
	if str(step.get("phase", "out")) == "out" and step.get("at") == Vector2i.MAX:
		var water: Variant = boats.fishing_water(boat)
		if water == null:
			boats.no_water += 1
			boats.not_worth(int(step.get("landing", 0)))
			step["phase"] = "fail"
			return
		step["at"] = water
	if not boats.board(boat, person.id):
		step["phase"] = "fail"
		return
	step["boat"] = boat.id
	person.aboard = boat.id
	_follow(ctx, person, boat)


func update(ctx: AiContext, person: PersonData, step: Dictionary, minutes: float) -> Status:
	if str(step.get("phase", "")) == "fail" or ctx.boats == null:
		return Status.FAILED
	if bool(step.get("unload", false)):
		return Status.DONE if person.carrying_amount > 0 else Status.FAILED
	var boats := ctx.boats
	var boat := boats.get_boat(int(step.get("boat", 0)))
	if boat == null or boat.state != BoatData.State.OUT or not boat.crew.has(person.id):
		return Status.FAILED # (swamped, carried off: ashore — see end)
	Needs.satisfy(person.needs, Needs.Need.PURPOSE, minutes / Config.needs.full_work_minutes)
	var stormy := _stormy(ctx)
	if stormy and ctx.rng != null and ctx.rng.randf() < SWAMP_PER_HOUR * minutes / 60.0:
		boats.swamp(boat, ctx.now())
		return Status.FAILED
	var phase := str(step.get("phase", "out"))
	if phase != "back" and (stormy or _late(ctx)):
		phase = "back"
	match phase:
		"out":
			step["way"] = float(step.get("way", 0.0)) + minutes
			var got := boats.paddle(boat, ActionStep.middle(step["at"]), minutes)
			if got == 1:
				phase = "fish"
			elif got == -1 or float(step["way"]) > MOST_MINUTES_OUT:
				phase = "back"
		"fish":
			ctx.face(person, ActionStep.middle(step["at"]))
			var time_up := tick(step, minutes)
			var strokes := int(float(step["elapsed"]) / WorkStep.STROKE_MINUTES)
			if strokes > int(step.get("strokes", 0)):
				var made := strokes - int(step.get("strokes", 0))
				step["strokes"] = strokes
				ctx.strokes.append([person.id, &"fish", 0])
				if WorkStep.catch_fish(ctx, person, step, made):
					time_up = true
			if time_up:
				phase = "back"
		"back":
			var got := boats.paddle(boat, boats.mooring_of(boat), minutes)
			if got != 0:
				step["phase"] = "home"
				_follow(ctx, person, boat)
				return Status.DONE
	step["phase"] = phase
	_follow(ctx, person, boat)
	return Status.RUNNING


func end(ctx: AiContext, person: PersonData, step: Dictionary) -> void:
	person.pose = PersonData.Pose.IDLE
	person.aboard = 0
	person.aboard_height = 0.0
	if int(step.get("boat", 0)) == 0:
		return # (never went aboard: still on the landing)
	var boats := ctx.boats
	var boat := boats.get_boat(int(step.get("boat", 0))) if boats != null else null
	var landing := ctx.props.get_prop(int(step.get("landing", 0))) if ctx.props != null else null
	if boat != null and boat.crew.has(person.id):
		# (However it ended, they come in: dropped for something else, they paddled home.)
		if boat.crew.size() == 1 and boat.state == BoatData.State.OUT:
			boats.bring_in(boat)
		else:
			boats.step_off(boat, person.id)
	# Ashore: on the landing — or, swamped far from it, the bank nearest.
	var ashore: Variant = null
	if boat != null and boat.state == BoatData.State.MOORED and landing != null:
		ashore = landing.tile
	elif ctx.places != null:
		ashore = ctx.places.fishing_bank(person.position)
	if ashore == null and landing != null:
		ashore = landing.tile
	if ashore != null and ctx.people != null:
		ctx.people.move(person.id, ashore)


func reluctance(step: Dictionary) -> float:
	return 0.6 if str(step.get("phase", "")) != "fail" else 0.0


func needs_state(_step: Dictionary) -> Needs.State:
	return Needs.State.WORKING


## The one aboard sits where the boat is.
static func _follow(ctx: AiContext, person: PersonData, boat: BoatData) -> void:
	if ctx.people == null:
		return
	var tile := boat.tile()
	var along := Vector2(sin(boat.heading), cos(boat.heading))
	var seat := boat.crew.find(person.id)
	var at := boat.position - along * 0.2 * float(seat - (boat.crew.size() - 1) * 0.5)
	tile = WorldCoords.world2d_to_tile(at)
	var offset := (at - Vector2(tile)).clamp(Vector2.ZERO, Vector2(0.999, 0.999))
	person.aboard_height = maxf(ctx.world.get_water(boat.tile()), 0.0) + SEAT if ctx.world != null else boat.height + SEAT
	ctx.people.place(person, tile, offset, atan2(along.y, along.x))


static func _stormy(ctx: AiContext) -> bool:
	return ctx.weather != null and ctx.weather.is_storm()


static func _late(ctx: AiContext) -> bool:
	return ctx.clock != null and ctx.clock.hour() >= DUSK_HOUR
