class_name ObserveTool
extends ToolBase
## Looking without touching (bible §23.2): a tap shows what something is
## instead of disturbing it, and nothing can be picked up. Nothing done with
## this tool is noticed by the world's inhabitants.

const ID := &"observe"


func _init() -> void:
	id = ID


func tap(target: Picker.Result) -> InteractionResponse:
	var report := ctx.session.interactions.inspect(target)
	if report != null and ctx.ui != null:
		ctx.ui.open_inspect(report, ctx.session.world.height_step)
	return null
