extends TestCase
## The HUD keeps clear of a phone's notch, camera hole and home indicator
## (SafeArea, bible §26.4): iOS tells of its safe area, Android of its
## cutouts; headless and the desktop tell of nothing.

## An iPhone 14: 1170×2532, a 141 px band for the notch, 102 px for the home indicator.
const PHONE := Vector2i(1170, 2532)
const PHONE_SAFE := Rect2i(0, 141, 1170, 2532 - 141 - 102)
## A Note20 held upright: 1080×2400 with a camera hole at the top centre.
const NOTE := Vector2i(1080, 2400)
const NOTE_HOLE := Rect2i(500, 0, 80, 90)


func after_each() -> void:
	SafeArea.stop_pretending()


func _per_pixel(window: Vector2i) -> Vector2:
	return get_viewport().get_visible_rect().size / Vector2(window)


func test_nothing_to_keep_clear_of_headless() -> void:
	for edge: Side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
		assert_eq(SafeArea.inset(get_viewport(), edge), 0.0)
	assert_eq(SafeArea.inset(null, SIDE_TOP), 0.0)


func test_the_safe_area_gives_every_edge_its_inset_in_canvas_units() -> void:
	SafeArea.pretend(PHONE, PHONE_SAFE)
	var per := _per_pixel(PHONE)
	assert_near(SafeArea.inset(get_viewport(), SIDE_TOP), 141.0 * per.y, 0.01)
	assert_near(SafeArea.inset(get_viewport(), SIDE_BOTTOM), 102.0 * per.y, 0.01)
	assert_eq(SafeArea.inset(get_viewport(), SIDE_LEFT), 0.0)
	assert_eq(SafeArea.inset(get_viewport(), SIDE_RIGHT), 0.0)
	# The notch is the whole top edge's business: the corners move too.
	assert_near(SafeArea.inset(get_viewport(), SIDE_TOP, Vector2(0.0, 100.0)), 141.0 * per.y, 0.01)


func test_a_cutout_counts_only_where_it_crosses() -> void:
	SafeArea.pretend(NOTE, Rect2i(), [NOTE_HOLE])
	var per := _per_pixel(NOTE)
	assert_near(SafeArea.inset(get_viewport(), SIDE_TOP), 90.0 * per.y, 0.01, "the whole edge: the hole")
	var hole_left := 500.0 * per.x
	assert_near(SafeArea.inset(get_viewport(), SIDE_TOP, Vector2(hole_left - 10.0, hole_left + 10.0)), 90.0 * per.y, 0.01)
	assert_eq(SafeArea.inset(get_viewport(), SIDE_TOP, Vector2(0.0, 200.0)), 0.0, "the ☰'s corner is clear of it")
	assert_eq(SafeArea.inset(get_viewport(), SIDE_LEFT), 0.0, "a hole at the top is not at the side")
	assert_eq(SafeArea.inset(get_viewport(), SIDE_BOTTOM), 0.0)


func test_a_hole_at_the_side_when_held_on_its_side() -> void:
	var window := Vector2i(2400, 1080)
	SafeArea.pretend(window, Rect2i(), [Rect2i(0, 500, 90, 80)])
	var per := _per_pixel(window)
	assert_near(SafeArea.inset(get_viewport(), SIDE_LEFT), 90.0 * per.x, 0.01)
	assert_eq(SafeArea.inset(get_viewport(), SIDE_LEFT, Vector2(0.0, 200.0)), 0.0, "the ☰, higher up, is clear")
	assert_eq(SafeArea.inset(get_viewport(), SIDE_TOP), 0.0)
	assert_eq(SafeArea.inset(get_viewport(), SIDE_RIGHT), 0.0)


func test_the_menu_button_and_the_clock_drop_below_the_notch() -> void:
	SafeArea.pretend(PHONE, PHONE_SAFE)
	var per := _per_pixel(PHONE)
	var menu := MenuButtonRound.new()
	add_child(menu)
	assert_near(menu.position.y, MenuButtonRound.TOP + 141.0 * per.y, 0.01)
	assert_eq(menu.position.x, MenuButtonRound.EDGE_MARGIN, "no notch at the side")
	var clock := SpeedControl.new()
	add_child(clock)
	assert_near(clock.offset_top, SpeedControl.TOP + 141.0 * per.y, 0.01)
	assert_eq(clock.offset_right, -SpeedControl.EDGE_MARGIN)
	menu.queue_free()
	clock.queue_free()


func test_without_a_phone_the_corners_are_where_they_were() -> void:
	var menu := MenuButtonRound.new()
	add_child(menu)
	assert_eq(menu.position, Vector2(MenuButtonRound.EDGE_MARGIN, MenuButtonRound.TOP))
	var clock := SpeedControl.new()
	add_child(clock)
	assert_eq(clock.offset_top, SpeedControl.TOP)
	assert_eq(clock.offset_right, -SpeedControl.EDGE_MARGIN)
	menu.queue_free()
	clock.queue_free()


func test_the_banner_hangs_below_the_cutout_or_the_notch() -> void:
	assert_eq(FollowBanner.top_for(get_viewport()), FollowBanner.TOP)
	SafeArea.pretend(NOTE, Rect2i(), [NOTE_HOLE])
	assert_eq(FollowBanner.top_for(get_viewport()), FollowBanner.TOP, "the Note20's hole: the baseline already clears it")
	SafeArea.pretend(NOTE, Rect2i(), [Rect2i(500, 0, 80, 200)])
	assert_near(FollowBanner.top_for(get_viewport()), 200.0 * _per_pixel(NOTE).y + FollowBanner.BELOW_CUTOUT, 0.01, "a deeper one: under it")
	SafeArea.pretend(PHONE, PHONE_SAFE)
	assert_near(FollowBanner.top_for(get_viewport()), 141.0 * _per_pixel(PHONE).y + FollowBanner.BELOW_CUTOUT, 0.01)
	SafeArea.pretend(NOTE, Rect2i(), [Rect2i(500, 0, 80, 20)])
	assert_eq(FollowBanner.top_for(get_viewport()), FollowBanner.TOP, "a shallow hole: the baseline already clears it")


func test_the_row_of_tools_lifts_above_a_home_indicator_only_when_it_must() -> void:
	var view := get_viewport().get_visible_rect().size
	var margin := ToolBar.bottom_margin_for(view)
	assert_eq(ToolBar.bottom_for(get_viewport()), margin)
	SafeArea.pretend(PHONE, PHONE_SAFE)
	var indicator := 102.0 * _per_pixel(PHONE).y
	assert_near(ToolBar.bottom_for(get_viewport()), maxf(margin, indicator + ToolBar.LANDSCAPE_BOTTOM_MARGIN), 0.01)
	# A deeper one than the margin allows for: the row rises with it.
	SafeArea.pretend(PHONE, Rect2i(0, 0, 1170, 2532 - 1000))
	var deep := 1000.0 * _per_pixel(PHONE).y
	assert_near(ToolBar.bottom_for(get_viewport()), deep + ToolBar.LANDSCAPE_BOTTOM_MARGIN, 0.01)
	assert_true(ToolBar.bottom_for(get_viewport()) > margin)
