class_name SafeArea
extends RefCounted
## The part of the screen the phone lets the HUD use (bible §26.4): inside the
## notch and above the home indicator on iOS, clear of the camera hole on
## Android. The corner controls keep their margins, measured from here rather
## than from the screen's edge (the owner, 2026-10-15: on the iPhone 14 the ☰
## and the clock sat under the notch).
##
## iOS says where the safe area is (DisplayServer.get_display_safe_area);
## Android says where the cutouts are (get_display_cutouts) — on it only a
## cutout that crosses a control moves it, so the Note20's hole at the top
## centre moves the follow banner and not the corners. Insets are in the
## canvas's units (the HUD's), not the window's pixels. Headless and desktop:
## zero, so nothing moves in the editor or the tests.

## What a phone would say, for tests and tools: the window in pixels, the
## safe area in it (iOS-style) and the cutouts (Android-style). When the
## window is set they stand in for the phone — on any platform, headless
## included. Clear them with `stop_pretending`.
static var pretend_window := Vector2i.ZERO
static var pretend_safe_area := Rect2i()
static var pretend_cutouts: Array[Rect2i] = []


## How far in from `edge` (SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM) a
## control must sit to be clear of the screen's furniture, in canvas units.
## `along` is the control's span across that edge (its x-range for the top
## and bottom edges, its y-range for the sides): on Android only a cutout
## that crosses it counts. Left out, the whole edge counts.
static func inset(viewport: Viewport, edge: Side, along := Vector2(-INF, INF)) -> float:
	if viewport == null:
		return 0.0
	var window := Vector2(_window())
	if window.x <= 0.0 or window.y <= 0.0:
		return 0.0
	var per_pixel := viewport.get_visible_rect().size / window
	var across := per_pixel.y if edge == SIDE_TOP or edge == SIDE_BOTTOM else per_pixel.x
	var safe := _safe_area()
	if safe.size != Vector2i.ZERO:
		var pixels := 0.0
		match edge:
			SIDE_LEFT:
				pixels = safe.position.x
			SIDE_TOP:
				pixels = safe.position.y
			SIDE_RIGHT:
				pixels = window.x - safe.end.x
			SIDE_BOTTOM:
				pixels = window.y - safe.end.y
		return maxf(pixels, 0.0) * across
	var deepest := 0.0
	for cutout in _cutouts():
		var rect := Rect2(cutout)
		# A cutout is on the edge it lies near (a fifth of the screen, as the
		# banner judged it): its depth is how far it reaches in from there.
		var depth := 0.0
		var span := Vector2.ZERO
		match edge:
			SIDE_LEFT:
				if rect.position.x < window.x * 0.2:
					depth = rect.end.x * per_pixel.x
					span = Vector2(rect.position.y, rect.end.y) * per_pixel.y
			SIDE_TOP:
				if rect.position.y < window.y * 0.2:
					depth = rect.end.y * per_pixel.y
					span = Vector2(rect.position.x, rect.end.x) * per_pixel.x
			SIDE_RIGHT:
				if rect.end.x > window.x * 0.8:
					depth = (window.x - rect.position.x) * per_pixel.x
					span = Vector2(rect.position.y, rect.end.y) * per_pixel.y
			SIDE_BOTTOM:
				if rect.end.y > window.y * 0.8:
					depth = (window.y - rect.position.y) * per_pixel.y
					span = Vector2(rect.position.x, rect.end.x) * per_pixel.x
		if depth > deepest and span.y > along.x and span.x < along.y:
			deepest = depth
	return deepest


## Pretends to be a phone, for tests and tools: `window` in pixels, with a
## `safe_area` in it (iOS) or `cutouts` (Android).
static func pretend(window: Vector2i, safe_area := Rect2i(), cutouts: Array[Rect2i] = []) -> void:
	pretend_window = window
	pretend_safe_area = safe_area
	pretend_cutouts = cutouts


static func stop_pretending() -> void:
	pretend(Vector2i.ZERO)


static func _window() -> Vector2i:
	if pretend_window != Vector2i.ZERO:
		return pretend_window
	if DisplayServer.get_name() == "headless":
		return Vector2i.ZERO
	return DisplayServer.window_get_size()


static func _safe_area() -> Rect2i:
	if pretend_window != Vector2i.ZERO:
		return pretend_safe_area
	if OS.get_name() == "iOS":
		return DisplayServer.get_display_safe_area()
	return Rect2i()


static func _cutouts() -> Array[Rect2i]:
	if pretend_window != Vector2i.ZERO:
		return pretend_cutouts
	var found: Array[Rect2i] = []
	if OS.get_name() == "Android":
		for cutout: Rect2 in DisplayServer.get_display_cutouts():
			found.append(Rect2i(cutout))
	return found
