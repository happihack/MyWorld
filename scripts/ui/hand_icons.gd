class_name HandIcons
extends RefCounted
## The icons, drawn by hand (the owner's direction, 2026-10-09): one loose
## line, every segment a little curved, circles that don't quite meet. Kept
## as the strokes themselves (on a 24-unit grid) and rasterised when first
## asked for at a size, in white — the colour is given when they are drawn,
## so the same icon is cream on the lid and ink on paper.

const PATHS := {
	&"menu": '<path d="M4.5 7.2c5-.6 10-.5 15 .1M4 12.3c5.3.4 10.4.3 15.6-.2M4.6 17.4c3.3.5 6.6.4 9.8-.1"/>',
	&"world": '<path d="M3.5 9.2l8.6-4.8 8.6 4.6-.3 8.1-8.5 4.9-8.6-4.7z"/><path d="M3.5 9.2l8.4 4.9 8.6-4.9"/><path d="M12 14.2c.2 2.6.1 5.2-.2 7.8"/>',
	&"people": '<path d="M9 5.2c2 0 3.2 1.4 3.1 3.1-.1 1.8-1.5 2.9-3.2 2.8C7.2 11 6 9.8 6 8.2c0-1.7 1.3-3 3-3z"/><path d="M3.2 20c.4-3.6 2.6-5.9 5.9-5.9 3.2 0 5.5 2.2 6 5.8"/><path d="M17 6.8c1.5 0 2.5 1.1 2.4 2.4-.1 1.4-1.1 2.3-2.5 2.2-1.3-.1-2.2-1-2.1-2.3.1-1.3 1-2.3 2.2-2.3z"/><path d="M16.9 14.6c2.6.2 4.3 2 4.5 5.2"/>',
	&"civilization": '<path d="M3.8 11.2l8.3-7.1 8.1 7.3"/><path d="M6.2 9.6c-.2 3.5-.2 7 .1 10.5 4 .3 8 .3 11.9-.1.2-3.5.1-7-.2-10.5"/><path d="M15.4 4.3c.1 1 .1 2 0 3.1"/><path d="M10.2 20.2c-.1-1.7-.1-3.4.1-5.1 1.3-.1 2.5-.1 3.8.1.1 1.7.1 3.4-.1 5"/>',
	&"history": '<path d="M6.8 3.2c3.4-.4 6.9-.4 10.4 0M6.9 20.9c3.5.3 7 .3 10.4-.1"/><path d="M8 3.3c-.3 4.8 3.9 6.2 4 8.9.1 2.8-4.3 4.1-4 8.7"/><path d="M16.1 3.2c.4 4.7-3.8 6.1-3.9 8.9 0 2.7 4.3 4.1 3.9 8.7"/>',
	&"player": '<path d="M12.1 13.2c-.1-2.6-.1-5.1 0-7.6.1-1.1.8-1.8 1.8-1.8s1.7.8 1.7 1.9c.1 2.5.1 5 0 7.5"/><path d="M15.6 13.1l3.2 1.3c1 .5 1.4 1.4 1.1 2.4l-.9 3.3c-.4 1.3-1.5 2-2.9 2h-3.3c-1.4 0-2.5-.6-3.3-1.7l-3-4.2c-.5-.7-.4-1.5.2-2 .6-.5 1.4-.4 2 .1l2.9 2.3"/><path d="M9.4 6.1c1.2-2.6 5.2-3.6 8.4-.3"/><path d="M7 3.4c3-3.3 10-3.4 13.5.2"/>',
	&"settings": '<path d="M4.2 7.1c3-.3 6-.3 9 .1M18.2 7.1l1.9-.1"/><path d="M15.5 4.5c1.5 0 2.5 1.1 2.5 2.5s-1.1 2.5-2.5 2.6c-1.4 0-2.6-1.2-2.5-2.6.1-1.4 1.1-2.5 2.5-2.5z"/><path d="M4 17.1l3-.1M12.1 17c2.7.2 5.3.2 8-.1"/><path d="M9.5 14.5c1.4 0 2.6 1.1 2.5 2.5s-1.2 2.5-2.6 2.5c-1.4-.1-2.4-1.2-2.4-2.6s1.1-2.4 2.5-2.4z"/>',
	&"close": '<path d="M6.2 6.1c4 3.9 7.9 7.9 11.7 11.9M17.8 6.2c-3.9 3.9-7.8 7.9-11.6 11.8"/>',
	&"hand": '<path d="M8.1 12.1c-.1-2 0-4 .1-6 0-.9.6-1.5 1.4-1.5.9 0 1.5.7 1.5 1.6v5.9"/><path d="M11.1 11.9V4.6c0-.9.6-1.6 1.5-1.6s1.5.7 1.5 1.6v7.4"/><path d="M14.1 12V6.1c0-.9.7-1.5 1.5-1.5.9 0 1.5.7 1.5 1.6v7.9"/><path d="M17.1 13.6v-4c0-.9.6-1.5 1.5-1.5s1.5.7 1.4 1.6l-.1 6.4c0 3.4-2.6 6-6 6h-1.4c-1.8 0-3.5-.8-4.6-2.2l-3.3-4.3c-.5-.7-.4-1.6.3-2.1.6-.4 1.4-.3 2 .2l1.3 1.5"/>',
	&"look": '<path d="M2.2 12.1c2.6-3.9 6-6.3 9.9-6.4 3.9 0 7.3 2.4 9.8 6.3-2.6 4-6 6.3-10 6.4-3.9 0-7.3-2.4-9.7-6.3z"/><path d="M12 9.1c1.7 0 2.9 1.3 2.9 2.9s-1.3 2.9-3 2.9-2.9-1.3-2.8-3c.1-1.6 1.3-2.8 2.9-2.8z"/>',
	&"weather": '<path d="M7.4 16.1c-2.5-.2-4.3-2.1-4.3-4.5 0-2.4 1.9-4.4 4.3-4.4.9-2.5 3.2-4.1 5.9-4.1 3.3 0 6 2.6 6.1 5.9 1.8.3 3.2 1.8 3.1 3.6-.1 1.9-1.6 3.4-3.5 3.5-3.9.1-7.8.1-11.6 0z"/><path d="M9.1 18.6l-1 2.9M13.1 18.5l-1.1 3M17.2 18.6l-1.1 2.8"/>',
	&"wind": '<path d="M9.6 4.7c1.2-1.2 3.1-.7 3.4.9.3 1.6-1.1 2.6-2.3 2.5-3 0-6 0-8.8-.1"/><path d="M12.6 19.3c1.2 1.2 3.2.7 3.4-.9.3-1.7-1.2-2.6-2.4-2.5-3.9.1-7.8.1-11.7 0"/><path d="M17.8 7.6c1.4-1.5 3.9-.8 4.2 1.2.3 2-1.5 3.3-3 3.2-5.6.1-11.3.1-17 0"/>',
	&"water": '<path d="M12 2.8c-2.4 2.8-6.7 7.5-6.5 11.4.2 3.6 3 6.4 6.5 6.4 3.6 0 6.5-2.9 6.5-6.5 0-3.9-4.2-8.5-6.5-11.3z"/>',
	&"stories": '<path d="M4.1 4.6c0-1.4 1.2-2.6 2.6-2.6 4.4-.1 8.8-.1 13.2 0 .1 5.3.1 10.7-.1 16-4.3.1-8.7.1-13 0-1.4 0-2.6 1.1-2.6 2.5"/><path d="M4.1 20.5c-.2-5.3-.2-10.6 0-15.9M6.6 18c4.4-.2 8.9-.2 13.3 0"/>',
	&"home": '<path d="M3.2 10.6l8.8-7.4 8.9 7.3"/><path d="M5.1 9.6c-.2 3.5-.2 7 .1 10.5 4.6.2 9.2.2 13.8-.1.2-3.5.1-7-.1-10.4"/><path d="M10 20.1c-.1-2-.1-4 .1-6 1.3-.1 2.6-.1 3.9.1.1 2 .1 3.9 0 5.9"/>',
	&"play": '<path d="M7.2 4.3c4.4 2.4 8.7 5 12.9 7.6-4.2 2.7-8.5 5.3-12.9 7.8-.2-5.1-.2-10.3 0-15.4z"/>',
	&"pause": '<path d="M8 4.5c.3 5 .2 10-.2 15M16 4.4c.3 5 .3 10.1-.1 15.1"/>',
	&"alert": '<path d="M12 3.1c-3.5 5.5-6.8 11.1-10 16.8 6.7.3 13.4.3 20.1 0-3.3-5.7-6.6-11.3-10.1-16.8z"/><path d="M12 9.8c.1 1.4.1 2.8 0 4.2M12 17.1v.1"/>',
	# A sprig: a stem with two leaves (the blessings' button).
	&"bless": '<path d="M12.2 20.6c.3-4.6.2-9.2-.4-13.8"/><path d="M11.6 13.1c-3.3-.3-5.6-2.3-6.5-5.7 3.4.2 5.8 2.1 6.5 5.7z"/><path d="M12.1 9.9c.5-3.4 2.8-5.5 6.2-6.1-.7 3.4-2.9 5.6-6.2 6.1z"/>',
	&"chevron": '<path d="M9 6.2c2 2 4 3.9 5.9 5.9-2 2-3.9 4-5.9 5.9"/>',
	&"back": '<path d="M21 12.3c-6 .3-12 .2-18-.3"/><path d="M9 5.5C7 7.9 5.3 9.9 3.5 12c2 2.1 3.8 4.2 5.8 6.2"/>',
	&"plus": '<path d="M12 4.5c.3 5 .2 10-.4 15M4.6 12.4c5-.6 10-.5 14.8.2"/>',
	&"search": '<path d="M11 4.6c3.6 0 6.4 2.8 6.4 6.3 0 3.6-2.9 6.4-6.4 6.5-3.6 0-6.4-2.9-6.4-6.5.1-3.5 2.9-6.3 6.4-6.3z"/><path d="M15.9 15.8c1.5 1.3 2.9 2.7 4.2 4.2"/>',
	&"door": '<path d="M5 4.5c4.5-.6 9-.5 13.5.2M5 4.5c-.4 5-.3 10 .3 15 4.5.5 9 .4 13.2-.2.5-5 .4-10-.2-15"/><path d="M10 8.5c2.5 1 5 1.2 7.5.5"/><path d="M15 12.5v.1"/>',
	&"power": '<path d="M12 3.2c.1 3 .1 6 0 9"/><path d="M6.6 7.1c-3.2 3.3-3 8.2.3 11.3 3.2 3 8.1 2.9 11.1-.3 2.9-3.2 2.7-8-.6-11"/>',
	&"star": '<path d="M12 3.2c1.2 2.4 2.3 4.8 3.4 7.2 2.6.4 5.2.7 7.8 1-1.9 1.8-3.8 3.6-5.6 5.5.5 2.6 1 5.2 1.4 7.8-2.3-1.3-4.7-2.5-7-3.7-2.4 1.2-4.7 2.5-7 3.7.5-2.6.9-5.2 1.4-7.8C4.6 15.1 2.7 13.3.8 11.4c2.6-.3 5.2-.6 7.8-1C9.7 8 10.8 5.6 12 3.2z"/>',
	&"box_small": '<path d="M8.5 10.2l3.6-2 3.5 1.9-.1 3.6-3.5 2.1-3.6-2z"/><path d="M8.5 10.2l3.5 2 3.6-2M12 12.2v3.6"/>',
	&"box_medium": '<path d="M6 9.4l6-3.2 6 3.1-.2 6-5.9 3.4-6-3.3z"/><path d="M6 9.4l5.9 3.3 6.1-3.3M12 12.7v5.9"/>',
	&"box_large": '<path d="M3.5 8.6l8.6-4.6 8.5 4.5-.3 8.4-8.3 4.7-8.6-4.6z"/><path d="M3.5 8.6l8.4 4.8 8.7-4.8M12 13.4v8.2"/>',
	&"arrow": '<path d="M3 13c8-4 16-3 28-1" transform="scale(0.72) translate(1,2)"/><path d="M24 5c3 3 5 5 7 7-3 2-5 4-8 7" transform="scale(0.72) translate(1,2)"/>',
}

## The drawn line, in the 24-unit grid.
const STROKE := 2.2

static var _cache: Dictionary = {}


## The icon `id`, rasterised `px` pixels across (white; colour it when drawing).
static func texture(id: StringName, px: int) -> Texture2D:
	if not PATHS.has(id) or px <= 0:
		return null
	var key := "%s:%d" % [id, px]
	if _cache.has(key):
		return _cache[key]
	var svg := ('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="24" height="24" fill="none" '
		+ 'stroke="#ffffff" stroke-width="%s" stroke-linecap="round" stroke-linejoin="round">%s</svg>') % [STROKE, PATHS[id]]
	var image := Image.new()
	if image.load_svg_from_string(svg, px / 24.0) != OK:
		return null
	var made := ImageTexture.create_from_image(image)
	_cache[key] = made
	return made


## Draws the icon `id` in `color`, fitted in `rect`.
static func draw(on: CanvasItem, id: StringName, rect: Rect2, color: Color) -> void:
	var side := int(ceil(minf(rect.size.x, rect.size.y)))
	var made := texture(id, side)
	if made == null:
		return
	var square := Rect2(rect.position + (rect.size - Vector2(side, side)) * 0.5, Vector2(side, side))
	on.draw_texture_rect(made, square, false, color)


static func has(id: StringName) -> bool:
	return PATHS.has(id)
