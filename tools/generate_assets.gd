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

const GLASS := Color(0.10, 0.13, 0.18)
const HEADLIGHT := Color(1.0, 0.97, 0.75)
const TAILLIGHT := Color(0.85, 0.08, 0.08)
const TYRE := Color(0.06, 0.06, 0.06)

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

func _blend(img: Image, x: int, y: int, c: Color) -> void:
	if x < 0 or y < 0 or x >= img.get_width() or y >= img.get_height():
		return
	img.set_pixel(x, y, img.get_pixel(x, y).blend(c))


func _in_rrect(x: int, y: int, r: Rect2i, radius: float) -> bool:
	var px := x + 0.5
	var py := y + 0.5
	var qx := clampf(px, r.position.x + radius, r.end.x - radius)
	var qy := clampf(py, r.position.y + radius, r.end.y - radius)
	return Vector2(px - qx, py - qy).length() <= radius


## Rounded rectangle. `shade` > 0 adds a cylindrical highlight so bodies look rounded.
func _rrect(img: Image, r: Rect2i, radius: float, c: Color, shade := 0.0) -> void:
	var cx := r.position.x + r.size.x * 0.5
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			if not _in_rrect(x, y, r, radius):
				continue
			var col := c
			if shade > 0.0:
				var t: float = absf(x + 0.5 - cx) / (r.size.x * 0.5)
				col = c.lightened(shade * 0.6 * (1.0 - t)).darkened(shade * t * t)
			_blend(img, x, y, col)


func _rect(img: Image, r: Rect2i, c: Color) -> void:
	_rrect(img, r, 0.0, c)


func _save_png(img: Image, file_name: String) -> void:
	img.save_png(ProjectSettings.globalize_path(SPRITE_DIR + file_name))


# ---------------------------------------------------------------- road

func _make_road() -> void:
	var img := Image.create(ROAD_W, TILE_H, false, Image.FORMAT_RGBA8)
	var road_right := ROAD_LEFT + LANE_W * LANES
	for y in TILE_H:
		for x in ROAD_W:
			var n := rng.randf_range(-1.0, 1.0)
			var c: Color
			if x < ROAD_LEFT - 14 or x >= road_right + 14:
				c = Color(0.36, 0.33, 0.20).lightened(n * 0.08)  # dry verge
			elif x < ROAD_LEFT or x >= road_right:
				c = Color(0.24, 0.23, 0.21).lightened(n * 0.10)  # gravel shoulder
			else:
				c = Color(0.15, 0.15, 0.16).lightened(n * 0.05)  # asphalt
				# Worn tyre tracks in the middle of each lane.
				var in_lane := fmod(x - ROAD_LEFT, float(LANE_W))
				if absf(in_lane - LANE_W * 0.5 + 14) < 5 or absf(in_lane - LANE_W * 0.5 - 14) < 5:
					c = c.darkened(0.12)
			img.set_pixel(x, y, c)

	# A few tileable asphalt patches.
	for i in 6:
		var px := rng.randi_range(ROAD_LEFT + 6, road_right - 30)
		var py := rng.randi_range(0, TILE_H - 1)
		var w := rng.randi_range(10, 26)
		var h := rng.randi_range(8, 30)
		for yy in h:
			for xx in w:
				_blend(img, px + xx, (py + yy) % TILE_H, Color(0, 0, 0, 0.08))

	# Solid edge lines.
	for y in TILE_H:
		for x in range(ROAD_LEFT + 2, ROAD_LEFT + 5):
			img.set_pixel(x, y, Color(0.85, 0.85, 0.80))
		for x in range(road_right - 5, road_right - 2):
			img.set_pixel(x, y, Color(0.85, 0.85, 0.80))

	# Lane dividers: double yellow between directions, white dashes elsewhere.
	for i in range(1, LANES):
		var lx := ROAD_LEFT + LANE_W * i
		for y in TILE_H:
			if i == ONCOMING_LANES:
				for x in [lx - 4, lx - 3, lx - 2, lx + 2, lx + 3, lx + 4]:
					img.set_pixel(x, y, Color(0.85, 0.68, 0.10).lightened(rng.randf() * 0.05))
			elif y % 80 < 44:
				for x in range(lx - 1, lx + 2):
					img.set_pixel(x, y, Color(0.82, 0.82, 0.80, 1.0).darkened(rng.randf() * 0.12))

	# Guard-rail posts on the verge.
	for y in range(4, TILE_H, 32):
		for post_x in [6, ROAD_W - 18]:
			_rect(img, Rect2i(post_x, y, 12, 12), Color(0.30, 0.18, 0.10))
			_rect(img, Rect2i(post_x + 1, y + 1, 10, 10), Color(0.48, 0.30, 0.18))
			_rect(img, Rect2i(post_x + 2, y + 2, 5, 3), Color(0.62, 0.42, 0.28))
	_save_png(img, "road_tile.png")


# ---------------------------------------------------------------- cars

## Canvas for a car of body size w x h. Leaves room for mirrors.
func _car_canvas(w: int, h: int) -> Image:
	return Image.create(w + 8, h + 2, false, Image.FORMAT_RGBA8)


## Generic passenger car seen from above, facing up.
## spec: ws = windshield [y, h] fractions, roof = [y, h], rear = [y, h].
func _car(w: int, h: int, color: Color, spec: Dictionary) -> Image:
	var img := _car_canvas(w, h)
	var ox := 4
	var oy := 1
	# Tyres peeking out.
	for ty in [int(h * 0.14), int(h * 0.70)]:
		_rect(img, Rect2i(ox - 1, oy + ty, 3, int(h * 0.16)), TYRE)
		_rect(img, Rect2i(ox + w - 2, oy + ty, 3, int(h * 0.16)), TYRE)
	# Mirrors.
	var my := oy + int(h * spec.ws[0]) + 2
	_rect(img, Rect2i(ox - 3, my, 4, 4), color.darkened(0.3))
	_rect(img, Rect2i(ox + w - 1, my, 4, 4), color.darkened(0.3))
	# Body.
	_rrect(img, Rect2i(ox, oy, w, h), 7, color.darkened(0.55))
	_rrect(img, Rect2i(ox + 1, oy + 1, w - 2, h - 2), 6, color, 0.5)
	# Bonnet crease.
	_rect(img, Rect2i(ox + w / 2, oy + 5, 1, int(h * spec.ws[0]) - 7), color.darkened(0.15))
	# Glass and roof.
	var ws := Rect2i(ox + 4, oy + int(h * spec.ws[0]), w - 8, int(h * spec.ws[1]))
	_rrect(img, ws, 3, GLASS)
	_rect(img, Rect2i(ws.position.x + 2, ws.position.y + 2, ws.size.x - 10, 2), Color(1, 1, 1, 0.25))
	var roof := Rect2i(ox + 4, oy + int(h * spec.roof[0]), w - 8, int(h * spec.roof[1]))
	_rrect(img, roof, 3, color.darkened(0.25))
	_rrect(img, roof.grow(-1), 3, color.lightened(0.08), 0.35)
	_rect(img, Rect2i(ox + 2, roof.position.y, 2, roof.size.y), GLASS)
	_rect(img, Rect2i(ox + w - 4, roof.position.y, 2, roof.size.y), GLASS)
	if spec.rear[1] > 0.0:
		_rrect(img, Rect2i(ox + 5, oy + int(h * spec.rear[0]), w - 10, int(h * spec.rear[1])), 2, GLASS)
	# Lights.
	_rrect(img, Rect2i(ox + 3, oy + 1, 7, 3), 1, HEADLIGHT)
	_rrect(img, Rect2i(ox + w - 10, oy + 1, 7, 3), 1, HEADLIGHT)
	_rrect(img, Rect2i(ox + 3, oy + h - 4, 7, 3), 1, TAILLIGHT)
	_rrect(img, Rect2i(ox + w - 10, oy + h - 4, 7, 3), 1, TAILLIGHT)
	if spec.get("stripes", false):
		var sc: Color = spec.get("stripe_color", Color.WHITE)
		for sx in [w / 2 - 5, w / 2 + 2]:
			for y in range(oy + 2, oy + h - 2):
				var x: int = ox + sx
				var on_glass := y >= ws.position.y and y < ws.end.y
				if not on_glass:
					_blend(img, x, y, sc)
					_blend(img, x + 1, y, sc)
					_blend(img, x + 2, y, sc)
	if spec.get("spoiler", false):
		_rrect(img, Rect2i(ox - 2, oy + h - 9, w + 4, 5), 2, Color(0.08, 0.08, 0.1))
	return img


func _make_truck(color: Color, cargo: Color) -> Image:
	var w := 46
	var h := 124
	var img := _car_canvas(w, h)
	var ox := 4
	var oy := 1
	for ty in [10, 74, 92, 108]:
		_rect(img, Rect2i(ox - 1, oy + ty, 3, 12), TYRE)
		_rect(img, Rect2i(ox + w - 2, oy + ty, 3, 12), TYRE)
	_rect(img, Rect2i(ox - 3, oy + 12, 4, 5), color.darkened(0.4))
	_rect(img, Rect2i(ox + w - 1, oy + 12, 4, 5), color.darkened(0.4))
	# Cab.
	_rrect(img, Rect2i(ox + 1, oy, w - 2, 30), 6, color.darkened(0.55))
	_rrect(img, Rect2i(ox + 2, oy + 1, w - 4, 28), 5, color, 0.5)
	_rrect(img, Rect2i(ox + 5, oy + 7, w - 10, 8), 2, GLASS)
	_rrect(img, Rect2i(ox + 3, oy + 1, 7, 3), 1, HEADLIGHT)
	_rrect(img, Rect2i(ox + w - 10, oy + 1, 7, 3), 1, HEADLIGHT)
	# Cargo box with roof ribs.
	_rect(img, Rect2i(ox + w / 2 - 3, oy + 29, 6, 4), Color(0.1, 0.1, 0.1))
	_rrect(img, Rect2i(ox, oy + 32, w, h - 32), 3, cargo.darkened(0.5))
	_rrect(img, Rect2i(ox + 1, oy + 33, w - 2, h - 34), 2, cargo, 0.3)
	for ry in range(oy + 40, oy + h - 4, 10):
		_rect(img, Rect2i(ox + 2, ry, w - 4, 1), cargo.darkened(0.2))
	_rect(img, Rect2i(ox + 3, oy + h - 3, 6, 2), TAILLIGHT)
	_rect(img, Rect2i(ox + w - 9, oy + h - 3, 6, 2), TAILLIGHT)
	return img


func _make_bus(color: Color) -> Image:
	var w := 48
	var h := 140
	var img := _car_canvas(w, h)
	var ox := 4
	var oy := 1
	for ty in [16, 104]:
		_rect(img, Rect2i(ox - 1, oy + ty, 3, 16), TYRE)
		_rect(img, Rect2i(ox + w - 2, oy + ty, 3, 16), TYRE)
	_rect(img, Rect2i(ox - 3, oy + 3, 4, 6), Color(0.1, 0.1, 0.1))
	_rect(img, Rect2i(ox + w - 1, oy + 3, 4, 6), Color(0.1, 0.1, 0.1))
	_rrect(img, Rect2i(ox, oy, w, h), 8, color.darkened(0.55))
	_rrect(img, Rect2i(ox + 1, oy + 1, w - 2, h - 2), 7, color, 0.45)
	_rrect(img, Rect2i(ox + 4, oy + 3, w - 8, 7), 2, GLASS)
	# Side window strips and roof hatches.
	_rect(img, Rect2i(ox + 2, oy + 16, 2, h - 26), GLASS)
	_rect(img, Rect2i(ox + w - 4, oy + 16, 2, h - 26), GLASS)
	for hy in [30, 64, 98]:
		_rrect(img, Rect2i(ox + w / 2 - 8, oy + hy, 16, 12), 2, color.darkened(0.25))
		_rrect(img, Rect2i(ox + w / 2 - 7, oy + hy + 1, 14, 10), 2, color.lightened(0.15))
	_rect(img, Rect2i(ox + 3, oy + h - 4, 6, 3), TAILLIGHT)
	_rect(img, Rect2i(ox + w - 9, oy + h - 4, 6, 3), TAILLIGHT)
	return img


func _make_cars() -> void:
	var sedan := {"ws": [0.27, 0.17], "roof": [0.44, 0.28], "rear": [0.73, 0.10]}
	var hatch := {"ws": [0.24, 0.18], "roof": [0.42, 0.40], "rear": [0.0, 0.0]}
	var sports := {"ws": [0.36, 0.15], "roof": [0.51, 0.18], "rear": [0.70, 0.07]}
	var van := {"ws": [0.13, 0.13], "roof": [0.26, 0.70], "rear": [0.0, 0.0]}

	var sedan_colors := [Color(0.80, 0.15, 0.15), Color(0.15, 0.30, 0.85), Color(0.90, 0.90, 0.92),
		Color(0.60, 0.62, 0.66), Color(0.15, 0.55, 0.30), Color(0.75, 0.48, 0.28)]
	for i in sedan_colors.size():
		_save_png(_car(36, 68, sedan_colors[i], sedan), "sedan_%d.png" % i)

	var hatch_colors := [Color(0.90, 0.30, 0.70), Color(0.20, 0.25, 0.80), Color(0.95, 0.80, 0.10), Color(0.12, 0.12, 0.14)]
	for i in hatch_colors.size():
		_save_png(_car(34, 58, hatch_colors[i], hatch), "hatch_%d.png" % i)

	var sports_colors := [Color(0.95, 0.45, 0.05), Color(0.10, 0.70, 0.75), Color(0.85, 0.85, 0.15)]
	for i in sports_colors.size():
		var s := sports.duplicate()
		s["stripes"] = true
		s["stripe_color"] = Color(0.05, 0.05, 0.05, 0.85)
		_save_png(_car(36, 66, sports_colors[i], s), "sports_%d.png" % i)

	var van_colors := [Color(0.92, 0.92, 0.94), Color(0.35, 0.40, 0.50), Color(0.55, 0.15, 0.15)]
	for i in van_colors.size():
		_save_png(_car(42, 82, van_colors[i], van), "van_%d.png" % i)

	_save_png(_make_truck(Color(0.20, 0.35, 0.75), Color(0.85, 0.85, 0.85)), "truck_0.png")
	_save_png(_make_truck(Color(0.75, 0.15, 0.12), Color(0.55, 0.50, 0.42)), "truck_1.png")
	_save_png(_make_bus(Color(0.95, 0.78, 0.08)), "bus_0.png")
	_save_png(_make_bus(Color(0.88, 0.88, 0.90)), "bus_1.png")

	var player := {"ws": [0.33, 0.16], "roof": [0.49, 0.20], "rear": [0.69, 0.08],
		"stripes": true, "stripe_color": Color(1, 1, 1, 0.95), "spoiler": true}
	_save_png(_car(38, 72, Color(0.85, 0.08, 0.10), player), "player.png")


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
