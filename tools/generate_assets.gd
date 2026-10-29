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
const TILE_H := 160
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
	_make_road()
	_make_cars()
	_make_particles()
	_make_audio()
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

func _make_road() -> void:
	var img := Image.create(ROAD_W, TILE_H, false, Image.FORMAT_RGBA8)
	var road_right := ROAD_LEFT + LANE_W * LANES
	var grass := Color(0.55, 0.75, 0.33)
	var curb := Color(0.89, 0.86, 0.73)
	var curb_edge := Color(0.74, 0.70, 0.57)
	var asphalt := Color(0.36, 0.37, 0.42)
	for y in TILE_H:
		for x in ROAD_W:
			var c: Color
			if x < ROAD_LEFT - 14 or x >= road_right + 14:
				c = grass
				if (y / 20) % 2 == 0:
					c = c.lightened(0.04)  # soft mowing stripes
			elif x < ROAD_LEFT - 3 or x >= road_right + 3:
				c = curb
			elif x < ROAD_LEFT or x >= road_right:
				c = curb_edge
			else:
				c = asphalt.lightened(rng.randf_range(-0.012, 0.012))
			img.set_pixel(x, y, c)

	# Curb joints.
	for y in range(0, TILE_H, 40):
		_rrect(img, Rect2(ROAD_LEFT - 14, y, 11, 1), 0, curb_edge)
		_rrect(img, Rect2(road_right + 3, y, 11, 1), 0, curb_edge)

	# Solid edge lines.
	var white := Color(0.96, 0.96, 0.96)
	_rrect(img, Rect2(ROAD_LEFT + 4, -2, 3, TILE_H + 4), 0, white)
	_rrect(img, Rect2(road_right - 7, -2, 3, TILE_H + 4), 0, white)

	# Lane markings: double yellow between directions, rounded white dashes elsewhere.
	for i in range(1, LANES):
		var lx := ROAD_LEFT + LANE_W * i
		if i == ONCOMING_LANES:
			_rrect(img, Rect2(lx - 5, -2, 3, TILE_H + 4), 0, YELLOW)
			_rrect(img, Rect2(lx + 2, -2, 3, TILE_H + 4), 0, YELLOW)
		else:
			for y in [0, 80]:
				_rrect(img, Rect2(lx - 2, y + 2, 4, 40), 2, Color(white, 0.9))

	# Round bushes on the verges (kept inside the tile so it repeats cleanly).
	for side_x in [8.0, ROAD_W - 8.0]:
		for by in [40.0, 120.0]:
			var cy: float = by + rng.randf_range(-6, 6)
			_circle(img, Vector2(side_x + 1.5, cy + 2.5), 10, Color(0.2, 0.3, 0.1, 0.35))
			_circle(img, Vector2(side_x, cy), 10, Color(0.24, 0.45, 0.20))
			_circle(img, Vector2(side_x, cy), 8.6, Color(0.36, 0.62, 0.26))
			_circle(img, Vector2(side_x - 2.5, cy - 2.5), 4.5, Color(0.48, 0.74, 0.32))
	_save_png(img, "road_tile.png")


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
