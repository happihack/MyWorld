class_name BlessingBar
extends DisasterBar
## The blessings to choose from (the owner and Josh, 2026-10-16): a row of
## small round buttons that slides out to the left of the Blessing button,
## as the disasters do from theirs — lights in the sky, and the rest as they
## come. Each draws its own glyph.

const GOLD := Color(0.93, 0.78, 0.40)
const BERRY := Color(0.78, 0.18, 0.28)


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
		BlessingSystem.BOUNTY:
			# A bush: a round crown on a short stem, three berries on it.
			canvas.draw_arc(center + Vector2(0.0, -0.1) * u, u * 0.95, 0.0, TAU, 24, ink, width, true)
			canvas.draw_line(center + Vector2(0.0, 0.85) * u, center + Vector2(0.0, 1.35) * u, ink, width, true)
			for p: Vector2 in [Vector2(-0.4, -0.3), Vector2(0.35, -0.05), Vector2(-0.05, 0.4)]:
				canvas.draw_circle(center + p * u, u * 0.18, BERRY if lit else ink)
		BlessingSystem.SOIL:
			# Furrows, and a sprout standing up from the middle one.
			for row: float in [0.35, 0.8, 1.25]:
				canvas.draw_line(center + Vector2(-1.2, row) * u, center + Vector2(1.2, row) * u, ink, width * 0.8, true)
			canvas.draw_line(center + Vector2(0.0, 0.35) * u, center + Vector2(0.0, -0.9) * u, ink, width, true)
			canvas.draw_arc(center + Vector2(-0.45, -0.55) * u, u * 0.45, -PI * 0.1, PI * 0.5, 8, GOLD if lit else ink, width * 0.8, true)
			canvas.draw_arc(center + Vector2(0.45, -0.85) * u, u * 0.45, PI * 0.5, PI * 1.1, 8, GOLD if lit else ink, width * 0.8, true)
		BlessingSystem.WATERS:
			# A fish: a leaf-shaped body and a forked tail, over a ripple.
			var body := PackedVector2Array()
			for i in 13:
				var t := float(i) / 12.0 * TAU
				body.append(center + Vector2(cos(t) * 0.85, sin(t) * 0.4 - 0.15) * u)
			canvas.draw_polyline(body, ink, width, true)
			canvas.draw_polyline(PackedVector2Array([center + Vector2(0.8, -0.15) * u, center + Vector2(1.3, -0.6) * u,
				center + Vector2(1.3, 0.3) * u, center + Vector2(0.8, -0.15) * u]), ink, width * 0.8, true)
			canvas.draw_circle(center + Vector2(-0.4, -0.25) * u, u * 0.09, ink)
			canvas.draw_arc(center + Vector2(0.0, 1.0) * u, u * 0.9, PI * 1.15, PI * 1.85, 10, GOLD if lit else ink, width * 0.7, true)
		_:
			canvas.draw_arc(center, u * 0.8, 0.0, TAU, 24, ink, width, true)
