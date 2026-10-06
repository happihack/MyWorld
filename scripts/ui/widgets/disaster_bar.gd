class_name DisasterBar
extends HBoxContainer
## The disasters to choose from (the owner's design, 2026-10-05): a row of
## small round buttons that slides out to the left of the Disaster button —
## earthquake, eclipse, storm, flood, whirlwind, blood, falling stars. Half
## the size of the buttons in the column. Each draws its own glyph.

## One was picked (the warning comes next).
signal chosen(kind: StringName)

const BLOOD_RED := Color(0.80, 0.10, 0.12)
const STAR := Color(1.0, 0.70, 0.30)

var _buttons: Dictionary = {} # kind -> Button
## Can one be brought down now (else they are shown resting, dimmed)?
var can_strike := true:
	set(value):
		can_strike = value
		for button: Button in _buttons.values():
			button.queue_redraw()


func _init() -> void:
	name = "DisasterBar"
	mouse_filter = Control.MOUSE_FILTER_IGNORE # only the buttons take touches
	add_theme_constant_override(&"separation", 14)
	for kind in DisasterSystem.KINDS:
		var button := Button.new()
		button.name = String(kind).capitalize().replace(" ", "")
		button.flat = true
		button.focus_mode = Control.FOCUS_NONE
		button.text = ""
		button.tooltip_text = MemoryText.translate("DISASTER_" + String(kind).to_upper())
		var side := size_of_one()
		button.custom_minimum_size = Vector2(side, side)
		button.add_to_group(InputRouter.UI_BLOCKER_GROUP) # touches here never reach the world
		button.draw.connect(_draw_button.bind(button, kind))
		button.button_down.connect(button.queue_redraw)
		button.button_up.connect(button.queue_redraw)
		button.pressed.connect(func() -> void: chosen.emit(kind))
		add_child(button)
		_buttons[kind] = button


## Half as big as the round buttons of the column.
static func size_of_one() -> float:
	return roundf(SpeedControl.BUTTON_SIZE * 0.5)


func button(kind: StringName) -> Button:
	return _buttons.get(kind)


func _draw_button(button: Button, kind: StringName) -> void:
	var center := button.size * 0.5
	var radius := minf(button.size.x, button.size.y) * 0.5 - 1.0
	button.draw_circle(center, radius, HomeButton.BACKDROP_PRESSED if button.button_pressed else HomeButton.BACKDROP)
	button.draw_arc(center, radius, 0.0, TAU, 32, HomeButton.RING, maxf(radius * 0.07, 1.5), true)
	var ink := HomeButton.GLYPH if can_strike else Color(HomeButton.GLYPH, 0.35)
	draw_glyph(button, kind, center, radius * 0.44, ink, can_strike)


## The sign of a disaster, drawn on `canvas` around `center` (`u`: a unit
## of its size).
static func draw_glyph(canvas: CanvasItem, kind: StringName, center: Vector2, u: float, ink: Color, lit: bool = true) -> void:
	var width := maxf(u * 0.22, 2.0)
	match kind:
		DisasterSystem.EARTHQUAKE:
			# The ground cracked, and shaking above it.
			var crack := PackedVector2Array()
			for p: Vector2 in [Vector2(-1.25, 0.45), Vector2(-0.6, 0.45), Vector2(-0.35, -0.05), Vector2(-0.05, 0.85),
					Vector2(0.25, 0.2), Vector2(0.55, 0.45), Vector2(1.25, 0.45)]:
				crack.append(center + p * u)
			canvas.draw_polyline(crack, ink, width, true)
			for side: float in [-1.0, 1.0]:
				canvas.draw_arc(center + Vector2(side * 0.55, -0.35) * u, u * 0.35, PI * 1.15, PI * 1.85, 8, ink, width * 0.7, true)
		DisasterSystem.ECLIPSE:
			# The dark sun, its fire round its rim.
			for i in 8:
				var way := Vector2.from_angle(TAU * i / 8.0)
				canvas.draw_line(center + way * u * 1.05, center + way * u * 1.35, ink, width * 0.7, true)
			canvas.draw_circle(center, u * 0.85, ink)
			canvas.draw_circle(center + Vector2(0.18, -0.12) * u, u * 0.72, HomeButton.BACKDROP_PRESSED)
		DisasterSystem.STORM:
			# A cloud, and lightning out of it.
			var base := center + Vector2(0.0, -u * 0.35)
			canvas.draw_circle(base + Vector2(-u * 0.55, u * 0.1), u * 0.42, ink)
			canvas.draw_circle(base + Vector2(u * 0.05, -u * 0.2), u * 0.58, ink)
			canvas.draw_circle(base + Vector2(u * 0.62, u * 0.12), u * 0.4, ink)
			canvas.draw_rect(Rect2(base + Vector2(-u * 0.55, u * 0.08), Vector2(u * 1.17, u * 0.44)), ink)
			canvas.draw_colored_polygon(PackedVector2Array([center + Vector2(0.1, 0.15) * u, center + Vector2(-0.35, 0.8) * u,
				center + Vector2(-0.02, 0.72) * u, center + Vector2(-0.2, 1.3) * u, center + Vector2(0.4, 0.55) * u,
				center + Vector2(0.06, 0.62) * u, center + Vector2(0.32, 0.15) * u]), STAR if lit else ink)
		DisasterSystem.FLOOD:
			# Waves, one over the other.
			for row in 3:
				var wave := PackedVector2Array()
				for n in 13:
					var x := lerpf(-1.2, 1.2, n / 12.0)
					wave.append(center + Vector2(x, (row - 1) * 0.62 + sin(x * 4.0) * 0.16) * u)
				canvas.draw_polyline(wave, ink, width, true)
		DisasterSystem.TORNADO:
			# A funnel of wind, narrowing to the ground.
			for row in 5:
				var half := lerpf(1.25, 0.2, row / 4.0)
				var y := lerpf(-1.0, 0.95, row / 4.0)
				var x := sin(row * 1.3) * 0.12
				canvas.draw_line(center + Vector2(x - half, y) * u, center + Vector2(x + half, y) * u, ink, width, true)
		DisasterSystem.BLOOD:
			# A drop, red.
			var red := BLOOD_RED if lit else ink
			var belly := center + Vector2(0.0, u * 0.35)
			canvas.draw_circle(belly, u * 0.72, red)
			canvas.draw_colored_polygon(PackedVector2Array([center + Vector2(0.0, -u * 1.25),
				belly + Vector2(u * 0.66, -u * 0.28), belly + Vector2(-u * 0.66, -u * 0.28)]), red)
		DisasterSystem.METEORS:
			# A burning stone, its trail behind it.
			var head := center + Vector2(-0.45, 0.45) * u
			for n in 3:
				var off := Vector2(-0.3 + n * 0.3, 0.3 - n * 0.3) * u * 0.6
				canvas.draw_line(head + off, head + off + Vector2(1.5, -1.5) * u * (0.9 - n * 0.15), ink, width * 0.8, true)
			canvas.draw_circle(head, u * 0.5, STAR if lit else ink)
