extends SceneTree
## Generates every sprite and sound used by Traffic Lanebreaker.
## Run from the project folder:
##   godot --headless --path . --script res://tools/generate_assets.gd
## then let the editor (or `godot --headless --path . --import`) import them.

const SPRITE_DIR := "res://assets/sprites/"
const AUDIO_DIR := "res://assets/audio/"
const MIX_RATE := 22050

# Road layout (must match scripts/game.gd).
const ROAD_W := 672
const TILE_H := 320
const MARGIN := 120   # extra roadside each side, seen when the camera zooms out
const ROAD_LEFT := 36
const LANE_W := 60
const LANES := 10
const ONCOMING_LANES := 2

# Toy-like palette: flat colours, dark outlines, lavender glass.
const OUTLINE := Color(0.17, 0.15, 0.24)
const GLASS := Color(0.72, 0.73, 0.96)
const HEADLIGHT := Color(1.0, 0.95, 0.70)
const TAILLIGHT := Color(0.95, 0.25, 0.25)
const TYRE := Color(0.20, 0.19, 0.25)
const WHITE := Color(0.95, 0.95, 0.97)

const RED := Color(0.94, 0.33, 0.26)
const ORANGE := Color(0.98, 0.52, 0.20)
const YELLOW := Color(0.99, 0.74, 0.22)
const GREEN := Color(0.27, 0.66, 0.36)
const LIME := Color(0.55, 0.78, 0.30)
const BLUE := Color(0.27, 0.40, 0.88)
const TEAL := Color(0.20, 0.68, 0.72)
const PINK := Color(0.93, 0.45, 0.68)
const PURPLE := Color(0.55, 0.40, 0.85)
const GREY := Color(0.42, 0.43, 0.50)
const CHARCOAL := Color(0.28, 0.28, 0.34)

var rng := RandomNumberGenerator.new()


func _init() -> void:
	rng.seed = 1337
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SPRITE_DIR))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(AUDIO_DIR))
	_make_roads()
	_make_cars()
	_make_particles()
	_make_audio()
	_make_music()
	print("Traffic Lanebreaker assets generated.")
	quit()


# ---------------------------------------------------------------- drawing helpers
# Shapes are drawn from signed distance fields, so every edge is anti-aliased.

func _blend(img: Image, x: int, y: int, c: Color) -> void:
	if x < 0 or y < 0 or x >= img.get_width() or y >= img.get_height() or c.a <= 0.0:
		return
	img.set_pixel(x, y, img.get_pixel(x, y).blend(c))


## Rounded rectangle with soft edges. `r` is the corner radius.
func _rrect(img: Image, rect: Rect2, r: float, c: Color) -> void:
	r = clampf(r, 0.0, minf(rect.size.x, rect.size.y) * 0.5)
	var center := rect.get_center()
	var half := rect.size * 0.5 - Vector2(r, r)
	for y in range(floori(rect.position.y) - 1, ceili(rect.end.y) + 1):
		for x in range(floori(rect.position.x) - 1, ceili(rect.end.x) + 1):
			var p := Vector2(x + 0.5, y + 0.5) - center
			var q := Vector2(absf(p.x), absf(p.y)) - half
			var d := Vector2(maxf(q.x, 0.0), maxf(q.y, 0.0)).length() + minf(maxf(q.x, q.y), 0.0) - r
			var cover := clampf(0.5 - d, 0.0, 1.0)
			if cover > 0.0:
				_blend(img, x, y, Color(c, c.a * cover))


func _circle(img: Image, center: Vector2, radius: float, c: Color) -> void:
	_rrect(img, Rect2(center - Vector2(radius, radius), Vector2(radius, radius) * 2.0), radius, c)


## Outlined, two-tone panel: dark outline, shaded sides, flat top.
func _panel(img: Image, rect: Rect2, r: float, c: Color, inset := 2.5) -> void:
	_rrect(img, rect, r, OUTLINE)
	_rrect(img, rect.grow(-1.4), r - 1.4, c.darkened(0.22))
	_rrect(img, Rect2(rect.position.x + inset + 1.0, rect.position.y + 2.0,
		rect.size.x - (inset + 1.0) * 2.0, rect.size.y - 4.0), r - inset, c)


func _save_png(img: Image, file_name: String) -> void:
	img.save_png(ProjectSettings.globalize_path(SPRITE_DIR + file_name))


# ---------------------------------------------------------------- road

## Scenery themes. Each produces road_<id>.png: the same road with a different roadside.
const THEMES := {
	"country": {"verge": Color(0.55, 0.75, 0.33), "curb": Color(0.89, 0.86, 0.73),
		"asphalt": Color(0.36, 0.37, 0.42)},
	"city": {"verge": Color(0.78, 0.78, 0.80), "curb": Color(0.86, 0.86, 0.88),
		"asphalt": Color(0.33, 0.34, 0.39)},
	"desert": {"verge": Color(0.93, 0.80, 0.55), "curb": Color(0.86, 0.68, 0.48),
		"asphalt": Color(0.40, 0.38, 0.40)},
	"snow": {"verge": Color(0.92, 0.95, 0.99), "curb": Color(0.80, 0.84, 0.90),
		"asphalt": Color(0.38, 0.40, 0.46)},
}


func _make_roads() -> void:
	for id in THEMES:
		_make_road(id, THEMES[id])


## Draws a shape three times so anything crossing the top/bottom edge wraps seamlessly.
func _wrap_rrect(img: Image, rect: Rect2, r: float, c: Color) -> void:
	for dy in [-TILE_H, 0, TILE_H]:
		var moved := Rect2(rect.position + Vector2(0, dy), rect.size)
		if moved.end.y > 0 and moved.position.y < TILE_H:
			_rrect(img, moved, r, c)


func _wrap_circle(img: Image, center: Vector2, radius: float, c: Color) -> void:
	_wrap_rrect(img, Rect2(center - Vector2(radius, radius), Vector2(radius, radius) * 2.0), radius, c)


func _make_road(id: String, theme: Dictionary) -> void:
	var w := ROAD_W + MARGIN * 2
	var img := Image.create(w, TILE_H, false, Image.FORMAT_RGBA8)
	var left := MARGIN + ROAD_LEFT                  # asphalt starts here
	var right := MARGIN + ROAD_LEFT + LANE_W * LANES
	var verge: Color = theme["verge"]
	var curb: Color = theme["curb"]
	var curb_edge := curb.darkened(0.18)
	var asphalt: Color = theme["asphalt"]
	for y in TILE_H:
		for x in w:
			var c: Color
			if x < left - 14 or x >= right + 14:
				c = verge
				if id == "country" and (y / 20) % 2 == 0:
					c = c.lightened(0.04)  # mowing stripes
				elif id == "desert":
					c = c.darkened(0.03 * (1.0 + sin((x + y * 0.6) * 0.05)))  # dune ripples
			elif x < left - 3 or x >= right + 3:
				c = curb
			elif x < left or x >= right:
				c = curb_edge
			else:
				c = asphalt.lightened(rng.randf_range(-0.012, 0.012))
			img.set_pixel(x, y, c)

	for y in range(0, TILE_H, 40):
		_rrect(img, Rect2(left - 14, y, 11, 1), 0, curb_edge)
		_rrect(img, Rect2(right + 3, y, 11, 1), 0, curb_edge)

	# Road markings.
	var white := Color(0.96, 0.96, 0.96)
	_rrect(img, Rect2(left + 4, -2, 3, TILE_H + 4), 0, white)
	_rrect(img, Rect2(right - 7, -2, 3, TILE_H + 4), 0, white)
	for i in range(1, LANES):
		var lx := left + LANE_W * i
		if i == ONCOMING_LANES:
			_rrect(img, Rect2(lx - 5, -2, 3, TILE_H + 4), 0, YELLOW)
			_rrect(img, Rect2(lx + 2, -2, 3, TILE_H + 4), 0, YELLOW)
		else:
			for y in range(0, TILE_H, 80):
				_rrect(img, Rect2(lx - 2, y + 2, 4, 40), 2, Color(white, 0.9))

	# Roadside decoration on both verges.
	for side in [-1, 1]:
		var inner: float = left - 14 if side < 0 else right + 14   # verge edge next to the curb
		match id:
			"country": _decorate_country(img, inner, side)
			"city": _decorate_city(img, inner, side)
			"desert": _decorate_desert(img, inner, side)
			"snow": _decorate_snow(img, inner, side)
	_save_png(img, "road_%s.png" % id)


## x position `dist` px out from the verge edge on `side`.
func _out(inner: float, side: int, dist: float) -> float:
	return inner + dist * side


func _tree(img: Image, pos: Vector2, r: float, dark: Color, mid: Color, light: Color) -> void:
	_wrap_circle(img, pos + Vector2(3, 4), r, Color(0.1, 0.12, 0.08, 0.3))
	_wrap_circle(img, pos, r, dark)
	_wrap_circle(img, pos, r - 1.6, mid)
	_wrap_circle(img, pos - Vector2(r * 0.3, r * 0.3), r * 0.45, light)


func _decorate_country(img: Image, inner: float, side: int) -> void:
	for y in [40.0, 120.0, 200.0, 280.0]:   # bushes along the curb
		_tree(img, Vector2(_out(inner, side, 9), y + rng.randf_range(-6, 6)), 9,
			Color(0.24, 0.45, 0.20), Color(0.36, 0.62, 0.26), Color(0.48, 0.74, 0.32))
	for i in 7:   # big trees further out
		var pos := Vector2(_out(inner, side, rng.randf_range(42, MARGIN + 6)), rng.randf_range(0, TILE_H))
		_tree(img, pos, rng.randf_range(14, 22),
			Color(0.20, 0.40, 0.18), Color(0.30, 0.56, 0.24), Color(0.44, 0.70, 0.30))
	for i in 18:  # flowers
		var pos := Vector2(_out(inner, side, rng.randf_range(20, MARGIN + 10)), rng.randf_range(0, TILE_H))
		var petal: Color = [Color(1, 0.95, 0.6), Color(1, 0.7, 0.8), WHITE].pick_random()
		_wrap_circle(img, pos, 2.2, petal)


func _decorate_city(img: Image, inner: float, side: int) -> void:
	# Pavement slabs next to the curb.
	for y in range(0, TILE_H, 32):
		_rrect(img, Rect2(minf(inner, _out(inner, side, 40)), y, 40, 1), 0, Color(0.68, 0.68, 0.72))
	# Street lamps.
	for y in [60.0, 220.0]:
		var lamp := Vector2(_out(inner, side, 6), y)
		_wrap_rrect(img, Rect2(lamp.x - 1.5 - (12 if side > 0 else 0), y - 1.5, 15, 3), 1.5, CHARCOAL)
		_wrap_circle(img, Vector2(lamp.x - 12 * side, y), 4.5, OUTLINE)
		_wrap_circle(img, Vector2(lamp.x - 12 * side, y), 3, Color(1.0, 0.95, 0.7))
	# Rooftops of buildings beyond the pavement.
	var roof_colors := [Color(0.55, 0.58, 0.68), Color(0.80, 0.55, 0.45), Color(0.62, 0.70, 0.78),
		Color(0.85, 0.78, 0.60), Color(0.50, 0.50, 0.58)]
	var by := 0.0
	while by < TILE_H:
		var h := rng.randf_range(50, 90)
		h = minf(h, TILE_H - by)
		var x0 := _out(inner, side, 46)
		var bw := MARGIN + 10.0
		var rect := Rect2(x0 if side > 0 else x0 - bw, by + 3, bw, h - 6)
		var col: Color = roof_colors.pick_random()
		_rrect(img, rect, 4, OUTLINE)
		_rrect(img, rect.grow(-1.5), 3, col.darkened(0.15))
		_rrect(img, rect.grow(-5), 2, col)
		# Rooftop AC units.
		var ac := Rect2(rect.position + Vector2(rng.randf_range(8, 40), rng.randf_range(8, maxf(9, h - 30))), Vector2(16, 12))
		_rrect(img, ac, 2, OUTLINE)
		_rrect(img, ac.grow(-1.2), 1.5, Color(0.85, 0.86, 0.9))
		by += h


func _decorate_desert(img: Image, inner: float, side: int) -> void:
	var cactus := Color(0.35, 0.62, 0.36)
	for i in 6:
		var pos := Vector2(_out(inner, side, rng.randf_range(24, MARGIN)), rng.randf_range(0, TILE_H))
		_wrap_circle(img, pos + Vector2(3, 4), 9, Color(0.5, 0.35, 0.2, 0.25))
		# Top-down cactus: a round trunk with two arms.
		_wrap_rrect(img, Rect2(pos.x - 13, pos.y - 3.5, 26, 7), 3.5, OUTLINE)
		_wrap_rrect(img, Rect2(pos.x - 12, pos.y - 2.5, 24, 5), 2.5, cactus.darkened(0.1))
		_wrap_circle(img, pos, 7.5, OUTLINE)
		_wrap_circle(img, pos, 6.2, cactus)
		_wrap_circle(img, pos - Vector2(2, 2), 2.5, cactus.lightened(0.25))
	for i in 9:  # rocks
		var pos := Vector2(_out(inner, side, rng.randf_range(10, MARGIN + 10)), rng.randf_range(0, TILE_H))
		var r := rng.randf_range(3, 7)
		_wrap_circle(img, pos, r, Color(0.62, 0.48, 0.36))
		_wrap_circle(img, pos - Vector2(1, 1), r * 0.6, Color(0.74, 0.60, 0.46))


func _decorate_snow(img: Image, inner: float, side: int) -> void:
	for y in range(10, TILE_H, 40):   # snow banks along the curb
		_wrap_circle(img, Vector2(_out(inner, side, 5), y + rng.randf_range(-4, 4)), 7, WHITE)
	for i in 8:   # pine trees seen from above
		var pos := Vector2(_out(inner, side, rng.randf_range(30, MARGIN + 4)), rng.randf_range(0, TILE_H))
		var r := rng.randf_range(13, 19)
		_wrap_circle(img, pos + Vector2(3, 4), r, Color(0.3, 0.35, 0.5, 0.25))
		_wrap_circle(img, pos, r, Color(0.14, 0.34, 0.30))
		_wrap_circle(img, pos, r * 0.75, Color(0.20, 0.45, 0.38))
		_wrap_circle(img, pos, r * 0.45, Color(0.28, 0.55, 0.45))
		for k in 5:  # snow caps
			var a := TAU * k / 5.0 + rng.randf()
			_wrap_circle(img, pos + Vector2(cos(a), sin(a)) * r * 0.6, 2.2, WHITE)

# ---------------------------------------------------------------- vehicles

## Canvas for a vehicle of body size w x h. The 4 px side margin leaves room for
## wheels and mirrors; the game subtracts it to get the body size.
func _canvas(w: int, h: int) -> Image:
	return Image.create(w + 8, h + 2, false, Image.FORMAT_RGBA8)


func _wheels(img: Image, ox: float, w: float, ys: Array, length: float) -> void:
	for wy in ys:
		_rrect(img, Rect2(ox - 2.0, wy, 5, length), 2.2, TYRE)
		_rrect(img, Rect2(ox + w - 3.0, wy, 5, length), 2.2, TYRE)


func _lights(img: Image, ox: float, oy: float, w: float, h: float) -> void:
	_rrect(img, Rect2(ox + 4, oy + 1.8, 7, 3.4), 1.7, HEADLIGHT)
	_rrect(img, Rect2(ox + w - 11, oy + 1.8, 7, 3.4), 1.7, HEADLIGHT)
	_rrect(img, Rect2(ox + 4, oy + h - 5.0, 7, 3.0), 1.5, TAILLIGHT)
	_rrect(img, Rect2(ox + w - 11, oy + h - 5.0, 7, 3.0), 1.5, TAILLIGHT)


## Passenger car seen from above, facing up.
## spec: cab = [start, end] of the glasshouse, roof = [start, end] (fractions of h).
func _car(w: int, h: int, color: Color, spec: Dictionary) -> Image:
	var img := _canvas(w, h)
	var ox := 4.0
	var oy := 1.0
	_wheels(img, ox, w, [oy + h * 0.13, oy + h * 0.69], h * 0.18)
	# Mirrors.
	var my: float = oy + h * spec.cab[0] + 2.0
	_rrect(img, Rect2(ox - 3.5, my, 5, 4), 1.5, OUTLINE)
	_rrect(img, Rect2(ox + w - 1.5, my, 5, 4), 1.5, OUTLINE)

	_panel(img, Rect2(ox, oy, w, h), 9, color)
	# Bonnet highlight.
	_rrect(img, Rect2(ox + 7, oy + 4.5, w - 14, h * spec.cab[0] - 8.0), 3, color.lightened(0.16))

	var cab := Rect2(ox + 3.5, oy + h * spec.cab[0], w - 7.0, h * (spec.cab[1] - spec.cab[0]))
	_rrect(img, cab.grow(1.2), 6, OUTLINE)
	_rrect(img, cab, 5, GLASS)
	_rrect(img, Rect2(cab.position.x + 3, cab.position.y + 2, cab.size.x * 0.4, 2), 1, Color(1, 1, 1, 0.7))
	var roof_color: Color = spec.get("roof_color", color.lightened(0.10))
	var roof := Rect2(ox + 5.5, oy + h * spec.roof[0], w - 11.0, h * (spec.roof[1] - spec.roof[0]))
	_rrect(img, roof.grow(0.8), 4.5, roof_color.darkened(0.25))
	_rrect(img, roof, 4, roof_color)

	if spec.get("stripes", false):
		var sc: Color = spec.get("stripe_color", WHITE)
		for sx in [w * 0.5 - 6.0, w * 0.5 + 2.0]:
			_rrect(img, Rect2(ox + sx, oy + 3, 4, cab.position.y - oy - 3.5), 1, sc)
			_rrect(img, Rect2(ox + sx, roof.position.y, 4, roof.size.y), 1, sc)
			_rrect(img, Rect2(ox + sx, cab.end.y + 1.5, 4, oy + h - cab.end.y - 4.0), 1, sc)
	if spec.get("lightbar", false):
		var lb_y := roof.get_center().y - 3.0
		_rrect(img, Rect2(roof.position.x + 1, lb_y - 0.8, roof.size.x - 2, 7.6), 3, OUTLINE)
		_rrect(img, Rect2(roof.position.x + 2, lb_y, roof.size.x * 0.5 - 2.5, 6), 2.5, Color(0.95, 0.25, 0.25))
		_rrect(img, Rect2(roof.get_center().x + 0.5, lb_y, roof.size.x * 0.5 - 2.5, 6), 2.5, Color(0.3, 0.5, 1.0))
	if spec.get("taxi_sign", false):
		var ts := Rect2(roof.get_center().x - 7, roof.get_center().y - 3.5, 14, 7)
		_rrect(img, ts.grow(1), 2.5, OUTLINE)
		_rrect(img, ts, 2, Color(1.0, 0.92, 0.55))
	if spec.get("spoiler", false):
		_rrect(img, Rect2(ox - 2.5, oy + h - 10, w + 5, 6), 3, OUTLINE)
		_rrect(img, Rect2(ox - 1.5, oy + h - 9, w + 3, 4), 2, color.darkened(0.3))
	_lights(img, ox, oy, w, h)
	return img


## Box truck: cab up front, cargo box behind. `extra` adds a ladder or garbage lid.
func _truck(cab_color: Color, box_color: Color, extra := "") -> Image:
	var w := 46
	var h := 124
	var img := _canvas(w, h)
	var ox := 4.0
	var oy := 1.0
	_wheels(img, ox, w, [oy + 10, oy + 76, oy + 96], 14)
	_rrect(img, Rect2(ox - 3.5, oy + 11, 5, 5), 1.5, OUTLINE)
	_rrect(img, Rect2(ox + w - 1.5, oy + 11, 5, 5), 1.5, OUTLINE)
	# Cab.
	_panel(img, Rect2(ox + 1, oy, w - 2, 32), 8, cab_color)
	_rrect(img, Rect2(ox + 5, oy + 6, w - 10, 10).grow(1), 4, OUTLINE)
	_rrect(img, Rect2(ox + 5, oy + 6, w - 10, 10), 3.5, GLASS)
	_rrect(img, Rect2(ox + 8, oy + 8, 12, 2), 1, Color(1, 1, 1, 0.7))
	_rrect(img, Rect2(ox + 6, oy + 19, w - 12, 9), 3, cab_color.lightened(0.12))
	# Cargo box.
	_rrect(img, Rect2(ox + w * 0.5 - 4, oy + 30, 8, 6), 1, OUTLINE)
	_panel(img, Rect2(ox, oy + 34, w, h - 34), 5, box_color, 2.0)
	match extra:
		"ladder":
			_rrect(img, Rect2(ox + 12, oy + 38, 4, h - 44), 1.5, Color(0.80, 0.82, 0.86))
			_rrect(img, Rect2(ox + w - 16, oy + 38, 4, h - 44), 1.5, Color(0.80, 0.82, 0.86))
			for ry in range(int(oy) + 42, int(oy) + h - 8, 9):
				_rrect(img, Rect2(ox + 14, ry, w - 28, 2.5), 1, Color(0.70, 0.72, 0.78))
		"garbage":
			_rrect(img, Rect2(ox + 6, oy + 42, w - 12, 34), 4, box_color.lightened(0.15))
			_rrect(img, Rect2(ox + 6, oy + 82, w - 12, 30), 4, box_color.darkened(0.12))
		_:
			for ry in range(int(oy) + 44, int(oy) + h - 6, 12):
				_rrect(img, Rect2(ox + 5, ry, w - 10, 1.6), 0.8, box_color.darkened(0.12))
	if extra == "ladder":
		_rrect(img, Rect2(ox + 9, oy + 21, w - 18, 6), 3, OUTLINE)
		_rrect(img, Rect2(ox + 10, oy + 22, (w - 20) * 0.5, 4), 2, Color(0.95, 0.25, 0.25))
		_rrect(img, Rect2(ox + w * 0.5, oy + 22, (w - 20) * 0.5, 4), 2, Color(0.3, 0.5, 1.0))
	_lights(img, ox, oy, w, h)
	return img


func _bus(color: Color) -> Image:
	var w := 48
	var h := 140
	var img := _canvas(w, h)
	var ox := 4.0
	var oy := 1.0
	_wheels(img, ox, w, [oy + 16, oy + 104], 17)
	_rrect(img, Rect2(ox - 3.5, oy + 4, 5, 6), 1.5, OUTLINE)
	_rrect(img, Rect2(ox + w - 1.5, oy + 4, 5, 6), 1.5, OUTLINE)
	_panel(img, Rect2(ox, oy, w, h), 9, color)
	_rrect(img, Rect2(ox + 5, oy + 4, w - 10, 9).grow(1), 4, OUTLINE)
	_rrect(img, Rect2(ox + 5, oy + 4, w - 10, 9), 3.5, GLASS)
	# Side windows and roof.
	_rrect(img, Rect2(ox + 2.5, oy + 18, 4, h - 30), 2, GLASS)
	_rrect(img, Rect2(ox + w - 6.5, oy + 18, 4, h - 30), 2, GLASS)
	_rrect(img, Rect2(ox + 8, oy + 17, w - 16, h - 28), 4, color.lightened(0.10))
	for hy in [30, 64, 98]:
		_rrect(img, Rect2(ox + w * 0.5 - 8, oy + hy, 16, 13).grow(1), 3, OUTLINE)
		_rrect(img, Rect2(ox + w * 0.5 - 8, oy + hy, 16, 13), 3, WHITE)
	_lights(img, ox, oy, w, h)
	return img


func _make_cars() -> void:
	var sedan := {"cab": [0.28, 0.80], "roof": [0.43, 0.71]}
	var hatch := {"cab": [0.25, 0.88], "roof": [0.41, 0.84]}
	var sports := {"cab": [0.37, 0.78], "roof": [0.51, 0.70]}
	var van := {"cab": [0.12, 0.95], "roof": [0.25, 0.93]}

	var sedan_colors := [RED, BLUE, WHITE, GREY, GREEN, ORANGE]
	for i in sedan_colors.size():
		_save_png(_car(36, 68, sedan_colors[i], sedan), "sedan_%d.png" % i)
	var taxi := sedan.duplicate()
	taxi["taxi_sign"] = true
	_save_png(_car(36, 68, YELLOW, taxi), "sedan_6.png")
	var police := sedan.duplicate()
	police["roof_color"] = WHITE
	police["lightbar"] = true
	_save_png(_car(36, 68, CHARCOAL, police), "sedan_7.png")

	var hatch_colors := [PINK, BLUE, YELLOW, PURPLE]
	for i in hatch_colors.size():
		_save_png(_car(34, 58, hatch_colors[i], hatch), "hatch_%d.png" % i)

	var sports_colors := [ORANGE, TEAL, LIME]
	for i in sports_colors.size():
		var s := sports.duplicate()
		s["stripes"] = true
		s["stripe_color"] = Color(OUTLINE, 0.85)
		_save_png(_car(36, 66, sports_colors[i], s), "sports_%d.png" % i)

	var van_colors := [WHITE, BLUE, GREEN]
	for i in van_colors.size():
		_save_png(_car(42, 82, van_colors[i], van), "van_%d.png" % i)
	var ambulance := van.duplicate()
	ambulance["roof_color"] = WHITE
	ambulance["lightbar"] = true
	_save_png(_car(42, 82, Color(0.97, 0.97, 0.99), ambulance), "van_3.png")

	_save_png(_truck(BLUE, WHITE), "truck_0.png")
	_save_png(_truck(GREEN, GREEN.lightened(0.1), "garbage"), "truck_1.png")
	_save_png(_truck(RED, RED, "ladder"), "truck_2.png")
	_save_png(_bus(YELLOW), "bus_0.png")
	_save_png(_bus(BLUE), "bus_1.png")

	var player := {"cab": [0.34, 0.77], "roof": [0.49, 0.69], "stripes": true,
		"stripe_color": WHITE, "spoiler": true}
	_save_png(_car(38, 72, RED, player), "player.png")


func _make_particles() -> void:
	for spec in [["smoke.png", 32], ["spark.png", 8]]:
		var size: int = spec[1]
		var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
		var c := (size - 1) * 0.5
		for y in size:
			for x in size:
				var d := clampf(Vector2(x - c, y - c).length() / (size * 0.5), 0.0, 1.0)
				img.set_pixel(x, y, Color(1, 1, 1, pow(1.0 - d, 2.0)))
		_save_png(img, spec[0])


# ---------------------------------------------------------------- audio

func _save_wav(samples: PackedFloat32Array, file_name: String, peak := 0.9) -> void:
	var max_abs := 0.0001
	for s in samples:
		max_abs = maxf(max_abs, absf(s))
	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	for i in samples.size():
		data.encode_s16(i * 2, int(clampf(samples[i] / max_abs * peak, -1.0, 1.0) * 32767.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = MIX_RATE
	wav.stereo = false
	wav.data = data
	wav.save_to_wav(ProjectSettings.globalize_path(AUDIO_DIR + file_name))


func _buffer(seconds: float) -> PackedFloat32Array:
	var b := PackedFloat32Array()
	b.resize(int(seconds * MIX_RATE))
	return b


func _make_audio() -> void:
	rng.seed = 4242   # own seed, so sounds stay the same when sprites change
	# Engine: exactly 1 s of whole-Hz tones so it loops seamlessly; pitch is scaled in game.
	var engine := _buffer(1.0)
	var lp := 0.0
	var f := 50.0
	for i in engine.size():
		var t := float(i) / MIX_RATE
		var saw := fmod(t * f, 1.0) * 2.0 - 1.0
		var s := sin(TAU * f * t) * 0.5 + sin(TAU * 2 * f * t) * 0.3 + saw * 0.25 + sin(TAU * 3 * f * t) * 0.12
		s *= 0.75 + 0.25 * sin(TAU * 25 * t)
		s += rng.randf_range(-1, 1) * 0.08
		lp += (s - lp) * 0.35
		engine[i] = lp
	_save_wav(engine, "engine_loop.wav", 0.6)

	# Crash: noisy impact, low thump and metallic rattles.
	var crash := _buffer(1.4)
	lp = 0.0
	var metal := []
	for k in 5:
		metal.append(rng.randf_range(700, 2600))
	for i in crash.size():
		var t := float(i) / MIX_RATE
		lp += (rng.randf_range(-1, 1) - lp) * 0.25
		var s := lp * exp(-t * 3.5) * 1.3
		s += sin(TAU * (60.0 - 25.0 * t) * t) * exp(-t * 6.0) * 0.9
		for m in metal:
			s += sin(TAU * m * t) * exp(-t * 9.0) * 0.06
		s *= minf(1.0, t / 0.004)
		crash[i] = tanh(s * 1.5)
	_save_wav(crash, "crash.wav", 0.95)

	# Whoosh: band-passed noise swell for near misses.
	var whoosh := _buffer(0.55)
	var lp_a := 0.0
	var lp_b := 0.0
	for i in whoosh.size():
		var t := float(i) / whoosh.size()
		var n := rng.randf_range(-1, 1)
		var cut := lerpf(0.12, 0.45, t)
		lp_a += (n - lp_a) * cut
		lp_b += (n - lp_b) * 0.03
		whoosh[i] = (lp_a - lp_b) * pow(sin(PI * t), 2.0)
	_save_wav(whoosh, "whoosh.wav", 0.7)

	# Horn: two detuned, softly clipped tones.
	var horn := _buffer(0.55)
	for i in horn.size():
		var t := float(i) / MIX_RATE
		var env := minf(1.0, t / 0.02) * minf(1.0, (0.55 - t) / 0.08)
		horn[i] = (tanh(3.0 * sin(TAU * 370 * t)) + tanh(3.0 * sin(TAU * 466 * t))) * 0.5 * env
	_save_wav(horn, "horn.wav", 0.55)

	# Countdown beeps.
	for spec in [["beep.wav", 660.0, 0.18], ["beep_go.wav", 1320.0, 0.45]]:
		var beep := _buffer(spec[2])
		for i in beep.size():
			var t := float(i) / MIX_RATE
			var env := minf(1.0, t / 0.005) * exp(-t * 5.0)
			beep[i] = tanh(2.0 * sin(TAU * spec[1] * t)) * env
		_save_wav(beep, spec[0], 0.5)

	# Speed-up: rising sweep.
	var sweep := _buffer(0.4)
	var phase := 0.0
	for i in sweep.size():
		var t := float(i) / sweep.size()
		phase += TAU * lerpf(500.0, 1150.0, t) / MIX_RATE
		sweep[i] = tanh(2.5 * sin(phase)) * sin(PI * t)
	_save_wav(sweep, "speed_up.wav", 0.45)


# ---------------------------------------------------------------- music

const BPM := 128.0


func _midi(note: float) -> float:
	return 440.0 * pow(2.0, (note - 69.0) / 12.0)


## Adds a decaying tone into `buf` starting at `start` seconds.
func _tone(buf: PackedFloat32Array, start: float, length: float, freq: float, vol: float,
		wave: String, decay: float) -> void:
	var i0 := int(start * MIX_RATE)
	var n := int(length * MIX_RATE)
	var phase := 0.0
	var lp := 0.0
	for i in n:
		var idx := i0 + i
		if idx >= buf.size():
			return
		var t := float(i) / MIX_RATE
		phase = fmod(phase + freq / MIX_RATE, 1.0)
		var s := 0.0
		match wave:
			"saw": s = phase * 2.0 - 1.0
			"square": s = 1.0 if phase < 0.5 else -1.0
			_: s = sin(TAU * phase)
		lp += (s - lp) * 0.25   # soften harsh edges
		var env := minf(1.0, t / 0.004) * exp(-t * decay) * minf(1.0, (length - t) / 0.01)
		buf[idx] += lp * env * vol


func _make_music() -> void:
	rng.seed = 2026
	var beat := 60.0 / BPM
	var bars := 8
	var music := _buffer(bars * 4 * beat)
	# A minor: Am - F - C - G, twice.
	var chords := [[57, 60, 64], [53, 57, 60], [48, 52, 55], [55, 59, 62]]
	for bar in bars:
		var chord: Array = chords[bar % 4]
		var t0 := bar * 4 * beat
		for b in 4:
			var tb := t0 + b * beat
			# Kick on every beat.
			var kick_n := int(0.25 * MIX_RATE)
			for i in kick_n:
				var idx := int(tb * MIX_RATE) + i
				var t := float(i) / MIX_RATE
				music[idx] += sin(TAU * (45.0 * t + 75.0 * (1.0 - exp(-t * 30.0)) / 30.0)) * exp(-t * 12.0) * 0.9
			# Clap on beats 2 and 4.
			if b % 2 == 1:
				var lp := 0.0
				for i in int(0.15 * MIX_RATE):
					var t := float(i) / MIX_RATE
					var n := rng.randf_range(-1, 1)
					lp += (n - lp) * 0.6
					music[int(tb * MIX_RATE) + i] += (n - lp) * exp(-t * 22.0) * 0.45
			# Off-beat hi-hats.
			var th := tb + beat * 0.5
			var prev := 0.0
			for i in int(0.05 * MIX_RATE):
				var t := float(i) / MIX_RATE
				var n := rng.randf_range(-1, 1)
				music[int(th * MIX_RATE) + i] += (n - prev) * exp(-t * 70.0) * 0.18
				prev = n
			# Driving eighth-note bass on the chord root.
			for e in 2:
				var note: float = chord[0] - 24 + (12 if e == 1 and b % 2 == 1 else 0)
				_tone(music, tb + e * beat * 0.5, beat * 0.45, _midi(note), 0.38, "saw", 6.0)
		# Sixteenth-note arpeggio, one octave up.
		for s in 16:
			var note: float = chord[[0, 1, 2, 1][s % 4]] + 12
			_tone(music, t0 + s * beat * 0.25, beat * 0.22, _midi(note), 0.10, "square", 14.0)
		# Soft pad holding the chord for the bar.
		for note in chord:
			_tone(music, t0, 4 * beat - 0.02, _midi(note), 0.07, "saw", 0.6)
			_tone(music, t0, 4 * beat - 0.02, _midi(note) * 1.004, 0.05, "saw", 0.6)
	_save_wav(music, "music_loop.wav", 0.7)
