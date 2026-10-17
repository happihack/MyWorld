class_name BlessingBar
extends DisasterBar
## The blessings to choose from (the owner and Josh, 2026-10-16): a row of
## small round buttons that slides out to the left of the Blessing button,
## as the disasters do from theirs — lights in the sky, and the rest as they
## come. Each draws its own glyph.

const GOLD := Color(0.93, 0.78, 0.40)


func _init() -> void:
	super._init()
	name = "BlessingBar"


func kinds() -> Array[StringName]:
	return BlessingSystem.KINDS


func tooltip_key(kind: StringName) -> String:
	return "BLESSING_" + String(kind).to_upper()


func glyph(canvas: CanvasItem, kind: StringName, center: Vector2, u: float, ink: Color, lit: bool) -> void:
	draw_blessing_glyph(canvas, kind, center, u, ink, lit)


## The sign of a blessing, drawn on `canvas` around `center` (`u`: a unit
## of its size).
static func draw_blessing_glyph(canvas: CanvasItem, kind: StringName, center: Vector2, u: float, ink: Color, lit: bool = true) -> void:
	var width := maxf(u * 0.22, 2.0)
	match kind:
		BlessingSystem.LIGHTS:
			# Lights over the land: a horizon, and rays rising from behind it in a fan.
			canvas.draw_line(center + Vector2(-1.25, 0.7) * u, center + Vector2(1.25, 0.7) * u, ink, width, true)
			for i in 5:
				var angle := -PI * 0.5 + (i - 2) * 0.42
				var from := center + Vector2(0.0, 0.7) * u + Vector2.from_angle(angle) * u * 0.35
				var to := center + Vector2(0.0, 0.7) * u + Vector2.from_angle(angle) * u * (1.45 if i % 2 == 0 else 1.1)
				canvas.draw_line(from, to, GOLD if lit else ink, width * 0.8, true)
		_:
			canvas.draw_arc(center, u * 0.8, 0.0, TAU, 24, ink, width, true)
