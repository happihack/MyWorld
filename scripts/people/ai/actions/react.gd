class_name ReactStep
extends ActionStep
## Show what one feels for a while (bible §14.4): turn to what happened, hold
## a pose, with a sign above the head.
##   {"type": "react", "pose": int (PersonData.Pose), "emote": String,
##    "minutes": float, "elapsed": float, "look": Vector2 (optional, world X/Z)}

const TYPE := &"react"


static func make(pose: PersonData.Pose, emote: StringName, minutes: float, look_at: Variant = null) -> Dictionary:
	var step := {"type": String(TYPE), "pose": int(pose), "emote": String(emote), "minutes": minutes, "elapsed": 0.0}
	if typeof(look_at) == TYPE_VECTOR2:
		step["look"] = look_at
	return step


func begin(ctx: AiContext, person: PersonData, step: Dictionary) -> void:
	var pose := int(step.get("pose", PersonData.Pose.IDLE))
	person.pose = pose as PersonData.Pose if pose >= 0 and pose < PersonData.Pose.size() else PersonData.Pose.IDLE
	person.emote = StringName(str(step.get("emote", "")))
	if typeof(step.get("look")) == TYPE_VECTOR2:
		ctx.face(person, step["look"])


func update(_ctx: AiContext, _person: PersonData, step: Dictionary, minutes: float) -> Status:
	return Status.DONE if tick(step, minutes) else Status.RUNNING


func end(ctx: AiContext, person: PersonData, step: Dictionary) -> void:
	person.emote = &""
	super.end(ctx, person, step)
